#!/usr/bin/env bash
# W6 lane (W5 done 03:53; 96-series dependency 98b satisfied):
# functional stats umbrella -> SIAMCAT ML -> visualization -> core microbiome
# (bacteria via metaphlan4 merged species; virus via votu_table) -> LEfSe
# standalone -> final report. Parameter self-check: no n_perm/n_repeats knobs
# in these scripts (grep-verified); SIAMCAT on n=6 expected exploratory only.
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
META="$WD/metadata.csv"
BACT="$WD/result/metaphlan4/merged/taxonomy_species.tsv"
VIR="$WD/result/virus/votu/votu_table.tsv"

fail() { echo "=== W6 ABORTED at $1 ($(date +%T)) ==="; exit 1; }

[ -f "$WD/result/stat/functional/functional_analysis_done.txt" ] || grep -q "96" /tmp/lane_w6_final.log 2>/dev/null && echo "[96] already ran" || bash scripts/96_stat_functional.sh -w "$WD" -r "$REPO" -m "$META" || fail 96
bash scripts/96_stat_ml_siamcat.sh -w "$WD" -r "$REPO" -t 16 -m "$META" || fail siamcat
bash scripts/94_stat_visualization.sh -w "$WD" -r "$REPO" -m "$META" || fail 94

echo "=== [$(date +%T)] W6: 99a core microbiome (bacteria) ==="
bash scripts/99a_core_microbiome.sh -i "$BACT" -m "$META" -o "$WD/result/stat/core_microbiome/bacteria" -d bacteria && echo "[99a-bac] OK" || echo "[99a-bac] FAIL"
echo "=== [$(date +%T)] W6: 99a core microbiome (virus) ==="
bash scripts/99a_core_microbiome.sh -i "$VIR" -m "$META" -o "$WD/result/stat/core_microbiome/virus" -d virus && echo "[99a-vir] OK" || echo "[99a-vir] FAIL"
echo "=== [$(date +%T)] W6: 99b LEfSe (bacteria) ==="
bash scripts/99b_lefse.sh -i "$BACT" -m "$META" -o "$WD/result/stat/lefse/bacteria" -d bacteria -y rel_abundance && echo "[99b-bac] OK" || echo "[99b-bac] FAIL"

bash scripts/98_stat_report.sh -w "$WD" -r "$REPO" || fail 98report
echo "=== W6 DONE $(date +%T) ==="
