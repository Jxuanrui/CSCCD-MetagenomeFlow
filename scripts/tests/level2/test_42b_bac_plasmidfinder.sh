#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_42b_bac_plasmidfinder.sh
# Purpose: Integration test for 42b_bac_plasmidfinder.sh against
#          Test_CI_fixture -- exercises the "assembly-product dependency"
#          pattern (needs a real contigs.fa, not a hand-crafted fasta, since
#          PlasmidFinder's blastn step behaves differently on real assembly
#          output vs synthetic sequences).
#
# Prerequisite chain (run once, reused across test runs -- NOT cleaned up,
# unlike the one-shot plasmidfinder output itself):
#   01_qc_fastp.sh -> 02_qc_kneaddata.sh -> 16_bac_megahit.sh
# If Test_CI_fixture/result/assembly/megahit/T01/T01.contigs.fa is missing,
# this test builds it first.
#
# Usage: bash scripts/tests/level2/test_42b_bac_plasmidfinder.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="${REPO_ROOT}/Project/Test_CI_fixture"
SAMPLE="T01"
CONTIGS="${FIXTURE}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
RESULT_DIR="${FIXTURE}/result/mge/plasmidfinder/${SAMPLE}"
SENTINEL="${RESULT_DIR}/results_tab.tsv"

cleanup() {
    # One-shot verification output -- always cleaned up. The contigs.fa
    # prerequisite is deliberately left in place for reuse by future runs.
    rm -rf "${RESULT_DIR}" "${FIXTURE}/logs/plasmidfinder"
}
trap cleanup EXIT

if [ ! -s "${CONTIGS}" ]; then
    echo "[INFO] contigs.fa not found, building assembly prerequisite chain for ${SAMPLE}..."
    bash "${REPO_ROOT}/scripts/01_qc_fastp.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/02_qc_kneaddata.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/16_bac_megahit.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}" --min-contig-len 200
fi

if [ ! -s "${CONTIGS}" ]; then
    echo "[FAIL] contigs.fa still missing after building prerequisites: ${CONTIGS}"
    exit 1
fi

echo "[INFO] Running 42b_bac_plasmidfinder.sh against Test_CI_fixture (${SAMPLE})..."
if ! bash "${REPO_ROOT}/scripts/42b_bac_plasmidfinder.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}"; then
    echo "[FAIL] 42b_bac_plasmidfinder.sh exited non-zero"
    exit 1
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[FAIL] results_tab.tsv not found: ${SENTINEL}"
    exit 1
fi

N_COLS="$(head -1 "${SENTINEL}" | awk -F '\t' '{print NF}')"
if [ "${N_COLS}" -lt 3 ]; then
    echo "[FAIL] results_tab.tsv has unexpectedly few columns (${N_COLS}): ${SENTINEL}"
    exit 1
fi

echo "[PASS] 42b_bac_plasmidfinder.sh: results_tab.tsv OK (${N_COLS} columns)"
