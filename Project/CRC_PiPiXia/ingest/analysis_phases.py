#!/usr/bin/env python3
"""Project-local Stage-1b analysis runner: phased, resource-capped, formal run.

Belongs to Project/CRC_PiPiXia/ingest/, NOT the main pipeline. Executes the
read-based chain over a dataset's published FASTQ (data/<run>.done required):

  Phase fastp       01_qc_fastp.sh            cap 8   (light)
  Phase kneaddata   02_qc_kneaddata.sh        cap 6   (~13 GB each)
  Phase pairrepair  02b_qc_pair_repair.sh     cap 8
  Phase metaphlan4  11_bac_metaphlan4.sh      cap 6
  Phase humann3     13_bac_humann3.sh         cap 6   (balanced formal mode)
  Phase kraken2     14_bac_kraken2.sh         cap 2   (77 GB DB per job)
  Phase merge       11b/13b/14b               serial

Failure semantics: any step that exits non-zero, times out, or leaves the
expected output missing marks the sample FAILED; failed samples are excluded
from all later phases. Merges run only when the success set equals the full
expected set; otherwise the run is recorded as INCOMPLETE and merges are
skipped (no silently partial matrices).

Every step's stdout/stderr goes to logs/scripts/<run>.<step>.log; wall time
and sampled peak RSS (process tree, KB) are recorded in logs/analysis.jsonl.
Frozen parameters (manifest hash, HUMAnN mode, per-run read-len, tool
versions) are written to manifests/analysis_manifest.json before launch.

Usage:
  python3 Project/CRC_PiPiXia/ingest/analysis_phases.py \
    --workdir Project/CRC_PiPiXia/PRJEB22893 \
    --manifest Project/CRC_PiPiXia/PRJEB22893/manifests/download_manifest_all25.json \
    --sample ERR2162205            # single-sample validation run
  python3 ... --samples-all        # all runs in the manifest
"""

import argparse
import gzip
import json
import math
import re
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE))
from run_project import jlog, read_length, now, REPO  # noqa: E402

ACTIVATE = REPO / "scripts" / "activate.sh"
SCRIPTS = REPO / "scripts"

CAPS = {"fastp": 8, "kneaddata": 6, "pairrepair": 8, "metaphlan4": 6,
        "humann3": 6, "kraken2": 2}
HUMANN_MODE = "balanced"
MAX_HOURS_DEFAULT = 36
# Bracken ships exact-length kmer_distrib indexes only; snap the measured
# read length down to the largest built index (db/kraken2/pluspf).
BRACKEN_LENGTHS = (50, 75, 100, 150, 200, 250, 300)


def snap_read_len(measured):
    fits = [l for l in BRACKEN_LENGTHS if l <= measured]
    return max(fits) if fits else 50


def tree_pids(root):
    """All live pids in the process tree rooted at root (inclusive)."""
    pids, stack = {root}, [root]
    while stack:
        pid = stack.pop()
        try:
            with open("/proc/%d/task/%d/children" % (pid, pid)) as fh:
                for child in fh.read().split():
                    c = int(child)
                    if c not in pids:
                        pids.add(c)
                        stack.append(c)
        except OSError:
            continue
    return pids


def tree_rss_kb(pids):
    total = 0
    for pid in pids:
        try:
            with open("/proc/%d/status" % pid) as fh:
                for line in fh:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
                        break
        except (OSError, ValueError):
            continue
    return total


def peak_rss_poll(proc, stop, result):
    """Sample the true process-tree RSS (KB) until the process exits.

    Walks /proc/<pid>/task/<pid>/children recursively — ps --ppid does not
    recurse and -N inverts the match, which polluted earlier samples with
    unrelated processes (log showed ~5.9 GB on 0.1 s idempotent skips)."""
    peak = 0
    while not stop.is_set():
        pids = tree_pids(proc.pid)
        if pids:
            try:
                peak = max(peak, tree_rss_kb(pids))
            except (OSError, ValueError):
                pass
        stop.wait(2.0)
    result["peak_kb"] = peak


