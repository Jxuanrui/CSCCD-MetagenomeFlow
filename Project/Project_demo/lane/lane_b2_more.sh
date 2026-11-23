#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"

for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] B2: 35_semibin2 $s ==="
  bash scripts/35_bac_semibin2.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== B2 semibin2 DONE $(date +%H:%M:%S) ==="
