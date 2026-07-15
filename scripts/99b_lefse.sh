#!/usr/bin/env bash
# ==============================================================================
# Script: 95b_stat_lefse.sh
# Purpose: Run LEfSe-like biomarker discovery on a feature-by-sample table
# ==============================================================================

set -euo pipefail

show_help() {
cat <<'EOF'
Usage: bash 95b_stat_lefse.sh -i ABUNDANCE_TSV -m METADATA_CSV -o OUTPUT_DIR \
       -d DIMENSION -y TYPE [--lda-threshold 2.0] [--min-prevalence 0.1]

Required:
  -i, --abundance-file  Feature-by-sample TSV
  -m, --metadata-file   CSV containing sample_id and group columns
  -o, --output-dir      Output directory
  -d, --dimension       Data dimension: bacteria, fungi, or virus
  -y, --type            Feature type: taxonomy, kegg_ko, arg, etc.

Optional:
      --lda-threshold   Minimum LDA score (default: 2.0)
      --min-prevalence  Minimum non-zero sample prevalence (default: 0.1)
      --wilcoxon-alpha  Wilcoxon validation alpha (default: 0.05)
  -h, --help            Show this help message
EOF
}

ABUNDANCE_FILE=""
METADATA_FILE=""
OUTPUT_DIR=""
DIMENSION=""
TYPE=""
LDA_THRESHOLD="2.0"
MIN_PREVALENCE="0.1"
WILCOXON_ALPHA="0.05"

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "[ERROR] Missing value for $1" >&2
        show_help >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--abundance-file) require_value "$@"; ABUNDANCE_FILE="$2"; shift 2 ;;
        -m|--metadata-file) require_value "$@"; METADATA_FILE="$2"; shift 2 ;;
        -o|--output-dir) require_value "$@"; OUTPUT_DIR="$2"; shift 2 ;;
        -d|--dimension) require_value "$@"; DIMENSION="$2"; shift 2 ;;
        -y|--type) require_value "$@"; TYPE="$2"; shift 2 ;;
        --lda-threshold) require_value "$@"; LDA_THRESHOLD="$2"; shift 2 ;;
        --min-prevalence) require_value "$@"; MIN_PREVALENCE="$2"; shift 2 ;;
        --wilcoxon-alpha) require_value "$@"; WILCOXON_ALPHA="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; show_help >&2; exit 1 ;;
    esac
done

if [[ -z "${ABUNDANCE_FILE}" || -z "${METADATA_FILE}" || -z "${OUTPUT_DIR}" ||
      -z "${DIMENSION}" || -z "${TYPE}" ]]; then
    echo "[ERROR] Missing required arguments" >&2
    show_help >&2
    exit 1
fi

[[ -f "${ABUNDANCE_FILE}" ]] || { echo "[ERROR] Abundance file not found: ${ABUNDANCE_FILE}" >&2; exit 1; }
[[ -f "${METADATA_FILE}" ]] || { echo "[ERROR] Metadata file not found: ${METADATA_FILE}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
R_SCRIPT="${SCRIPT_DIR}/99b_lefse.R"
R_ENV="${REPO}/envs/r_stat"

[[ -f "${R_SCRIPT}" ]] || { echo "[ERROR] R script not found: ${R_SCRIPT}" >&2; exit 1; }
mkdir -p "${OUTPUT_DIR}"

echo "[INFO] Running LEfSe analysis"
echo "[INFO] Input: ${ABUNDANCE_FILE}"
echo "[INFO] Metadata: ${METADATA_FILE}"
echo "[INFO] Dimension/type: ${DIMENSION}/${TYPE}"
echo "[INFO] LDA threshold: ${LDA_THRESHOLD}; prevalence: ${MIN_PREVALENCE}"

R_ARGS=(
    "${R_SCRIPT}"
    --abundance-file "${ABUNDANCE_FILE}"
    --metadata-file "${METADATA_FILE}"
    --output-dir "${OUTPUT_DIR}"
    --lda-threshold "${LDA_THRESHOLD}"
    --wilcoxon-alpha "${WILCOXON_ALPHA}"
    --min-prevalence "${MIN_PREVALENCE}"
    --dimension "${DIMENSION}"
    --type "${TYPE}"
)

if [[ -x "${R_ENV}/bin/Rscript" ]]; then
    "${R_ENV}/bin/Rscript" "${R_ARGS[@]}"
else
    Rscript "${R_ARGS[@]}"
fi

for expected in lefse_results.tsv lefse_barplot.pdf; do
    [[ -s "${OUTPUT_DIR}/${expected}" ]] || {
        echo "[ERROR] Expected output missing or empty: ${OUTPUT_DIR}/${expected}" >&2
        exit 1
    }
done

echo "[INFO] LEfSe analysis completed: ${OUTPUT_DIR}"
