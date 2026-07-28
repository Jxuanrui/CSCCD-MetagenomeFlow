#!/usr/bin/env bash
# ==============================================================================
# Script: test_97_crosscohort.sh
# Purpose: Test cross-cohort validation with mock multi-cohort data
# ==============================================================================

set -euo pipefail

REPO=~/Course/Maxmetagenome
BASE_PROJECT="${REPO}/Project/Project_example"

echo "=============================================================================="
echo "Testing Cross-Cohort Validation Framework"
echo "=============================================================================="

# Check if base project exists
if [ ! -d "${BASE_PROJECT}" ]; then
    echo "[ERROR] Base project not found: ${BASE_PROJECT}"
    exit 1
fi

# Create mock cohorts by copying Project_example
MOCK_DIR="${REPO}/Project/_test_crosscohort"
mkdir -p "${MOCK_DIR}"

echo "[INFO] Creating 3 mock cohorts from Project_example..."

for cohort in Cohort_A Cohort_B Cohort_C; do
    cohort_path="${MOCK_DIR}/${cohort}"

    if [ ! -d "${cohort_path}" ]; then
        echo "  Creating ${cohort}..."
        cp -r "${BASE_PROJECT}" "${cohort_path}"

        # Modify metadata to add cohort label
        if [ -f "${cohort_path}/metadata.csv" ]; then
            sed -i "1s/$/,cohort/" "${cohort_path}/metadata.csv"
            sed -i "2,\$s/$/,${cohort}/" "${cohort_path}/metadata.csv"
        fi
    else
        echo "  ${cohort} already exists, skipping"
    fi
done

echo "[INFO] Mock cohorts created at: ${MOCK_DIR}"

# Test 1: Local multi-cohort mode
echo ""
echo "=============================================================================="
echo "Test 1: Local Multi-Cohort Mode (3 cohorts)"
echo "=============================================================================="

bash "${REPO}/scripts/97_stat_crosscohort.sh" \
    -w "${MOCK_DIR}/Cohort_A" \
    -r "${REPO}" \
    -m "${BASE_PROJECT}/metadata.csv" \
    -g "Group" \
    --source local \
    --cohorts "Cohort_A,Cohort_B,Cohort_C" \
    --train-cohort "Cohort_A" \
    --force

EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ]; then
    echo "[SUCCESS] Test 1 passed"
    echo "[INFO] Results: ${MOCK_DIR}/Cohort_A/result/viz_crosscohort/"
    ls -lh "${MOCK_DIR}/Cohort_A/result/viz_crosscohort/"
else
    echo "[ERROR] Test 1 failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

# Test 2: With meta-analysis
echo ""
echo "=============================================================================="
echo "Test 2: Local Multi-Cohort with Meta-Analysis"
echo "=============================================================================="

bash "${REPO}/scripts/97_stat_crosscohort.sh" \
    -w "${MOCK_DIR}/Cohort_A" \
    -r "${REPO}" \
    -m "${BASE_PROJECT}/metadata.csv" \
    -g "Group" \
    --source local \
    --cohorts "Cohort_A,Cohort_B,Cohort_C" \
    --meta-analysis \
    --force

EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ]; then
    echo "[SUCCESS] Test 2 passed"

    if [ -f "${MOCK_DIR}/Cohort_A/result/viz_crosscohort/meta_analysis_results.tsv" ]; then
        echo "[INFO] Meta-analysis results:"
        cat "${MOCK_DIR}/Cohort_A/result/viz_crosscohort/meta_analysis_results.tsv"
    fi
else
    echo "[ERROR] Test 2 failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

echo ""
echo "=============================================================================="
echo "All Tests Passed!"
echo "=============================================================================="
echo ""
echo "Cleanup: rm -rf ${MOCK_DIR}"
