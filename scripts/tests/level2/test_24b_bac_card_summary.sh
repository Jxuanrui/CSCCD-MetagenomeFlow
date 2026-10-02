#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_24b_bac_card_summary.sh
# Purpose: Integration test for 24b_bac_card_summary.sh against
#          Test_CI_fixture -- pure statistical aggregation of an existing
#          rgi_results.txt (no new external tool), so this test focuses on
#          verifying the summary tables are produced and internally consistent.
#
# Prerequisite chain (run once, reused across test runs -- NOT cleaned up,
# unlike the one-shot summary output itself):
#   01_qc_fastp.sh -> 02_qc_kneaddata.sh -> 16_bac_megahit.sh ->
#   17_bac_prodigal.sh -> 18_bac_cdhit.sh -> 24_bac_card.sh
# If Test_CI_fixture/result/annotation/card/rgi_results.txt is missing,
# this test builds it first.
#
# Usage: bash scripts/tests/level2/test_24b_bac_card_summary.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="${REPO_ROOT}/Project/Test_CI_fixture"
SAMPLE="T01"
RGI_TXT="${FIXTURE}/result/annotation/card/rgi_results.txt"
OUT_DIR="${FIXTURE}/result/annotation/card/summary"
REPORT_TXT="${OUT_DIR}/card_summary_report.txt"

cleanup() {
    # One-shot verification output -- always cleaned up. rgi_results.txt
    # and its own prerequisites are deliberately left in place for reuse.
    rm -rf "${OUT_DIR}" "${FIXTURE}/logs/card_summary"
}
trap cleanup EXIT

if [ ! -s "${RGI_TXT}" ]; then
    echo "[INFO] rgi_results.txt not found, building prerequisite chain for ${SAMPLE}..."
    bash "${REPO_ROOT}/scripts/01_qc_fastp.sh" -s "${SAMPLE}" -t 4 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/02_qc_kneaddata.sh" -s "${SAMPLE}" -t 4 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/16_bac_megahit.sh" -s "${SAMPLE}" -t 4 -w "${FIXTURE}" -r "${REPO_ROOT}" --min-contig-len 200
    bash "${REPO_ROOT}/scripts/17_bac_prodigal.sh" -s "${SAMPLE}" -t 4 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/18_bac_cdhit.sh" -t 4 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/24_bac_card.sh" -t 4 -w "${FIXTURE}" -r "${REPO_ROOT}"
fi

if [ ! -s "${RGI_TXT}" ]; then
    echo "[FAIL] rgi_results.txt still missing after building prerequisites: ${RGI_TXT}"
    exit 1
fi

echo "[INFO] Running 24b_bac_card_summary.sh against Test_CI_fixture (${SAMPLE})..."
if ! bash "${REPO_ROOT}/scripts/24b_bac_card_summary.sh" -w "${FIXTURE}" -r "${REPO_ROOT}"; then
    echo "[FAIL] 24b_bac_card_summary.sh exited non-zero"
    exit 1
fi

if [ ! -s "${REPORT_TXT}" ]; then
    echo "[FAIL] card_summary_report.txt not found: ${REPORT_TXT}"
    exit 1
fi

TIER_TSV="${OUT_DIR}/card_confidence_tier_summary.tsv"
if [ ! -s "${TIER_TSV}" ]; then
    echo "[FAIL] card_confidence_tier_summary.tsv not found: ${TIER_TSV}"
    exit 1
fi

TOTAL_ROWS="$(($(wc -l < "${RGI_TXT}") - 1))"
TIER_SUM="$(awk -F'\t' 'NR>1{sum+=$2} END{print sum+0}' "${TIER_TSV}")"
if [ "${TIER_SUM}" -ne "${TOTAL_ROWS}" ]; then
    echo "[FAIL] tier summary N_hits sum (${TIER_SUM}) != total rgi_results.txt rows (${TOTAL_ROWS})"
    exit 1
fi

for f in card_drug_class_summary.tsv card_resistance_mechanism_summary.tsv card_snp_evidence_summary.tsv; do
    if [ ! -f "${OUT_DIR}/${f}" ]; then
        echo "[FAIL] expected output missing: ${OUT_DIR}/${f}"
        exit 1
    fi
done

echo "[PASS] 24b_bac_card_summary.sh: report + tables OK, tier sum matches total (${TOTAL_ROWS} rows)"
