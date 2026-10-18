#!/usr/bin/env bash
# W5 gate (supervisor 4th review P0-2): smoke-test the fixed 91/92/93 consumers
# the moment the V3 lane finishes, BEFORE any W5/98-series stats run.
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"

while ! grep -q "V3-TAIL DONE" /tmp/lane_v3tail.log 2>/dev/null; do sleep 120; done
echo "=== [$(date +%T)] GATE: V3 done, running 91/92/93 smoke re-verification ==="

bash scripts/91_stat_diversity.sh -t 16 -w "$WD" -r "$REPO" && echo "[91] OK" || echo "[91] FAIL"
bash scripts/92_stat_differential.sh -t 16 -w "$WD" -r "$REPO" && echo "[92] OK" || echo "[92] FAIL"
bash scripts/93_stat_cooccurrence.sh -t 16 -w "$WD" -r "$REPO" && echo "[93] OK" || echo "[93] FAIL"
echo "=== GATE DONE $(date +%T) — check virus_mt status in 91 log and *_count columns excluded in 93 ==="
