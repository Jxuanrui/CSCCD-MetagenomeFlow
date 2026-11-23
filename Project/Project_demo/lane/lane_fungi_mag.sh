#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# 79c-f fungi MAG chain watcher (user approved 2026-10-14, supervisor 4th
# review decision #4): starts when the F lane finishes; all 6 samples with
# continue-on-error (only Sample4 has fungal assembly content by design).
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

while ! grep -q "F-LANE DONE" /tmp/lane_f_fungi.log 2>/dev/null; do sleep 120; done
echo "=== [$(date +%T)] F done, fungi MAG chain (79c-79f) starts ==="

for s in $SAMPLES; do echo "=== [$(date +%T)] FM: 79c_coverm $s ==="; bash scripts/79c_fun_coverm_depth.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[79c/$s] OK" || echo "[79c/$s] FAIL"; done
for s in $SAMPLES; do bash scripts/79d_fun_metabat2.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[79d/$s] OK" || echo "[79d/$s] FAIL"; done
for s in $SAMPLES; do bash scripts/79e_fun_euk_qc_per_bin.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[79e/$s] OK" || echo "[79e/$s] FAIL"; done
for s in $SAMPLES; do bash scripts/79f_fun_metaeuk_per_bin.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[79f/$s] OK" || echo "[79f/$s] FAIL"; done
echo "=== FUNGI-MAG DONE $(date +%T) ==="
