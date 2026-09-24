#!/usr/bin/env python3
"""Dataset orchestrator: staged sqlite samples -> ENA download -> bacteria light-tier chain.

Flow per cohort (study accession):
  1. read staged samples from mining/seed_registry.sqlite (read-only URI)
  2. resolve each ERS -> runs + fastq URLs via ENA portal API -> runs_manifest.json
  3. GATE 1: drop samples with no paired WGS run
  4. download fastq.gz pairs into workdir/data/ (<RUN>_1/2.fastq.gz), MD5-verified, resume-safe
  5. write workdir/samplesheet.csv + workdir/metadata.csv
  6. GATE 2 (best-effort): MGnify API v2 amplicon screen per run (record only, never drops)
  7. per sample: 01 fastp -> 02 kneaddata -> 02b pair repair -> 11 metaphlan4
     -> GATE 3 (profile non-empty, host fraction < 0.8) -> [13 humann3] -> 14 kraken2 -> 15c sylph
  8. multi-sample once: 13b humann3 merge (--with-humann), 98b integration tables (non-smoke)

Every step is appended to workdir/logs/mining_run.jsonl as one JSON line.
Platform scripts are invoked via bash after sourcing scripts/activate.sh; they are
idempotent (own sentinels), so re-running this orchestrator resumes where it stopped.

Usage:
  python3 run_dataset.py --study ERP187412 --n 8 --with-humann --threads 16
  python3 run_dataset.py --study ERP187412 --samples ERS28821761 --smoke
"""

import argparse
import csv
import hashlib
import json
import re
import shlex
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_URI = f"file:{ROOT / 'mining' / 'seed_registry.sqlite'}?mode=ro"
ENA_FILEREPORT = ("https://www.ebi.ac.uk/ena/portal/api/filereport"
                  "?accession={acc}&result=read_run"
                  "&fields=run_accession,library_strategy,read_count,base_count,fastq_ftp,fastq_md5"
                  "&format=json")
MGNIFY_RUN_ANALYSES = "https://www.ebi.ac.uk/metagenomics/api/v2/runs/{run}/analyses?page_size=1"

# Per-sample chain: (script, extra args) in execution order. 13 inserted for --with-humann.
CHAIN_CORE = [
    ("01_qc_fastp.sh", []),
    ("02_qc_kneaddata.sh", []),
    ("02b_qc_pair_repair.sh", []),
    ("11_bac_metaphlan4.sh", []),
]
CHAIN_TAIL = [
    ("14_bac_kraken2.sh", []),
    ("15c_bac_sylph.sh", []),
]
CHAIN_HUMANN = ("13_bac_humann3.sh", ["--speed-mode", "fast"])

# 02b_qc_pair_repair.sh takes -s/-w/-r only (mgx_parse exits 1 on unknown -t).
NO_THREADS_FLAG = {"02b_qc_pair_repair.sh"}

_LOCK = threading.Lock()
ARGS = None          # set in main()
WORKDIR = None       # set in main()
JSONL = None         # set in main()


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def jlog(sample, step, status, seconds=0.0, **extra):
    rec = {"ts": now_iso(), "sample": sample, "step": step, "status": status,
           "seconds": round(seconds, 1)}
    rec.update(extra)
    with _LOCK:
        with open(JSONL, "a") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
        detail = f" {extra['detail']}" if "detail" in extra and extra["detail"] else ""
        print(f"[{rec['ts']}] {sample} {step}: {status} ({rec['seconds']}s){detail}",
              flush=True)


def http_get_json(url, timeout=60):
    """GET url -> parsed JSON. One 30 s backoff on 429/5xx, then raise."""
    last_err = None
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8")), resp.status
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return None, 404
            last_err = err
            if attempt == 1 and (err.code == 429 or err.code >= 500):
                time.sleep(30)
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as err:
            last_err = err
            if attempt == 1:
                time.sleep(30)
                continue
            raise
    raise last_err


# ---------------------------------------------------------------- sqlite / selection

def load_study_samples(study):
    con = sqlite3.connect(DB_URI, uri=True)
    try:
        cur = con.execute(
            "SELECT canonical_key, study_name FROM incremental_candidates "
            "WHERE study_accession=? ORDER BY canonical_key", (study,))
        rows = cur.fetchall()
    finally:
        con.close()
    keys = [r[0] for r in rows]
    study_name = rows[0][1] if rows else ""
    return keys, study_name


