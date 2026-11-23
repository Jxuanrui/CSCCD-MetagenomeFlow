#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] B1: 17_prodigal $s ==="
  bash scripts/17_bac_prodigal.sh -s "$s" -t 1 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== B1 prodigal DONE $(date +%H:%M:%S) ==="
