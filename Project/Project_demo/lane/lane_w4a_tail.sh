#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"
for step in 41_bac_prokka 41b_bac_mlst 41c_bac_pangenome 41d_bac_snippy; do
    echo "=== [$(date +%T)] W4A-TAIL: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || { echo "=== W4A-TAIL ABORTED at $step ==="; exit 1; }
done
echo "=== W4A-TAIL DONE $(date +%T) ==="
