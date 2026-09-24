#!/usr/bin/env bash
# ==============================================================================
# Script: 41c_bac_pangenome.sh
# Purpose: Aggregate pan-genome analysis for MAG annotations with Roary
# Input  : ${WORKDIR}/result/binning/prokka/*.gff or one-level-deep *.gff
# Output : ${WORKDIR}/result/wgs/pangenome/summary_statistics.txt
# Env    : ${REPO}/envs/prokaWGS
# Usage  : bash 41c_bac_pangenome.sh -w WORKDIR -r REPO -t THREADS
#          [--identity 95] [--core-definition 99]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
Usage: bash 41c_bac_pangenome.sh -w WORKDIR -r REPO -t THREADS [--identity 95] [--core-definition 99]
Required:
  -w  Working directory
  -r  CSCCD-MetagenomeFlow repository root
  -t  Thread count
Optional:
  --identity         Protein identity cutoff for Roary (default: 95)
  --core-definition  Core genome definition in percent (default: 99)
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
IDENTITY="95"
CORE_DEFINITION="99"
# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:THREADS w:WORKDIR r:REPO"
export MGX_OPTS_LONG="identity:IDENTITY core-definition:CORE_DEFINITION"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require THREADS WORKDIR REPO

mgx_begin
PROKKA_DIR="${WORKDIR}/result/binning/prokka"
OUTDIR="${WORKDIR}/result/wgs/pangenome"
SENTINEL="${OUTDIR}/summary_statistics.txt"
FAILED_SENTINEL="${OUTDIR}/summary_statistics.txt.FAILED"
MATRIX_NOTE="${OUTDIR}/presence_absence_matrix.txt"
PLACEHOLDER_NOTE="roary not available in envs/prokaWGS"

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[pangenome] Result exists, skip: ${SENTINEL}"
    exit 0
fi
if [ ${FORCE} -eq 0 ] && [ -f "${FAILED_SENTINEL}" ]; then
    echo "[pangenome] Previous FAILED sentinel exists, skip: ${FAILED_SENTINEL}"
    cp "${FAILED_SENTINEL}" "${SENTINEL}"
    exit 0
fi

mkdir -p "${OUTDIR}"

GFF_FILES=()
if [ -d "${PROKKA_DIR}" ]; then
    while IFS= read -r f; do GFF_FILES+=("$f"); done < <(
        find "${PROKKA_DIR}" -maxdepth 1 -type f -name "*.gff" | sort
    )
fi
if [ ${#GFF_FILES[@]} -eq 0 ] && [ -d "${PROKKA_DIR}" ]; then
    while IFS= read -r f; do GFF_FILES+=("$f"); done < <(
        find "${PROKKA_DIR}" -mindepth 2 -maxdepth 2 -type f -name "*.gff" | sort
    )
fi
if [ ${#GFF_FILES[@]} -lt 3 ]; then
    printf "Insufficient GFF files for Roary: found %s, require at least 3\n" "${#GFF_FILES[@]}" > "${FAILED_SENTINEL}"
    : > "${SENTINEL}"
    printf "Pan-genome presence/absence matrix: NA\n" > "${MATRIX_NOTE}"
    echo "[pangenome] WARNING: need at least 3 GFF files, found ${#GFF_FILES[@]}"
    exit 0
fi

if ! env_has_cmd "${REPO}/envs/prokaWGS" roary; then
    echo "[pangenome] WARNING: ${PLACEHOLDER_NOTE}"
    {
        printf "WARNING\t%s\n" "${PLACEHOLDER_NOTE}"
        printf "INPUT_GFFS\t%s\n" "${#GFF_FILES[@]}"
    } > "${SENTINEL}"
    printf "Pan-genome presence/absence matrix: %s\n" "${OUTDIR}/gene_presence_absence.csv" > "${MATRIX_NOTE}"
    exit 0
fi

rm -f "${FAILED_SENTINEL}"

ROARY_LOG="${OUTDIR}/roary.log"
echo "[pangenome] Running Roary on ${#GFF_FILES[@]} genomes | identity: ${IDENTITY} | core: ${CORE_DEFINITION}"
set +e
# 注: 管道（conda | tee）无法走 mgx_try 包装，保留 set +e ... set -e 结构
mgx_conda prokaWGS roary \
        -p "${THREADS}" \
        -e \
        --mafft \
        -i "${IDENTITY}" \
        -cd "${CORE_DEFINITION}" \
        -f "${OUTDIR}" \
        "${GFF_FILES[@]}" \
    2>&1 | tee "${ROARY_LOG}"
EXIT_CODE=$?
set -e
# Roary treats "cluster count exceeds --group_limit" as its own early-exit
# condition and returns 0 in that case (only truly unexpected failures give
# a non-zero exit), so this check must run regardless of EXIT_CODE.
if grep -q "exceeds limit\|Exiting early because number of clusters is too high" "${ROARY_LOG}"; then
    CLUSTER_NOTE="Roary cluster count exceeded --group_limit (see ${ROARY_LOG}); likely a genuinely diverse multi-species MAG set rather than contamination"
    printf "WARNING\t%s\n" "${CLUSTER_NOTE}" > "${FAILED_SENTINEL}"
    printf "INPUT_GFFS\t%s\n" "${#GFF_FILES[@]}" >> "${FAILED_SENTINEL}"
    cp "${FAILED_SENTINEL}" "${SENTINEL}"
    printf "Pan-genome presence/absence matrix: NA\n" > "${MATRIX_NOTE}"
    echo "[pangenome] WARNING: ${CLUSTER_NOTE}"
    exit 0
fi
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] roary failed"
    exit ${EXIT_CODE}
fi

if [ ! -f "${SENTINEL}" ] || [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Missing Roary summary: ${SENTINEL}"
    exit 1
fi

CORE_GENES=$(awk -F'\t' 'tolower($1) ~ /^core genes/ {print $NF; exit}' "${SENTINEL}")
ACCESSORY_GENES=$(awk -F'\t' '
    tolower($1) ~ /^accessory genes/ {print $NF; found=1; exit}
    END {if (!found) print ""}
' "${SENTINEL}")
if [ -z "${ACCESSORY_GENES}" ]; then
    ACCESSORY_GENES=$(awk -F'\t' '
        tolower($1) ~ /^shell genes/ {shell=$NF+0; shell_seen=1}
        tolower($1) ~ /^cloud genes/ {cloud=$NF+0; cloud_seen=1}
        END {
            if (shell_seen || cloud_seen) {
                print shell + cloud
            }
        }
    ' "${SENTINEL}")
fi
UNIQUE_GENES=$(awk -F'\t' '
    tolower($1) ~ /^unique genes/ {print $NF; found=1; exit}
    END {if (!found) print ""}
' "${SENTINEL}")
if [ -z "${UNIQUE_GENES}" ]; then
    UNIQUE_GENES=$(awk -F'\t' 'tolower($1) ~ /^cloud genes/ {print $NF; exit}' "${SENTINEL}")
fi

printf "Pan-genome presence/absence matrix: %s\n" "${OUTDIR}/gene_presence_absence.csv" > "${MATRIX_NOTE}"
echo "[pangenome] total genomes: ${#GFF_FILES[@]} | core genes: ${CORE_GENES:-NA} | accessory genes: ${ACCESSORY_GENES:-NA} | unique genes: ${UNIQUE_GENES:-NA}"
mgx_end "pangenome"
