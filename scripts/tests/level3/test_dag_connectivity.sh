#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level3/test_dag_connectivity.sh
# Purpose: Validate the Snakemake rule graph is fully connected (no
#          MissingInputException / CircularDependencyError) via a dry-run
#          against Test_CI_fixture. Does NOT require real fastq/intermediate
#          files -- dry-run only needs samplesheet.csv/metadata.csv to resolve
#          the sample_id column.
# Usage:   bash scripts/tests/level3/test_dag_connectivity.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SNAKEMAKE="${REPO_ROOT}/miniforge3/bin/snakemake"
CONFIG="${REPO_ROOT}/pipeline/config/config.test_ci.yaml"
SNAKEFILE="${REPO_ROOT}/pipeline/Snakefile"
PROFILE="${REPO_ROOT}/pipeline/profiles/auto"

if [ ! -x "${SNAKEMAKE}" ]; then
    echo "[ERROR] snakemake not found at ${SNAKEMAKE}"
    exit 1
fi
if [ ! -f "${REPO_ROOT}/Project/Test_CI_fixture/samplesheet.csv" ]; then
    echo "[ERROR] Test_CI_fixture missing -- see Project/Test_CI_fixture/README.md"
    exit 1
fi

cd "${REPO_ROOT}"

echo "[INFO] Running Snakemake dry-run against Test_CI_fixture..."
LOG="$(mktemp)"
trap 'rm -f "${LOG}"' EXIT

if ! "${SNAKEMAKE}" -s "${SNAKEFILE}" --configfile "${CONFIG}" --profile "${PROFILE}" -n > "${LOG}" 2>&1; then
    echo "[FAIL] snakemake dry-run exited non-zero:"
    cat "${LOG}"
    exit 1
fi

if grep -qE "MissingInputException|CircularDependencyError|AmbiguousRuleException" "${LOG}"; then
    echo "[FAIL] DAG connectivity issue detected:"
    grep -E "MissingInputException|CircularDependencyError|AmbiguousRuleException" -A5 "${LOG}"
    exit 1
fi

JOB_COUNT="$(grep -E '^total' "${LOG}" | awk '{print $2}')"
echo "[PASS] DAG dry-run OK, ${JOB_COUNT:-?} total jobs resolved, no connectivity errors."

# ── Off-DAG chains: rules NOT in rule all (e.g. crosscohort_validation,
#    viz_statistics_all) are invisible to the full dry-run above.
#    Supervisor finding 2026-09-29: explicit-target dry-runs required.
#    Targets MUST be absolute (WORKDIR-constant rules declare absolute paths).
echo "[INFO] Explicit-target dry-run for off-DAG crosscohort chain..."
FIXTURE="$("${REPO_ROOT}/miniforge3/bin/python" -c "import yaml;print(yaml.safe_load(open('${CONFIG}'))['workdir'])")"
OFFLOG="$(mktemp)"
if ! "${SNAKEMAKE}" -s "${SNAKEFILE}" --configfile "${CONFIG}" -n -- \
        "${FIXTURE}/result/viz_crosscohort/crosscohort_done.txt" \
        "${FIXTURE}/result/viz_statistics_all_done.txt" > "${OFFLOG}" 2>&1; then
    echo "[FAIL] off-DAG chain dry-run exited non-zero:"
    cat "${OFFLOG}"
    rm -f "${OFFLOG}"
    exit 1
fi
if grep -qE "MissingInputException|MissingRuleException|AmbiguousRuleException|CircularDependencyError" "${OFFLOG}"; then
    echo "[FAIL] off-DAG chain connectivity issue:"
    grep -E "MissingInputException|MissingRuleException|AmbiguousRuleException|CircularDependencyError" -A5 "${OFFLOG}"
    rm -f "${OFFLOG}"
    exit 1
fi
rm -f "${OFFLOG}"
echo "[PASS] Off-DAG chain (crosscohort + viz_statistics_all) resolves."
