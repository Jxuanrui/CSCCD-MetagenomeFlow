#!/usr/bin/env bash
# ==============================================================================
# Script: 97_stat_crosscohort.sh
# Purpose: Enhanced cross-cohort validation with local multi-cohort support
# Usage:   bash 97_stat_crosscohort.sh -w WORKDIR -r REPO -m METADATA_CSV -g GROUP_COL
#                                    [--source local|curated] [--cohorts dir1,dir2,dir3]
#                                    [--train-cohort name] [--condition CRC] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 97_stat_crosscohort.sh -w WORKDIR -r REPO -m METADATA_CSV -g GROUP_COL [OPTIONS]

Required:
  -w  Project work directory (used as default cohort if --source local without --cohorts)
  -r  Repository root
  -m  Metadata CSV (must have columns: sample_id, GROUP_COL, cohort)
  -g  Group column name (e.g., Group, Disease)

Optional:
  --source          Data source: local|curated (default: local)
  --cohorts         Comma-separated cohort dirs (for local) or names (for curated)
                    Example: --cohorts "Project_A,Project_B,Project_C"
  --train-cohort    Cohort name to train on (default: first cohort)
  --test-cohorts    Comma-separated test cohort names (default: all except train)
  --condition       Condition for curatedMGD: CRC|T2D|IBD (default: CRC)
  --meta-analysis   Enable meta-analysis with random-effects model
  --force           Re-run even if sentinel exists
  -h, --help        Show this help message

Output directory: ${WORKDIR}/result/viz_crosscohort/

Examples:
  # Local multi-cohort (3 projects)
  bash 97_stat_crosscohort.sh -w Project_A -r ~/Course/CSCCD-MetagenomeFlow \
       -m metadata.csv -g Group \
       --source local --cohorts "Project_A,Project_B,Project_C" \
       --train-cohort Project_A

  # curatedMetagenomicData (online, requires network)
  bash 97_stat_crosscohort.sh -w Project_example -r ~/Course/CSCCD-MetagenomeFlow \
       -m metadata.csv -g Group \
       --source curated --condition CRC
EOF
}

SOURCE="local"
COHORTS=""
TRAIN_COHORT=""
TEST_COHORTS=""
CONDITION="CRC"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV g:GROUP_COL"
export MGX_OPTS_FLAG="force meta-analysis"
export MGX_OPTS_LONG="source:SOURCE cohorts:COHORTS train-cohort:TRAIN_COHORT test-cohorts:TEST_COHORTS condition:CONDITION"
mgx_parse "$@"
mgx_require WORKDIR REPO METADATA_CSV GROUP_COL

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

ML_DIR="${WORKDIR}/result/stat/ml"
RESULT_DIR="${WORKDIR}/result/viz_crosscohort"
LOG_DIR="${WORKDIR}/logs/stat/crosscohort"
SENTINEL="${RESULT_DIR}/crosscohort_done.txt"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/97_stat_crosscohort_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=============================================================================="
echo "Cross-Cohort Validation"
echo "Start time: $(date)"
echo "=============================================================================="

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

# Validate source mode
if [ "${SOURCE}" != "local" ] && [ "${SOURCE}" != "curated" ]; then
    echo "[ERROR] --source must be 'local' or 'curated'"
    exit 1
fi

# For local source, validate cohort directories
if [ "${SOURCE}" = "local" ]; then
    if [ -z "${COHORTS}" ]; then
        echo "[INFO] No --cohorts specified, using single cohort: ${WORKDIR}"
        COHORTS="$(basename ${WORKDIR})"
    fi
    IFS=',' read -ra COHORT_ARRAY <<< "${COHORTS}"
    echo "[INFO] Local cohorts: ${COHORTS}"
    for cohort in "${COHORT_ARRAY[@]}"; do
        cohort_path="$(dirname ${WORKDIR})/${cohort}"
        if [ ! -d "${cohort_path}" ]; then
            echo "[ERROR] Cohort directory not found: ${cohort_path}"
            exit 1
        fi
    done
fi

# Set train cohort
if [ -z "${TRAIN_COHORT}" ]; then
    if [ "${SOURCE}" = "local" ]; then
        TRAIN_COHORT="${COHORT_ARRAY[0]}"
    else
        TRAIN_COHORT="first_available"
    fi
fi

echo "[INFO] Configuration:"
echo "  Source: ${SOURCE}"
echo "  Cohorts: ${COHORTS}"
echo "  Train cohort: ${TRAIN_COHORT}"
echo "  Group column: ${GROUP_COL}"
echo "  Metadata: ${METADATA_CSV}"
echo "  Meta-analysis: ${META_ANALYSIS}"

# Export variables for R script
export WORKDIR REPO METADATA_CSV GROUP_COL SOURCE COHORTS TRAIN_COHORT TEST_COHORTS CONDITION META_ANALYSIS ML_DIR RESULT_DIR

echo "[INFO] Running R script for cross-cohort analysis..."

(cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/97_crosscohort.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] R script failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "=============================================================================="
mgx_end "crosscohort"
echo "Results: ${RESULT_DIR}"
echo "Log: ${LOG_FILE}"
echo "=============================================================================="
