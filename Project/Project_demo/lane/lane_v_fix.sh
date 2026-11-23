#!/bin/bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO}"
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"

echo "=== [$(date +%H:%M:%S)] V-FIX: 54_checkv 交集模式重跑 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] 54 $s ==="
  bash scripts/54_vir_checkv_contig.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force 2>&1 | grep -E "交集|耗时|ERROR|WARN" | head -3
done

echo "=== [$(date +%H:%M:%S)] V-FIX: 54b filter 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  bash scripts/54b_vir_checkv_filter.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -2
done

echo "=== [$(date +%H:%M:%S)] V-FIX: 55 prodigal_gv 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  bash scripts/55_vir_prodigal_gv.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -2
done
echo "=== V-FIX DONE $(date +%H:%M:%S) ==="
