#!/usr/bin/env bash
# ==============================================================================
# Script: 96c_functional_redundancy.sh
# Purpose: Quantify species-level functional redundancy and identify keystone functions
# Usage:   bash 96c_functional_redundancy.sh -f FUNCTIONAL_TSV -t TAXONOMY_TSV -o OUTPUT_DIR [-d DIMENSION] [-y TYPE] [--ml-importance CSV]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'HELP'
Usage: bash 96c_functional_redundancy.sh -f FUNCTIONAL_TSV -t TAXONOMY_TSV -o OUTPUT_DIR [options]

Required:
  -f, --functional-file  Functional abundance TSV
  -t, --taxonomy-file    Species/taxonomy abundance TSV
  -o, --output-dir       Output directory

Optional:
  -d, --dimension        bacteria|fungi|virus (default: bacteria)
  -y, --type             Functional type, e.g. kegg_ko|arg|vog (default: kegg_ko)
      --ml-importance    Optional SHAP importance CSV
  -h, --help             Show this help message
HELP
}

DIMENSION="bacteria"
FUNCTIONAL_TYPE="kegg_ko"
ML_IMPORTANCE=""

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="f:FUNCTIONAL_FILE t:TAXONOMY_FILE o:OUTPUT_DIR d:DIMENSION y:FUNCTIONAL_TYPE"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="functional-file:FUNCTIONAL_FILE taxonomy-file:TAXONOMY_FILE output-dir:OUTPUT_DIR dimension:DIMENSION type:FUNCTIONAL_TYPE ml-importance:ML_IMPORTANCE"
mgx_parse "$@"
mgx_require FUNCTIONAL_FILE TAXONOMY_FILE OUTPUT_DIR
if [[ ! -f "${FUNCTIONAL_FILE}" ]]; then echo "[ERROR] Functional file not found: ${FUNCTIONAL_FILE}" >&2; exit 1; fi
if [[ ! -f "${TAXONOMY_FILE}" ]]; then echo "[ERROR] Taxonomy file not found: ${TAXONOMY_FILE}" >&2; exit 1; fi

DIMENSION="$(printf '%s' "${DIMENSION}" | tr '[:upper:]' '[:lower:]')"
FUNCTIONAL_TYPE="$(printf '%s' "${FUNCTIONAL_TYPE}" | tr '[:upper:]' '[:lower:]')"
case "${DIMENSION}" in bacteria|fungi|virus) ;; *) echo "[ERROR] Invalid dimension: ${DIMENSION}" >&2; exit 1 ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R_SCRIPT="${SCRIPT_DIR}/96c_functional_redundancy.R"
if [[ ! -f "${R_SCRIPT}" ]]; then echo "[ERROR] R script not found: ${R_SCRIPT}" >&2; exit 1; fi
mkdir -p "${OUTPUT_DIR}"

if [[ -n "${R_SCRIPT_BIN:-}" ]]; then
    RSCRIPT="${R_SCRIPT_BIN}"
elif [[ -x "${SCRIPT_DIR}/../envs/r_stat/bin/Rscript" ]]; then
    RSCRIPT="${SCRIPT_DIR}/../envs/r_stat/bin/Rscript"
else
    RSCRIPT="$(command -v Rscript || true)"
fi
if [[ -z "${RSCRIPT}" ]]; then echo "[ERROR] Rscript executable not found" >&2; exit 1; fi

OUTPUT_SUMMARY="${OUTPUT_DIR}/redundancy_summary.tsv"
if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_SUMMARY}" ] && [ -s "${OUTPUT_SUMMARY}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_SUMMARY}"; exit 0
fi

command=("${RSCRIPT}" "${R_SCRIPT}"
  --functional-file "${FUNCTIONAL_FILE}"
  --taxonomy-file "${TAXONOMY_FILE}"
  --output-dir "${OUTPUT_DIR}"
  --dimension "${DIMENSION}"
  --type "${FUNCTIONAL_TYPE}")
if [[ -n "${ML_IMPORTANCE}" ]]; then command+=(--ml-importance "${ML_IMPORTANCE}"); fi

echo "[INFO] Running functional redundancy analysis"
echo "[INFO] Dimension/type: ${DIMENSION}/${FUNCTIONAL_TYPE}"
echo "[INFO] Output: ${OUTPUT_DIR}"
"${command[@]}"

echo "[INFO] Functional redundancy analysis completed"
