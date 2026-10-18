#!/usr/bin/env bash
# W5 gate v2 (corrected 2026-10-16): the original gate omitted the required
# -m METADATA_CSV / -g GROUP_COL — all three smoke tests died in arg parsing.
# Rerun 91/92/93 with full parameters.
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
META="$WD/metadata.csv"

bash scripts/91_stat_diversity.sh -w "$WD" -r "$REPO" -t 16 -m "$META" && echo "[91] OK" || echo "[91] FAIL"
bash scripts/92_stat_differential.sh -w "$WD" -r "$REPO" -t 16 -m "$META" -g group && echo "[92] OK" || echo "[92] FAIL"
bash scripts/93_stat_cooccurrence.sh -w "$WD" -r "$REPO" -t 16 -m "$META" && echo "[93] OK" || echo "[93] FAIL"
echo "=== GATE-V2 DONE $(date +%T) ==="
