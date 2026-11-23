#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] LANE-V: 51_megahit $s ==="
  bash scripts/51_vir_megahit.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== LANE-V megahit DONE $(date +%H:%M:%S) ==="
