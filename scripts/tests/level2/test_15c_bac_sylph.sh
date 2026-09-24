#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_15c_bac_sylph.sh
# Purpose: Integration test for 15c_bac_sylph.sh + 15d_bac_sylph_merge.sh
#          against Test_CI_fixture. Requires the real GTDB-R220 sylph
#          database (13.1GB) + taxonomy metadata to be present; SKIPs
#          (not FAILs) if the database hasn't been downloaded yet, matching
#          the project's existing convention for large-DB-dependent tools
#          (e.g. 76_fun_ccmetagen.sh's nt-DB skip pattern).
#
# Prerequisite: 02_qc_kneaddata.sh output for sample T01 (already present
# in Test_CI_fixture as a shared prerequisite for other level2 tests).
#
# Usage: bash scripts/tests/level2/test_15c_bac_sylph.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="${REPO_ROOT}/Project/Test_CI_fixture"
SAMPLE="T01"

DB_SYLDB="${REPO_ROOT}/db/sylph/gtdb-r220-c200-dbv1.syldb"
DB_METADATA="${REPO_ROOT}/db/sylph/gtdb_r220_metadata.tsv.gz"

if [ ! -s "${DB_SYLDB}" ] || [ ! -s "${DB_METADATA}" ]; then
    echo "[SKIP] sylph GTDB-R220 database or taxonomy metadata not present, skipping test"
    echo "       (${DB_SYLDB}, ${DB_METADATA})"
    exit 0
fi

RESULT_DIR="${FIXTURE}/result/sylph/${SAMPLE}"
MERGED_DIR="${FIXTURE}/result/sylph/merged"
SYLPHMPA="${RESULT_DIR}/${SAMPLE}.sylphmpa"
MERGED_TSV="${MERGED_DIR}/sylph_profile_merged.tsv"

cleanup() {
    # One-shot verification output -- always cleaned up.
    rm -rf "${FIXTURE}/result/sylph" "${FIXTURE}/logs/sylph"
}
trap cleanup EXIT

INPUT_R1="${FIXTURE}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
if [ ! -s "${INPUT_R1}" ]; then
    echo "[INFO] kneaddata output not found, building QC prerequisite chain for ${SAMPLE}..."
    bash "${REPO_ROOT}/scripts/01_qc_fastp.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}"
    bash "${REPO_ROOT}/scripts/02_qc_kneaddata.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}"
fi

if [ ! -s "${INPUT_R1}" ]; then
    echo "[FAIL] kneaddata output still missing after building prerequisites: ${INPUT_R1}"
    exit 1
fi

echo "[INFO] Running 15c_bac_sylph.sh against Test_CI_fixture (${SAMPLE})..."
if ! bash "${REPO_ROOT}/scripts/15c_bac_sylph.sh" -s "${SAMPLE}" -t 2 -w "${FIXTURE}" -r "${REPO_ROOT}"; then
    echo "[FAIL] 15c_bac_sylph.sh exited non-zero"
    exit 1
fi

if [ ! -s "${SYLPHMPA}" ]; then
    echo "[FAIL] ${SAMPLE}.sylphmpa not found: ${SYLPHMPA}"
    exit 1
fi

N_LINES="$(wc -l < "${SYLPHMPA}")"
if [ "${N_LINES}" -lt 3 ]; then
    echo "[FAIL] ${SAMPLE}.sylphmpa has unexpectedly few lines (${N_LINES}): ${SYLPHMPA}"
    exit 1
fi

echo "[INFO] Running 15d_bac_sylph_merge.sh against Test_CI_fixture..."
if ! bash "${REPO_ROOT}/scripts/15d_bac_sylph_merge.sh" -w "${FIXTURE}" -r "${REPO_ROOT}"; then
    echo "[FAIL] 15d_bac_sylph_merge.sh exited non-zero"
    exit 1
fi

if [ ! -s "${MERGED_TSV}" ]; then
    echo "[FAIL] sylph_profile_merged.tsv not found: ${MERGED_TSV}"
    exit 1
fi

N_COLS="$(head -1 "${MERGED_TSV}" | awk -F '\t' '{print NF}')"
if [ "${N_COLS}" -lt 2 ]; then
    echo "[FAIL] sylph_profile_merged.tsv has unexpectedly few columns (${N_COLS}): ${MERGED_TSV}"
    exit 1
fi

echo "[PASS] 15c_bac_sylph.sh + 15d_bac_sylph_merge.sh: sylph_profile_merged.tsv OK (${N_COLS} columns)"
