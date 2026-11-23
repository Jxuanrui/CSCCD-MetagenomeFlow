#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# W5 gate v3 (2026-10-16): pre-init regression fixed (unset-only semantics);
# rerun 91/92/93 smoke verification with full parameters.
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"
META="$WD/metadata.csv"

bash scripts/91_stat_diversity.sh -w "$WD" -r "$REPO" -t 16 -m "$META" && echo "[91] OK" || echo "[91] FAIL"
bash scripts/92_stat_differential.sh -w "$WD" -r "$REPO" -t 16 -m "$META" -g group && echo "[92] OK" || echo "[92] FAIL"
bash scripts/93_stat_cooccurrence.sh -w "$WD" -r "$REPO" -t 16 -m "$META" && echo "[93] OK" || echo "[93] FAIL"
echo "=== GATE-V3 DONE $(date +%T) ==="
