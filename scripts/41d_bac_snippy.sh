#!/usr/bin/env bash
# ==============================================================================
# Script: 41d_bac_snippy.sh
# Purpose: Aggregate SNP/InDel analysis for dereplicated MAGs with Snippy
# Input  : ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa|*.fasta
# Output : ${WORKDIR}/result/wgs/snippy/core.tsv
# Env    : ${REPO}/envs/snippy (fallback: ${REPO}/envs/prokaWGS)
# Usage  : bash 41d_bac_snippy.sh -w WORKDIR -r REPO -t THREADS [-R REF]
# ==============================================================================

show_help() { cat << EOF
Usage: bash 41d_bac_snippy.sh -w WORKDIR -r REPO -t THREADS [-R REF_GENOME]
Required:
  -w  Working directory
  -r  MaxMetagenome repository root
  -t  Thread count
Optional:
  -R  Reference genome path (.fa/.fasta/.gbk/.gbff). If omitted, use the largest MAG.
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

strip_ext() {
    local name
    name="$(basename "$1")"
    name="${name%.fasta}"
    name="${name%.fa}"
    name="${name%.gbff}"
    name="${name%.gbk}"
    echo "${name}"
}

THREADS=""
WORKDIR=""
REPO=""
REF_GENOME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) THREADS="$2"; shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -R) REF_GENOME="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done
for v in THREADS WORKDIR REPO; do
    if [ -z "${!v}" ]; then
        echo "[ERROR] Missing required argument"
        show_help
        exit 1
    fi
done

SECONDS=0
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/wgs/snippy"
SENTINEL="${OUTDIR}/core.tsv"
CORE_TAB="${OUTDIR}/core.tab"
FULL_ALN="${OUTDIR}/core.full.aln"
CLEAN_ALN="${OUTDIR}/core.clean.aln"
SUMMARY_FILE="${OUTDIR}/summary.txt"
PLACEHOLDER_NOTE="snippy not available in envs/snippy or envs/prokaWGS"

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[snippy] Result exists, skip: ${SENTINEL}"
    exit 0
fi

mkdir -p "${OUTDIR}"

MAG_FILES=()
if [ -d "${MAGS_DIR}" ]; then
    while IFS= read -r f; do MAG_FILES+=("$f"); done < <(
        find "${MAGS_DIR}" -maxdepth 1 -type f \( -name "*.fa" -o -name "*.fasta" \) | sort
    )
fi
if [ ${#MAG_FILES[@]} -eq 0 ]; then
    echo "[snippy] WARNING: no dereplicated MAGs found, creating empty sentinel: ${SENTINEL}"
    : > "${SENTINEL}"
    : > "${SUMMARY_FILE}"
    exit 0
fi

SNIPPY_ENV=""
if env_has_cmd "${REPO}/envs/snippy" snippy && \
   env_has_cmd "${REPO}/envs/snippy" snippy-core && \
   env_has_cmd "${REPO}/envs/snippy" snippy-clean_full_aln; then
    SNIPPY_ENV="${REPO}/envs/snippy"
elif env_has_cmd "${REPO}/envs/prokaWGS" snippy && \
     env_has_cmd "${REPO}/envs/prokaWGS" snippy-core && \
     env_has_cmd "${REPO}/envs/prokaWGS" snippy-clean_full_aln; then
    SNIPPY_ENV="${REPO}/envs/prokaWGS"
else
    echo "[snippy] WARNING: ${PLACEHOLDER_NOTE}"
    {
        printf "sample\tstatus\tnote\n"
        printf "NA\tWARNING\t%s\n" "${PLACEHOLDER_NOTE}"
    } > "${SENTINEL}"
    exit 0
fi

if [ -n "${REF_GENOME}" ]; then
    if [ ! -f "${REF_GENOME}" ]; then
        echo "[ERROR] Reference genome not found: ${REF_GENOME}"
        exit 1
    fi
    REF="${REF_GENOME}"
else
    REF=""
    MAX_SIZE=-1
    for mag in "${MAG_FILES[@]}"; do
        SIZE=$(stat -c %s "${mag}" 2>/dev/null)
        if [ -z "${SIZE}" ]; then
            SIZE=$(wc -c < "${mag}")
        fi
        if [ "${SIZE}" -gt "${MAX_SIZE}" ]; then
            MAX_SIZE="${SIZE}"
            REF="${mag}"
        fi
    done
fi

if [ -z "${REF}" ]; then
    echo "[ERROR] Failed to determine reference genome"
    exit 1
fi

echo "[snippy] Running sequential Snippy on ${#MAG_FILES[@]} MAGs | ref: ${REF}"
SNIPPY_DIRS=()
COMPLETED=0
SKIPPED=0
for mag in "${MAG_FILES[@]}"; do
    MAG_NAME="$(strip_ext "${mag}")"
    MAG_OUT="${OUTDIR}/${MAG_NAME}"

    if [ -f "${MAG_OUT}/snps.tab" ] && [ -s "${MAG_OUT}/snps.tab" ]; then
        SNIPPY_DIRS+=("${MAG_OUT}")
        ((SKIPPED++))
        continue
    fi

    mkdir -p "${MAG_OUT}"
    conda run --prefix "${SNIPPY_ENV}" --no-capture-output \
        snippy \
            --cpus "${THREADS}" \
            --ref "${REF}" \
            --ctgs "${mag}" \
            --outdir "${MAG_OUT}"

    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[snippy] WARNING: failed for ${MAG_NAME}"
        continue
    fi
    if [ -f "${MAG_OUT}/snps.tab" ] && [ -s "${MAG_OUT}/snps.tab" ]; then
        SNIPPY_DIRS+=("${MAG_OUT}")
        ((COMPLETED++))
    fi
done

if [ ${#SNIPPY_DIRS[@]} -eq 0 ]; then
    echo "[ERROR] No successful Snippy outputs were produced"
    exit 1
fi

conda run --prefix "${SNIPPY_ENV}" --no-capture-output \
    snippy-core \
        --ref "${REF}" \
        --prefix "${OUTDIR}/core" \
        "${SNIPPY_DIRS[@]}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] snippy-core failed"
    exit ${EXIT_CODE}
fi

if [ ! -f "${FULL_ALN}" ] || [ ! -s "${FULL_ALN}" ]; then
    echo "[ERROR] Missing Snippy alignment: ${FULL_ALN}"
    exit 1
fi

conda run --prefix "${SNIPPY_ENV}" --no-capture-output \
    snippy-clean_full_aln "${FULL_ALN}" > "${CLEAN_ALN}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] snippy-clean_full_aln failed"
    exit ${EXIT_CODE}
fi

if [ ! -f "${CORE_TAB}" ] || [ ! -s "${CORE_TAB}" ]; then
    echo "[ERROR] Missing Snippy core table: ${CORE_TAB}"
    exit 1
fi

cp "${CORE_TAB}" "${SENTINEL}"
TOTAL_SNPS=$(awk 'NR > 1 {count++} END {print count + 0}' "${CORE_TAB}")
{
    printf "reference\t%s\n" "${REF}"
    printf "total_mags\t%s\n" "${#MAG_FILES[@]}"
    printf "successful_runs\t%s\n" "${#SNIPPY_DIRS[@]}"
    printf "total_snps\t%s\n" "${TOTAL_SNPS}"
    printf "clean_alignment\t%s\n" "${CLEAN_ALN}"
} > "${SUMMARY_FILE}"

echo "[snippy] Done in ${SECONDS}s | total MAGs: ${#MAG_FILES[@]} | successful runs: ${#SNIPPY_DIRS[@]} | total SNPs: ${TOTAL_SNPS}"
