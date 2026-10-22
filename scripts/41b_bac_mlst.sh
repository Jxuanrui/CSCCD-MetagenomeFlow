#!/usr/bin/env bash
# ==============================================================================
# Script: 41b_bac_mlst.sh
# Purpose: Aggregate MLST typing for dereplicated MAGs
# Input  : ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa|*.fasta
# Output : ${WORKDIR}/result/wgs/mlst/mlst.tsv
# Env    : ${REPO}/envs/prokaWGS (fallback to any mlst on PATH)
# Usage  : bash 41b_bac_mlst.sh -w WORKDIR -r REPO -t THREADS [--scheme SCHEME]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
Usage: bash 41b_bac_mlst.sh -w WORKDIR -r REPO -t THREADS [--scheme SCHEME]
Required:
  -w  Working directory
  -r  CSCCD-MetagenomeFlow repository root
  -t  Thread count
Optional:
  --scheme  MLST scheme name (default: auto)
EOF
}

env_has_cmd() {
    local env_prefix="$1"
    local cmd_name="$2"
    if [ -x "${env_prefix}/bin/${cmd_name}" ]; then
        return 0
    fi
    conda run --prefix "${env_prefix}" --no-capture-output which "${cmd_name}" >/dev/null 2>&1
}

THREADS=""
WORKDIR=""
REPO=""
FORCE=0
SCHEME="auto"
# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:THREADS w:WORKDIR r:REPO"
export MGX_OPTS_LONG="scheme:SCHEME"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require THREADS WORKDIR REPO

mgx_begin
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/wgs/mlst"
SENTINEL="${OUTDIR}/mlst.tsv"
RAW_OUT="${OUTDIR}/mlst_raw.txt"
PLACEHOLDER_NOTE="mlst not available in envs/prokaWGS"

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[mlst] Result exists, skip: ${SENTINEL}"
    exit 0
fi

mkdir -p "${OUTDIR}"

MAG_FILES=()
if [ -d "${MAGS_DIR}" ]; then
    while IFS= read -r f; do MAG_FILES+=("$f"); done < <(
        find "${MAGS_DIR}" -maxdepth 1 -type f \( -name "*.fa" -o -name "*.fasta" \) | sort
    )
fi
if [ ${#MAG_FILES[@]} -eq 0 ] && [ -d "${MAGS_DIR}" ]; then
    while IFS= read -r f; do MAG_FILES+=("$f"); done < <(
        find "${MAGS_DIR}" -type f \( -name "*.fa" -o -name "*.fasta" \) | sort
    )
fi
if [ ${#MAG_FILES[@]} -eq 0 ]; then
    echo "[mlst] WARNING: no dereplicated MAGs found, creating empty sentinel: ${SENTINEL}"
    : > "${SENTINEL}"
    : > "${RAW_OUT}"
    exit 0
fi

USE_CONDA_ENV=0
if env_has_cmd "${REPO}/envs/prokaWGS" mlst; then
    USE_CONDA_ENV=1
elif ! command -v mlst >/dev/null 2>&1; then
    echo "[mlst] WARNING: ${PLACEHOLDER_NOTE}"
    {
        printf "FILE\tSCHEME\tST\tALLELES\n"
        printf "NOTE\t%s\tNA\tNA\n" "${PLACEHOLDER_NOTE}"
    } > "${SENTINEL}"
    printf "%s\n" "${PLACEHOLDER_NOTE}" > "${RAW_OUT}"
    exit 0
fi

MLST_CMD=(mlst --nopath --quiet --threads "${THREADS}")
if [ "${SCHEME}" != "auto" ]; then
    MLST_CMD+=(--scheme "${SCHEME}")
fi
MLST_CMD+=("${MAG_FILES[@]}")

echo "[mlst] Typing ${#MAG_FILES[@]} MAGs | scheme: ${SCHEME}"
if [ ${USE_CONDA_ENV} -eq 1 ]; then
    mgx_conda prokaWGS \
        "${MLST_CMD[@]}" > "${RAW_OUT}"
else
    "${MLST_CMD[@]}" > "${RAW_OUT}"
fi

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] mlst failed"
    exit ${EXIT_CODE}
fi

{
    printf "FILE\tSCHEME\tST\tALLELES\n"
    awk 'BEGIN{OFS="\t"} NF>0 {
        alleles="NA"
        if (NF > 3) {
            alleles=""
            for (i = 4; i <= NF; i++) {
                alleles = alleles (i == 4 ? "" : ";") $i
            }
        }
        print $1, $2, $3, alleles
    }' "${RAW_OUT}"
} > "${SENTINEL}"

DISTINCT_STS=$(awk -F'\t' 'NR > 1 && $3 != "" && $3 != "-" && $3 != "NA" {print $3}' "${SENTINEL}" | sort -u | wc -l)
echo "[mlst] total MAGs: ${#MAG_FILES[@]} | distinct STs: ${DISTINCT_STS}"
mgx_end "mlst"
