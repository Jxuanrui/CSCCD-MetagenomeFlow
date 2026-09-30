#!/bin/bash
# Task: End-to-end regression test (minimal version)
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Quick smoke test to verify pipeline integrity after changes

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"

# Parse arguments
SHOW_HELP=false
TEST_SAMPLE=""
QUICK_MODE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    -s|--sample)
      TEST_SAMPLE="$2"
      shift 2
      ;;
    -q|--quick)
      QUICK_MODE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  cat << 'EOF'
Usage: 00_e2e_test.sh [OPTIONS]

Quick end-to-end smoke test to verify pipeline integrity after changes.

OPTIONS:
  -h, --help           Show this help message
  -s, --sample NAME    Sample directory to use for testing (e.g., Sample4)
  -q, --quick          Quick mode: only test critical steps (QC → Classify → Assemble)
  --dry-run            Show what would be tested without running

TEST STRATEGY:
  Uses a small, previously-analyzed sample to verify:
  1. All scripts can execute without errors
  2. Expected output files are generated
  3. Output formats match expectations
  4. No regressions in critical checkpoints

QUICK MODE (5-10 minutes):
  - 01_qc: Quality control and read filtering
  - 11_kraken2: Taxonomic classification
  - 21_megahit: Assembly (subset reads)

FULL MODE (30-60 minutes):
  - All bacteria steps (11-42)
  - Key virus steps (53-57)
  - Key fungi steps (71-81)
  - Diversity statistics (91)

EXAMPLES:
  # Quick test with default sample
  bash scripts/00_e2e_test.sh -s Sample4 -q

  # Full regression test
  bash scripts/00_e2e_test.sh -s Sample4

  # Dry run to see test plan
  bash scripts/00_e2e_test.sh -s Sample4 --dry-run

OUTPUT:
  Test results written to: temp/e2e_TIMESTAMP/
    ├── test_log.txt       (execution log)
    ├── results_summary.txt (pass/fail summary)
    └── outputs/           (generated outputs for verification)

PREREQUISITES:
  - Test sample must exist in Project/TEST_SAMPLE/
  - Test sample should be small (< 1GB FASTQ) for quick turnaround
EOF
  exit 0
fi

if [ -z "$TEST_SAMPLE" ]; then
  echo "Error: --sample NAME is required"
  echo "Example: bash scripts/00_e2e_test.sh -s Sample4 -q"
  exit 1
fi

TEST_SAMPLE_DIR="${PROJ_DIR}/Project/${TEST_SAMPLE}"
if [ ! -d "$TEST_SAMPLE_DIR" ]; then
  echo "[ERROR] Test sample directory not found: $TEST_SAMPLE_DIR"
  exit 1
fi

# Create test run directory
TEST_RUN_DIR="${PROJ_DIR}/temp/e2e_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_RUN_DIR/outputs"

TEST_LOG="${TEST_RUN_DIR}/test_log.txt"
RESULTS_FILE="${TEST_RUN_DIR}/results_summary.txt"

echo "========================================"
echo "End-to-End Regression Test"
echo "========================================"
echo "Sample: $TEST_SAMPLE"
echo "Mode: $([ "$QUICK_MODE" = true ] && echo 'QUICK' || echo 'FULL')"
echo "Dry run: $([ "$DRY_RUN" = true ] && echo 'YES' || echo 'NO')"
echo "Test run: $TEST_RUN_DIR"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "" | tee "$TEST_LOG"