LOCK_WAIT_MAX_S = 1800  # per-step total lock-wait ceiling before lock_timeout


def is_lock_contention(tail):
    """Strict match of the platform flock guard line: another instance holds
    this (workdir, step, sample) lock and refused double-launch. Matched only
    against bytes written by the CURRENT attempt (fresh log per attempt)."""
    return "已有实例在运行" in tail and "flock" in tail


def proc_pid_rss(pid):
    try:
        with open("/proc/%d/status" % pid) as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


HUMANN_LIB = REPO / "envs" / "humann4" / "lib"


def run_step(workdir, run, step, script, extra, threads, log):
    """Run one platform step with peak-RSS monitoring and lock-contention retry.

    Handoff rules baked in (2026-11-10, after the orphan+relay incidents):
    1. The platform scripts are idempotent and each holds a per-(workdir,
       step, sample) flock: if a previous instance is still running, the new
       one exits 65 with a [GUARD] line instead of double-running. We treat
       that as lock contention — wait, then retry (bounded) — never as a
       sample failure.
    2. Resume protocol: after ANY crash/kill, rerun the same command. Idempotency
       plus outputs_ok (existence + fastp .json + full gzip -t) make that safe.
       No external relay watchers: they raced on partially-written files.
    """
    logfile = workdir / "logs" / "scripts" / ("%s.%s.log" % (run, step))
    # preserve history: a previous attempt's (or a previous orchestrator's)
    # step log is rotated with a timestamp suffix instead of being truncated
    if logfile.exists():
        stamp = time.strftime("%Y%m%dT%H%M%S")
        logfile.rename(logfile.with_name("%s.%s.rotated.log" % (logfile.name, stamp)))
    # 02b_qc_pair_repair.sh takes -s/-w/-r only (mgx_parse exits 1 on unknown -t)
    threads_arg = "" if script == "02b_qc_pair_repair.sh" else " -t %d" % threads
    cmd = ["bash", "-c",
           "source %s && bash %s -s %s%s -w %s -r %s %s"
           % (ACTIVATE, SCRIPTS / script, run, threads_arg, workdir, REPO,
              " ".join(extra))]
    attempts = 3
    started = time.monotonic()
    peak_gb = 0.0
    lock_wait_total = 0.0
    for attempt in range(1, attempts + 1):
        # fresh log per attempt: the contention parse below must only ever see
        # bytes written by the current attempt, never a previous attempt's tail
        env = os.environ.copy()
        if script == "13_bac_humann3.sh":
            # migration casualty: envs/humann4/bin/glpsol carries an old-prefix
            # RPATH; humann's MinPath subprocesses need this to resolve libglpk
            env["LD_LIBRARY_PATH"] = (str(HUMANN_LIB) + ":"
                                      + env.get("LD_LIBRARY_PATH", ""))
        proc = subprocess.Popen(cmd, cwd=str(REPO), stdout=open(logfile, "w"),
                                stderr=subprocess.STDOUT, start_new_session=True,
                                env=env)
        stop, result = threading.Event(), {"peak_kb": 0}
        monitor = threading.Thread(target=peak_rss_poll, args=(proc, stop, result))
        monitor.start()
        try:
            code = proc.wait(timeout=remaining_seconds(workdir))
        except subprocess.TimeoutExpired:
            stop.set(); monitor.join()
            kill_tree(proc)
            jlog(log, run=run, step=step, status="timeout", attempt=attempt,
                 seconds=round(time.monotonic() - started, 1),
                 peak_gb=round(result["peak_kb"] / 1e6, 2), log=str(logfile))
            return False, 0, round(time.monotonic() - started, 1)
        stop.set(); monitor.join()
        peak_gb = max(peak_gb, round(result["peak_kb"] / 1e6, 2))
        if code == 0:
            break
        tail = ""
        try:
            tail = logfile.read_text(errors="replace")[-2000:]
        except OSError:
            pass
        if attempt < attempts and is_lock_contention(tail):
            # Another instance holds the per-sample lock (e.g. resumed while
            # an orphaned step was still finishing). Wait for it to release,
            # then retry: the step is idempotent and will skip-if-done.
            # Bounded: deadline (subprocess timeout) + LOCK_WAIT_MAX_S total;
            # exhaustion is recorded as lock_timeout, never masked as a plain
            # tool failure.
            if lock_wait_total + 120 > LOCK_WAIT_MAX_S:
                jlog(log, run=run, step=step, status="lock_timeout",
                     attempt=attempt, waited_s=round(lock_wait_total, 1),
                     log=str(logfile))
                return False, peak_gb, round(time.monotonic() - started, 1)
            lock_wait_total += 120
            jlog(log, run=run, step=step, status="lock_contention",
                 attempt=attempt, retry_after_s=120,
                 waited_s=round(lock_wait_total, 1), log=str(logfile))
            time.sleep(120)
            continue
        seconds = round(time.monotonic() - started, 1)
        jlog(log, run=run, step=step, status="failed", exit_code=code,
             attempt=attempt, seconds=seconds, peak_gb=peak_gb, log=str(logfile))
        return False, peak_gb, seconds
    seconds = round(time.monotonic() - started, 1)
    jlog(log, run=run, step=step, status="ok", attempt=attempt,
         seconds=seconds, peak_gb=peak_gb, log=str(logfile))
    return True, peak_gb, seconds


