#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_91_stat_diversity.sh
# Purpose: Integration test for 91_stat_diversity.sh against Test_CI_fixture --
#          exercises the "raw integration product" input-dependency pattern
#          (reads result/metaphlan4/merged/taxonomy.tsv directly, no
#          result/stat pre-processing step). Virus/fungi tables are
#          intentionally absent from the fixture, so this also exercises the
#          script's graceful-skip path for missing dimensions.
# Usage:   bash scripts/tests/level2/test_91_stat_diversity.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="${REPO_ROOT}/Project/Test_CI_fixture"
RESULT_DIR="${FIXTURE}/result/stat"
SENTINEL="${RESULT_DIR}/diversity_alpha_summary.tsv"

cleanup() {
    rm -rf "${RESULT_DIR}" "${FIXTURE}/logs/stat"
}
trap cleanup EXIT

echo "[INFO] Ensuring fixture taxonomy table exists..."
if [ ! -f "${FIXTURE}/result/metaphlan4/merged/taxonomy.tsv" ]; then
    conda run --prefix "${REPO_ROOT}/envs/r_stat" --no-capture-output \
        Rscript "${REPO_ROOT}/scripts/tests/level2/generate_fixture_taxonomy_table.R" "${REPO_ROOT}"
fi

echo "[INFO] Running 91_stat_diversity.sh against Test_CI_fixture..."
if ! bash "${REPO_ROOT}/scripts/91_stat_diversity.sh" \
        -w "${FIXTURE}" -r "${REPO_ROOT}" -t 2 -m "${FIXTURE}/metadata.csv" --force; then
    echo "[FAIL] 91_stat_diversity.sh exited non-zero"
    exit 1
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[FAIL] Sentinel not found: ${SENTINEL}"
    exit 1
fi

if ! awk -F '\t' 'NR == 1 { next } { n++ } END { exit (n > 0 ? 0 : 1) }' "${SENTINEL}"; then
    echo "[FAIL] Sentinel has no data rows: ${SENTINEL}"
    exit 1
fi

echo "[PASS] 91_stat_diversity.sh: alpha diversity summary sentinel OK"
