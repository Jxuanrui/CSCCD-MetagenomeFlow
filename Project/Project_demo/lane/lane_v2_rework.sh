#!/usr/bin/env bash
# V2 lane (supervisor 2026-10-13 re-review P0-1/P0-2/P0-3):
# 54 union fix for the 2 samples with multi-provirus contigs (main outputs
# bit-identical, so no downstream cascade beyond what the index change needs),
# then 58 index rebuild (vOTU-only) -> 59 x6 -> 60. Strict chain.
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

fail() { echo "=== V2 ABORTED at $1 ($(date +%T)) ==="; exit 1; }

for s in Sample3 Sample10; do
    echo "=== [$(date +%T)] V2: 54_checkv $s (union full-ID dedup) ==="
    bash scripts/54_vir_checkv_contig.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "54/$s"
done

bash scripts/58_vir_salmon_build.sh -t 16 -w "$WD" -r "$REPO" --force || fail 58
for s in $SAMPLES; do bash scripts/59_vir_salmon_quant.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "59/$s"; done
bash scripts/60_vir_votu_table.sh -t 16 -w "$WD" -r "$REPO" --force || fail 60
echo "=== V2 DONE $(date +%T) ==="
