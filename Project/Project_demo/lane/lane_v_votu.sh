#!/bin/bash
cd /home/labuser/Course/Maxmetagenome
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome

echo "=== [$(date +%H:%M:%S)] V: 56_vclust（跨样本 vOTU 聚类） ==="
bash scripts/56_vir_votu_gen.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3

echo "=== [$(date +%H:%M:%S)] V: 57_votu_genomad ==="
bash scripts/57_vir_votu_genomad.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3

echo "=== [$(date +%H:%M:%S)] V: 58_salmon_build ==="
bash scripts/58_vir_salmon_build.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3

echo "=== [$(date +%H:%M:%S)] V: 59_salmon_quant 逐样本 ==="
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "--- 59 $s ---"
  bash scripts/59_vir_salmon_quant.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -2
done

echo "=== [$(date +%H:%M:%S)] V: 60_votu_table ==="
bash scripts/60_vir_votu_table.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3
echo "=== V vOTU chain DONE $(date +%H:%M:%S) ==="
