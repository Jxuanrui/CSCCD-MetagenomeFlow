#!/usr/bin/env bash
# ==============================================================================
# Script: 97_stat_crosscohort.sh
# Purpose: Enhanced cross-cohort validation with local multi-cohort support
# Usage:   bash 97_stat_crosscohort.sh -w WORKDIR -r REPO -m METADATA_CSV -g GROUP_COL
#                                    [--source local|curated] [--cohorts dir1,dir2,dir3]
#                                    [--train-cohort name] [--condition CRC] [--force]
# ==============================================================================

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
  bash 97_stat_crosscohort.sh -w Project_A -r ~/Course/Maxmetagenome \
       -m metadata.csv -g Group \
       --source local --cohorts "Project_A,Project_B,Project_C" \
       --train-cohort Project_A

  # curatedMetagenomicData (online, requires network)
  bash 97_stat_crosscohort.sh -w Project_example -r ~/Course/Maxmetagenome \
       -m metadata.csv -g Group \
       --source curated --condition CRC
EOF
}

WORKDIR=""
REPO=""
METADATA_CSV=""
GROUP_COL=""
SOURCE="local"
COHORTS=""
TRAIN_COHORT=""
TEST_COHORTS=""
CONDITION="CRC"
META_ANALYSIS=0
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        --source) SOURCE="$2"; shift 2 ;;
        --cohorts) COHORTS="$2"; shift 2 ;;
        --train-cohort) TRAIN_COHORT="$2"; shift 2 ;;
        --test-cohorts) TEST_COHORTS="$2"; shift 2 ;;
        --condition) CONDITION="$2"; shift 2 ;;
        --meta-analysis) META_ANALYSIS=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ] || [ -z "${METADATA_CSV}" ] || [ -z "${GROUP_COL}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

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

(cd "${WORKDIR}" && conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${REPO}/scripts/97_crosscohort.R")

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
echo "[SUCCESS] Cross-cohort validation completed in ${SECONDS}s"
echo "Results: ${RESULT_DIR}"
echo "Log: ${LOG_FILE}"
echo "=============================================================================="
