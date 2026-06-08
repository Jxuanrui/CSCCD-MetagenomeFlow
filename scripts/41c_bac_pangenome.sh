#!/usr/bin/env bash
# ==============================================================================
# Script: 41c_bac_pangenome.sh
# Purpose: Aggregate pan-genome analysis for MAG annotations with Roary
# Input  : ${WORKDIR}/result/binning/bakta/*.gff or one-level-deep *.gff
# Output : ${WORKDIR}/result/wgs/pangenome/summary_statistics.txt
# Env    : ${REPO}/envs/prokaWGS
# Usage  : bash 41c_bac_pangenome.sh -w WORKDIR -r REPO -t THREADS
#          [--identity 95] [--core-definition 99]
# ==============================================================================

show_help() { cat << EOF
Usage: bash 41c_bac_pangenome.sh -w WORKDIR -r REPO -t THREADS [--identity 95] [--core-definition 99]
Required:
  -w  Working directory
  -r  MaxMetagenome repository root
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
IDENTITY="95"
CORE_DEFINITION="99"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) THREADS="$2"; shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        --identity) IDENTITY="$2"; shift 2 ;;
        --core-definition) CORE_DEFINITION="$2"; shift 2 ;;
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
BAKTA_DIR="${WORKDIR}/result/binning/bakta"
OUTDIR="${WORKDIR}/result/wgs/pangenome"
SENTINEL="${OUTDIR}/summary_statistics.txt"
FAILED_SENTINEL="${OUTDIR}/summary_statistics.txt.FAILED"
MATRIX_NOTE="${OUTDIR}/presence_absence_matrix.txt"
PLACEHOLDER_NOTE="roary not available in envs/prokaWGS"

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[pangenome] Result exists, skip: ${SENTINEL}"
    exit 0
fi
if [ -f "${FAILED_SENTINEL}" ] && [ -s "${FAILED_SENTINEL}" ]; then
    echo "[pangenome] Previous FAILED sentinel exists, skip: ${FAILED_SENTINEL}"
    exit 0
fi

mkdir -p "${OUTDIR}"

GFF_FILES=()
if [ -d "${BAKTA_DIR}" ]; then
    while IFS= read -r f; do GFF_FILES+=("$f"); done < <(
        find "${BAKTA_DIR}" -maxdepth 1 -type f -name "*.gff" | sort
    )
fi
if [ ${#GFF_FILES[@]} -eq 0 ] && [ -d "${BAKTA_DIR}" ]; then
    while IFS= read -r f; do GFF_FILES+=("$f"); done < <(
        find "${BAKTA_DIR}" -mindepth 2 -maxdepth 2 -type f -name "*.gff" | sort
    )
fi
if [ ${#GFF_FILES[@]} -lt 3 ]; then
    printf "Insufficient GFF files for Roary: found %s, require at least 3\n" "${#GFF_FILES[@]}" > "${FAILED_SENTINEL}"
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

echo "[pangenome] Running Roary on ${#GFF_FILES[@]} genomes | identity: ${IDENTITY} | core: ${CORE_DEFINITION}"
conda run --prefix "${REPO}/envs/prokaWGS" --no-capture-output \
    roary \
        -p "${THREADS}" \
        -e \
        --mafft \
        -i "${IDENTITY}" \
        -cd "${CORE_DEFINITION}" \
        -f "${OUTDIR}" \
        "${GFF_FILES[@]}"

EXIT_CODE=$?
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
echo "[pangenome] Done in ${SECONDS}s | total genomes: ${#GFF_FILES[@]} | core genes: ${CORE_GENES:-NA} | accessory genes: ${ACCESSORY_GENES:-NA} | unique genes: ${UNIQUE_GENES:-NA}"