def kill_tree(proc):
    try:
        os.killpg(os.getpgid(proc.pid), 15)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), 9)
        except ProcessLookupError:
            pass


def expected_outputs(step, run, workdir):
    """Minimal non-empty artefacts that mark the step genuinely done."""
    r = workdir / "result"
    return {
        "fastp": [r / "fastp" / run / f"{run}_1.fastq.gz"],
        "kneaddata": [r / "kneaddata" / run / f"{run}_1.kneaddata_raw.fastq.gz"],
        "pairrepair": [r / "kneaddata" / run / f"{run}_1.kneaddata.fastq.gz"],
        "metaphlan4": [r / "metaphlan4" / run / f"{run}_profile.txt"],
        "humann3": [r / "humann3" / run / f"{run}_pathabundance_relab.tsv"],
        "kraken2": [r / "kraken2" / run / "bracken" / f"{run}_S.bracken"],
    }[step]


def outputs_ok(step, run, workdir):
    """Existence + non-empty + integrity + minimal per-step content semantics.
    Returns (bool, reason)."""
    paths = expected_outputs(step, run, workdir)
    if step == "fastp":
        paths = paths + [workdir / "result" / "fastp" / run / f"{run}.json"]
    for p in paths:
        if not p.exists():
            return False, f"missing {p.name}"
        if p.stat().st_size == 0:
            return False, f"empty {p.name}"
    for p in paths:
        if p.name.endswith(".fastq.gz") and not gzip_stream_ok(p):
            return False, f"gzip truncated {p.name}"
    r = workdir / "result"
    if step == "fastp":
        try:
            summary = json.loads((r / "fastp" / run / f"{run}.json").read_text())
            if "summary" not in summary:
                return False, "fastp json lacks summary"
        except (ValueError, OSError):
            return False, "fastp json unreadable"
    if step == "metaphlan4":
        text = (r / "metaphlan4" / run / f"{run}_profile.txt").read_text(errors="replace")
        if not any(line.startswith("k__") for line in text.splitlines()):
            return False, "metaphlan profile has no kingdom-level rows"
    if step == "humann3":
        text = (r / "humann3" / run / f"{run}_pathabundance_relab.tsv").read_text(errors="replace")
        if "UNMAPPED" not in text:
            return False, "humann relab lacks UNMAPPED control row"
    if step == "kraken2":
        bracken = (r / "kraken2" / run / "bracken" / f"{run}_S.bracken")
        lines = bracken.read_text(errors="replace").splitlines()
        if len(lines) < 2 or "name" not in lines[0]:
            return False, "bracken S table empty or wrong header"
    return True, ""


def gzip_stream_ok(path):
    try:
        return subprocess.run(["gzip", "-t", str(path)],
                              capture_output=True, timeout=600).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


