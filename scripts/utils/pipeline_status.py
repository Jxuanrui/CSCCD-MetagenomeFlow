#!/usr/bin/env python3
"""Pipeline status recovery tool (Supervisor 18th D phase).

Reads run_events.jsonl + validation log + product file mtimes to reconstruct
the current state of a workdir after an interruption. Outputs a JSON summary
of what has been run, what succeeded/failed, and what can be safely resumed.

Usage:
    python3 scripts/utils/pipeline_status.py <workdir>
"""
import json, os, sys, time
from collections import defaultdict
from datetime import datetime


def read_events(workdir):
    events = []
    path = os.path.join(workdir, "logs", "run_events.jsonl")
    if not os.path.isfile(path):
        return events
    for line in open(path):
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def pair_events(events):
    """Match start events with their end events (supervisor 18th B logic)."""
    paired = {}
    pending = {}
    for e in events:
        step = e.get("step_id", "")
        sample = e.get("sample_id", "")
        code = e.get("exit_code")
        key = (step, sample)
        if code == -1:  # start
            pending.setdefault(key, []).append(e)
        else:  # end
            stack = pending.get(key)
            if stack:
                start = stack.pop()
                paired[key] = {
                    "step": step.replace(".sh", ""),
                    "sample": sample,
                    "exit_code": code,
                    "duration_sec": e.get("duration_sec", 0),
                    "started_at": start.get("started_at", ""),
                    "ended_at": e.get("ts", ""),
                }
    return paired


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 pipeline_status.py <workdir>")
        sys.exit(1)
    workdir = os.path.abspath(sys.argv[1])

    events = read_events(workdir)
    if not events:
        print(json.dumps({"workdir": workdir, "status": "NO_EVENTS",
                          "message": "no run_events.jsonl found"}))
        return

    paired = pair_events(events)

    # Summary by exit code
    succeeded = {k: v for k, v in paired.items() if v["exit_code"] == 0}
    failed = {k: v for k, v in paired.items() if v["exit_code"] != 0}
    running = {}  # unmatched starts
    for key, stack in _get_unmatched(events, paired).items():
        if stack:
            running[key] = {"step": key[0].replace(".sh", ""), "sample": key[1]}

    # Steps that can be safely resumed (succeeded and not currently running)
    resumable = []
    for key, info in succeeded.items():
        if key not in running:
            resumable.append(info["step"])

    output = {
        "workdir": workdir,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "total_events": len(events),
        "total_paired": len(paired),
        "succeeded": len(succeeded),
        "failed": len(failed),
        "possibly_running": len(running),
        "failed_steps": sorted(set(v["step"] for v in failed.values())),
        "resumable_downstream": sorted(set(resumable)),
        "recommendation": (
            "SAFE_TO_RESUME: skip steps listed in resumable_downstream" if not running
            else "CAUTION: {} steps may still be running; verify with ps/flock before restarting".format(len(running))
        )
    }
    print(json.dumps(output, indent=1))


def _get_unmatched(events, paired):
    """Return pending start events that never got an end."""
    pending = defaultdict(list)
    paired_keys = set(paired.keys())
    for e in events:
        key = (e.get("step_id", ""), e.get("sample_id", ""))
        if e.get("exit_code") == -1 and key not in paired_keys:
            pending[key].append(e)
    return dict(pending)


if __name__ == "__main__":
    main()
