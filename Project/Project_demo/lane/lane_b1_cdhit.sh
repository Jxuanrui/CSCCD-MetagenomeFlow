#!/bin/bash
cd /home/labuser/Course/Maxmetagenome
source scripts/activate.sh >/dev/null 2>&1
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
echo "=== [$(date +%H:%M:%S)] B1: 18_cdhit ==="
bash scripts/18_bac_cdhit.sh -w "$WD" -r "$REPO" -t 16 2>&1 | tail -3
echo "=== B1 cdhit DONE $(date +%H:%M:%S) ==="
