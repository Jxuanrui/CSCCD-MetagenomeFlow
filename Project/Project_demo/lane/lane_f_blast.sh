#!/bin/bash
cd /home/labuser/Course/Maxmetagenome
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome

echo "=== [$(date +%H:%M:%S)] F: 72b metaphlan4_merge ==="
bash scripts/72b_fun_metaphlan4_merge.sh -w "$WD" -r "$REPO" 2>&1 | tail -3

echo "=== [$(date +%H:%M:%S)] F: 74 blast_gutdb 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] F: 74_blast $s ==="
  bash scripts/74_fun_blast_gutdb.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== F blast DONE $(date +%H:%M:%S) ==="
