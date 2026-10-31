#!/usr/bin/env bash
# ==============================================================================
# Script: 91_stat_diversity.sh
# Purpose: Alpha/Beta diversity analysis for bacteria, virus, and fungi tables
# Usage:   bash 91_stat_diversity.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                   [-g GROUP_COL] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 91_stat_diversity.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                 [-g GROUP_COL] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV

Optional:
  -g  Group column in metadata (default: group)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

GROUP_COL="group"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:THREADS m:METADATA_CSV g:GROUP_COL"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO THREADS METADATA_CSV

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
TREE_FILE="${WORKDIR}/result/metaphlan4/merged/mpa_tree.nwk"
RESULT_DIR="${WORKDIR}/result/stat"
LOG_DIR="${WORKDIR}/logs/stat/diversity"
SENTINEL="${RESULT_DIR}/diversity_alpha_summary.tsv"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/91_stat_diversity_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=============================================================================="
echo "Diversity Analysis"
echo "Start time: $(date)"
echo "=============================================================================="

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running diversity statistics"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Results dir: ${RESULT_DIR}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL BACT_TABLE VIR_TABLE FUNGI_DIR TREE_FILE RESULT_DIR

echo "[INFO] Running R script for diversity analysis..."

(cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/91_diversity.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 91_stat_diversity.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "=============================================================================="
mgx_end "diversity"
echo "Results: ${RESULT_DIR}"
echo "Log: ${LOG_FILE}"
echo "=============================================================================="
