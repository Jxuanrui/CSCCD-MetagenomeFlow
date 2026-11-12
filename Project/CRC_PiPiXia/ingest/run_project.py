#!/usr/bin/env python3
"""Project-local download orchestrator (Stage 1b Phase A).

This file belongs to the CRC_PiPiXia project (Project/CRC_PiPiXia/ingest/),
NOT to the main pipeline. The read-based ANALYSIS chain lives exclusively in
analysis_phases.py (phased, resource-capped, integrity-gated); this file only
downloads and publishes verified FASTQ. It never touches scripts/, pipeline/, db/ or
Project/Project01/. Downloads default to the audited manifest URLs: Aspera via
the iSeq environment's ascp bundle, with curl as the explicit fallback; the
iSeq accession CLI is an optional non-default backend because it re-queries
ENA. Only reads whose ENA library_strategy is WGS are accepted; AMPLICON is
rejected.

Usage:
  python3 Project/CRC_PiPiXia/ingest/run_project.py \
    --table <xlsx> --workdir Project/CRC_PiPiXia/PRJEB22893 \
    --runs ERR2162205,ERR2162213 --threads 16 --parallel 4

  # Download-only by design: the analysis phase runs exclusively through
  # analysis_phases.py (phased, resource-capped, integrity-gated). This file
  # never invokes platform analysis scripts.
"""

import argparse
import gzip
import hashlib
import json
import math
import os
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE))
import run_tables as rt  # noqa: E402  (same project ingest tool)

ISEQ_BIN = HERE / "envs" / "iseq" / "bin"
# IBM Aspera Connect 4.2.19 (ascp 4.4.7): the only build whose anonymous-key
# authentication ENA currently accepts; the older ascp 4.4.2 in envs/iseq
# fails with "failed to authenticate" using the same key.
CONNECT_DIR = HERE / "tools" / ".aspera" / "connect"
ASCP_BIN = CONNECT_DIR / "bin" / "ascp"
ASCP_KEY = CONNECT_DIR / "etc" / "aspera_bypass_rsa.pem"
MIN_FREE_GB = 50
DISK_HEADROOM = 1.5
DEADLINE = None


def remaining_seconds():
    """Wall-clock budget for downloads and analysis (None = unbounded)."""
    if DEADLINE is None:
        return None
    left = DEADLINE - time.monotonic()
    if left <= 0:
        raise SystemExit("wall-clock limit exceeded")
    return left


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def jlog(path, **record):
    record = {"ts": now(), **record}
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    print("[%s] %s" % (record["ts"], json.dumps(record, ensure_ascii=False)),
          flush=True)


def run_process(cmd, timeout=None, env=None, cwd=None, log_path=None):
    """Run one command in its own process group; kill the whole group on timeout."""
    budget = remaining_seconds() if timeout is None else timeout
    if budget is not None and budget <= 0:
        raise SystemExit("wall-clock limit exceeded")
    fh = open(log_path, "w", encoding="utf-8") if log_path else subprocess.DEVNULL
    try:
        proc = subprocess.Popen(cmd, env=env, cwd=cwd, stdout=fh,
                                stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return proc.wait(timeout=budget)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
            return 124
    finally:
        if log_path:
            fh.close()


def copy_with_deadline(src, dest):
    with open(src, "rb") as fin, open(dest, "wb") as fout:
        while True:
            remaining_seconds()
            chunk = fin.read(8 << 20)
            if not chunk:
                break
            fout.write(chunk)
        fout.flush()
        os.fsync(fout.fileno())


def md5_of(path):
    digest = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(8 << 20), b""):
            remaining_seconds()
            digest.update(chunk)
    return digest.hexdigest()


def gzip_ok(path):
    """Full gzip stream/CRC check (not just the first chunk)."""
    try:
        return run_process(["gzip", "-t", str(path)],
                           timeout=remaining_seconds()) == 0
    except (OSError, subprocess.SubprocessError):
        return False


def read_length(fastq):
    with gzip.open(fastq, "rt", errors="replace") as fh:
        for _ in range(4):
            line = fh.readline()
    line = line.strip()
    return len(line) if line else 0


