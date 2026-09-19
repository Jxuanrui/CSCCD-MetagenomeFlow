#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_28_bac_antismash.sh
# Purpose: Integration test for 28_bac_antismash.sh (antiSMASH 8.0.4) on real
#          long contigs. The Test_CI_fixture assembly is entirely <1000bp
#          (antiSMASH hard minimum), so the test derives its input at run
#          time from the Project_example S03 assembly (2609 contigs, 363
#          >=1000bp) -- generator style, no test data committed. SKIPs (not
#          FAILs) when the source assembly or db/antismash8 is absent,
#          matching the level2 large-DB convention.
# Usage:   bash scripts/tests/level2/test_28_bac_antismash.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SOURCE_CONTIGS="${REPO_ROOT}/Project/Project_example/result/assembly/megahit/S03/S03.contigs.fa"
DB_ANTISMASH8="${REPO_ROOT}/db/antismash8"
SAMPLE="T28"
MAX_CONTIGS=20

if [ ! -s "${SOURCE_CONTIGS}" ]; then
    echo "[SKIP] Project_example S03 assembly not present: ${SOURCE_CONTIGS}"
    exit 0
fi
if [ ! -d "${DB_ANTISMASH8}" ]; then
    echo "[SKIP] db/antismash8 not downloaded yet, skipping test"
    exit 0
fi

WORKDIR="$(mktemp -d /tmp/mgx_test28_XXXXXX)"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

echo "[INFO] Deriving >=1000bp contig subset (first ${MAX_CONTIGS}) from S03..."
mkdir -p "${WORKDIR}/result/assembly/megahit/${SAMPLE}"
# seqkit head closes its stdin once it has n records -> upstream seqkit dies on
# SIGPIPE under pipefail; split into two file-based steps instead of a pipe.
TMP_LONG="${WORKDIR}/long_ge1000.fa"
"${REPO_ROOT}/envs/assembly/bin/seqkit" seq -m 1000 -w 0 "${SOURCE_CONTIGS}" > "${TMP_LONG}"
"${REPO_ROOT}/envs/assembly/bin/seqkit" head -n "${MAX_CONTIGS}" "${TMP_LONG}" \
    > "${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
rm -f "${TMP_LONG}"

N_CONTIGS=$(grep -c '^>' "${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa" || true)
echo "[INFO] ${SAMPLE}: ${N_CONTIGS} contigs >=1000bp"
if [ "${N_CONTIGS}" -eq 0 ]; then
    echo "[SKIP] no >=1000bp contigs in source assembly"
    exit 0
fi

echo "[INFO] Running 28_bac_antismash.sh (antiSMASH 8.0.4)..."
bash "${REPO_ROOT}/scripts/28_bac_antismash.sh" \
    -s "${SAMPLE}" -t 8 -w "${WORKDIR}" -r "${REPO_ROOT}" --force

RESULT_DIR="${WORKDIR}/result/annotation/antismash/${SAMPLE}"
SENTINEL="${RESULT_DIR}/antismash_done.txt"

# --- Assertions ---------------------------------------------------------------
fail() { echo "[FAIL] $1"; exit 1; }

[ -f "${SENTINEL}" ] || fail "sentinel missing: ${SENTINEL}"
[ -s "${RESULT_DIR}/${SAMPLE}.contigs.json" ] || fail "antismash output JSON missing: ${RESULT_DIR}/${SAMPLE}.contigs.json"
[ -s "${RESULT_DIR}/${SAMPLE}.contigs.gbk" ] || fail "annotated GenBank missing: ${RESULT_DIR}/${SAMPLE}.contigs.gbk"

N_REGIONS=$(find "${RESULT_DIR}" -name "*.region*.gbk" 2>/dev/null | wc -l || true)
echo "[INFO] regions found: ${N_REGIONS} (informational; gut contigs may legitimately have 0)"

echo ""
echo "=============================================================================="
echo "[PASS] 28_bac_antismash integration test: exit 0, sentinel present,"
echo "       output structure valid, ${N_REGIONS} region(s) on ${N_CONTIGS} real contigs."
echo "=============================================================================="
