#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"

echo "=== [$(date +%H:%M:%S)] B1: 19_salmon_build ==="
bash scripts/19_bac_salmon_build.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3

echo "=== [$(date +%H:%M:%S)] B1: 20_salmon_quant 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] B1: 20 $s ==="
  bash scripts/20_bac_salmon_quant.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== B1 salmon DONE $(date +%H:%M:%S) ==="