def get_details(table):
    """Verify the whole table against ENA and return per-run download details."""
    dataset = rt.parse_table(table)
    if dataset["status"] != "READY":
        raise SystemExit("table is not locally READY: %s" % dataset["blockers"])
    verification = rt.verify_dataset(dataset)
    if verification["verify_status"] != "VERIFIED":
        raise SystemExit("ENA verification is not VERIFIED: %s %s"
                         % (verification["verify_status"],
                            verification["verify_blockers"]))
    study = dataset["dataset_id"]
    payload = rt._http_fetch_json(rt._ena_url(study))
    if not isinstance(payload, list):
        raise SystemExit("invalid ENA response for %s" % study)
    entries = {}
    for entry in payload:
        run = str(entry.get("run_accession") or "").strip()
        if run:
            entries[run] = entry
    expected = list(dataset["expected_runs"])
    missing = [run for run in expected if run not in entries]
    if missing:
        raise SystemExit("expected runs missing from ENA: %s" % missing[:10])
    details = {}
    for run in expected:
        entry = entries[run]
        problems = rt._verify_run_fields(entry)
        if problems:
            raise SystemExit("run %s has field problems: %s" % (run, problems))
        urls = [u.strip() for u in str(entry.get("fastq_ftp") or "").split(";")
                if u.strip()]
        md5s = [m.strip() for m in str(entry.get("fastq_md5") or "").split(";")
                if m.strip()]
        sizes = [int(x) for x in str(entry.get("fastq_bytes") or "").split(";")
                 if x.strip().isdigit()]
        if len(urls) != 2 or len(md5s) != 2 or len(sizes) != 2:
            raise SystemExit("run %s lacks two FASTQ/URL/MD5/byte entries" % run)
        details[run] = {
            "run": run,
            "strategy": str(entry.get("library_strategy") or ""),
            "layout": str(entry.get("library_layout") or ""),
            "urls": [url if "://" in url else "https://" + url for url in urls],
            "md5s": md5s,
            "sizes": sizes,
        }
    amplicon = [run for run, item in details.items()
                if item["strategy"] != "WGS"]
    if amplicon:
        raise SystemExit("non-WGS runs must not be analyzed: %s" % amplicon[:10])
    return dataset, details


