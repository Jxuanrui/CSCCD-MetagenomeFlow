#!/usr/bin/env bash
# B3-heavy annotation lane: catalog-wide heavy annotation steps (independent, continue-on-error)
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
for step in 25_bac_dbcan 30_bac_ncyc 31_bac_pcyc 31b_bac_scyc 31c_bac_pfam 31d_bac_uniprot; do
    echo "=== [$(date +%T)] B3H: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || echo "[$step] FAIL"
done
echo "=== B3-heavy DONE $(date +%T) ==="
