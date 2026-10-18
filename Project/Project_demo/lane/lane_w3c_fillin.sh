#!/usr/bin/env bash
# W3-C lane (supervisor 4th review P1-8: fill-in execution, no wave gating;
# user approved 2026-10-14). Light per-sample steps at -t 8 to fit real
# headroom (nominal 48t already allocated, observed load ~28).
# 31e fegenie (reads 17 faa), 42 mge, 42b plasmidfinder (read 16/17 products).
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

for s in $SAMPLES; do echo "=== [$(date +%T)] W3C: 31e_fegenie $s ==="; bash scripts/31e_bac_fegenie.sh -s "$s" -t 8 -w "$WD" -r "$REPO" && echo "[31e/$s] OK" || echo "[31e/$s] FAIL"; done
for s in $SAMPLES; do echo "=== [$(date +%T)] W3C: 42_mge $s ==="; bash scripts/42_bac_mge.sh -s "$s" -t 8 -w "$WD" -r "$REPO" && echo "[42/$s] OK" || echo "[42/$s] FAIL"; done
for s in $SAMPLES; do echo "=== [$(date +%T)] W3C: 42b_plasmidfinder $s ==="; bash scripts/42b_bac_plasmidfinder.sh -s "$s" -t 8 -w "$WD" -r "$REPO" && echo "[42b/$s] OK" || echo "[42b/$s] FAIL"; done
echo "=== W3-C DONE $(date +%T) ==="
