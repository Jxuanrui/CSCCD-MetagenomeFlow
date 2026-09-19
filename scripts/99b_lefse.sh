#!/usr/bin/env bash
# ==============================================================================
# Script: 95b_stat_lefse.sh
# Purpose: Run LEfSe-like biomarker discovery on a feature-by-sample table
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

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

LDA_THRESHOLD="2.0"
MIN_PREVALENCE="0.1"
WILCOXON_ALPHA="0.05"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="i:ABUNDANCE_FILE m:METADATA_FILE o:OUTPUT_DIR d:DIMENSION y:TYPE"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="abundance-file:ABUNDANCE_FILE metadata-file:METADATA_FILE output-dir:OUTPUT_DIR dimension:DIMENSION type:TYPE lda-threshold:LDA_THRESHOLD min-prevalence:MIN_PREVALENCE wilcoxon-alpha:WILCOXON_ALPHA"
mgx_parse "$@"
mgx_require ABUNDANCE_FILE METADATA_FILE OUTPUT_DIR DIMENSION TYPE

[[ -f "${ABUNDANCE_FILE}" ]] || { echo "[ERROR] Abundance file not found: ${ABUNDANCE_FILE}" >&2; exit 1; }
[[ -f "${METADATA_FILE}" ]] || { echo "[ERROR] Metadata file not found: ${METADATA_FILE}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
R_SCRIPT="${SCRIPT_DIR}/99b_lefse.R"
R_ENV="${REPO}/envs/r_stat"

[[ -f "${R_SCRIPT}" ]] || { echo "[ERROR] R script not found: ${R_SCRIPT}" >&2; exit 1; }
mkdir -p "${OUTPUT_DIR}"

OUTPUT_BIOMARKERS="${OUTPUT_DIR}/lefse_biomarkers.tsv"
if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_BIOMARKERS}" ] && [ -s "${OUTPUT_BIOMARKERS}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_BIOMARKERS}"; exit 0
fi

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
