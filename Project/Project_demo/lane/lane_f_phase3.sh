#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"

echo "=== [$(date +%H:%M:%S)] LANE-F: 78_megahit（真菌组装，需组装器互斥） ==="
# 78 逐样本组装（等 LANE-V virsorter2 不用组装器，可以并行）
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] LANE-F: 78_megahit $s ==="
  bash scripts/78_fun_megahit.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== LANE-F megahit DONE $(date +%H:%M:%S) ==="