PHASES = [
    ("fastp", "01_qc_fastp.sh", [], 8),
    ("kneaddata", "02_qc_kneaddata.sh", [], 16),
    ("pairrepair", "02b_qc_pair_repair.sh", [], 8),
    ("metaphlan4", "11_bac_metaphlan4.sh", [], 16),
    ("humann3", "13_bac_humann3.sh", ["--speed-mode", HUMANN_MODE], 16),
    ("kraken2", "14_bac_kraken2.sh", [], 16),
]


def run_phase(workdir, name, script, extra, base_threads, runs, log,
              read_lens, humann_mode):
    """One phase across runs; returns the set of samples that pass."""
    caps = {"humann3": 6, "kraken2": 2}.get(name, CAPS.get(name, 6))
    passed, peaks = set(), {}
    lock = threading.Lock()

    def one(run):
        step_threads = base_threads
        extra_args = list(extra)
        if name == "humann3":
            extra_args = ["--speed-mode", humann_mode]
        if name == "kraken2":
            extra_args = ["--read-len",
                          str((read_lens.get(run) or {}).get("bracken", 100))]
        run_ok, peak, _ = run_step(workdir, run, name, script, extra_args,
                                   step_threads, log)
        out_ok, reason = outputs_ok(name, run, workdir)
        # both gates must pass: a non-zero exit or timeout must never be
        # rescued by stale/left-over artefacts that happen to look valid
        ok = run_ok and out_ok
        with lock:
            if ok:
                passed.add(run)
                peaks[run] = peak
        if not run_ok:
            jlog(log, run=run, step=name, status="step_failed")
        elif not out_ok:
            jlog(log, run=run, step=name, status="outputs_invalid",
                 reason=reason)
        return ok

    with ThreadPoolExecutor(max_workers=caps) as pool:
        list(pool.map(one, sorted(runs)))
    jlog(log, step="phase", phase=name, passed=len(passed), of=len(runs),
         cap=caps, peak_gb_max=round(max(peaks.values()), 2) if peaks else 0)
    return passed


def tool_versions(workdir, log):
    """Probe versions through the same env prefixes the step scripts use
    (mgx_conda == conda run --prefix envs/<name>); bare PATH probes fail
    because activate.sh does not put tool envs on PATH."""
    probes = {
        "fastp": ("fastp", ["fastp", "--version"]),
        "kneaddata": ("kneaddata", ["kneaddata", "--version"]),
        "metaphlan4": ("humann4", ["metaphlan", "--version"]),
        "humann3": ("humann4", ["humann", "--version"]),
        "kraken2": ("kraken2", ["kraken2", "--version"]),
        "bracken": ("kraken2", ["bracken", "-v"]),
    }
    versions, codes = {}, {}
    for name, (env, cmd) in probes.items():
        prefix = REPO / "envs" / env
        try:
            proc = subprocess.run(
                [str(REPO / "miniforge3" / "bin" / "conda"), "run",
                 "--prefix", str(prefix), "--no-capture-output", *cmd],
                cwd=str(REPO), capture_output=True, text=True, timeout=180)
            lines = [l.strip() for l in (proc.stdout or "").splitlines()
                     + (proc.stderr or "").splitlines()
                     if l.strip() and "CSCCD-MetagenomeFlow" not in l]
            # version lines carry a dotted number; banners/copyrights may not
            version_lines = [l for l in lines if re.search(r"\d+\.\d+", l)]
            versions[name] = (version_lines or lines or ["unknown"])[-1][:80]
            codes[name] = {"env_prefix": str(prefix), "exit_code": proc.returncode}
        except (OSError, subprocess.SubprocessError) as exc:
            versions[name] = "unknown"
            codes[name] = {"env_prefix": str(prefix), "error": str(exc)[:120]}
    jlog(log, step="versions", probe_exit=codes,
         **{k: v for k, v in versions.items()})
    return versions, codes


