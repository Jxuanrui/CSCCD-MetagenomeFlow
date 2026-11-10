# validate_step Integration Status (18th review round B4, 2026-10-30)

## Current Status: NOT INTEGRATED

validate_step.py exists as a standalone CLI but is **not called by any pipeline
execution path** (not in libcommon.sh, not in Snakemake rules, not in any
pipeline script). It is documented in Tutorial.md as an optional manual step.

## Required Integration Points

| Entry Point | Status | Implementation Plan |
|---|---|---|
| Snakemake rules (production) | ❌ Not integrated | Add `run:` directive or `onsuccess:`/`onerror:` blocks |
| Individual script (Mode 1) | ❌ Not integrated | Add post-mgx_end validation call in libcommon.sh |
| Monitor (run_monitor.py) | ❌ Not integrated | Add validation status display alongside exit code |
| AI Agent workflow | ❌ Not integrated | 内部治理文档 routing matrix should reference validate_step |

## Recommended Minimal Integration (for AI Agent workflow)

In `内部治理文档` §6 Routing Matrix, add:
```
After any pipeline step completes:
  → python3 scripts/utils/validate_step.py <step_id> <sample> <workdir>
  → If verdict == "FAIL": report to user, do not proceed to downstream
  → If verdict == "UNVERIFIED": warn user, proceed with caution label
  → If verdict == "PASS": proceed normally
```

## Blocking Behavior (to be implemented)

- FAIL → block downstream in Snakemake (add `checkpoint:` or post-rule validation)
- UNVERIFIED → label in report, do not block
- PASS → normal flow