def load_manifest(path):
    """Load a previously audited manifest as the locked execution input."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    expected = list(data.get("expected_runs") or [])
    selected = list(data.get("selected_runs") or [])
    details = data.get("runs") or {}
    if not expected or not selected:
        raise SystemExit("manifest has no expected/selected runs")
    if len(expected) != len(set(expected)) or len(selected) != len(set(selected)):
        raise SystemExit("manifest contains duplicate run accessions")
    if not set(selected) <= set(expected):
        raise SystemExit("manifest selected_runs are not a subset of expected_runs")
    if set(selected) != set(details):
        raise SystemExit("manifest runs do not match selected_runs")
    if not rt.PRJ_RE.fullmatch(str(data.get("dataset") or "")):
        raise SystemExit("manifest dataset is not a PRJ accession")
    total = 0
    for run in selected:
        item = details[run]
        if item.get("strategy") != "WGS" or item.get("layout") != "PAIRED":
            raise SystemExit("manifest run %s is not WGS/PAIRED" % run)
        urls = item.get("urls")
        md5s = item.get("md5s")
        sizes = item.get("sizes")
        if not isinstance(urls, list) or not isinstance(md5s, list) \
                or not isinstance(sizes, list):
            raise SystemExit("manifest run %s has non-list fields" % run)
        if len(urls) != 2 or len(md5s) != 2 or len(sizes) != 2:
            raise SystemExit("manifest run %s lacks two files" % run)
        if any(not rt._valid_fastq_url(url) for url in urls):
            raise SystemExit("manifest run %s has an invalid FASTQ URL" % run)
        if any(not rt.MD5_RE.match(str(value)) for value in md5s):
            raise SystemExit("manifest run %s has an invalid MD5" % run)
        for size in sizes:
            if isinstance(size, bool) or not isinstance(size, int) or not (0 < size <= 10**13):
                raise SystemExit("manifest run %s has an invalid size" % run)
        total += sum(sizes)
    if "selected_bytes" in data and int(data["selected_bytes"]) != total:
        raise SystemExit("manifest selected_bytes does not equal the size sum")
    dataset = {"dataset_id": data["dataset"],
               "status": "READY", "expected_runs": expected}
    return dataset, details, selected


def disk_gate(workdir, selected, details):
    need = sum(sum(details[run]["sizes"]) for run in selected)
    free = shutil.disk_usage(str(workdir)).free
    required = int(need * DISK_HEADROOM + MIN_FREE_GB * 1e9)
    if free < required:
        raise SystemExit("insufficient disk: free=%d required=%d" % (free, required))
    return need, free, required


def iseq_env():
    env = os.environ.copy()
    env["PATH"] = str(ISEQ_BIN) + ":" + env.get("PATH", "")
    return env


def iseq_version(log_dir):
    logfile = log_dir / "iseq_version.log"
    try:
        budget = remaining_seconds()
        budget = 30 if budget is None else min(30, budget)
        code = run_process([str(ISEQ_BIN / "iseq"), "--version"],
                           timeout=budget, env=iseq_env(), log_path=str(logfile))
        if code != 0:
            return "unavailable"
        text = [line.strip() for line in logfile.read_text().splitlines() if line.strip()]
        return text[-1] if text else "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unavailable"


def find_iseq_files(run, root):
    """Find iSeq <run>_1/_2.fastq.gz under its output tree."""
    found = []
    for path in root.rglob("*.fastq.gz"):
        name = path.name
        if name in (run + "_1.fastq.gz", run + "_2.fastq.gz"):
            found.append(path)
    return {p.name: p for p in found}


def publish(run, files, data_dir, details, log):
    """Validate size/MD5/gzip, then atomically expose data/<run>_1/_2."""
    data_dir.mkdir(parents=True, exist_ok=True)
    done = data_dir / (run + ".done")
    done.unlink(missing_ok=True)  # a stale marker must never survive a retry
    ordered = []
    for idx in (1, 2):
        src = files.get(run + "_%d.fastq.gz" % idx)
        if src is None:
            return False
        dest = data_dir / ("%s_%d.fastq.gz" % (run, idx))
        expected_size = details[run]["sizes"][idx - 1]
        expected_md5 = details[run]["md5s"][idx - 1]
        if (dest.exists() and dest.stat().st_size == expected_size
                and md5_of(dest) == expected_md5 and gzip_ok(dest)):
            ordered.append(dest)
            continue
        if src.stat().st_size != expected_size:
            jlog(log, run=run, step="publish", status="size_mismatch",
                 file=src.name, got=src.stat().st_size, expected=expected_size)
            return False
        if md5_of(src) != expected_md5 or not gzip_ok(src):
            jlog(log, run=run, step="publish", status="integrity_failed",
                 file=src.name)
            return False
        tmp = dest.with_suffix(dest.suffix + ".tmp")
        copy_with_deadline(src, tmp)
        tmp.replace(dest)
        ordered.append(dest)
    done.write_text(now() + "\n")
    jlog(log, run=run, step="download", status="done",
         bytes=sum(p.stat().st_size for p in ordered))
    return True


def curl_download(run, details, data_dir, log):
    env = os.environ.copy()
    done = data_dir / (run + ".done")
    done.unlink(missing_ok=True)
    for idx, (url, md5, size) in enumerate(zip(details[run]["urls"],
                                               details[run]["md5s"],
                                               details[run]["sizes"]), start=1):
        dest = data_dir / ("%s_%d.fastq.gz" % (run, idx))
        if (dest.exists() and dest.stat().st_size == size
                and md5_of(dest) == md5 and gzip_ok(dest)):
            continue
        part = dest.with_suffix(dest.suffix + ".part")
        cmd = ["curl", "-sSfL", "--continue-at", "-", "--retry", "5",
               "--retry-delay", "10", "--retry-all-errors",
               "--connect-timeout", "60", "-o", str(part), url]
        code = run_process(cmd, timeout=remaining_seconds(), env=env)
        if code == 124:
            jlog(log, run=run, step="curl", status="timeout", file=dest.name)
            return False
        if code != 0 or not part.exists():
            jlog(log, run=run, step="curl", status="failed", file=dest.name,
                 exit_code=code)
            return False
        if part.stat().st_size != size or md5_of(part) != md5 or not gzip_ok(part):
            jlog(log, run=run, step="curl", status="integrity_failed",
                 file=dest.name)
            part.unlink(missing_ok=True)
            return False
        part.replace(dest)
        jlog(log, run=run, step="curl", status="done", file=dest.name,
             bytes=size)
    done.write_text(now() + "\n")
    return True


def aspera_src(url):
    """Manifest ENA HTTPS/FTP URL -> era-fasp ENA Aspera source."""
    parsed = urllib.parse.urlsplit(url if "://" in url else "https://" + url)
    if parsed.netloc.lower() != "ftp.sra.ebi.ac.uk":
        raise SystemExit("unexpected FASTQ host in manifest: %s" % parsed.netloc)
    return "era-fasp@fasp.sra.ebi.ac.uk:" + parsed.path


def aspera_fetch(run, details, dl_dir, log):
    """Locked-URL Aspera transfer with IBM Aspera Connect's ascp 4.4.7."""
    ascp, key = ASCP_BIN, ASCP_KEY
    if not ascp.exists() or not key.exists():
        jlog(log, run=run, step="aspera", status="unavailable",
             ascp=str(ascp), key=str(key))
        return False
    for url in details[run]["urls"]:
        logfile = log.parent / ("ascp_%s_%s.log" % (run, Path(url).name))
        code = run_process(
            [str(ascp), "-P", "33001", "-i", str(key), "-QT",
             "-l", "1000M", "-k1", "-d", aspera_src(url), str(dl_dir)],
            timeout=remaining_seconds(), log_path=str(logfile))
        if code != 0:
            jlog(log, run=run, step="aspera", status="failed", exit_code=code,
                 file=Path(url).name, log=str(logfile))
            return False
    return True


