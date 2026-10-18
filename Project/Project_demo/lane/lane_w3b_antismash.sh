#!/usr/bin/env bash
# W3-B watcher (fill-in policy, user-approved 2026-10-14): start 28 antismash
# per-sample chain at -t 8 as soon as the W3-C fill-in lane releases its slot.
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

while ! grep -q "W3-C DONE" /tmp/lane_w3c_fillin.log 2>/dev/null; do sleep 120; done
echo "=== [$(date +%T)] W3-C done, antismash chain starts at -t 8 ==="

for s in $SAMPLES; do echo "=== [$(date +%T)] W3B: 28_antismash $s ==="; bash scripts/28_bac_antismash.sh -s "$s" -t 8 -w "$WD" -r "$REPO" && echo "[28/$s] OK" || echo "[28/$s] FAIL"; done
for s in $SAMPLES; do bash scripts/28b_bac_bgc_novelty.sh -s "$s" -t 8 -w "$WD" -r "$REPO" && echo "[28b/$s] OK" || echo "[28b/$s] FAIL"; done
echo "=== W3-B DONE $(date +%T) ==="
