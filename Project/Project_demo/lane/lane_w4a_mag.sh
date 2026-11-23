#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# W4-A lane (unblocked by R-lane completion 16:33; user-approved plan):
# taxonomy + annotation chain on the 128 dereplicated MAGs.
# Strict chain: gtdbtk -> prokka -> mlst -> pangenome -> snippy.
# gtdbtk/iphop stagger respected: V3's iphop is ~10h away at chain tail.
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"

fail() { echo "=== W4A ABORTED at $1 ($(date +%T)) ==="; exit 1; }

for step in 40_bac_gtdbtk 41_bac_prokka 41b_bac_mlst 41c_bac_pangenome 41d_bac_snippy; do
    echo "=== [$(date +%T)] W4A: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || fail "$step"
done
echo "=== W4-A DONE $(date +%T) ==="