def published_ok(run, data_dir, details):
    """Resume guard: a run counts as done only if both FASTQs exist AND match
    the manifest size AND md5 AND pass a full gzip stream check — a truncated
    or replaced file must never ride the .done fast-path."""
    for idx, (md5, size) in enumerate(zip(details[run]["md5s"],
                                          details[run]["sizes"]), start=1):
        p = data_dir / ("%s_%d.fastq.gz" % (run, idx))
        if not p.exists() or p.stat().st_size != size:
            return False
        if md5_of(p) != md5 or not gzip_ok(p):
            return False
    return True


def download(selected, details, workdir, parallel, log, backend="locked-aspera"):
    data_dir, dl_dir = workdir / "data", workdir / "downloads"
    data_dir.mkdir(parents=True, exist_ok=True)
    dl_dir.mkdir(parents=True, exist_ok=True)
    runlist = workdir / "manifests" / "selected_runs.txt"
    runlist.parent.mkdir(parents=True, exist_ok=True)
    runlist.write_text("\n".join(selected) + "\n")

    if backend in ("locked-aspera", "locked-curl"):
        # Locked manifest URLs only: Aspera (Connect ascp 4.4.7) or curl.
        ok = []
        for run in selected:
            # Idempotent resume: a run already published with a valid .done
            # and intact verified files is never re-downloaded.
            done = data_dir / (run + ".done")
            if done.exists():
                verified = published_ok(run, data_dir, details)
                if verified:
                    jlog(log, run=run, step="download", status="already_done")
                    ok.append(run)
                    continue
            if backend == "locked-aspera" and aspera_fetch(run, details, dl_dir, log):
                if publish(run, find_iseq_files(run, dl_dir),
                           data_dir, details, log):
                    ok.append(run)
                    continue
            if curl_download(run, details, data_dir, log):
                ok.append(run)
            else:
                jlog(log, run=run, step="download", status="FAILED",
                     backend=backend)
        return ok

    # Optional iSeq accession mode (not the default; re-queries ENA).
    for label, extra in (("iseq_aspera", ["-a", "-g"]),
                         ("iseq_https", ["-g", "-r", "https"])):
        cmd = [str(ISEQ_BIN / "iseq"), "-i", str(runlist), *extra,
               "-p", str(parallel), "-o", str(dl_dir), "-Q"]
        logfile = workdir / "logs" / ("iseq_%s.log" % label)
        jlog(log, step="iseq", status="start", method=label)
        started = time.monotonic()
        code = run_process(cmd, timeout=remaining_seconds(), env=iseq_env(),
                           log_path=logfile)
        if code == 124:
            jlog(log, step="iseq", status="timeout", method=label,
                 seconds=round(time.monotonic() - started, 1))
            raise SystemExit("wall-clock limit exceeded during iSeq")
        jlog(log, step="iseq", status="end", method=label,
             exit_code=code, seconds=round(time.monotonic() - started, 1),
             log=str(logfile))
        if code == 0:
            break

    ok = []
    for run in selected:
        files = find_iseq_files(run, dl_dir)
        if publish(run, files, data_dir, details, log):
            ok.append(run)
        elif curl_download(run, details, data_dir, log):
            ok.append(run)
        else:
            jlog(log, run=run, step="download", status="FAILED",
                 backend=backend)
    return ok


