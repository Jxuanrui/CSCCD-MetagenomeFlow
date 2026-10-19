#!/usr/bin/env bash
# ==============================================================================
# Script: 96_functional_integrated.sh
# Purpose: Cross-database integrated functional visualization
# Usage:   bash 96_functional_integrated.sh [-w WORKDIR] [-r REPO] [-m METADATA_CSV] -d DIMENSION [-c CPUS] [--force]
# Output:  result/stat/{dimension}/functional/00_summary/
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 96_functional_integrated.sh [-w WORKDIR] [-r REPO] [-m METADATA_CSV] -d DIMENSION [-c CPUS] [--force]

Required:
  -d  Dimension: bacteria|fungi|virus

Optional:
  -w  Project work directory (default: current directory)
  -r  Repository root (default: parent directory of this script)
  -m  Metadata CSV (default: result/stat/metadata.tsv)
  -g  Metadata group column (default: GROUP_COL env or group)
  -c  CPU threads for parallel loading (default: CPUS env or 1)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKDIR="$(pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
METADATA_CSV=""
GROUP_COL="${GROUP_COL:-group}"
DIMENSION=""
CPUS="${CPUS:-1}"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV g:GROUP_COL d:DIMENSION c:CPUS"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="cpus:CPUS"
mgx_parse "$@"
mgx_require DIMENSION

DIMENSION="$(printf '%s' "${DIMENSION}" | tr '[:upper:]' '[:lower:]')"

case "${DIMENSION}" in
    bacteria|fungi|virus) ;;
    *) echo "[ERROR] Invalid dimension: ${DIMENSION}"; show_help; exit 1 ;;
esac

if ! [[ "${CPUS}" =~ ^[0-9]+$ ]] || [ "${CPUS}" -lt 1 ]; then
    echo "[ERROR] CPUS must be a positive integer: ${CPUS}"
    exit 1
fi

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
        echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
        exit 1
    fi
    METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"
fi

R_SCRIPT="${REPO}/scripts/96_functional_integrated.R"
if [ ! -f "${R_SCRIPT}" ]; then
    echo "[ERROR] R script not found: ${R_SCRIPT}"
    exit 1
fi

mgx_begin

STAT_ROOT="${WORKDIR}/result/stat"
DIM_ROOT="${STAT_ROOT}/${DIMENSION}"
OUT_DIR="${DIM_ROOT}/functional/00_summary"
LOG_DIR="${WORKDIR}/logs/stat/${DIMENSION}/functional/00_summary"
SENTINEL="${OUT_DIR}/${DIMENSION}_summary_done.txt"
STATUS_TSV="${OUT_DIR}/${DIMENSION}_summary_status.tsv"

mkdir -p "${OUT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/96_functional_integrated.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Existing integrated outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running ${DIMENSION} integrated functional visualization"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV:-${STAT_ROOT}/metadata.tsv}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] CPUS: ${CPUS}"
echo "[INFO] Output directory: ${OUT_DIR}"

export WORKDIR REPO METADATA_CSV GROUP_COL STAT_ROOT DIMENSION CPUS OUT_DIR FORCE SENTINEL

if command -v conda >/dev/null 2>&1 && [ -d "${REPO}/envs/r_stat" ]; then
    RUNNER=(conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${R_SCRIPT}")
else
    RUNNER=(Rscript "${R_SCRIPT}")
fi

(cd "${WORKDIR}" && "${RUNNER[@]}")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 96_functional_integrated.sh failed with exit code ${EXIT_CODE}"
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
    echo "[ERROR] Integrated status contains non-OK steps: ${STATUS_TSV}"
    exit 1
fi

mgx_end "functional_integrated"
echo "[INFO] Status: ${STATUS_TSV}"
echo "[INFO] Sentinel: ${SENTINEL}"
