#!/usr/bin/env python3
"""Project-local download orchestrator (Stage 1b Phase A).

This file belongs to the CRC_PiPiXia project (Project/CRC_PiPiXia/ingest/),
NOT to the main pipeline. The read-based ANALYSIS chain lives exclusively in
analysis_phases.py (phased, resource-capped, integrity-gated); this file only
downloads and publishes verified FASTQ. It never touches scripts/, pipeline/, db/ or
Project/Project01/. Downloads use the audited manifest URLs and default to
locked-aria2 (aria2c, 8 segmented HTTPS connections); locked-aspera and
locked-curl remain selectable, and the iSeq accession CLI stays a non-default
backend because it re-queries ENA instead of honouring the locked manifest.
The default was switched from locked-aspera on 2026-11-14 with the user's
explicit approval, after the A/B pilot cleared the publish gate (§28) and
ascp measured 2.5-3.1 MB/s against aria2c's 37-46 MB/s fast phase (§27.1).
Only reads whose ENA library_strategy is WGS are accepted; AMPLICON is
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
import concurrent.futures
import fcntl
import gzip
import hashlib
import json
import math
import os
import queue
import re
import shutil
import threading
import signal
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

# Reusable per-dataset download benchmark (user request: try every available
# download method per dataset, keep the fastest fitting one). Kept as a sibling
# module so the logic is shared, not duplicated inside this orchestrator.
import download_benchmark as bench  # noqa: E402

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE))
import run_tables as rt  # noqa: E402  (same project ingest tool)

ISEQ_BIN = HERE / "envs" / "iseq" / "bin"
# IBM Aspera Transfer SDK (ascp 4.4.8.2592), the installation the user tested
# and documented in "Aspera 启动与使用说明.md". The earlier attempt used the
# Connect 4.2.19 build (ascp 4.4.7) with a "-d" flag and "-l 1000M"; that is not
# the documented invocation. Correct form (tutorial §5/§13):
#   ascp -QT -k1 -l 300m -P 33001 -i <key> era-fasp@fasp.sra.ebi.ac.uk:<path> <dir>
ASCP_BIN = Path("/home/admin-user/.aspera/sdk/ascp")
ASCP_KEY = Path("/home/admin-user/.aspera/sdk/aspera_bypass_rsa.pem")
ASCP_RATE = "300m"
# Symlink into this project's ingest/envs/ -> platform envs/dram/bin/aria2c,
# so the project does not reach into a shared conda prefix directly.
ARIA2_BIN = HERE / "envs" / "aria2c"
ARIA2_CA_DEFAULT = "/etc/ssl/certs/ca-certificates.crt"
# Low-throughput watchdog (see run_monitored): a collapse to ~120 KB/s on a
# 62 MB/s-capable link must not burn an hour per file.
ARIA2_MIN_BPS = 400_000
# Politeness budget. EBI's download service refused EVERY connection on
# 2026-11-15 after an overnight run opened 8 workers x 8 segments and restarted
# 540 times; www.ebi.ac.uk and NCBI stayed reachable in the same minute, so this
# was an IP-level block from ftp.sra.ebi.ac.uk, not a route failure.
ARIA2_CONNECTIONS = 4
ARIA2_BLOCK_STREAK = 5        # consecutive refused connects before backing off
ARIA2_BLOCK_SLEEP_S = 1800    # long pause: hammering extends the block
ARIA2_STALL_WINDOW_S = 90
ARIA2_MAX_RESTARTS = 8
# Optional HTTP proxy passthrough (supervisor 2026-11-22 P0: the VPN download
# path moved inside the audited runner, so the bash loop is gone). Empty string
# means direct connection, exactly the pre-2026-11-22 behaviour.
PROXY = ""
# Echo aria2's native progress lines to the terminal while STILL writing the
# complete per-file logfile (user request 2026-11-23: they want the transfer
# progress visible live in their terminal; the monitor keeps reading the
# logfile, so completeness there is non-negotiable).
PROGRESS_ECHO = False
# Runs whose --progress pump hard-failed (timeout or logfile-write error) in
# this execution. Queue level (supervisor P0, 2026-11-23 round 3): such a run
# is refused at aria2_download entry and filtered out of every retry pass, so
# a still-alive old pump can never race a fresh attempt on the same logfile
# and the run can never publish here. A later process (--manifest rerun)
# starts with an empty set and resumes from .part/.aria2.
_PUMP_BROKEN_RUNS = set()
# Terminal echo is best-effort: dedicated daemon writers consume bounded
# queues for BOTH stdout and stderr, so a blocked/broken terminal can never
# stall the log-draining pump OR the download control flow (jlog, hard-fail
# notices) — supervisors P0, 2026-11-23 rounds 3-4. Overflow is dropped from
# the display only; the logfile (and jsonl audit) stays authoritative.
_WRITERS = {}
_STREAM_STATE = {"out": True, "err": True}


def _stream_writer(name):
    q = _WRITERS[name]
    while True:
        text = q.get()
        if not _STREAM_STATE[name]:
            continue
        # resolve the stream at write time: tests (and redirects) may swap
        # sys.stdout mid-process, and each line must go where stdout NOW is
        stream = sys.stdout if name == "out" else sys.stderr
        try:
            stream.write(text)
            stream.flush()
        except Exception:
            _STREAM_STATE[name] = False
            if name == "out":
                _emit("err", "run_project: --progress terminal echo disabled "
                             "(stdout unusable); download continues, the "
                             "logfile stays authoritative\n")


def _ensure_writer(name):
    if name not in _WRITERS:
        q = queue.Queue(maxsize=4096)
        _WRITERS[name] = q
        threading.Thread(target=_stream_writer, args=(name,), daemon=True).start()
    return _WRITERS[name]


def _emit(name, text):
    """Non-blocking console emit: never blocks, never raises (supervisor P0:
    a permanently blocked stdout must not hang download control flow)."""
    try:
        q = _ensure_writer(name)
        q.put_nowait(text)
    except Exception:
        pass  # display overflow/closed: the logfile/jsonl stay authoritative


def _drain_streams(timeout_s=15):
    """Test/shutdown helper: wait until both display queues are drained."""
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if all(q.empty() for q in _WRITERS.values()):
            time.sleep(0.2)  # let the writer take the last items
            return
        time.sleep(0.05)
# Burst cycling: measured 2026-11-14, the route hands ~370 MB at 37-46 MB/s and
# then collapses to 1-2 MB/s inside the SAME transfer, while a fresh aria2c
# repeatedly re-enters the fast phase (five back-to-back probes each fetched
# ~371 MB at 46 MB/s). Re-opening the connections after this many bytes keeps
# the transfer in the fast phase; resume makes the cycle lossless.
# Live aria2c children spawned by this process's own worker threads. The
# startup sweep must never kill these (it exists to clean up LEAKED processes
# from a previously killed orchestrator, not to fight itself).
_worker_procs = set()
# Consecutive "connection refused" replies from the download host. EBI refused
# every connection on 2026-11-15 (www.ebi.ac.uk and NCBI stayed up) after an
# overnight run opened 64 sockets and restarted 540 times. Once the streak hits
# ARIA2_BLOCK_STREAK the queue stops attempting and waits a long time, because
# every extra attempt extends the block.
_refusal_streak = 0
ARIA2_BURST_BYTES = 340 * 1024 * 1024
ARIA2_MAX_BURST_CYCLES = 400
ARIA2_PASSES = 3          # whole-queue passes before the curl last resort
CURL_LAST_RESORT_S = 600  # per-file cap for the single-connection last resort
RETRY_BACKOFF_S = 300      # pause between whole-queue passes (let a throttle expire)
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
    # Audit logging is best-effort for CONTROL FLOW: a broken stdout (the
    # --progress echo case) must never crash the download or the hard-fail
    # propagation paths (supervisor P0, 2026-11-23 round 3). The jsonl file
    # write stays first; if even that fails we say so on stderr once per call
    # site and move on.
    record = {"ts": now(), **record}
    line = json.dumps(record, ensure_ascii=False)
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError as exc:
        _emit("err", "run_project: jlog file write failed (%s): %s\n"
              % (path, exc))
    _emit("out", "[%s] %s\n" % (record["ts"], line))


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
        if integrity_ok(dest, expected_size, expected_md5):
            ordered.append(dest)
            continue
        if src.stat().st_size != expected_size:
            jlog(log, run=run, step="publish", status="size_mismatch",
                 file=src.name, got=src.stat().st_size, expected=expected_size)
            return False
        if not integrity_ok(src, expected_size, expected_md5):
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


def http_url(url):
    """ENA's filereport emits host-relative URLs ("ftp.sra.ebi.ac.uk/vol1/...",
    no scheme). curl would resolve that as a local path and aria2c rejects it
    outright, so both backends must normalise first. The host allow-list is
    re-checked here, so normalisation can never be steered at another host."""
    parsed = urllib.parse.urlsplit(url if "://" in url else "https://" + url)
    if parsed.netloc.lower() != "ftp.sra.ebi.ac.uk":
        raise SystemExit("unexpected FASTQ host in manifest: %s" % parsed.netloc)
    return parsed.geturl()


def part_is_poisoned(part):
    """True when a .part must not be resumed by curl.

    aria2c with 8 segments writes SPARSE files: st_size races to the full length
    while only part of it is allocated. curl's --continue-at - resumes from
    st_size, so it appends the remaining bytes AFTER a hole, producing a file
    whose MD5 can never match — and every retry repeated the same mistake
    (measured 2026-11-15: 83 FAILED, ~10 h, zero progress). Any .part that has
    an aria2 control file, or whose allocated size is materially below its
    apparent size, is therefore restarted from zero instead of resumed.
    """
    if not part.exists():
        return False
    control = part.with_suffix(part.suffix + ".aria2")
    if control.exists():
        return True
    st = part.stat()
    return st.st_size > 0 and (st.st_blocks * 512) < st.st_size * 0.95


def reset_part(part):
    for p in (part, part.with_suffix(part.suffix + ".aria2")):
        p.unlink(missing_ok=True)


def curl_download(run, details, data_dir, log, budget=None):
    env = os.environ.copy()
    done = data_dir / (run + ".done")
    done.unlink(missing_ok=True)
    for idx, (url, md5, size) in enumerate(zip(details[run]["urls"],
                                               details[run]["md5s"],
                                               details[run]["sizes"]), start=1):
        dest = data_dir / ("%s_%d.fastq.gz" % (run, idx))
        if integrity_ok(dest, size, md5):
            continue
        part = dest.with_suffix(dest.suffix + ".part")
        if part_is_poisoned(part):
            jlog(log, run=run, step="curl", status="part_reset",
                 file=dest.name, reason="sparse_or_aria2_control")
            reset_part(part)
        cmd = ["curl", "-sSfL", "--continue-at", "-", "--retry", "5",
               "--retry-delay", "10", "--retry-all-errors",
               "--connect-timeout", "60", "-o", str(part), http_url(url)]
        code = run_process(cmd, timeout=budget if budget else remaining_seconds(),
                          env=env)
        if code == 124:
            jlog(log, run=run, step="curl", status="timeout", file=dest.name)
            return False
        if code != 0 or not part.exists():
            jlog(log, run=run, step="curl", status="failed", file=dest.name,
                 exit_code=code)
            return False
        if not integrity_ok(part, size, md5):
            jlog(log, run=run, step="curl", status="integrity_failed",
                 file=dest.name)
            part.unlink(missing_ok=True)
            return False
        part.replace(dest)
        jlog(log, run=run, step="curl", status="done", file=dest.name,
             bytes=size)
    done.write_text(now() + "\n")
    return True


def allocated_bytes(path):
    """Bytes actually written, not the file's apparent length.

    aria2c with --file-allocation=none and 8 segments pwrite()s at 8 independent
    offsets, so st_size jumps to the highest offset touched within seconds while
    most of the file is still a hole. st_blocks*512 (i.e. what `du` reports) is
    the honest progress measure; measured live: st_size showed a 406MB "file"
    whose real throughput was 20KB/s.
    """
    try:
        st = path.stat()
    except OSError:
        return 0
    blocks = getattr(st, "st_blocks", 0) * 512
    return blocks if blocks else st.st_size


def _log_shows_refusal(log_path, tail_bytes=4096):
    """True when aria2c's log ends in a connection refusal.

    A refused connection is not a slow transfer: it means the service is
    rejecting us, and retrying immediately makes it worse. The orchestrator
    turns this into a long pause instead of burning the whole pass.
    """
    try:
        with open(log_path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - tail_bytes))
            tail = fh.read().decode("utf-8", "replace")
    except OSError:
        return False
    return ("Connection refused" in tail) or ("Failed to establish connection" in tail)


def _echo_pump(proc, log_path, state):
    """Relay a child's output to the logfile AND the terminal (--progress).

    The logfile write is authoritative: it happens first and its failure
    marks state["log_ok"]=False, which join_pump() turns into a hard attempt
    failure (no refusal detection, no next attempt, run poisoned at queue
    level). Terminal output is best-effort via a bounded queue drained by a
    dedicated daemon writer, so a blocked/broken terminal can never stall
    this pump or the log drain — overflow lines are dropped from the display
    only. Daemon thread; run_monitored joins it explicitly at every
    termination point (supervisor P0, 2026-11-23)."""
    state["log_ok"] = True
    try:
        with open(log_path, "a", encoding="utf-8") as fh:
            for raw in iter(proc.stdout.readline, b""):
                text = raw.decode("utf-8", errors="replace")
                fh.write(text)
                fh.flush()
                _emit("out", text)
    except Exception as exc:
        state["log_ok"] = False
        state["log_err"] = str(exc)[:200]
        _emit("err", "run_project: --progress logfile pump failed: %s\n" % exc)


def run_monitored(cmd, log_path, part, min_bps, window_s, poll_s=15,
                   on_restart=None, echo=False):
    """Run one transfer, restarting it (resume intact) when it crawls.

    Measured on PRJEB43119: the same host serves one object at 62 MB/s and
    another at 120 KB/s in the same minute, and a single object can collapse
    mid-transfer (1.1GiB at 120KiB/s, ETA 1h, while a fresh connection to a
    different object in parallel pulled 16 MB/s). Waiting an hour for a
    throttled object is a waste of the whole pipeline, so a sustained rate
    below `min_bps` over `window_s` terminates the attempt and re-opens fresh
    connections; the .part/.aria2 state makes the restart free.

    With echo=True the child's stdout is a pipe drained by _echo_pump (which
    mirrors it to the terminal), so proc.wait() can never block on a full
    pipe and the logfile stays complete.

    Returns (exit_code, restarts, reason). exit_code is None when the restart
    budget was exhausted with every attempt still crawling.
    """
    restarts = 0
    bursts = 0
    pump = None

    def join_pump(timeout_s=60):
        # Supervisor P0 (2026-11-23, round 2): joining without checking
        # liveness, or with a silently-failed pump, is not a guarantee. This
        # returns True only when the pump thread FINISHED and completed its
        # logfile drain. Any timeout or logfile-write failure is a hard
        # attempt failure ("pump_unresponsive"): no refusal detection on a
        # torn tail, no next attempt racing the same logfile.
        nonlocal pump
        if pump is None:
            return True
        pump.join(timeout=timeout_s)
        alive = pump.is_alive()
        state = getattr(pump, "_state", {})
        ok = (not alive) and state.get("log_ok", False)
        pump = None
        return ok

    while True:
        fh = open(log_path, "a", encoding="utf-8")
        try:
            if echo:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT,
                                        start_new_session=True)
                state = {}
                pump = threading.Thread(target=_echo_pump,
                                        args=(proc, log_path, state),
                                        daemon=True)
                pump._state = state
                pump.start()
            else:
                proc = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT,
                                        start_new_session=True)
        finally:
            fh.close()
        _worker_procs.add(proc)
        last = allocated_bytes(part)
        burst_base = last
        last_t = start_t = time.monotonic()
        low_marks = []  # rate samples inside the current window
        reason = "exited"
        while True:
            budget = remaining_seconds()
            wait = poll_s if budget is None else max(1.0, min(poll_s, budget))
            try:
                code = proc.wait(timeout=wait)
                reason = "exited"
                if not join_pump():
                    # torn-log risk: refusal detection must not run
                    return proc.returncode, restarts, "pump_unresponsive"
                break
            except subprocess.TimeoutExpired:
                pass
            if budget is not None and budget <= wait:
                _kill_group(proc)
                if not join_pump():
                    return 124, restarts, "pump_unresponsive"
                return 124, restarts, "wall_clock"
            cur = allocated_bytes(part)
            now_t = time.monotonic()
            # Rate over the REAL elapsed interval, not the nominal poll_s: near
            # the wall-clock deadline the wait is clamped and a fixed divisor
            # would silently distort the measurement (supervisor P1).
            elapsed = max(now_t - last_t, 1e-3)
            rate = (cur - last) / elapsed
            last, last_t = cur, now_t
            low_marks.append(rate)
            if cur - burst_base >= ARIA2_BURST_BYTES:
                _kill_group(proc)
                if not join_pump():
                    return None, restarts, "pump_unresponsive"
                reason = "burst_exhausted"
                break
            if (now_t - start_t) >= window_s:
                if max(low_marks) < min_bps:
                    _kill_group(proc)
                    if not join_pump():
                        return None, restarts, "pump_unresponsive"
                    reason = "low_throughput"
                    break
                low_marks = low_marks[len(low_marks) // 2:]
        if reason == "exited":
            _worker_procs.discard(proc)
            if code != 0 and _log_shows_refusal(log_path):
                return code, restarts, "refused"
            return code, restarts, reason
        if reason == "burst_exhausted":
            bursts += 1
            if on_restart is not None:
                on_restart(("burst", bursts), round(ARIA2_BURST_BYTES / 1e6, 1))
            if bursts > ARIA2_MAX_BURST_CYCLES:
                return None, restarts, "burst_cycles_exhausted"
            continue
        restarts += 1
        # Per-attempt audit record (supervisor requirement: every backend/attempt
        # is individually reconstructable, and a same-backend retry is
        # distinguishable from a backend switch).
        if on_restart is not None:
            on_restart(restarts, round(sum(low_marks) / max(window_s, 1) / 1e6, 3))
        if restarts > ARIA2_MAX_RESTARTS:
            return None, restarts, reason
        # fall through and respawn; .part / .aria2 state is preserved


def _kill_group(proc):
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()


def aria2_download(run, details, data_dir, log):
    """Locked-URL aria2c segmented transfer (x8/s8/k1M), CA verified explicitly.

    aria2c lives in envs/dram whose bundled CA store is stale, so the system
    bundle is passed with --ca-certificate; certificate verification is NEVER
    disabled (no --check-certificate=false). Partial state lives in the sidecar
    '<dest>.aria2' control file inside data/, which is inert to every downstream
    glob (*.fastq.gz/.done/.part) and removed on success."""
    if run in _PUMP_BROKEN_RUNS:
        # Queue-level hard fail (supervisor P0, 2026-11-23 round 3): a run
        # whose --progress pump died or outlived its join is never retried
        # and never published in this execution — the queue filters it out
        # of `pending`; this guard is the second line of defence so no fresh
        # attempt can ever reopen a logfile an old pump may still hold.
        jlog(log, run=run, step="aria2", status="pump_poisoned_refused")
        return False
    if not ARIA2_BIN.exists():
        jlog(log, run=run, step="aria2", status="unavailable", bin=str(ARIA2_BIN))
        return False
    ca = bench.resolve_ca()
    if not ca:
        jlog(log, run=run, step="aria2", status="no_ca_bundle")
        return False
    done = data_dir / (run + ".done")
    for idx, (url, md5, size) in enumerate(zip(details[run]["urls"],
                                               details[run]["md5s"],
                                               details[run]["sizes"]), start=1):
        dest = data_dir / ("%s_%d.fastq.gz" % (run, idx))
        if integrity_ok(dest, size, md5):
            continue
        part = dest.with_suffix(dest.suffix + ".part")
        # Resume is preserved, never thrown away: aria2c resumes from its own
        # .aria2 control file when present, and --continue=true also resumes a
        # sequential partial left behind by ascp/curl (1.2GB of one run was
        # already on disk). A wrong-length partial can only produce a file that
        # fails the size/MD5/gzip gate below, so keeping it is safe.
        cmd = [str(ARIA2_BIN), "-x", str(ARIA2_CONNECTIONS),
               "-s", str(ARIA2_CONNECTIONS), "-k", "1M",
               "--ca-certificate", ca, "--file-allocation=none",
               "--continue=true", "--allow-overwrite=true",
               "--auto-file-renaming=false",
               "--summary-interval=30", "--console-log-level=warn",
               "-d", str(data_dir), "-o", part.name, http_url(url)]
        if PROXY:
            cmd += ["--all-proxy", PROXY]
        logfile = log.parent / ("aria2_%s_%s.log" % (run, dest.name))
        started = time.monotonic()
        code, restarts, reason = run_monitored(
            cmd, str(logfile), part, ARIA2_MIN_BPS, ARIA2_STALL_WINDOW_S,
            echo=PROGRESS_ECHO,
            on_restart=lambda n, mbps: jlog(
                log, run=run, step="aria2",
                status=("burst_cycle" if isinstance(n, tuple) else
                        "restart_same_backend"),
                file=dest.name,
                attempt=(n[1] if isinstance(n, tuple) else n),
                observed_mb_per_s=mbps, min_bps=ARIA2_MIN_BPS,
                window_s=ARIA2_STALL_WINDOW_S,
                burst_mb=(ARIA2_BURST_BYTES // 1000000)))
        secs = round(time.monotonic() - started, 1)
        if restarts:
            jlog(log, run=run, step="aria2", status="restarted",
                 file=dest.name, restarts=restarts, reason=reason,
                 min_bps=ARIA2_MIN_BPS, window_s=ARIA2_STALL_WINDOW_S)
        if reason == "pump_unresponsive":
            # --progress pump failed or outlived its join budget: the logfile
            # tail cannot be trusted for refusal detection and the next
            # attempt must not race it. Poison the run for the WHOLE
            # execution (supervisor P0 2026-11-23 round 3): filtered from
            # every later retry pass and refused at entry, so it can never
            # publish here; a later --manifest rerun (fresh process, empty
            # poison set) resumes from .part/.aria2.
            _PUMP_BROKEN_RUNS.add(run)
            jlog(log, run=run, step="aria2", status="pump_unresponsive",
                 file=dest.name, echo=PROGRESS_ECHO, poisoned=True)
            return False
        if code == 124:
            jlog(log, run=run, step="aria2", status="timeout", file=dest.name,
                 seconds=secs, ca=ca)
            return False
        if reason == "refused":
            global _refusal_streak
            _refusal_streak += 1
            jlog(log, run=run, step="aria2", status="refused", file=dest.name,
                 streak=_refusal_streak, threshold=ARIA2_BLOCK_STREAK)
            return False
        if code is None:
            jlog(log, run=run, step="aria2", status="stalled_out", file=dest.name,
                 seconds=secs, restarts=restarts, min_bps=ARIA2_MIN_BPS)
            return False
        if code != 0 or not part.exists():
            jlog(log, run=run, step="aria2", status="failed", exit_code=code,
                 file=dest.name, seconds=secs, ca=ca, log=str(logfile))
            return False
        if not integrity_ok(part, size, md5):
            jlog(log, run=run, step="aria2", status="integrity_failed",
                 file=dest.name, seconds=secs, ca=ca)
            part.unlink(missing_ok=True)
            dest.with_suffix(dest.suffix + ".aria2").unlink(missing_ok=True)
            return False
        part.replace(dest)
        dest.with_suffix(dest.suffix + ".aria2").unlink(missing_ok=True)
        jlog(log, run=run, step="aria2", status="done", file=dest.name,
             bytes=size, seconds=secs,
             mb_per_s=round(size / max(secs, 0.1) / 1e6, 2))
    done.write_text(now() + "\n")
    return True


def aspera_src(url):
    """Manifest ENA HTTPS/FTP URL -> era-fasp ENA Aspera source."""
    parsed = urllib.parse.urlsplit(http_url(url))
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
        # Exactly the documented invocation: no -d, rate 300m, -QT -k1.
        code = run_process(
            [str(ascp), "-QT", "-k1", "-l", ASCP_RATE, "-P", "33001",
             "-i", str(key), aspera_src(url), str(dl_dir)],
            timeout=remaining_seconds(), log_path=str(logfile))
        if code != 0:
            jlog(log, run=run, step="aspera", status="failed", exit_code=code,
                 file=Path(url).name, log=str(logfile))
            return False
    return True


def integrity_ok(path, size, md5):
    """One-pass integrity check: size, then MD5.

    A matching MD5 proves the file is byte-identical to the FASTQ ENA
    published, so the gzip stream is necessarily intact — a separate `gzip -t`
    is logically redundant and costs a full extra decompression pass on every
    file (precedent: commit 30eb5bb dropped gzip -t for the same reason). gzip
    is still checked when no expected MD5 is available, so the fallback keeps
    its purpose instead of doubling I/O on the normal path.
    """
    try:
        if path.stat().st_size != size:
            return False
    except OSError:
        return False
    if not md5:
        return gzip_ok(path)
    return md5_of(path) == md5


def published_ok(run, data_dir, details):
    """Resume guard: a run counts as done only if both FASTQs exist AND match
    the manifest size AND md5 (MD5 match is byte-identity to the published
    FASTQ, so gzip-stream integrity is implied, never re-run as `gzip -t` —
    see verify_published's integrity_policy). A truncated or replaced file
    must never ride the .done fast-path."""
    for idx, (md5, size) in enumerate(zip(details[run]["md5s"],
                                          details[run]["sizes"]), start=1):
        p = data_dir / ("%s_%d.fastq.gz" % (run, idx))
        if not p.exists() or p.stat().st_size != size:
            return False
        if not integrity_ok(p, size, md5):
            return False
    return True


def download(selected, details, workdir, parallel, log, backend="locked-aspera"):
    global _refusal_streak
    data_dir, dl_dir = workdir / "data", workdir / "downloads"
    data_dir.mkdir(parents=True, exist_ok=True)
    dl_dir.mkdir(parents=True, exist_ok=True)
    runlist = workdir / "manifests" / "selected_runs.txt"
    runlist.parent.mkdir(parents=True, exist_ok=True)
    runlist.write_text("\n".join(selected) + "\n")

    if backend in ("locked-aspera", "locked-curl", "locked-aria2"):
        # Locked manifest URLs only. aria2c gets several whole-queue passes
        # before anything else: per-object throttling on this host is transient
        # (one object crawled at 120 KB/s while another pulled 16 MB/s in the
        # same minute), so the same object usually flies on a later pass, and
        # every pass resumes from .part/.aria2 instead of restarting.
        ok = []
        pending = []
        for run in selected:
            # Idempotent resume: a run already published with a valid .done
            # and intact verified files is never re-downloaded.
            done = data_dir / (run + ".done")
            if done.exists() and published_ok(run, data_dir, details):
                jlog(log, run=run, step="download", status="already_done")
                ok.append(run)
                continue
            pending.append(run)

        passes = ARIA2_PASSES if backend == "locked-aria2" else 1
        workers = max(1, int(parallel))
        for attempt in range(1, passes + 1):
            if not pending:
                break
            if _refusal_streak >= ARIA2_BLOCK_STREAK:
                jlog(log, step="download", status="service_refused_backoff",
                     streak=_refusal_streak, sleep_s=ARIA2_BLOCK_SLEEP_S)
                time.sleep(min(ARIA2_BLOCK_SLEEP_S, remaining_seconds()))
                _refusal_streak = 0
            if attempt > 1:
                # Back off before hammering a host that may be throttling us:
                # the whole point of a later pass is a better window, so an
                # immediate retry would just burn the same bad minutes.
                jlog(log, step="download", status="retry_pass", attempt=attempt,
                     runs=len(pending), backoff_s=RETRY_BACKOFF_S)
                time.sleep(min(RETRY_BACKOFF_S, remaining_seconds()))
            # Parallel workers: measured 2026-11-14, the route throttles per
            # transfer, not per IP (18.5 MB/s on one object while the serial
            # queue crawled at 0.16 MB/s), so independent connection groups
            # multiply the aggregate rate instead of sharing a cap.
            failed = []
            if workers == 1:
                for run in pending:
                    run_ok = _download_one(run, backend, data_dir, dl_dir,
                                           details, log)[1]
                    (ok if run_ok else failed).append(run)
            else:
                with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                    futures = {run: pool.submit(_download_one, run, backend,
                                                data_dir, dl_dir, details, log)
                               for run in pending}
                    for run, fut in futures.items():
                        _, run_ok = fut.result()
                        (ok if run_ok else failed).append(run)
            if _PUMP_BROKEN_RUNS:
                # Queue-level hard fail (supervisor P0 2026-11-23 round 3):
                # pump-poisoned runs leave the retry queue entirely — no
                # further attempt in this execution, so no publish either.
                # The final "download incomplete" summary in main() reports
                # them; a fresh --manifest rerun resumes from .part/.aria2.
                for broken in sorted({r for r in failed
                                      if r in _PUMP_BROKEN_RUNS}):
                    jlog(log, run=broken, step="download",
                         status="pump_poisoned_skipped")
                    failed.remove(broken)
            pending = failed

        # Last resort. For aria2 the curl fallback is deliberately NOT used:
        # measured 2026-11-15 it resumed aria2's sparse partials at the wrong
        # offset, so every attempt ended integrity_failed and deleted the file —
        # 10 h of zero progress. A failed aria2 run is simply deferred to the
        # next pass (resume-safe) instead of being handed to curl.
        for run in pending:
            if backend != "locked-aria2" and curl_download(
                    run, details, data_dir, log, budget=CURL_LAST_RESORT_S):
                ok.append(run)
            else:
                jlog(log, run=run, step="download", status="DEFERRED",
                     backend=backend, reason="retry_on_next_pass")
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


BENCHMARK_REPORTS = ("download_benchmark.json", "download_benchmark_pilot.json")


def _benchmark_recommendation(workdir):
    """Read back what the per-dataset benchmark advised, if it has been run.

    Both the default name and the pilot name are accepted: the probe run for
    this dataset was written as download_benchmark_pilot.json, and a record
    that says "not_run" only because of a filename mismatch is misleading
    (supervisor P1). The report actually read is named in the result."""
    for name in BENCHMARK_REPORTS:
        path = workdir / "manifests" / name
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {"status": "unreadable", "report": name}
        return {"status": "found", "report": name,
                "throughput_candidate": data.get("throughput_candidate"),
                "throughput_note": data.get("throughput_note"),
                "integrity_status": data.get("integrity_status"),
                "probe_runs": data.get("probe_runs"),
                "generated_at": data.get("generated_at"),
                "pilot_validation": data.get("pilot_validation", "not_recorded")}
    return {"status": "not_run",
            "searched": [str(workdir / "manifests" / n) for n in BENCHMARK_REPORTS]}


def sweep_orphan_aria2(workdir):
    """Kill aria2c processes still writing into this workdir's data dir.

    aria2c is started with start_new_session=True so a timeout can kill the
    whole group; the flip side is that a SIGKILLed orchestrator leaks its
    children. Leaked downloaders then fight the next run for the same .part and
    .aria2 control files — measured 2026-11-14: two orphans dropped a 24 MB/s
    object to 0.15 MB/s and corrupted each other's resume state, which looked
    exactly like EBI per-object throttling. The caller holds the exclusive run
    lock, so any aria2c pointed at this dataset is by definition an orphan.
    """
    data_dir = str((workdir / "data").resolve())
    killed = []
    mine = {p.pid for p in _worker_procs}
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        if int(entry) in mine:
            continue
        try:
            raw = open("/proc/%s/cmdline" % entry, "rb").read()
        except OSError:
            continue
        args = [a for a in raw.decode("utf-8", "replace").split("\x00") if a]
        if not args or not any(a.endswith("aria2c") for a in args):
            continue
        if data_dir in args:
            try:
                os.kill(int(entry), signal.SIGKILL)
                killed.append(int(entry))
            except OSError:
                pass
    return killed


def _download_one(run, backend, data_dir, dl_dir, details, log):
    """Full per-run flow for one worker thread (verify-skip, fetch, publish).

    Threads touch disjoint files, so the only shared state is the append-only
    ingest log; each jlog is a single append and stays atomic enough for audit.
    """
    if backend == "locked-aria2" and _refusal_streak >= ARIA2_BLOCK_STREAK:
        return run, False   # the host is refusing us; do not add more sockets
    done = data_dir / (run + ".done")
    if done.exists() and published_ok(run, data_dir, details):
        jlog(log, run=run, step="download", status="already_done")
        return run, True
    if backend == "locked-aspera":
        if aspera_fetch(run, details, dl_dir, log):
            if publish(run, find_iseq_files(run, dl_dir),
                       data_dir, details, log):
                return run, True
    if backend == "locked-aria2" and aria2_download(run, details, data_dir, log):
        return run, True
    if backend == "locked-curl" and curl_download(run, details, data_dir, log):
        return run, True
    return run, False


def verify_published(selected, details, workdir):
    """Independent read-back of published FASTQ (no download, no writes to data/).

    Used for two gates: the A/B pilot evidence, and the final dataset-wide
    check before analysis. Every file is re-hashed from disk, so a .done marker
    can never be the only witness."""
    data_dir = workdir / "data"
    records = []
    for run in selected:
        files = []
        for idx, (md5, size) in enumerate(zip(details[run]["md5s"],
                                              details[run]["sizes"]), start=1):
            path = data_dir / ("%s_%d.fastq.gz" % (run, idx))
            rec = {"file": path.name, "expected_bytes": size,
                   "expected_md5": md5, "exists": path.exists(),
                   "bytes": 0, "size_match": False, "md5": None,
                   "md5_match": False, "gzip_ok": None,
                   "gzip_check": "not_run"}
            if path.exists():
                rec["bytes"] = path.stat().st_size
                rec["size_match"] = rec["bytes"] == size
                if rec["size_match"]:
                    rec["md5"] = md5_of(path)
                    rec["md5_match"] = rec["md5"] == md5
                if rec["md5_match"]:
                    # Byte-identical to the published file => the gzip stream is
                    # necessarily intact, so no second full read is spent
                    # proving it. Recorded as implied, never as "checked".
                    rec["gzip_ok"] = True
                    rec["gzip_check"] = "implied_by_md5_match"
                elif not md5:
                    rec["gzip_ok"] = gzip_ok(path)
                    rec["gzip_check"] = "run (no expected md5)"
            files.append(rec)
        ok = all(f["size_match"] and f["md5_match"] for f in files)
        records.append({"run": run, "ok": ok,
                        "done_marker": (data_dir / (run + ".done")).exists(),
                        "files": files})
    ok_runs = sum(1 for r in records if r["ok"])
    payload = {"verified_at": now(), "workdir": str(workdir),
               "runs": len(records), "runs_ok": ok_runs,
               "files": sum(len(r["files"]) for r in records),
               "files_ok": sum(1 for r in records for f in r["files"]
                               if f["size_match"] and f["md5_match"]),
               "integrity_policy": "MD5 match is byte-identity to the published "
                                   "FASTQ; gzip stream check is implied, not "
                                   "re-run (commit 30eb5bb precedent)",
               "all_ok": ok_runs == len(records), "records": records}
    out = workdir / "manifests" / "verification.json"
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    return payload, out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--runs", default="",
                        help="explicit comma-separated subset; required unless --manifest is used")
    parser.add_argument("--manifest", default="",
                        help="locked audited manifest; execution reads only it and does not rebuild")
    parser.add_argument("--parallel", type=int, default=1,
                        help="concurrent runs for the locked backends (default 1 = "
                             "serial). Each worker owns disjoint files; the publish "
                             "gate and resume logic are per-run.")
    parser.add_argument("--proxy", default="",
                        help="optional HTTP proxy passed to aria2c --all-proxy "
                             "(e.g. http://127.0.0.1:7890). Empty = direct "
                             "connection. The proxy endpoint itself is only an "
                             "address: bring mihomo/node_watch up beforehand "
                             "(see download SOP).")
    parser.add_argument("--progress", action="store_true",
                        help="echo aria2's native progress lines to this "
                             "terminal while keeping the per-file logfile "
                             "byte-complete (the low-speed monitor and refusal "
                             "detector still read the logfile; nothing about "
                             "the aria2 command itself changes)")
    parser.add_argument("--download-backend",
                        choices=("locked-aspera", "locked-aria2", "locked-curl", "iseq"),
                        default="locked-aria2",
                        help="locked-aria2 (default: segmented HTTPS, measured 30+ MB/s on "
                             "PRJEB43119 and the only backend that cleared the A/B publish "
                             "gate), locked-aspera, locked-curl, or optional iSeq accession "
                             "mode. Run download_benchmark.py first to pick the fastest "
                             "backend for a new dataset.")
    parser.add_argument("--verify-only", action="store_true",
                        help="re-hash published FASTQ against the locked manifest "
                             "(size+MD5; gzip integrity is implied by the MD5 "
                             "byte-identity match and recorded as "
                             "implied_by_md5_match, never re-run as gzip -t; a "
                             "real gzip check runs only for files without an "
                             "expected MD5) and write manifests/verification.json; "
                             "never downloads")
    parser.add_argument("--dry-run", action="store_true",
                        help="read-only ENA metadata query, write the audited manifest, "
                             "and exit without downloading FASTQ")
    parser.add_argument("--max-hours", type=float, default=12,
                        help="hard wall-clock budget for downloads + analysis (default 12)")
    args = parser.parse_args(argv)
    # Proxy address validation is the FIRST thing after parsing (supervisor P0,
    # 2026-11-22 round 2): an invalid --proxy must exit before any path is
    # resolved, any directory is created, or any log/lock file is opened.
    _proxy = args.proxy.strip()
    if _proxy and not re.match(r"^https?://[\w.:-]+$", _proxy):
        parser.error("--proxy must look like http://host:port")
    global PROGRESS_ECHO
    PROGRESS_ECHO = bool(args.progress)
    if not math.isfinite(args.max_hours) or args.max_hours <= 0:
        parser.error("--max-hours must be a finite positive number")
    if args.manifest and args.runs:
        parser.error("--manifest and --runs are mutually exclusive")
    if args.verify_only and not args.manifest:
        parser.error("--verify-only requires --manifest")
    if not args.manifest and not args.runs:
        parser.error("execution requires explicit --runs or a locked --manifest")
    if args.manifest and args.download_backend == "iseq":
        parser.error("--manifest cannot use the iseq accession backend; use locked-aspera or locked-curl")
    global DEADLINE, PROXY
    DEADLINE = time.monotonic() + args.max_hours * 3600
    PROXY = _proxy  # validated immediately after parse_args, above

    workdir = Path(args.workdir).resolve()
    if "Project01" in workdir.parts:
        raise SystemExit("refusing to write Project01")
    for sub in ("data", "downloads", "logs/scripts", "manifests", "temp", "result"):
        (workdir / sub).mkdir(parents=True, exist_ok=True)
    log = workdir / "logs" / "ingest.jsonl"

    # Single-instance guard (supervisor P0: a pilot must never contend with
    # another downloader for the same FASTQ). The fd is held for the whole
    # process lifetime; a second orchestrator on this workdir exits instead of
    # racing — the §23 dual-instance incident cannot recur.
    lock_fh = open(workdir / "manifests" / "run.lock", "w")
    try:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("another run_project.py already owns %s" % workdir)
    lock_fh.write("%d %s\n" % (os.getpid(), args.download_backend))
    lock_fh.flush()
    orphans = sweep_orphan_aria2(workdir)
    if orphans:
        jlog(log, step="startup", status="orphan_aria2_killed", pids=orphans)

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
         free=free, required=required, manifest=str(manifest_path),
         backend=args.download_backend, proxy=(PROXY or "direct"),
         progress_echo=PROGRESS_ECHO)

    # The selected backend is part of the auditable record, not just a CLI flag
    # (supervisor P0). Written before any transfer so a crash still leaves it.
    selection = {
        "dataset": dataset["dataset_id"],
        "recorded_at": now(),
        "backend": args.download_backend,
        "proxy": PROXY or "direct",
        "progress_echo": PROGRESS_ECHO,
        "manifest": str(manifest_path),
        "selected_runs": len(selected),
        "selected_bytes": need,
        "benchmark_report": str(workdir / "manifests" / "download_benchmark.json"),
        "benchmark_recommendation": _benchmark_recommendation(workdir),
    }
    (workdir / "manifests" / "backend_selection.json").write_text(
        json.dumps(selection, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    if args.dry_run:
        print("DRY-RUN manifest:", manifest_path)
        return 0

    if args.verify_only:
        payload, out = verify_published(selected, details, workdir)
        print("VERIFY:", "%d/%d runs, %d/%d files" % (
            payload["runs_ok"], payload["runs"], payload["files_ok"],
            payload["files"]), "->", out)
        return 0 if payload["all_ok"] else 3

    write_samplesheet(selected, workdir)
    ok = download(selected, details, workdir, args.parallel, log,
                  backend=args.download_backend)
    if len(ok) != len(selected):
        # Exit-path console output goes through the non-blocking queue too
        # (supervisor P0 2026-11-23 round 5): a blocked terminal must not hang
        # the final exit. int code keeps the interpreter silent on stderr.
        _emit("err", "download incomplete: %d/%d (see %s; poisoned runs: %s)"
              % (len(ok), len(selected), log,
                 sorted(_PUMP_BROKEN_RUNS) or "none"))
        _drain_streams(timeout_s=10)
        raise SystemExit(1)

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

    _emit("out", "DONE: %d runs published in %s\n" % (len(selected), workdir))
    # Bounded drain so the queued tail line actually reaches the terminal
    # before the daemon writers die at process exit; a blocked terminal just
    # costs the 10s cap, never an infinite hang.
    _drain_streams(timeout_s=10)


if __name__ == "__main__":
    sys.exit(main())
