#!/usr/bin/env bash
# ==============================================================================
# Script: 96_functional_permanova.sh
# Purpose: PERMANOVA analysis for functional composition
# Usage:   bash 96_functional_permanova.sh -w WORKDIR -r REPO [-m METADATA_CSV] [-g GROUP_COL] [-d DIMENSION] [--force]
# Output:  result/stat/{dimension}/functional/permanova_summary.tsv
#          result/stat/{dimension}/functional/permanova_bubble.{pdf,svg,tiff}
#          result/stat/{dimension}/functional/{dimension}_permanova_status.tsv
#          result/stat/{dimension}/functional/{dimension}_permanova_done.txt
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 96_functional_permanova.sh -w WORKDIR -r REPO [-m METADATA_CSV] [-g GROUP_COL] [-d DIMENSION] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV/TSV (default: result/stat/metadata.tsv)
  -g  Metadata group column (default: GROUP_COL env or group)
  -d  Dimension: bacteria|fungi|virus (default: run all dimensions)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message

Outputs:
  result/stat/{dimension}/functional/permanova_summary.tsv
  result/stat/{dimension}/functional/permanova_bubble.{pdf,svg,tiff}
  result/stat/{dimension}/functional/{dimension}_permanova_status.tsv
  result/stat/{dimension}/functional/{dimension}_permanova_done.txt
EOF
}

METADATA_CSV=""
GROUP_COL="${GROUP_COL:-group}"
DIMENSION=""

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV g:GROUP_COL d:DIMENSION"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

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

R_SCRIPT="${REPO}/scripts/96_functional_permanova.R"
if [ ! -f "${R_SCRIPT}" ]; then
    echo "[ERROR] R script not found: ${R_SCRIPT}"
    exit 1
fi

if [ -n "${DIMENSION}" ]; then
    DIMENSION="$(printf '%s' "${DIMENSION}" | tr '[:upper:]' '[:lower:]')"
    case "${DIMENSION}" in
        bacteria|fungi|virus) DIMENSIONS=("${DIMENSION}") ;;
        *) echo "[ERROR] Invalid dimension: ${DIMENSION}"; show_help; exit 1 ;;
    esac
else
    DIMENSIONS=(bacteria fungi virus)
fi

run_dimension() {
    local dim="$1"
    local start_seconds
    local stat_root
    local out_dir
    local log_dir
    local log_file
    local sentinel
    local status_tsv

    start_seconds=${SECONDS}
    stat_root="${WORKDIR}/result/stat"
    out_dir="${stat_root}/${dim}/functional"
    log_dir="${WORKDIR}/logs/stat/${dim}/functional/permanova"
    log_file="${log_dir}/96_functional_permanova.log"
    sentinel="${out_dir}/${dim}_permanova_done.txt"
    status_tsv="${out_dir}/${dim}_permanova_status.tsv"

    mkdir -p "${out_dir}" "${log_dir}"

    (
        set -euo pipefail

        if [ "${FORCE}" -eq 0 ] && [ -s "${sentinel}" ]; then
            echo "[INFO] Existing PERMANOVA outputs detected for ${dim}, skipping rerun"
            echo "  Sentinel: ${sentinel}"
            echo "[INFO] Use --force to re-run"
            exit 0
        fi

        echo "[INFO] Running ${dim} functional PERMANOVA"
        echo "[INFO] Workdir: ${WORKDIR}"
        echo "[INFO] Metadata: ${METADATA_CSV:-${stat_root}/metadata.tsv}"
        echo "[INFO] Group column: ${GROUP_COL}"
        echo "[INFO] Output directory: ${out_dir}"

        export WORKDIR REPO METADATA_CSV GROUP_COL STAT_ROOT="${stat_root}"
        export DIMENSION="${dim}" OUT_DIR="${out_dir}" FORCE SENTINEL="${sentinel}"

        if command -v conda >/dev/null 2>&1 && [ -d "${REPO}/envs/r_stat" ]; then
            RUNNER=(conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${R_SCRIPT}")
        else
            RUNNER=(Rscript "${R_SCRIPT}")
        fi

        set +e
        (cd "${WORKDIR}" && "${RUNNER[@]}")
        exit_code=$?
        set -e
        if [ ${exit_code} -ne 0 ]; then
            echo "[ERROR] 96_functional_permanova.sh failed for ${dim} with exit code ${exit_code}"
            exit ${exit_code}
        fi

        if [ ! -s "${sentinel}" ]; then
            echo "[ERROR] Expected sentinel not generated: ${sentinel}"
            exit 1
        fi

        if [ ! -s "${status_tsv}" ]; then
            echo "[ERROR] Expected status file not generated: ${status_tsv}"
            exit 1
        fi

        if ! awk -F '\t' 'NR > 1 && $2 != "OK" { bad = 1 } END { exit bad }' "${status_tsv}"; then
            echo "[ERROR] PERMANOVA status contains non-OK steps: ${status_tsv}"
            exit 1
        fi

        echo "[INFO] ${dim} functional PERMANOVA completed in $((SECONDS - start_seconds))s"
        echo "[INFO] Status: ${status_tsv}"
        echo "[INFO] Sentinel: ${sentinel}"
    ) 2>&1 | tee -a "${log_file}"

    local status=${PIPESTATUS[0]}
    return "${status}"
}

for dim in "${DIMENSIONS[@]}"; do
    if ! run_dimension "${dim}"; then
        exit 1
    fi
done

echo "[INFO] Functional PERMANOVA wrapper completed for: ${DIMENSIONS[*]}"
