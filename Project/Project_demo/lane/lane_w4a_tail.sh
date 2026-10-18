#!/usr/bin/env bash
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
for step in 41_bac_prokka 41b_bac_mlst 41c_bac_pangenome 41d_bac_snippy; do
    echo "=== [$(date +%T)] W4A-TAIL: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || { echo "=== W4A-TAIL ABORTED at $step ==="; exit 1; }
done
echo "=== W4A-TAIL DONE $(date +%T) ==="
