#!/usr/bin/env python3
"""Parse `/usr/bin/time -v` benchmark logs from benchmark_functional_analysis.sh
into a single TSV summary table.

Usage: python3 parse_benchmark_logs.py logs/benchmark_*.log > benchmark_summary.tsv

Each input log is expected to be named benchmark_{dimension}_{func_type}.log
and contain a standard `/usr/bin/time -v` report appended to the wrapped
script's own stdout/stderr.
"""
import re
import sys
from pathlib import Path

FIELDS = [
    ("wall_clock_sec", r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(\S+)", "time"),
    ("user_time_sec", r"User time \(seconds\):\s*([\d.]+)", "float"),
    ("system_time_sec", r"System time \(seconds\):\s*([\d.]+)", "float"),
    ("cpu_percent", r"Percent of CPU this job got:\s*(\d+)%", "int"),
    ("max_rss_kb", r"Maximum resident set size \(kbytes\):\s*(\d+)", "int"),
    ("major_page_faults", r"Major \(requiring I/O\) page faults:\s*(\d+)", "int"),
    ("minor_page_faults", r"Minor \(reclaiming a frame\) page faults:\s*(\d+)", "int"),
    ("fs_inputs", r"File system inputs:\s*(\d+)", "int"),
    ("fs_outputs", r"File system outputs:\s*(\d+)", "int"),
    ("exit_status", r"Exit status:\s*(\d+)", "int"),
]


def parse_wall_clock(value: str) -> str:
    """Normalize h:mm:ss / m:ss.ss into total seconds (string) for easy sorting."""
    parts = value.split(":")
    try:
        parts = [float(p) for p in parts]
    except ValueError:
        return value
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + part
    return f"{seconds:.2f}"


def parse_log(path: Path) -> dict:
    text = path.read_text(errors="replace")
    name = path.stem  # benchmark_{dimension}_{func_type}
    m = re.match(r"benchmark_([a-zA-Z]+)_(.+)$", name)
    dimension, func_type = (m.group(1), m.group(2)) if m else ("", name)

    row = {"dimension": dimension, "func_type": func_type, "log_file": str(path)}
    for key, pattern, kind in FIELDS:
        match = re.search(pattern, text)
        if not match:
            row[key] = "NA"
            continue
        raw = match.group(1)
        if key == "wall_clock_sec":
            row[key] = parse_wall_clock(raw)
        else:
            row[key] = raw

    if row.get("exit_status", "NA") == "NA":
        # /usr/bin/time -v wasn't reached (e.g. command not found before time ran)
        row["status"] = "TIME_REPORT_MISSING"
    elif row["exit_status"] == "0":
        row["status"] = "OK"
    else:
        row["status"] = "FAILED"

    return row


def main(argv):
    if len(argv) < 2:
        print("Usage: parse_benchmark_logs.py <log1> [log2 ...]", file=sys.stderr)
        return 1

    paths = sorted(Path(p) for p in argv[1:])
    rows = [parse_log(p) for p in paths if p.is_file()]

    columns = ["dimension", "func_type", "status", "wall_clock_sec", "user_time_sec",
               "system_time_sec", "cpu_percent", "max_rss_kb", "major_page_faults",
               "minor_page_faults", "fs_inputs", "fs_outputs", "exit_status", "log_file"]

    print("\t".join(columns))
    for row in rows:
        print("\t".join(str(row.get(col, "NA")) for col in columns))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
