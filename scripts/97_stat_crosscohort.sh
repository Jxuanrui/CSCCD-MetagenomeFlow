#!/usr/bin/env bash
# ==============================================================================
# Script: 97_stat_crosscohort.sh
# Purpose: Enhanced cross-cohort validation with local multi-cohort support
# Usage:   bash 97_stat_crosscohort.sh -w WORKDIR -r REPO -m METADATA_CSV -g GROUP_COL
#                                    [--source local|curated] [--cohorts dir1,dir2,dir3]
#                                    [--train-cohort name] [--test-cohorts c1,c2]
#                                    [--condition CRC] [--force]
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
  --test-cohorts    Comma-separated EXTERNAL test cohort names
                    (default: all loaded cohorts except the train cohort;
                    the train cohort is always evaluated with role=in_sample)
  --condition       Condition for curatedMGD: CRC|T2D|IBD (default: CRC)
  --meta-analysis   Enable meta-analysis with random-effects model
  --no-mmuphin      Disable the MMUPHin sensitivity arm; the primary result
                    (batch_correction=none, uncorrected) is always computed
  --force           Re-run even if sentinel exists
  -h, --help        Show this help message

Failure semantics (T-11): prediction/plot failures inside 97_crosscohort.R
write result/viz_crosscohort/crosscohort_FAILED.txt and exit non-zero; the
crosscohort_done.txt sentinel is only written after all outputs succeed.
If upstream script 96 skipped model training (insufficient samples), this
script writes a SKIPPED sentinel plus header-only tables and exits 0.
Primary result = uncorrected (batch_correction=none); the MMUPHin-corrected
arm is co-reported as a sensitivity analysis (rows in the metrics tables).
A fresh (non-skipped) run first clears stale outputs of the previous round
(PDFs, meta_analysis_results.tsv, mmuphin_colsums.tsv) in the output dir.

Output directory: ${WORKDIR}/result/viz_crosscohort/

Examples:
  # Local multi-cohort (3 projects, train on A, external = B and C)
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

SOURCE="local"
COHORTS=""
TRAIN_COHORT=""
TEST_COHORTS=""
CONDITION="CRC"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV g:GROUP_COL"
export MGX_OPTS_FLAG="force meta-analysis no-mmuphin"
export MGX_OPTS_LONG="source:SOURCE cohorts:COHORTS train-cohort:TRAIN_COHORT test-cohorts:TEST_COHORTS condition:CONDITION"
mgx_parse "$@"
mgx_require WORKDIR REPO METADATA_CSV GROUP_COL

# W2-1: MMUPHin arm toggle (default on = sensitivity arm co-reported;
# --no-mmuphin restricts the run to the primary uncorrected result)
MMUPHIN_SENSITIVITY=1
if [ "${NO_MMUPHIN:-0}" -eq 1 ]; then MMUPHIN_SENSITIVITY=0; fi

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

ML_DIR="${WORKDIR}/result/stat/bacteria/ml"
RESULT_DIR="${WORKDIR}/result/viz_crosscohort"
LOG_DIR="${WORKDIR}/logs/stat/crosscohort"
SENTINEL="${RESULT_DIR}/crosscohort_done.txt"
FAILED_FILE="${RESULT_DIR}/crosscohort_FAILED.txt"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/97_stat_crosscohort_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# Header-only tables for skip paths; columns MUST match 97_crosscohort.R
AUC_SUMMARY_HEADER="cohort	role	batch_correction	auc	auc_ci_low	auc_ci_high	n_case	n_control	n_samples"
METRICS_HEADER="cohort	role	batch_correction	decision_threshold	n_samples	n_case	n_control	auroc	auc_ci_low	auc_ci_high	auprc	sensitivity	specificity	ppv	n_features_zero_filled"

skip_run() {
    echo "[INFO] SKIPPED: ${1}"
    echo "SKIPPED: ${1}" > "${SENTINEL}"
    echo "Timestamp: $(date)" >> "${SENTINEL}"
    echo "Upstream SIAMCAT model unavailable; no cross-cohort metrics computed." >> "${SENTINEL}"
    printf '%s\n' "${AUC_SUMMARY_HEADER}" > "${RESULT_DIR}/auc_summary.tsv"
    printf '%s\n' "${METRICS_HEADER}" > "${RESULT_DIR}/crosscohort_metrics.tsv"
    exit 0
}

