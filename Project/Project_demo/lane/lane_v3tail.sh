#!/usr/bin/env bash
# V3-tail relaunch: 70 phabox2 (env fixed) -> 69 vcontact3 -> 68 iphop.
# gtdbtk (W4-A) still in pplacer — iphop is last in this chain, hours away;
# stagger rule gtdbtk-vs-iphop respected.
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"

fail() { echo "=== V3-TAIL ABORTED at $1 ($(date +%T)) ==="; exit 1; }

bash scripts/70_vir_phabox2.sh -t 16 -w "$WD" -r "$REPO" || fail 70
bash scripts/69_vir_vcontact3.sh -t 16 -w "$WD" -r "$REPO" || fail 69
bash scripts/68_vir_iphop.sh -t 16 -w "$WD" -r "$REPO" || fail 68
echo "=== V3-TAIL DONE $(date +%T) ==="