def elf_preflight(workdir, log):
    """ldd every chain binary; any 'not found' (migration RPATH casualty,
    e.g. humann4/glpsol -> libglpk.so.36) blocks the run before compute."""
    binaries = [
        REPO / "envs/fastp/bin/fastp",
        REPO / "envs/kneaddata/bin/bowtie2",
        REPO / "envs/kneaddata/bin/kneaddata",
        REPO / "envs/humann4/bin/humann",
        REPO / "envs/humann4/bin/diamond",
        REPO / "envs/humann4/bin/glpsol",
        REPO / "envs/humann4/bin/bowtie2",
        REPO / "envs/kraken2/bin/kraken2",
        REPO / "envs/kraken2/bin/bracken",
    ]
    broken = []
    # ldd must see the same LD_LIBRARY_PATH the runtime step will inject,
    # otherwise the glpsol/libglpk migration casualty false-positives here
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = (str(HUMANN_LIB) + ":"
                              + env.get("LD_LIBRARY_PATH", ""))
    for b in binaries:
        if not b.exists():
            broken.append(f"{b.name}: missing")
            continue
        try:
            out = subprocess.run(["ldd", str(b)], capture_output=True,
                                 text=True, timeout=60, env=env).stdout
            if "not found" in out:
                missing = [l.split()[0] for l in out.splitlines()
                           if "not found" in l]
                broken.append(f"{b.name}: {', '.join(missing)}")
        except (OSError, subprocess.SubprocessError) as exc:
            broken.append(f"{b.name}: ldd failed {exc}")
    if broken:
        jlog(log, step="elf_preflight", status="BLOCKED", broken=broken)
        raise SystemExit("ELF dependency preflight failed: %s" % broken)
    jlog(log, step="elf_preflight", status="ok", binaries=len(binaries))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--sample", default="", help="single-run validation")
    parser.add_argument("--runs", default="",
                        help="explicit comma-separated subset (e.g. the 2-run small batch)")
    parser.add_argument("--samples-all", action="store_true",
                        help="run every run in the manifest")
    parser.add_argument("--threads", type=int, default=16)
    parser.add_argument("--max-hours", type=float, default=MAX_HOURS_DEFAULT)
    args = parser.parse_args()

    selections = sum(bool(x) for x in (args.sample, args.runs, args.samples_all))
    if selections != 1:
        parser.error("use exactly one of --sample / --runs / --samples-all")
    if not math.isfinite(args.max_hours) or args.max_hours <= 0:
        parser.error("--max-hours must be a finite positive number")
    import run_project
    run_project.DEADLINE = time.monotonic() + args.max_hours * 3600

    workdir = Path(args.workdir).resolve()
    if "Project01" in workdir.parts:
        raise SystemExit("refusing to write Project01")
    log = workdir / "logs" / "analysis.jsonl"
    (workdir / "logs" / "scripts").mkdir(parents=True, exist_ok=True)

    man = json.load(open(args.manifest))
    dataset = man["dataset"]
    expected = sorted(man["selected_runs"])
    runs = ([args.sample] if args.sample
            else [x.strip() for x in args.runs.split(",") if x.strip()]
            if args.runs else expected)
    if not set(runs) <= set(expected):
        raise SystemExit("requested runs are not in the manifest")

    read_lens = {}
    for run in runs:
        fq = workdir / "data" / (run + "_1.fastq.gz")
        rl = read_length(fq) if fq.exists() else 0
        measured = rl if 50 <= rl <= 300 else 150
        read_lens[run] = {"measured": measured,
                          "bracken": snap_read_len(measured)}
        if not (workdir / "data" / (run + ".done")).exists():
            raise SystemExit(f"{run} is not published in data/ (no .done)")

    import hashlib
    def sha256_file(path):
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    code_hashes = {
        "analysis_phases.py": sha256_file(Path(__file__).resolve()),
        "run_project.py": sha256_file(HERE / "run_project.py"),
        "run_tables.py": sha256_file(HERE / "run_tables.py"),
    }
    versions, codes = tool_versions(workdir, log)
    # hard gate (P0): a broken env must block the formal run, never degrade
    # to "command not found but phases look green". Both the version string
    # and the probe exit code are checked; a non-zero probe (or a probe that
    # died on an exception) blocks even if a version-like string was printed.
    broken = {}
    for k, v in versions.items():
        probe = codes.get(k, {})
        if v == "unknown" or "not found" in v or "bash:" in v:
            broken[k] = {"version": v, "probe": probe}
        elif probe.get("exit_code", 1) != 0 or "error" in probe:
            broken[k] = {"version": v, "probe": probe}
    if broken:
        jlog(log, step="versions", status="BLOCKED", broken=broken)
        raise SystemExit("tool version probe failed: %s" % broken)

    manifest = {
        "dataset": dataset,
        "generated_at": now(),
        "download_manifest": str(Path(args.manifest).resolve()),
        "download_manifest_sha256": __import__("hashlib").sha256(
            Path(args.manifest).read_bytes()).hexdigest(),
        "humann_mode": HUMANN_MODE,
        "caps": {"humann3": 6, "kraken2": 2, "default": 6},
        "read_len": read_lens,
        "runs": runs,
        "tool_versions": versions,
        "tool_version_exit_codes": codes,
        "code_hashes": code_hashes,
    }

    (workdir / "manifests" / "analysis_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    jlog(log, step="analysis_start", dataset=dataset, runs=len(runs),
         mode=HUMANN_MODE, read_len={k: v["bracken"] for k, v in read_lens.items()})
    elf_preflight(workdir, log)

    alive = set(runs)
    peak_max = 0.0
    for name, script, extra, base_threads in PHASES:
        if not alive:
            break
        passed = run_phase(workdir, name, script, extra, base_threads,
                           alive, log, read_lens, HUMANN_MODE)
        alive &= passed
        failed = sorted(set(runs) - alive)
        if failed:
            jlog(log, step="failures_after_phase", phase=name, failed=failed)

    (workdir / "manifests" / "analysis_result.json").write_text(json.dumps({
        "run_id": time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()),
        "dataset": dataset, "finished_at": now(),
        "analysis_manifest_sha256": __import__("hashlib").sha256(
            (workdir / "manifests" / "analysis_manifest.json").read_bytes()).hexdigest(),
        "code_hashes": code_hashes,
        "requested": sorted(runs), "succeeded": sorted(alive),
        "failed": sorted(set(runs) - alive),
        "complete": len(alive) == len(runs),
    }, indent=2, ensure_ascii=False) + "\n")

    if args.sample:
        print("VALIDATION DONE:", args.sample, "ok" if alive else "FAILED")
        return 0 if alive else 1
    if len(alive) != len(runs):
        jlog(log, step="analysis", status="INCOMPLETE",
             failed=sorted(set(runs) - alive))
        print("INCOMPLETE:", len(alive), "/", len(runs))
        return 1

    # merges only on a complete success set
    for script in ("11b_bac_metaphlan4_merge.sh", "13b_bac_humann3_merge.sh",
                   "14b_bac_kraken2_merge.sh"):
        code = run_script_merge(script, workdir)
        jlog(log, step=script, status="ok" if code == 0 else "failed",
             exit_code=code)
        if code != 0:
            raise SystemExit("merge failed: " + script)
    jlog(log, step="analysis", status="COMPLETE", samples=len(runs))
    print("COMPLETE:", len(runs), "samples in", workdir)
    return 0


def run_script_merge(script, workdir):
    cmd = ["bash", "-c", "source %s && bash %s -w %s -r %s"
           % (ACTIVATE, SCRIPTS / script, workdir, REPO)]
    proc = subprocess.Popen(cmd, cwd=str(REPO),
                            stdout=open(workdir / "logs" / "scripts"
                                        / ("ALL.%s.log" % script), "w"),
                            stderr=subprocess.STDOUT, start_new_session=True)
    return proc.wait()


def remaining_seconds(workdir):
    # delegate to run_project's deadline if set, else unbounded
    try:
        import run_project
        return run_project.remaining_seconds()
    except SystemExit:
        raise
    except Exception:
        return None


if __name__ == "__main__":
    sys.exit(main())
