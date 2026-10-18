#!/bin/bash
cd /home/labuser/Course/Maxmetagenome
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome

echo "=== [$(date +%H:%M:%S)] V: 54b_checkv_filter 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] V: 54b $s ==="
  bash scripts/54b_vir_checkv_filter.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done

echo "=== [$(date +%H:%M:%S)] V: 55_prodigal_gv 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] V: 55 $s ==="
  bash scripts/55_vir_prodigal_gv.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== V 54b+55 DONE $(date +%H:%M:%S) ==="