def write_samplesheet(selected, workdir):
    path = workdir / "samplesheet.csv"
    with open(path, "w", newline="", encoding="utf-8") as fh:
        fh.write("sample_id,r1,r2,host_type,project_dir\n")
        for run in selected:
            fh.write("%s,%s,%s,human,%s\n" % (
                run, workdir / "data" / (run + "_1.fastq.gz"),
                workdir / "data" / (run + "_2.fastq.gz"), workdir))
    (workdir / "metadata.csv").write_text(
        "sample_id,dataset,group\n" + "".join(
            "%s,%s,\n" % (run, workdir.name) for run in selected),
        encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--runs", default="",
                        help="explicit comma-separated subset; required unless --manifest is used")
    parser.add_argument("--manifest", default="",
                        help="locked audited manifest; execution reads only it and does not rebuild")
    parser.add_argument("--parallel", type=int, default=4)
    parser.add_argument("--download-backend",
                        choices=("locked-aspera", "locked-curl", "iseq"),
                        default="locked-aspera",
                        help="locked-aspera (default), locked-curl, or optional iSeq accession mode")
    parser.add_argument("--dry-run", action="store_true",
                        help="read-only ENA metadata query, write the audited manifest, "
                             "and exit without downloading FASTQ")
    parser.add_argument("--max-hours", type=float, default=12,
                        help="hard wall-clock budget for downloads + analysis (default 12)")
    args = parser.parse_args(argv)
    if not math.isfinite(args.max_hours) or args.max_hours <= 0:
        parser.error("--max-hours must be a finite positive number")
    if args.manifest and args.runs:
        parser.error("--manifest and --runs are mutually exclusive")
    if not args.manifest and not args.runs:
        parser.error("execution requires explicit --runs or a locked --manifest")
    if args.manifest and args.download_backend == "iseq":
        parser.error("--manifest cannot use the iseq accession backend; use locked-aspera or locked-curl")
    global DEADLINE
    DEADLINE = time.monotonic() + args.max_hours * 3600

    workdir = Path(args.workdir).resolve()
    if "Project01" in workdir.parts:
        raise SystemExit("refusing to write Project01")
    for sub in ("data", "downloads", "logs/scripts", "manifests", "temp", "result"):
        (workdir / sub).mkdir(parents=True, exist_ok=True)
    log = workdir / "logs" / "ingest.jsonl"

    if args.manifest:
        dataset, details, selected = load_manifest(args.manifest)
        expected = list(dataset["expected_runs"])
        manifest_path = Path(args.manifest).resolve()
    else:
        dataset, details = get_details(args.table)
        expected = list(dataset["expected_runs"])
        selected = [x.strip() for x in args.runs.split(",") if x.strip()]
        if not set(selected) <= set(expected):
            raise SystemExit("selected runs are not in the table whitelist")
        manifest_path = workdir / "manifests" / "download_manifest.json"
    need, free, required = disk_gate(workdir, selected, details)
    manifest = {
        "dataset": dataset["dataset_id"],
        "generated_at": now(),
        "table": str(Path(args.table).resolve()),
        "iseq_version": iseq_version(workdir / "logs"),
        "download_backend": args.download_backend,
        "expected_runs": expected,
        "selected_runs": selected,
        "selected_bytes": need,
        "runs": {run: details[run] for run in selected},
    }
    if not args.manifest:
        manifest_path.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8")
    jlog(log, step="preflight", status="ok", dataset=dataset["dataset_id"],
         expected=len(expected), selected=len(selected), bytes=need,
         free=free, required=required, manifest=str(manifest_path))
    if args.dry_run:
        print("DRY-RUN manifest:", manifest_path)
        return 0

    write_samplesheet(selected, workdir)
    ok = download(selected, details, workdir, args.parallel, log,
                  backend=args.download_backend)
    if len(ok) != len(selected):
        raise SystemExit("download incomplete: %d/%d" % (len(ok), len(selected)))

    # Every selected run is now published in data/ (size+MD5+gzip verified and
    # .done written), so the Aspera staging area is redundant: delete it per
    # user rule "once a dataset finishes downloading, remove downloads/".
    dl_dir = workdir / "downloads"
    freed = 0
    if dl_dir.exists():
        if dl_dir.parent != workdir or dl_dir.name != "downloads":
            raise SystemExit("refusing to remove unexpected staging path: %s" % dl_dir)
        freed = sum(p.stat().st_size for p in dl_dir.rglob("*") if p.is_file())
        shutil.rmtree(dl_dir)
        if dl_dir.exists():  # post-delete verification, never silent
            raise SystemExit("downloads removal failed: %s still exists" % dl_dir)
        jlog(log, step="cleanup", status="downloads_removed",
             bytes=freed, verified=True)

    print("DONE:", len(selected), "samples in", workdir)


if __name__ == "__main__":
    sys.exit(main())
