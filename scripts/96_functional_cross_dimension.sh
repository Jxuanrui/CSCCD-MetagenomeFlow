#!/usr/bin/env bash
# ==============================================================================
# Script: 96_functional_cross_dimension.sh
# Purpose: Cross-dimension functional comparison visualization
# Usage:   bash 96_functional_cross_dimension.sh [-w WORKDIR] [-r REPO] [--force]
# Output:  result/stat/cross_dimension/functional/
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 96_functional_cross_dimension.sh [-w WORKDIR] [-r REPO] [--force]

Optional:
  -w  Project work directory (default: current directory)
  -r  Repository root (default: parent directory of this script)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message

Inputs:
  result/stat/bacteria/functional/*/results/maaslin3_significant.tsv
  result/stat/fungi/functional/*/results/maaslin3_significant.tsv
  result/stat/virus/functional/*/results/maaslin3_significant.tsv

Outputs:
  result/stat/cross_dimension/functional/
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKDIR="$(pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
METADATA_CSV="${METADATA_CSV:-}"
GROUP_COL="${GROUP_COL:-group}"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"

if [ ! -d "${WORKDIR}" ]; then
    echo "[ERROR] Workdir not found: ${WORKDIR}"
    exit 1
fi
if [ ! -d "${REPO}" ]; then
    echo "[ERROR] Repository root not found: ${REPO}"
    exit 1
fi

WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"

if [ -n "${METADATA_CSV}" ]; then
    if [ ! -f "${METADATA_CSV}" ]; then
        echo "[ERROR] Metadata file not found: ${METADATA_CSV}"
        exit 1
    fi
    METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"
fi

R_SCRIPT="${REPO}/scripts/96_functional_cross_dimension.R"
if [ ! -f "${R_SCRIPT}" ]; then
    echo "[ERROR] R script not found: ${R_SCRIPT}"
    exit 1
fi

mgx_begin

STAT_ROOT="${WORKDIR}/result/stat"
OUT_DIR="${STAT_ROOT}/cross_dimension/functional"
LOG_DIR="${WORKDIR}/logs/stat/cross_dimension/functional"
SENTINEL="${OUT_DIR}/cross_dimension_functional_done.txt"
STATUS_TSV="${OUT_DIR}/cross_dimension_status.tsv"

mkdir -p "${OUT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/96_functional_cross_dimension.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Existing cross-dimension outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

FOUND_SIG=0
for dim in bacteria fungi virus; do
    dim_func_root="${STAT_ROOT}/${dim}/functional"
    if [ -d "${dim_func_root}" ] && find "${dim_func_root}" -path "*/results/maaslin3_significant.tsv" -type f -print -quit | grep -q .; then
        FOUND_SIG=1
    else
        echo "[WARN] No maaslin3_significant.tsv files found for ${dim}: ${dim_func_root}"
    fi
done

if [ "${FOUND_SIG}" -eq 0 ]; then
    echo "[ERROR] No Maaslin3 significant result files found under ${STAT_ROOT}"
    exit 1
fi

echo "[INFO] Running cross-dimension functional visualization"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV:-${STAT_ROOT}/metadata.tsv}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Output directory: ${OUT_DIR}"

export WORKDIR REPO METADATA_CSV GROUP_COL STAT_ROOT OUT_DIR FORCE SENTINEL

if command -v conda >/dev/null 2>&1 && [ -d "${REPO}/envs/r_stat" ]; then
    RUNNER=(conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${R_SCRIPT}")
else
    RUNNER=(Rscript "${R_SCRIPT}")
fi

(cd "${WORKDIR}" && "${RUNNER[@]}")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 96_functional_cross_dimension.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

if [ ! -s "${STATUS_TSV}" ]; then
    echo "[ERROR] Expected status file not generated: ${STATUS_TSV}"
    exit 1
fi

if ! awk -F '\t' 'NR > 1 && $2 != "OK" { bad = 1 } END { exit bad }' "${STATUS_TSV}"; then
    echo "[ERROR] Cross-dimension status contains non-OK steps: ${STATUS_TSV}"
    exit 1
fi

mgx_end "functional_cross_dimension"
echo "[INFO] Status: ${STATUS_TSV}"
echo "[INFO] Sentinel: ${SENTINEL}"