echo "=============================================================================="
echo "Cross-Cohort Validation"
echo "Start time: $(date)"
echo "=============================================================================="

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    # W2-6: a SKIPPED sentinel is not a completed run - say so explicitly
    # instead of silently skipping as if results existed (still exit 0).
    if grep -q "^SKIPPED" "${SENTINEL}"; then
        echo "[INFO] Sentinel exists but marks a SKIPPED run: ${SENTINEL}"
        echo "[INFO] upstream skipped, rerun 96 then 97 --force"
    else
        echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
        echo "[INFO] Use --force to re-run"
    fi
    exit 0
fi

# Upstream SIAMCAT training skipped (insufficient samples) -> 97 skips too
# (P3-U-04: explicit SKIPPED, exit 0; never stop() on an upstream skip)
ML_SENTINEL="${ML_DIR}/siamcat_done.txt"
if [ ! -f "${ML_DIR}/siamcat_lasso.rds" ]; then
    if [ -f "${ML_SENTINEL}" ] && grep -q "^SKIPPED" "${ML_SENTINEL}"; then
        skip_run "upstream SIAMCAT training skipped (see ${ML_SENTINEL})"
    fi
    echo "[ERROR] SIAMCAT model not found: ${ML_DIR}/siamcat_lasso.rds"
    echo "[ERROR] Run script 96 first"
    exit 1
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
        COHORTS="$(basename "${WORKDIR}")"
    fi
    IFS=',' read -ra COHORT_ARRAY <<< "${COHORTS}"
    echo "[INFO] Local cohorts: ${COHORTS}"
    for cohort in "${COHORT_ARRAY[@]}"; do
        cohort_path="$(dirname "${WORKDIR}")/${cohort}"
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
echo "  Test cohorts: ${TEST_COHORTS:-<default: all except train>}"
echo "  Group column: ${GROUP_COL}"
echo "  Metadata: ${METADATA_CSV}"
echo "  Meta-analysis: ${META_ANALYSIS}"
echo "  MMUPHin sensitivity arm: ${MMUPHIN_SENSITIVITY} (primary result is always batch_correction=none)"

# Export variables for R script
export WORKDIR REPO METADATA_CSV GROUP_COL SOURCE COHORTS TRAIN_COHORT TEST_COHORTS CONDITION META_ANALYSIS MMUPHIN_SENSITIVITY ML_DIR RESULT_DIR

# Fresh run: clear stale sentinel / FAILED marker so a previous failure or
# success can never leak into this run's outcome (T-11), and clear the
# previous round's outputs (W2-6, §4.4 output hygiene): old PDFs, the
# meta-analysis table and the MMUPHin colSums evidence. The skip paths
# above return before this point, so resume/skip semantics are untouched.
rm -f "${SENTINEL}" "${FAILED_FILE}"
rm -f "${RESULT_DIR}"/*.pdf "${RESULT_DIR}/meta_analysis_results.tsv" "${RESULT_DIR}/mmuphin_colsums.tsv"

echo "[INFO] Running R script for cross-cohort analysis..."

set +e
(cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/97_crosscohort.R")
EXIT_CODE=$?
set -e

if [ ${EXIT_CODE} -ne 0 ]; then
    if [ -f "${FAILED_FILE}" ]; then
        echo "[ERROR] 97_crosscohort.R FAILED (see ${FAILED_FILE}):"
        cat "${FAILED_FILE}"
    else
        echo "[ERROR] R script failed with exit code ${EXIT_CODE}"
    fi
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi
if grep -q "^SKIPPED" "${SENTINEL}"; then
    echo "[INFO] 97_crosscohort reported SKIPPED (see ${SENTINEL})"
fi

echo "=============================================================================="
mgx_end "crosscohort"
echo "Results: ${RESULT_DIR}"
echo "Log: ${LOG_FILE}"
echo "=============================================================================="
