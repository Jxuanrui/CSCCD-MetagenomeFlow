#!/usr/bin/env bash
# ==============================================================================
# Script: 96b_pathway_activity.sh
# Purpose: Analyze HUMAnN3 pathway completeness, contributors, and activity
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'HELP'
Usage: bash 96b_pathway_activity.sh -w WORKDIR -m METADATA_FILE -o OUTPUT_DIR \
       -d bacteria [--min-coverage 0.5] [--top-n-contributors 5]

Required:
  -w, --workdir               Project work directory
  -m, --metadata-file         Metadata CSV/TSV
  -o, --output-dir            Output directory
  -d, --dimension             Data dimension (currently bacteria only)

Optional:
      --min-coverage          Medium/low coverage threshold (default: 0.5)
      --top-n-contributors    Contributors retained per pathway (default: 5)
  -h, --help                  Show this help message
HELP
}

METADATA_FILE=""
OUTPUT_DIR=""
DIMENSION=""
MIN_COVERAGE="0.5"
TOP_N_CONTRIBUTORS="5"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR m:METADATA_FILE o:OUTPUT_DIR d:DIMENSION"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="workdir:WORKDIR metadata-file:METADATA_FILE output-dir:OUTPUT_DIR dimension:DIMENSION min-coverage:MIN_COVERAGE top-n-contributors:TOP_N_CONTRIBUTORS"
mgx_parse "$@"
mgx_require WORKDIR METADATA_FILE OUTPUT_DIR DIMENSION

DIMENSION="$(printf '%s' "${DIMENSION}" | tr '[:upper:]' '[:lower:]')"
[[ "${DIMENSION}" == "bacteria" ]] || {
    echo "[ERROR] Pathway activity analysis currently supports only bacteria" >&2
    exit 1
}
[[ -d "${WORKDIR}" ]] || { echo "[ERROR] Work directory not found: ${WORKDIR}" >&2; exit 1; }
[[ -f "${METADATA_FILE}" ]] || { echo "[ERROR] Metadata file not found: ${METADATA_FILE}" >&2; exit 1; }
[[ "${MIN_COVERAGE}" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] || {
    echo "[ERROR] --min-coverage must be between 0 and 1: ${MIN_COVERAGE}" >&2
    exit 1
}
[[ "${TOP_N_CONTRIBUTORS}" =~ ^[1-9][0-9]*$ ]] || {
    echo "[ERROR] --top-n-contributors must be a positive integer: ${TOP_N_CONTRIBUTORS}" >&2
    exit 1
}

WORKDIR="$(cd "${WORKDIR}" && pwd)"
METADATA_FILE="$(cd "$(dirname "${METADATA_FILE}")" && pwd)/$(basename "${METADATA_FILE}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
R_SCRIPT="${SCRIPT_DIR}/96b_pathway_activity.R"
R_ENV="${REPO}/envs/r_stat"

HUMANN3_DIR=""
for candidate in \
    "${WORKDIR}/temp/31_bac_humann3" \
    "${WORKDIR}/result/humann3" \
    "${WORKDIR}/temp/humann3"; do
    if [[ -d "${candidate}" ]] && find "${candidate}" -type f -name '*_pathabundance*.tsv' -print -quit | grep -q .; then
        HUMANN3_DIR="${candidate}"
        break
    fi
done
if [[ -z "${HUMANN3_DIR}" ]]; then
    echo "[ERROR] HUMAnN3 output not found. Expected *_pathabundance.tsv under one of:" >&2
    echo "        ${WORKDIR}/temp/31_bac_humann3" >&2
    echo "        ${WORKDIR}/result/humann3" >&2
    echo "        ${WORKDIR}/temp/humann3" >&2
    exit 1
fi

[[ -f "${R_SCRIPT}" ]] || { echo "[ERROR] R script not found: ${R_SCRIPT}" >&2; exit 1; }
mkdir -p "${OUTPUT_DIR}"

PATHWAY_SUMMARY="${OUTPUT_DIR}/pathway_completeness_summary.csv"
if [ ${FORCE} -eq 0 ] && [ -f "${PATHWAY_SUMMARY}" ] && [ -s "${PATHWAY_SUMMARY}" ]; then
    echo "[INFO] 结果已存在，跳过: ${PATHWAY_SUMMARY}"; exit 0
fi

printf '[INFO] HUMAnN3 directory: %s\n' "${HUMANN3_DIR}"
printf '[INFO] Metadata: %s\n' "${METADATA_FILE}"
printf '[INFO] Output directory: %s\n' "${OUTPUT_DIR}"
printf '[INFO] Minimum coverage: %s; top contributors: %s\n' "${MIN_COVERAGE}" "${TOP_N_CONTRIBUTORS}"

R_ARGS=(
    "${R_SCRIPT}"
    --humann3-dir "${HUMANN3_DIR}"
    --metadata-file "${METADATA_FILE}"
    --output-dir "${OUTPUT_DIR}"
    --min-coverage "${MIN_COVERAGE}"
    --top-n-contributors "${TOP_N_CONTRIBUTORS}"
    --dimension "${DIMENSION}"
)

if [[ -x "${R_ENV}/bin/Rscript" ]]; then
    "${R_ENV}/bin/Rscript" "${R_ARGS[@]}"
else
    Rscript "${R_ARGS[@]}"
fi

for expected in \
    pathway_completeness_summary.csv \
    pathway_contributors_top5.csv \
    heatmap_pathway_species_contribution.pdf \
    pathway_activity_composition_correlation.csv \
    scatter_activity_composition.pdf \
    completeness_distribution.pdf; do
    [[ -s "${OUTPUT_DIR}/${expected}" ]] || {
        echo "[ERROR] Expected output missing or empty: ${OUTPUT_DIR}/${expected}" >&2
        exit 1
    }
done

echo "[INFO] Pathway activity analysis completed: ${OUTPUT_DIR}"
