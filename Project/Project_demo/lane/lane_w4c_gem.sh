#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# W4-C lane (user-approved 2026-10-15: GEM chain on top-10 MAGs by CheckM2
# comp-cont, demo scope with disclosure; full-128 would cost 2-4 days).
# 43 gapseq per MAG -> 43b carveme batch -> 43c cobrapy FBA per MAG.
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"
MAGS="Sample3__bin.019_sub Sample11__bin.009 Sample1__92 Sample10__metabat2_bin.120 Sample2__137 Sample3__154 Sample2__76 Sample1__bin.025_sub Sample4__27 Sample10__semibin2_91"

for m in $MAGS; do echo "=== [$(date +%T)] W4C: 43_gapseq $m ==="; bash scripts/43_bac_gem_gapseq.sh -m "$m" -t 8 -w "$WD" -r "$REPO" && echo "[43/$m] OK" || echo "[43/$m] FAIL"; done
for m in $MAGS; do bash scripts/43b_bac_gem_carveme.sh -m "$m" -t 8 -w "$WD" -r "$REPO" && echo "[43b/$m] OK" || echo "[43b/$m] FAIL"; done
for m in $MAGS; do bash scripts/43c_bac_gem_cobrapy_fba.sh -m "$m" -t 8 -w "$WD" -r "$REPO" && echo "[43c/$m] OK" || echo "[43c/$m] FAIL"; done
echo "=== W4-C DONE $(date +%T) ==="
