# Deprecated 2026-07-16: superseded by 91_stat_diversity.sh due to directory-convention duplication.
#!/usr/bin/env bash
# ==============================================================================
# Script: 03_beta_diversity.sh
# Purpose: Beta diversity analysis for bacteria, fungi, and virus dimensions
# Usage:   bash 03_beta_diversity.sh -w WORKDIR -r REPO [-m METADATA_TSV]
#                                      [-d DIMENSION] [-g GROUP_COL] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 03_beta_diversity.sh -w WORKDIR -r REPO [-m METADATA_TSV] [-d DIMENSION] [-g GROUP_COL] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata TSV/CSV (default: WORKDIR/result/stat/metadata.tsv)
  -d  Dimension: bacteria|fungi|virus|all (default: all)
  -g  Group column in metadata (default: group)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

require_value() {
    if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
        echo "[ERROR] Missing value for argument: $1"
        show_help
        exit 1
    fi
}

WORKDIR=""
REPO=""
METADATA_CSV=""
DIMENSION="all"
GROUP_COL="${GROUP_COL:-group}"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) require_value "$@"; WORKDIR="$2"; shift 2 ;;
        -r) require_value "$@"; REPO="$2"; shift 2 ;;
        -m) require_value "$@"; METADATA_CSV="$2"; shift 2 ;;
        -d) require_value "$@"; DIMENSION="$2"; shift 2 ;;
        -g) require_value "$@"; GROUP_COL="$2"; shift 2 ;;
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

DIMENSION="$(printf '%s' "${DIMENSION}" | tr '[:upper:]' '[:lower:]')"
case "${DIMENSION}" in
    bacteria|fungi|virus|all) ;;
    *) echo "[ERROR] Invalid dimension: ${DIMENSION}"; show_help; exit 1 ;;
esac

WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"
if [ -z "${METADATA_CSV}" ]; then
    METADATA_CSV="${WORKDIR}/result/stat/metadata.tsv"
else
    METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"
fi

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata file not found: ${METADATA_CSV}"
    exit 1
fi
if [ ! -x "${REPO}/envs/r_stat/bin/Rscript" ] && ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] Cannot find Rscript in ${REPO}/envs/r_stat and conda is not available"
    exit 1
fi

SECONDS=0

STAT_ROOT="${WORKDIR}/result/stat"
LOG_DIR="${WORKDIR}/logs/stat/beta_diversity"
mkdir -p "${STAT_ROOT}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/03_beta_diversity_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=============================================================================="
echo "Beta Diversity Analysis"
echo "Start time: $(date)"
echo "=============================================================================="
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Repo: ${REPO}"
echo "[INFO] Metadata: ${METADATA_CSV}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Dimension request: ${DIMENSION}"

if [ "${DIMENSION}" = "all" ]; then
    DIMENSIONS=(bacteria fungi virus)
else
    DIMENSIONS=("${DIMENSION}")
fi

run_dimension() {
    local dim="$1"
    local out_dir="${STAT_ROOT}/${dim}/diversity"
    local sentinel="${out_dir}/${dim}_beta_diversity_done.txt"
    mkdir -p "${out_dir}"

    if [ ${FORCE} -eq 0 ] && [ -s "${sentinel}" ]; then
        echo "[INFO] Existing ${dim} outputs detected, skipping rerun"
        echo "  Sentinel: ${sentinel}"
        echo "[INFO] Use --force to re-run"
        return 0
    fi

    echo "------------------------------------------------------------------------------"
    echo "[INFO] Running ${dim} beta diversity"
    echo "[INFO] Output directory: ${out_dir}"

    export WORKDIR REPO METADATA_CSV GROUP_COL STAT_ROOT DIMENSION="${dim}" OUT_DIR="${out_dir}" SENTINEL="${sentinel}" FORCE

    if command -v conda >/dev/null 2>&1; then
        (cd "${WORKDIR}" && conda run --prefix "${REPO}/envs/r_stat" --no-capture-output \
            Rscript "${REPO}/scripts/03_beta_diversity.R" \
            -w "${WORKDIR}" -r "${REPO}" -m "${METADATA_CSV}" -d "${dim}" -g "${GROUP_COL}")
    else
        (cd "${WORKDIR}" && "${REPO}/envs/r_stat/bin/Rscript" "${REPO}/scripts/03_beta_diversity.R" \
            -w "${WORKDIR}" -r "${REPO}" -m "${METADATA_CSV}" -d "${dim}" -g "${GROUP_COL}")
    fi

    local exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        echo "[ERROR] ${dim} beta diversity failed with exit code ${exit_code}"
        return ${exit_code}
    fi

    if [ ! -s "${sentinel}" ]; then
        echo "[ERROR] Expected sentinel not generated: ${sentinel}"
        return 1
    fi

    echo "[INFO] ${dim} beta diversity completed"
    echo "[INFO] Sentinel: ${sentinel}"
}

for dim in "${DIMENSIONS[@]}"; do
    run_dimension "${dim}"
done

echo "=============================================================================="
echo "[SUCCESS] Beta diversity analysis completed in ${SECONDS}s"
echo "Results: ${STAT_ROOT}/{bacteria,fungi,virus}/diversity"
echo "Log: ${LOG_FILE}"
echo "=============================================================================="