def even_stride(keys, n):
    """Pick n keys spread evenly across the sorted list."""
    if n >= len(keys):
        return list(keys)
    if n <= 1:
        return [keys[0]]
    step = (len(keys) - 1) / (n - 1)
    return list(dict.fromkeys(keys[round(i * step)] for i in range(n)))


# ---------------------------------------------------------------- ENA resolve + gates

def parse_run(entry):
    ftps = (entry.get("fastq_ftp") or "").split(";")
    ftps = [f for f in ftps if f]
    md5s = (entry.get("fastq_md5") or "").split(";")
    return {
        "run_accession": entry.get("run_accession") or "",
        "library_strategy": entry.get("library_strategy") or "",
        "read_count": entry.get("read_count") or "",
        "base_count": entry.get("base_count") or "",
        "fastq_urls": ["https://" + f for f in ftps],
        "fastq_md5s": md5s if len(md5s) == len(ftps) else [""] * len(ftps),
    }


def resolve_samples(ers_list):
    """Phase b: ERS -> runs. Politeness: >=1 s between filereport calls."""
    resolved = []
    for ers in ers_list:
        t0 = time.monotonic()
        try:
            data, _ = http_get_json(ENA_FILEREPORT.format(acc=ers), timeout=60)
        except Exception as err:  # noqa: BLE001 - degrade, keep going
            jlog(ers, "ena_resolve", "failed", time.monotonic() - t0, detail=str(err)[:200])
            resolved.append({"ers": ers, "status": "resolve_failed", "reason": str(err)[:200],
                             "runs": []})
            time.sleep(1)
            continue
        runs = [parse_run(e) for e in (data or [])]
        jlog(ers, "ena_resolve", "ok" if runs else "no_runs",
             time.monotonic() - t0, runs=len(runs))
        resolved.append({"ers": ers, "runs": runs})
        time.sleep(1)
    return resolved


def gate1_choose_run(entry):
    """GATE 1: keep only samples with a paired WGS run; pick max base_count."""
    runs = entry.get("runs", [])
    wgs_paired = [r for r in runs
                  if r["library_strategy"] == "WGS" and len(r["fastq_urls"]) == 2]
    if not wgs_paired:
        reason = "not_wgs" if runs else "no_runs"
        if runs and all(len(r["fastq_urls"]) != 2 for r in runs):
            reason = "no_paired_fastq"
        entry["status"] = "dropped_gate1"
        entry["reason"] = reason
        jlog(entry["ers"], "gate1", "dropped", 0, detail=reason)
        return None
    chosen = max(wgs_paired, key=lambda r: int(r["base_count"] or 0))
    entry["chosen_run"] = chosen
    entry["status"] = "kept"
    strategies = sorted({r["library_strategy"] for r in runs})
    jlog(entry["ers"], "gate1", "kept", 0, chosen_run=chosen["run_accession"],
         library_strategies=strategies)
    return chosen


def gate2_mgnify_screen(entry):
    """GATE 2 (best-effort, never drops): any MGnify analyses for the chosen run?"""
    run = entry.get("chosen_run")
    if not run:
        return
    acc = run["run_accession"]
    t0 = time.monotonic()
    try:
        data, status = http_get_json(MGNIFY_RUN_ANALYSES.format(run=acc), timeout=60)
    except Exception as err:  # noqa: BLE001
        run["mgnify"] = {"status": "unknown", "detail": str(err)[:200]}
        jlog(acc, "gate2", "unknown", time.monotonic() - t0, detail=str(err)[:120])
        time.sleep(1)
        return
    if status == 404 or not data or not data.get("items"):
        run["mgnify"] = {"status": "no_evidence"}
        jlog(acc, "gate2", "no_evidence", time.monotonic() - t0)
    else:
        exp_types = sorted({i.get("experiment_type", "") for i in data["items"]})
        run["mgnify"] = {"status": "analyses_found", "count": data.get("count"),
                         "experiment_types": exp_types}
        jlog(acc, "gate2", "analyses_found", time.monotonic() - t0,
             count=data.get("count"), experiment_types=exp_types)
    time.sleep(1)


# ---------------------------------------------------------------- download

