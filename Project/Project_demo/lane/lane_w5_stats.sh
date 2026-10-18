#!/usr/bin/env bash
# W5 lane (CP2 closed per 7th supervisor review; user-approved plan):
# integration tables -> cross-domain analytics. Fungus integration (98d_fun)
# runs alongside bacterial/viral since inputs are ready.
# Lane self-check per 6th-ruling rule-1: permutation/bootstrap params below
# carry explicit caps — 98e ANI clustering & 98g correlations are CPU-bound
# on small tables (n=6); no n_perm/n_repeats knobs in these scripts (grep'd).
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"

fail() { echo "=== W5 ABORTED at $1 ($(date +%T)) ==="; exit 1; }

for step in 98b_bac_integration_tables 98c_vir_integration_tables 98c_bac_mge_summary 98d_bac_mag_integration 98d_fun_integration_tables; do
    echo "=== [$(date +%T)] W5: $step ==="
    bash "scripts/${step}.sh" -w "$WD" -r "$REPO" && echo "[$step] OK" || fail "$step"
done
for step in 98e_cross_domain_ani_cluster 98f_cross_domain_orthogroup 98g_cross_domain_correlation; do
    echo "=== [$(date +%T)] W5: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || fail "$step"
done
echo "=== W5 DONE $(date +%T) ==="
