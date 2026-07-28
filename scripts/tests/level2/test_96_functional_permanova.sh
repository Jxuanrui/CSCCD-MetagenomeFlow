#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_96_functional_permanova.sh
# Purpose: Integration test for 96_functional_permanova.sh against
#          Test_CI_fixture -- exercises the "post-pipeline processed
#          product" input-dependency pattern (reads result/stat/metadata.tsv,
#          not the raw metadata.csv).
# Usage:   bash scripts/tests/level2/test_96_functional_permanova.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="${REPO_ROOT}/Project/Test_CI_fixture"
OUT_DIR="${FIXTURE}/result/stat/bacteria/functional"
SENTINEL="${OUT_DIR}/bacteria_permanova_done.txt"
STATUS_TSV="${OUT_DIR}/bacteria_permanova_status.tsv"

cleanup() {
    rm -rf "${OUT_DIR}" "${FIXTURE}/logs/stat/bacteria/functional"
}
trap cleanup EXIT

echo "[INFO] Ensuring fixture functional table exists..."
if [ ! -f "${FIXTURE}/result/integration/bacteria/kegg_ko_abundance.tsv" ]; then
    conda run --prefix "${REPO_ROOT}/envs/r_stat" --no-capture-output \
        Rscript "${REPO_ROOT}/scripts/tests/level2/generate_fixture_functional_table.R" "${REPO_ROOT}"
fi

STAT_METADATA="${FIXTURE}/result/stat/metadata.tsv"
if [ ! -f "${STAT_METADATA}" ]; then
    echo "[INFO] Generating fixture result/stat/metadata.tsv (post-pipeline processed product)..."
    mkdir -p "$(dirname "${STAT_METADATA}")"
    {
        printf '\tsample_id\tgroup\tsubject_id\tage\tBMI\n'
        printf 'T01\tT01\tcontrol\tC01\t35\t22.5\n'
        printf 'T02\tT02\tcontrol\tC02\t41\t24.1\n'
        printf 'T03\tT03\ttreat\tC03\t38\t23.0\n'
        printf 'T04\tT04\ttreat\tC04\t44\t25.3\n'
    } > "${STAT_METADATA}"
fi

echo "[INFO] Running 96_functional_permanova.sh against Test_CI_fixture (bacteria)..."
if ! bash "${REPO_ROOT}/scripts/96_functional_permanova.sh" \
        -w "${FIXTURE}" -r "${REPO_ROOT}" -d bacteria --force; then
    echo "[FAIL] 96_functional_permanova.sh exited non-zero"
    exit 1
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[FAIL] Sentinel not found: ${SENTINEL}"
    exit 1
fi

if [ ! -s "${STATUS_TSV}" ]; then
    echo "[FAIL] Status TSV not found: ${STATUS_TSV}"
    exit 1
fi

if ! awk -F '\t' 'NR > 1 && $2 != "OK" { bad = 1 } END { exit bad }' "${STATUS_TSV}"; then
    echo "[FAIL] Status TSV contains non-OK rows:"
    cat "${STATUS_TSV}"
    exit 1
fi

echo "[PASS] 96_functional_permanova.sh: sentinel + status.tsv OK"