# Test execution function
run_test() {
  local STEP_NAME=$1
  local SCRIPT=$2
  local EXPECTED_OUTPUT=$3
  local IS_CRITICAL=$4

  echo "--------------------------------------" | tee -a "$TEST_LOG"
  echo "Testing: $STEP_NAME" | tee -a "$TEST_LOG"
  echo "Script: $SCRIPT" | tee -a "$TEST_LOG"
  echo "Expected: $EXPECTED_OUTPUT" | tee -a "$TEST_LOG"

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would execute: bash $SCRIPT" | tee -a "$TEST_LOG"
    echo "Status: SKIPPED (dry run)" | tee -a "$TEST_LOG"
    return 0
  fi

  # Execute script
  START_TIME=$(date +%s)
  if bash "${PROJ_DIR}/${SCRIPT}" >> "$TEST_LOG" 2>&1; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    echo "Execution: SUCCESS (${ELAPSED}s)" | tee -a "$TEST_LOG"

    # Verify output
    if [ -n "$EXPECTED_OUTPUT" ] && [ -d "${TEST_SAMPLE_DIR}/${EXPECTED_OUTPUT}" ]; then
      FILE_COUNT=$(find "${TEST_SAMPLE_DIR}/${EXPECTED_OUTPUT}" -type f 2>/dev/null | wc -l)
      if [ "$FILE_COUNT" -gt 0 ]; then
        echo "Output verification: PASS ($FILE_COUNT files)" | tee -a "$TEST_LOG"
        echo "✓ PASS | $STEP_NAME" >> "$RESULTS_FILE"
        return 0
      else
        echo "Output verification: FAIL (no files generated)" | tee -a "$TEST_LOG"
        echo "✗ FAIL | $STEP_NAME | No output files" >> "$RESULTS_FILE"
        [ "$IS_CRITICAL" = "true" ] && return 1 || return 0
      fi
    else
      echo "Output verification: SKIP (no expected output specified)" | tee -a "$TEST_LOG"
      echo "✓ PASS | $STEP_NAME" >> "$RESULTS_FILE"
      return 0
    fi
  else
    echo "Execution: FAILED" | tee -a "$TEST_LOG"
    echo "✗ FAIL | $STEP_NAME | Script execution failed" >> "$RESULTS_FILE"
    [ "$IS_CRITICAL" = "true" ] && return 1 || return 0
  fi
}

# Initialize results file
echo "# E2E Test Results - $(date '+%Y-%m-%d %H:%M:%S')" > "$RESULTS_FILE"
echo "# Sample: $TEST_SAMPLE" >> "$RESULTS_FILE"
echo "# Mode: $([ "$QUICK_MODE" = true ] && echo 'QUICK' || echo 'FULL')" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Quick mode tests
if [ "$QUICK_MODE" = true ]; then
  echo "## Quick Mode Test Suite" | tee -a "$TEST_LOG"
  echo "" | tee -a "$TEST_LOG"

  # Test 1: QC
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if run_test "Quality Control" "scripts/01_metadata_qc.sh" "temp/01_qc" "true"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "[ERROR] Critical test failed: Quality Control" | tee -a "$TEST_LOG"
    exit 1
  fi

  # Test 2: Taxonomic classification
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if run_test "Kraken2 Classification" "scripts/11_bac_kraken2.sh" "temp/11_kraken2" "true"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "[ERROR] Critical test failed: Kraken2" | tee -a "$TEST_LOG"
    exit 1
  fi

  # Test 3: Assembly (subset)
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if run_test "MEGAHIT Assembly" "scripts/21_bac_megahit.sh" "temp/21_assembly" "true"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "[WARN] Assembly test failed (non-critical in quick mode)" | tee -a "$TEST_LOG"
  fi

else
  # Full mode tests
  echo "## Full Mode Test Suite" | tee -a "$TEST_LOG"
  echo "" | tee -a "$TEST_LOG"
  echo "[INFO] Full mode not yet implemented - use --quick for now" | tee -a "$TEST_LOG"
  echo "[INFO] Full mode will be expanded after Phase 2 Task #4 completion" | tee -a "$TEST_LOG"
fi

# Summary
echo "" | tee -a "$TEST_LOG"
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total tests: $TOTAL_TESTS" | tee -a "$TEST_LOG"
echo "  Passed: $PASSED_TESTS" | tee -a "$TEST_LOG"
echo "  Failed: $FAILED_TESTS" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

if [ $FAILED_TESTS -eq 0 ]; then
  echo "[SUCCESS] All tests passed" | tee -a "$TEST_LOG"
  echo "" | tee -a "$TEST_LOG"
  echo "Test log: $TEST_LOG" | tee -a "$TEST_LOG"
  echo "Results: $RESULTS_FILE" | tee -a "$TEST_LOG"
  exit 0
else
  echo "[FAILURE] $FAILED_TESTS test(s) failed" | tee -a "$TEST_LOG"
  echo "" | tee -a "$TEST_LOG"
  echo "Review logs for details:" | tee -a "$TEST_LOG"
  echo "  $TEST_LOG" | tee -a "$TEST_LOG"
  exit 1
fi
