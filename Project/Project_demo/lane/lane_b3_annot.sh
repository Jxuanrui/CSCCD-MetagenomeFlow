#!/bin/bash
cd /home/labuser/Course/Maxmetagenome
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome

echo "=== [$(date +%H:%M:%S)] B3: 21_eggNOG ==="
bash scripts/21_bac_eggnog.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3

echo "=== [$(date +%H:%M:%S)] B3: 22_KEGG ==="
bash scripts/22_bac_kegg.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3
echo "=== B3 eggNOG+KEGG DONE $(date +%H:%M:%S) ==="
