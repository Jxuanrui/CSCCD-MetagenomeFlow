#!/usr/bin/env bash
# W6 tail relaunch (96 umbrella already completed in the aborted run):
# siamcat (with the required -g) -> visualization -> core microbiome ->
# LEfSe -> final report.
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
META="$WD/metadata.csv"
BACT="$WD/result/metaphlan4/merged/taxonomy_species.tsv"
VIR="$WD/result/virus/votu/votu_table.tsv"

fail() { echo "=== W6-TAIL ABORTED at $1 ($(date +%T)) ==="; exit 1; }

bash scripts/96_stat_ml_siamcat.sh -w "$WD" -r "$REPO" -t 16 -m "$META" -g group || fail siamcat
bash scripts/94_stat_visualization.sh -w "$WD" -r "$REPO" -m "$META" || fail 94

echo "=== [$(date +%T)] W6: 99a core microbiome (bacteria) ==="
bash scripts/99a_core_microbiome.sh -i "$BACT" -m "$META" -o "$WD/result/stat/core_microbiome/bacteria" -d bacteria && echo "[99a-bac] OK" || echo "[99a-bac] FAIL"
echo "=== [$(date +%T)] W6: 99a core microbiome (virus) ==="
bash scripts/99a_core_microbiome.sh -i "$VIR" -m "$META" -o "$WD/result/stat/core_microbiome/virus" -d virus && echo "[99a-vir] OK" || echo "[99a-vir] FAIL"
echo "=== [$(date +%T)] W6: 99b LEfSe (bacteria) ==="
bash scripts/99b_lefse.sh -i "$BACT" -m "$META" -o "$WD/result/stat/lefse/bacteria" -d bacteria -y rel_abundance && echo "[99b-bac] OK" || echo "[99b-bac] FAIL"

bash scripts/98_stat_report.sh -w "$WD" -r "$REPO" || fail 98report
echo "=== W6-TAIL DONE $(date +%T) ==="
