#!/usr/bin/env bash
# ==============================================================================
# Script: 92_stat_differential.sh
# Purpose: Differential abundance analysis across bacteria, virus, and fungi
# Usage:   bash 92_stat_differential.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                      -g GROUP_COL [-d DIMENSION] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 92_stat_differential.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                    -g GROUP_COL [-d DIMENSION] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV
  -g  Group column in metadata

Optional:
  -d  Dimension: bacteria|virus|fungi|all (default: all)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

GROUP_COL=""
DIMENSION="all"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:THREADS m:METADATA_CSV g:GROUP_COL d:DIMENSION"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO THREADS METADATA_CSV GROUP_COL

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
RESULT_DIR="${WORKDIR}/result/stat"
VIZ_DIR="${WORKDIR}/result/stat"
LOG_DIR="${WORKDIR}/logs/stat/differential"
SENTINEL="${RESULT_DIR}/differential_summary.tsv"

mkdir -p "${RESULT_DIR}" "${VIZ_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/92_stat_differential.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

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

echo "[INFO] Running differential abundance analysis"
echo "[INFO] Dimension: ${DIMENSION}"
echo "[INFO] Statistics dir: ${RESULT_DIR}"
echo "[INFO] Visualization dir: ${VIZ_DIR}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL DIMENSION BACT_TABLE VIR_TABLE FUNGI_DIR RESULT_DIR VIZ_DIR FORCE

(cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/92_differential.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 92_stat_differential.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

mgx_end "differential"
echo "[INFO] Sentinel: ${SENTINEL}"
echo "[INFO] Visualizations: ${VIZ_DIR}"
