#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# R lane (supervisor 2026-10-13 P0-2 / decision A):
# 36b reassembly x6 strictly serial (assembler mutex), then 37/38/38b --force.
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

for s in $SAMPLES; do
    echo "=== [$(date +%T)] R: 36b_reassembly $s ==="
    bash scripts/36b_bac_bin_reassembly.sh -s "$s" -t 16 -w "$WD" -r "$REPO" || { echo "=== R-ABORTED at 36b/$s ==="; exit 1; }
done

# W3: defensive re-stage + quality chain redo (37 auto-detects reassembled_bins anyway)
rm -f "$WD/temp/checkm2_input/.done"
rm -rf "$WD/result/binning/checkm2/drep_input"
bash scripts/37_bac_checkm2.sh -t 16 -w "$WD" -r "$REPO" --force || { echo "=== R-ABORTED at 37 ==="; exit 1; }
bash scripts/38_bac_drep.sh -t 16 -w "$WD" -r "$REPO" --force || { echo "=== R-ABORTED at 38 ==="; exit 1; }
bash scripts/38b_bac_gunc.sh -t 16 -w "$WD" -r "$REPO" --force || { echo "=== R-ABORTED at 38b ==="; exit 1; }
echo "=== R-LANE DONE $(date +%T) ==="