def md5_of(path):
    digest = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(8 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_with_curl(url, dest, md5, acc):
    """Download url -> dest via curl with HTTP Range resume + retries.

    The ENA https endpoint cuts long transfers; curl --continue-at - --retry
    resumes past those cuts. A final md5 gate in Python remains mandatory.
    """
    part = dest.with_suffix(dest.suffix + ".part")
    cmd = ["curl", "-sSfL", "--continue-at", "-", "--retry", "30", "--retry-delay", "20",
           "--retry-all-errors", "--connect-timeout", "60",
           "--speed-limit", "10240", "--speed-time", "120",
           "-o", str(part), url]
    for attempt in (1, 2):
        t0 = time.monotonic()
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, errors="replace")
        if proc.returncode == 0 and part.exists() and part.stat().st_size > 0:
            if not md5 or md5_of(part) == md5:
                part.replace(dest)
                return True
            jlog(acc, "download_retry", "md5_mismatch", time.monotonic() - t0,
                 file=dest.name, attempt=attempt)
            part.unlink(missing_ok=True)              # corrupt: restart clean
            continue
        jlog(acc, "download_retry", "curl_error", time.monotonic() - t0, file=dest.name,
             attempt=attempt, detail=(proc.stderr or "")[-200:])
    part.unlink(missing_ok=True)
    return False


def download_run_fastq(entry):
    """Phase d: download chosen run pair into workdir/data/, MD5-verify, resume-safe."""
    run = entry["chosen_run"]
    acc = run["run_accession"]
    for idx, (url, md5) in enumerate(zip(run["fastq_urls"], run["fastq_md5s"]), start=1):
        dest = WORKDIR / "data" / f"{acc}_{idx}.fastq.gz"
        if dest.exists() and dest.stat().st_size > 0:
            if not md5 or md5_of(dest) == md5:
                jlog(acc, "download", "cached" if md5 else "cached_no_md5", 0, file=dest.name)
                continue
        t0 = time.monotonic()
        if fetch_with_curl(url, dest, md5, acc):
            jlog(acc, "download", "ok" if md5 else "ok_no_md5", time.monotonic() - t0,
                 file=dest.name, size_mb=round(dest.stat().st_size / 1e6, 1))
        else:
            jlog(acc, "download", "failed", time.monotonic() - t0, file=dest.name,
                 detail="incomplete or corrupt after retries")
            entry["status"] = "download_failed"
            return False
    return True


# ---------------------------------------------------------------- chain execution

# 02_qc_kneaddata.sh had a broken mgx_conda call (command name omitted) — fixed
# upstream 2026-09-22 (scripts/02_qc_kneaddata.sh now carries the command token).
# PATCHES is kept as the mechanism for any future script quirk; empty = run all
# platform scripts in place.
PATCHES = {}


def materialize_script(script):
    """Return the script path to execute (a patched copy under /tmp/m3 if needed)."""
    fixes = PATCHES.get(script)
    if not fixes:
        return ROOT / "scripts" / script
    src = (ROOT / "scripts" / script).read_text()
    if any(old not in src for old, _ in fixes):  # upstream already carries the fix
        return ROOT / "scripts" / script
    patched = Path("/tmp/m3") / script
    patched.parent.mkdir(parents=True, exist_ok=True)
    for old, new in fixes:
        src = src.replace(old, new)
    patched.write_text(src)
    return patched


