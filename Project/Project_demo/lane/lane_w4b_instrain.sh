#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# W4-B lane (last unrun MAG chain; dRep products ready since 10-14):
# 39 coverm quant x6 -> 39b instrain map x6 -> 39c instrain profile x6 ->
# 39d instrain compare. 39b->39c->39d strictly serial (per supervisor W4).
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

fail() { echo "=== W4B ABORTED at $1 ($(date +%T)) ==="; exit 1; }

for s in $SAMPLES; do echo "=== [$(date +%T)] W4B: 39_coverm $s ==="; bash scripts/39_bac_coverm_quant.sh -s "$s" -t 16 -w "$WD" -r "$REPO" || fail "39/$s"; done
for s in $SAMPLES; do bash scripts/39b_bac_instrain_map.sh -s "$s" -t 16 -w "$WD" -r "$REPO" || fail "39b/$s"; done
for s in $SAMPLES; do bash scripts/39c_bac_instrain_profile.sh -s "$s" -t 16 -w "$WD" -r "$REPO" || fail "39c/$s"; done
bash scripts/39d_bac_instrain_compare.sh -t 16 -w "$WD" -r "$REPO" || fail 39d
echo "=== W4-B DONE $(date +%T) ==="
