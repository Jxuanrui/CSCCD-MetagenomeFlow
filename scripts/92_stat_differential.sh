#!/usr/bin/env bash
# ==============================================================================
# Script: 92_stat_differential.sh
# Purpose: Differential abundance analysis across bacteria, virus, and fungi
# Usage:   bash 92_stat_differential.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                      -g GROUP_COL [-d DIMENSION] [--force]
# ==============================================================================

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

WORKDIR=""
REPO=""
THREADS=""
METADATA_CSV=""
GROUP_COL=""
DIMENSION="all"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        -d) DIMENSION="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ] || [ -z "${THREADS}" ] || [ -z "${METADATA_CSV}" ] || [ -z "${GROUP_COL}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
RESULT_DIR="${WORKDIR}/result/stat/diff"
VIZ_DIR="${WORKDIR}/result/viz_differential"
LOG_DIR="${WORKDIR}/logs/stat/diff"
SENTINEL="${RESULT_DIR}/diff_summary.tsv"
VOLCANO_PDF="${VIZ_DIR}/volcano_plot.pdf"
LEFSE_PDF="${VIZ_DIR}/lefse_lda_bars.pdf"

mkdir -p "${RESULT_DIR}" "${VIZ_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/92_stat_differential.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ] && [ -s "${VOLCANO_PDF}" ] && [ -s "${LEFSE_PDF}" ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "  Volcano PDF: ${VOLCANO_PDF}"
    echo "  LEfSe PDF: ${LEFSE_PDF}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running differential abundance analysis"
echo "[INFO] Dimension: ${DIMENSION}"
echo "[INFO] Statistics dir: ${RESULT_DIR}"
echo "[INFO] Visualization dir: ${VIZ_DIR}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL DIMENSION BACT_TABLE VIR_TABLE FUNGI_DIR RESULT_DIR VIZ_DIR FORCE

(cd "${WORKDIR}" && conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${REPO}/scripts/92_differential.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 92_stat_differential.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

if [ ! -s "${VOLCANO_PDF}" ]; then
    echo "[WARN] Volcano plot not generated: ${VOLCANO_PDF}"
fi

if [ ! -s "${LEFSE_PDF}" ]; then
    echo "[WARN] LEfSe LDA plot not generated: ${LEFSE_PDF}"
fi

echo "[INFO] Differential abundance analysis completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
echo "[INFO] Visualizations: ${VIZ_DIR}"