def run_platform_script(script, sample=None, extra=(), log_name=None):
    """Invoke a platform script under bash after sourcing scripts/activate.sh."""
    q = shlex.quote
    script_path = materialize_script(script)
    cmd = (f"source {q(str(ROOT / 'scripts' / 'activate.sh'))} && "
           f"bash {q(str(script_path))}")
    if sample:
        cmd += f" -s {q(sample)}"
        if script not in NO_THREADS_FLAG:
            cmd += f" -t {ARGS.threads}"
    cmd += f" -w {q(str(WORKDIR))} -r {q(str(ROOT))}"
    if extra:
        cmd += " " + " ".join(q(a) for a in extra)
    name = log_name or f"{sample or 'ALL'}.{script}.log"
    log_path = WORKDIR / "logs" / "scripts" / name
    t0 = time.monotonic()
    proc = subprocess.run(["bash", "-c", cmd], cwd=str(ROOT),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace")
    seconds = time.monotonic() - t0
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(proc.stdout or "")
    return proc.returncode, seconds, (proc.stdout or "").splitlines()[-15:]


def exec_step(sample, script, extra=()):
    code, seconds, tail = run_platform_script(script, sample=sample, extra=extra)
    who = sample or "ALL"
    if code == 0:
        jlog(who, script.replace(".sh", ""), "ok", seconds)
        return True
    jlog(who, script.replace(".sh", ""), "failed", seconds, exit_code=code,
         detail=" | ".join(tail)[-800:])
    return False


def metaphlan_has_rows(sample):
    profile = WORKDIR / "result" / "metaphlan4" / sample / f"{sample}_profile.txt"
    if not profile.exists():
        return False
    return any(line.strip() and not line.startswith("#")
               for line in profile.read_text(errors="replace").splitlines())


def host_fraction(sample):
    """Best-effort host fraction from the kneaddata log.

    KneadData writes per-stage READ COUNT lines; the meaningful pair is
    'Total reads after trimming' (input, R1) vs 'final pair1' (kept after all
    contaminant databases). Lines appear twice (timestamped + end summary).
    """
    log = WORKDIR / "result" / "kneaddata" / sample / "kneaddata.log"
    if not log.exists():
        return None
    total = kept = None
    for line in log.read_text(errors="replace").splitlines():
        if total is None and "Total reads after trimming" in line and "_1.fastq" in line:
            m = re.search(r":\s*([\d.]+)\s*$", line)
            if m:
                total = float(m.group(1))
        if "final pair1" in line:
            m = re.search(r":\s*([\d.]+)\s*$", line)
            if m:
                kept = float(m.group(1))
    if not total or kept is None:
        return None
    return 1.0 - kept / total


def gate3(sample):
    """GATE 3: metaphlan non-empty AND host fraction < 0.8 (unknown fraction tolerated)."""
    t0 = time.monotonic()
    mpa_ok = metaphlan_has_rows(sample)
    frac = host_fraction(sample)
    if mpa_ok and (frac is None or frac < 0.8):
        jlog(sample, "gate3", "passed" if frac is not None else "passed_frac_unknown",
             time.monotonic() - t0,
             metaphlan_nonempty=mpa_ok, host_fraction=None if frac is None else round(frac, 4))
        return True
    jlog(sample, "gate3", "gate3_failed", time.monotonic() - t0,
         metaphlan_nonempty=mpa_ok,
         host_fraction=None if frac is None else round(frac, 4))
    return False


def process_sample(entry):
    acc = entry["chosen_run"]["run_accession"]
    chain = list(CHAIN_CORE)
    if ARGS.with_humann and not ARGS.smoke:
        chain.append(CHAIN_HUMANN)
    chain += CHAIN_TAIL
    for script, extra in chain:
        if not exec_step(acc, script, extra):
            entry["chain_status"] = "step_failed"
            return
        if script == "11_bac_metaphlan4.sh" and not gate3(acc):
            entry["chain_status"] = "gate3_failed"
            return
    entry["chain_status"] = "completed"


# ---------------------------------------------------------------- outputs

def write_manifest(manifest, path):
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


def write_samplesheets(samples):
    ss = WORKDIR / "samplesheet.csv"
    with open(ss, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["sample_id", "r1", "r2", "host_type", "project_dir"])
        for entry in samples:
            acc = entry["chosen_run"]["run_accession"]
            w.writerow([acc,
                        WORKDIR / "data" / f"{acc}_1.fastq.gz",
                        WORKDIR / "data" / f"{acc}_2.fastq.gz",
                        "human", WORKDIR])
    md = WORKDIR / "metadata.csv"
    with open(md, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["sample_id", "study", "source"])
        for entry in samples:
            w.writerow([entry["chosen_run"]["run_accession"], ARGS.study, "mining"])
    return ss, md


# ---------------------------------------------------------------- main

def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Dataset orchestrator: sqlite staging -> ENA download -> light-tier chain.")
    p.add_argument("--study", required=True, help="study accession, e.g. ERP187412")
    p.add_argument("--n", type=int, default=8,
                   help="number of samples (even stride over sorted staged keys; default 8)")
    p.add_argument("--workdir", default=None,
                   help="project workdir (default mining/projects/<study>)")
    p.add_argument("--samples", default="",
                   help="explicit comma-separated ERS list (overrides --n selection)")
    p.add_argument("--with-humann", action="store_true",
                   help="also run 13 humann3 (--speed-mode fast) and 13b merge")
    p.add_argument("--threads", type=int, default=16, help="threads per platform step")
    p.add_argument("--jobs", type=int, default=1,
                   help="parallel sample lanes, each download->gate2->chain (default 1)")
    p.add_argument("--smoke", action="store_true",
                   help="stop after gates + 01/02/02b/11/14/15c (no HUMAnN/13b/98b)")
    args = p.parse_args(argv)
    if args.n < 1:
        p.error("--n must be >= 1")
    if args.jobs < 1:
        p.error("--jobs must be >= 1")
    return args


def main(argv=None):
    global ARGS, WORKDIR, JSONL
    ARGS = parse_args(argv)
    WORKDIR = (Path(ARGS.workdir) if ARGS.workdir
               else ROOT / "mining" / "projects" / ARGS.study).resolve()
    for sub in ("data", "temp", "result", "logs/scripts"):
        (WORKDIR / sub).mkdir(parents=True, exist_ok=True)
    JSONL = WORKDIR / "logs" / "mining_run.jsonl"

    # 1. staged samples
    keys, study_name = load_study_samples(ARGS.study)
    if not keys:
        print(f"[ERROR] no staged samples for study {ARGS.study} in seed_registry.sqlite")
        return 2
    selected = [k.strip() for k in ARGS.samples.split(",") if k.strip()] or even_stride(keys, ARGS.n)
    unknown = [k for k in selected if k not in set(keys)]
    if unknown:
        print(f"[ERROR] samples not staged for {ARGS.study}: {', '.join(unknown)}")
        return 2
    print(f"[orchestrator] study={ARGS.study} ({study_name}) staged={len(keys)} "
          f"selected={len(selected)} smoke={ARGS.smoke} humann={ARGS.with_humann and not ARGS.smoke}")

    manifest = {"study": ARGS.study, "study_name": study_name,
                "generated_at": now_iso(), "smoke": ARGS.smoke,
                "with_humann": ARGS.with_humann, "threads": ARGS.threads,
                "samples": None}

    # 2. resolve via ENA portal API
    entries = resolve_samples(selected)
    manifest["samples"] = entries
    write_manifest(manifest, WORKDIR / "runs_manifest.json")

    # 3. GATE 1 + choose run
    kept = [e for e in entries if gate1_choose_run(e)]

    # 4. pipelined per-sample lanes: download -> gate2 -> chain. Downloads and
    #    chains share the pool, so a cached/finished sample's chain starts
    #    immediately while later samples are still downloading.
    def run_one(entry):
        if not download_run_fastq(entry):
            return False
        gate2_mgnify_screen(entry)
        process_sample(entry)
        return True

    with ThreadPoolExecutor(max_workers=ARGS.jobs) as pool:
        ok_flags = list(pool.map(run_one, kept))
    runnable = [e for e, ok in zip(kept, ok_flags) if ok]
    write_manifest(manifest, WORKDIR / "runs_manifest.json")
    if not runnable:
        print("[ERROR] no samples survived gates + download")
        return 1

    # 5. samplesheet + metadata (survivors; consumed by the aggregate tail)
    ss, md = write_samplesheets(runnable)
    print(f"[orchestrator] wrote {ss} and {md}")

    # 8. multi-sample tail
    if not ARGS.smoke:
        if ARGS.with_humann:
            exec_step(None, "13b_bac_humann3_merge.sh")
        ok98 = exec_step(None, "98b_bac_integration_tables.sh",
                         extra=["-t", str(ARGS.threads)])
        if not ok98:
            print("[WARN] 98b integration failed (light-tier runs lack assembly/annotation "
                  "inputs); recorded in JSONL")

    # summary
    print("\n[summary] sample outcomes:")
    for entry in manifest["samples"]:
        acc = (entry.get("chosen_run") or {}).get("run_accession", entry["ers"])
        print(f"  {entry['ers']:>14} {acc:>14} {entry.get('status', 'kept'):<16} "
              f"chain={entry.get('chain_status', '-')}")
    failed = sum(1 for e in runnable if e.get("chain_status") != "completed")
    if failed == len(runnable):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
