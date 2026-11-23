#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"

echo "=== [$(date +%H:%M:%S)] LANE-F: 74a gut_db_build（一次性） ==="
bash scripts/74a_fun_gut_db_build.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3

for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] LANE-F: 74e_phf_profiler $s ==="
  bash scripts/74e_fun_phf_profiler.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done

echo "=== [$(date +%H:%M:%S)] LANE-F: 74f_phf_aggregate（一次性） ==="
bash scripts/74f_fun_phf_aggregate.sh -w "$WD" -r "$REPO" 2>&1 | tail -3

echo "=== LANE-F phase2 DONE $(date +%H:%M:%S) ==="
