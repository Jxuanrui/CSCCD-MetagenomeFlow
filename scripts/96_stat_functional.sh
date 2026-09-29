#!/usr/bin/env bash
# ==============================================================================
# Script: 96_stat_functional.sh
# Purpose: Functional differential abundance analysis using Maaslin3
# Input:   Functional abundance table selected by dimension and functional type
# Methods: Maaslin3 (differential analysis) + Hypergeometric test (enrichment)
# Usage:   bash 96_stat_functional.sh -w WORKDIR -r REPO [-m METADATA_CSV] [-d DIMENSION] [-t FUNC_TYPE] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 96_stat_functional.sh -w WORKDIR -r REPO [-m METADATA_CSV] [-d DIMENSION] [-t FUNC_TYPE] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV
  -d  Dimension: bacteria|fungi|virus (default: bacteria)
  -t  Functional type: pathway|kegg_ko|cog|cazyme|arg|vfdb|defense|ncyc|pcyc|funomic|amr|merops|phrog|vog|lifestyle|host_genus|viral_family
      default: pathway
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

METADATA_CSV=""
DIMENSION="bacteria"
FUNC_TYPE="pathway"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV d:DIMENSION t:FUNC_TYPE"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

# Normalize and validate batch parameters
DIMENSION="$(printf '%s' "${DIMENSION}" | tr '[:upper:]' '[:lower:]')"
FUNC_TYPE="$(printf '%s' "${FUNC_TYPE}" | tr '[:upper:]' '[:lower:]')"

case "${DIMENSION}" in
    bacteria|fungi|virus) ;;
    *) echo "[ERROR] Invalid dimension: ${DIMENSION}"; show_help; exit 1 ;;
esac

case "${FUNC_TYPE}" in
    pathway|kegg_ko|cog|cazyme|arg|vfdb|defense|ncyc|pcyc|funomic|amr|merops|phrog|vog|lifestyle|host_genus|viral_family) ;;
    *) echo "[ERROR] Invalid functional type: ${FUNC_TYPE}"; show_help; exit 1 ;;
esac

case "${DIMENSION}:${FUNC_TYPE}" in
    bacteria:pathway|bacteria:kegg_ko|bacteria:cog|bacteria:cazyme|bacteria:arg|bacteria:vfdb|bacteria:defense|bacteria:ncyc|bacteria:pcyc) ;;
    fungi:kegg_ko|fungi:cog|fungi:cazyme|fungi:vfdb|fungi:amr|fungi:merops|fungi:funomic) ;;
    virus:phrog|virus:vog|virus:lifestyle|virus:host_genus|virus:viral_family) ;;
    *)
        echo "[ERROR] Functional type '${FUNC_TYPE}' is not valid for dimension '${DIMENSION}'"
        exit 1
        ;;
esac

# Ensure absolute paths
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

GROUP_COL="${GROUP_COL:-group}"
STAT_ROOT="${WORKDIR}/result/stat"
DIM_ROOT="${STAT_ROOT}/${DIMENSION}"
OUT_DIR="${DIM_ROOT}/functional/${FUNC_TYPE}"
LOG_DIR="${WORKDIR}/logs/stat/${DIMENSION}/functional/${FUNC_TYPE}"
SENTINEL="${OUT_DIR}/${DIMENSION}_functional_${FUNC_TYPE}_done.txt"

mkdir -p "${OUT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/96_stat_functional.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ -n "${METADATA_CSV}" ] && [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running ${DIMENSION} functional analysis: ${FUNC_TYPE}"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV:-<none>}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Output directory: ${OUT_DIR}"

export WORKDIR REPO METADATA_CSV GROUP_COL STAT_ROOT DIMENSION FUNC_TYPE OUT_DIR FORCE SENTINEL

RUN_LOG="${LOG_DIR}/96_stat_functional.run.log"
# set -e 下 pipefail 会让下面这行管道一旦失败立即终止脚本，永远到不了
# EXIT_CODE 判断和 "zero data rows" 优雅降级分支 —— 必须临时关闭 errexit
set +e
(cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/96_stat_functional.R") 2>&1 | tee "${RUN_LOG}"
EXIT_CODE=${PIPESTATUS[0]}
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    if grep -q "zero data rows" "${RUN_LOG}"; then
        echo "[WARN] ${DIMENSION}/${FUNC_TYPE}: functional table has no data rows, writing empty-skip sentinel"
        mkdir -p "${OUT_DIR}"
        echo "SKIPPED: functional abundance table for ${DIMENSION}/${FUNC_TYPE} has a header but zero data rows" > "${SENTINEL}"
        exit 0
    fi
    if grep -q "No functional features retained after prevalence filtering" "${RUN_LOG}"; then
        echo "[WARN] ${DIMENSION}/${FUNC_TYPE}: no functional features survived prevalence filtering, writing empty-skip sentinel"
        mkdir -p "${OUT_DIR}"
        echo "SKIPPED: no functional features for ${DIMENSION}/${FUNC_TYPE} survived prevalence filtering (likely all-zero abundance data)" > "${SENTINEL}"
        exit 0
    fi
    if grep -q "maaslin3_analysis: subscript out of bounds" "${RUN_LOG}"; then
        echo "[WARN] ${DIMENSION}/${FUNC_TYPE}: maaslin3 crashed on this small feature set (upstream instability, see biobakery/maaslin3#25), writing skip sentinel"
        mkdir -p "${OUT_DIR}"
        echo "SKIPPED: maaslin3 failed with a subscript-out-of-bounds error on ${DIMENSION}/${FUNC_TYPE} (too few features for stable fitting)" > "${SENTINEL}"
        exit 0
    fi
    echo "[ERROR] 96_stat_functional.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

mgx_end "functional"
echo "[INFO] Sentinel: ${SENTINEL}"
