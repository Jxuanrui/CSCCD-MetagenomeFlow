#!/usr/bin/env bash
# V-rework lane (supervisor 2026-10-13 P0 / decisions D+E+B):
# virus chain rebuilt with prefixed gene IDs, contig-level-only TPM table,
# fixed union sensitivity output. Strict chain: abort on first failure.
export MGX_MONITOR=1
WD=/home/labuser/Course/Maxmetagenome/Project/Project_demo
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

fail() { echo "=== V-REWORK ABORTED at $1 ($(date +%T)) ==="; exit 1; }

for s in $SAMPLES; do echo "=== [$(date +%T)] V: 54_checkv $s ==="; bash scripts/54_vir_checkv_contig.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "54/$s"; done
for s in $SAMPLES; do bash scripts/54b_vir_checkv_filter.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "54b/$s"; done
for s in $SAMPLES; do bash scripts/55_vir_prodigal_gv.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "55/$s"; done
bash scripts/56_vir_votu_gen.sh -t 16 -w "$WD" -r "$REPO" --force || fail 56
bash scripts/57_vir_votu_genomad.sh -t 16 -w "$WD" -r "$REPO" --force || fail 57
bash scripts/58_vir_salmon_build.sh -t 16 -w "$WD" -r "$REPO" --force || fail 58
for s in $SAMPLES; do bash scripts/59_vir_salmon_quant.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "59/$s"; done
bash scripts/60_vir_votu_table.sh -t 16 -w "$WD" -r "$REPO" --force || fail 60
echo "=== V-REWORK DONE $(date +%T) ==="
