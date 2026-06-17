#!/usr/bin/env bash
# ==============================================================================
# Script: 91_stat_diversity.sh
# Purpose: Alpha/Beta diversity analysis for bacteria, virus, and fungi tables
# Usage:   bash 91_stat_diversity.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                   [-g GROUP_COL] [--force]
# ==============================================================================

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

WORKDIR=""
REPO=""
THREADS=""
METADATA_CSV=""
GROUP_COL="group"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ] || [ -z "${THREADS}" ] || [ -z "${METADATA_CSV}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
TREE_FILE="${WORKDIR}/result/metaphlan4/merged/mpa_tree.nwk"
RESULT_DIR="${WORKDIR}/result/stat/diversity"
VIZ_DIR="${WORKDIR}/result/viz_diversity"
LOG_DIR="${WORKDIR}/logs/stat/diversity"
SENTINEL="${RESULT_DIR}/alpha_diversity.tsv"
PCOA_PDF="${VIZ_DIR}/pcoa_ellipses_permanova.pdf"
RAREFACTION_PDF="${VIZ_DIR}/rarefaction_curves.pdf"

mkdir -p "${RESULT_DIR}" "${VIZ_DIR}" "${LOG_DIR}"
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

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ] && [ -s "${PCOA_PDF}" ] && [ -s "${RAREFACTION_PDF}" ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "  PCoA PDF: ${PCOA_PDF}"
    echo "  Rarefaction PDF: ${RAREFACTION_PDF}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running diversity statistics"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Statistics dir: ${RESULT_DIR}"
echo "[INFO] Visualization dir: ${VIZ_DIR}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL BACT_TABLE VIR_TABLE FUNGI_DIR TREE_FILE RESULT_DIR VIZ_DIR

echo "[INFO] Running R script for diversity analysis..."

(cd "${WORKDIR}" && conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${REPO}/scripts/91_diversity.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 91_stat_diversity.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

if [ ! -s "${PCOA_PDF}" ] || [ ! -s "${RAREFACTION_PDF}" ]; then
    echo "[ERROR] Expected visualization PDFs not generated under ${VIZ_DIR}"
    exit 1
fi

echo "=============================================================================="
echo "[SUCCESS] Diversity analysis completed in ${SECONDS}s"
echo "Statistics: ${RESULT_DIR}"
echo "Visualizations: ${VIZ_DIR}"
echo "Log: ${LOG_FILE}"
echo "=============================================================================="
