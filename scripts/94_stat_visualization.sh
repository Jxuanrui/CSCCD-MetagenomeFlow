#!/usr/bin/env bash
# ==============================================================================
# Script: 94_stat_visualization.sh
# Purpose: Unified downstream visualization across bacteria, virus, and fungi
# Usage:   bash 94_stat_visualization.sh -w WORKDIR -r REPO [-m METADATA_CSV] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 94_stat_visualization.sh -w WORKDIR -r REPO [-m METADATA_CSV] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
METADATA_CSV=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

SECONDS=0

GROUP_COL="${GROUP_COL:-group}"
BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
STAT_ROOT="${WORKDIR}/result/stat"
LOG_DIR="${WORKDIR}/logs/stat/visualization"
SENTINEL="${STAT_ROOT}/composition_done.txt"
# Per-dimension output (bacteria is the primary check; virus/fungi are bonus)
BACT_BARPLOT="${STAT_ROOT}/bacteria/composition/barplot_composition_by_group.pdf"
BACT_HEATMAP="${STAT_ROOT}/bacteria/composition/heatmap_genus.pdf"

mkdir -p "${STAT_ROOT}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/94_stat_visualization.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ -n "${METADATA_CSV}" ] && [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ] && [ -s "${BACT_BARPLOT}" ] && [ -s "${BACT_HEATMAP}" ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "  Bacteria barplot: ${BACT_BARPLOT}"
    echo "  Bacteria heatmap: ${BACT_HEATMAP}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running unified visualization"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV:-<none>}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Stat root: ${STAT_ROOT}"

export WORKDIR REPO METADATA_CSV GROUP_COL BACT_TABLE VIR_TABLE FUNGI_DIR STAT_ROOT FORCE SENTINEL

(cd "${WORKDIR}" && conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${REPO}/scripts/94_visualization.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 94_stat_visualization.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Visualization completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
