#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# B3-light annotation lane: catalog-wide light annotation steps (independent, continue-on-error)
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"
cd "$REPO"
for step in 23_bac_amrfinder 24_bac_card 24b_bac_card_summary 26_bac_vfdb 27_bac_bacmet 29_bac_defense_finder; do
    echo "=== [$(date +%T)] B3L: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || echo "[$step] FAIL"
done
echo "=== B3-light DONE $(date +%T) ==="
