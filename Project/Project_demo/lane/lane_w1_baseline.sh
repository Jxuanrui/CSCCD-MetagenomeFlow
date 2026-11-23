#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# W1 baseline rebuild (supervisor CP2-MAG condition C1, user-approved approve A).
# Shadow-workdir approach: symlink dastool bins into an isolated workdir, run
# 37/38/38b there (scripts fall back to dastool bins when reassembly/ absent),
# then copy outputs into result/binning/{checkm2,drep,gunc}_w1_baseline/.
# The REAL result paths (incl. drep output gtdbtk is reading right now) are
# never touched — lower risk than moving reassembly/ aside.
export MGX_MONITOR=1
export PATH="${REPO}/miniforge3/bin:$PATH"
REAL="$REPO/Project/Project_demo"
SHADOW="/tmp/w1_baseline_shadow"
cd "$REPO"

fail() { echo "=== BASELINE REBUILD ABORTED at $1 ($(date +%T)) ==="; exit 1; }

rm -rf "$SHADOW"
mkdir -p "$SHADOW/result/binning" "$SHADOW/temp" "$SHADOW/logs"
ln -s "$REAL/result/binning/dastool" "$SHADOW/result/binning/dastool"

echo "=== [$(date +%T)] W1 baseline: 37_checkm2 (shadow, dastool bins) ==="
bash scripts/37_bac_checkm2.sh -t 16 -w "$SHADOW" -r "$REPO" || fail 37
echo "=== [$(date +%T)] W1 baseline: 38_drep ==="
bash scripts/38_bac_drep.sh -t 16 -w "$SHADOW" -r "$REPO" || fail 38
echo "=== [$(date +%T)] W1 baseline: 38b_gunc ==="
bash scripts/38b_bac_gunc.sh -t 16 -w "$SHADOW" -r "$REPO" || fail 38b

echo "=== [$(date +%T)] archiving baseline to real workdir ==="
rm -rf "$REAL/result/binning/checkm2_w1_baseline" "$REAL/result/binning/drep_w1_baseline" "$REAL/result/binning/gunc_w1_baseline"
cp -r "$SHADOW/result/binning/checkm2" "$REAL/result/binning/checkm2_w1_baseline"
cp -r "$SHADOW/result/binning/drep"    "$REAL/result/binning/drep_w1_baseline"
cp -r "$SHADOW/result/binning/gunc"    "$REAL/result/binning/gunc_w1_baseline"
echo "checkm2_w1_baseline/report: $(wc -l < "$REAL/result/binning/checkm2_w1_baseline/quality_report.tsv") lines"
echo "drep_w1_baseline/genomes:   $(ls "$REAL/result/binning/drep_w1_baseline/dereplicated_genomes"/*.fa 2>/dev/null | wc -l)"
rm -rf "$SHADOW"
echo "=== W1 BASELINE REBUILD DONE $(date +%T) ==="
