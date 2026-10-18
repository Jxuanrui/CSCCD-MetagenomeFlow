#!/bin/bash
cd /home/labuser/Course/Maxmetagenome
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome

for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] LANE-F: 79_eukfinder $s ==="
  bash scripts/79_fun_eukfinder.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
for s in Sample1 Sample2 Sample10 Sample3 Sample4 Sample11; do
  echo "=== [$(date +%H:%M:%S)] LANE-F: 79b_veba_qc $s ==="
  bash scripts/79b_fun_veba_qc.sh -s "$s" -t 16 -w "$WD" -r "$REPO" 2>&1 | tail -3
done
echo "=== LANE-F phase4 (79+79b) DONE $(date +%H:%M:%S) ==="
