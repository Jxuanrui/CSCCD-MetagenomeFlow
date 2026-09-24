#!/usr/bin/env bash
# ==============================================================================
# Script: 99a_core_microbiome.sh
# Purpose: Identify and visualize global and group-specific core microbiomes
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 99a_core_microbiome.sh -i ABUNDANCE_TSV -m METADATA_CSV \
       -o OUTPUT_DIR -d DIMENSION [--prevalence-threshold 0.5] \
       [--min-abundance 0.0001]

Required:
  -i, --abundance-file       Feature-by-sample TSV
  -m, --metadata-file        CSV containing sample_id and optionally group
  -o, --output-dir           Output directory
  -d, --dimension            Data dimension: bacteria, fungi, or virus

Optional:
      --prevalence-threshold Minimum prevalence for core features (default: 0.5)
      --min-abundance        Values below this abundance become zero (default: 0.0001)
  -h, --help                 Show this help message
EOF
}

PREVALENCE_THRESHOLD="0.5"
MIN_ABUNDANCE="0.0001"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="i:ABUNDANCE_FILE m:METADATA_FILE o:OUTPUT_DIR d:DIMENSION"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="abundance-file:ABUNDANCE_FILE metadata-file:METADATA_FILE output-dir:OUTPUT_DIR dimension:DIMENSION prevalence-threshold:PREVALENCE_THRESHOLD min-abundance:MIN_ABUNDANCE"
mgx_parse "$@"
mgx_require ABUNDANCE_FILE METADATA_FILE OUTPUT_DIR DIMENSION

case "${DIMENSION}" in
    bacteria|fungi|virus) ;;
    *) echo "[ERROR] Dimension must be bacteria, fungi, or virus: ${DIMENSION}" >&2; exit 1 ;;
esac

[[ -f "${ABUNDANCE_FILE}" ]] || { echo "[ERROR] Abundance file not found: ${ABUNDANCE_FILE}" >&2; exit 1; }
[[ -f "${METADATA_FILE}" ]] || { echo "[ERROR] Metadata file not found: ${METADATA_FILE}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
R_SCRIPT="${SCRIPT_DIR}/99a_core_microbiome.R"
R_ENV="${REPO}/envs/r_stat"

[[ -f "${R_SCRIPT}" ]] || { echo "[ERROR] R script not found: ${R_SCRIPT}" >&2; exit 1; }
mkdir -p "${OUTPUT_DIR}"

OUTPUT_SUMMARY="${OUTPUT_DIR}/core_microbiome_summary.tsv"
if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_SUMMARY}" ] && [ -s "${OUTPUT_SUMMARY}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_SUMMARY}"; exit 0
fi

echo "[INFO] Running core microbiome analysis"
echo "[INFO] Input: ${ABUNDANCE_FILE}"
echo "[INFO] Metadata: ${METADATA_FILE}"
echo "[INFO] Dimension: ${DIMENSION}"
echo "[INFO] Prevalence threshold: ${PREVALENCE_THRESHOLD}; minimum abundance: ${MIN_ABUNDANCE}"

R_ARGS=(
    "${R_SCRIPT}"
    --abundance-file "${ABUNDANCE_FILE}"
    --metadata-file "${METADATA_FILE}"
    --output-dir "${OUTPUT_DIR}"
    --prevalence-threshold "${PREVALENCE_THRESHOLD}"
    --min-abundance "${MIN_ABUNDANCE}"
    --dimension "${DIMENSION}"
)

if [[ -x "${R_ENV}/bin/Rscript" ]]; then
    "${R_ENV}/bin/Rscript" "${R_ARGS[@]}"
else
    Rscript "${R_ARGS[@]}"
fi

for expected in \
    core_microbiome_global.csv \
    core_microbiome_case.csv \
    core_microbiome_control.csv \
    core_microbiome_summary.txt \
    venn_diagram.pdf \
    prevalence_curve.pdf \
    core_abundance_barplot.pdf; do
    [[ -s "${OUTPUT_DIR}/${expected}" ]] || {
        echo "[ERROR] Expected output missing or empty: ${OUTPUT_DIR}/${expected}" >&2
        exit 1
    }
done

echo "[INFO] Core microbiome analysis completed: ${OUTPUT_DIR}"
