#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/run_ci_checks.sh
# Purpose: Single entry point for the 3-layer test pyramid:
#            level 1 -- full-repo shellcheck static check
#            level 2 -- sampled integration tests against Test_CI_fixture
#            level 3 -- Snakemake DAG connectivity dry-run
# Usage:   bash scripts/tests/run_ci_checks.sh --level {1,2,3,all}
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEVEL="all"

show_help() {
cat <<'EOF'
Usage: bash scripts/tests/run_ci_checks.sh --level {1,2,3,all}

  --level 1     Layer 1 only: full-repo shellcheck scan
  --level 2     Layer 2 only: sampled integration tests (Test_CI_fixture)
  --level 3     Layer 3 only: Snakemake DAG connectivity dry-run
  --level all   Run all three layers (default)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --level) LEVEL="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

case "${LEVEL}" in
    1|2|3|all) ;;
    *) echo "[ERROR] Invalid --level: ${LEVEL}"; show_help; exit 1 ;;
esac

declare -a CHECK_NAMES
declare -a CHECK_RESULTS

run_check() {
    local name="$1"
    local script="$2"
    echo ""
    echo "=============================================================================="
    echo "[RUN] ${name}"
    echo "=============================================================================="
    if bash "${script}"; then
        CHECK_NAMES+=("${name}")
        CHECK_RESULTS+=("PASS")
    else
        CHECK_NAMES+=("${name}")
        CHECK_RESULTS+=("FAIL")
    fi
}

if [ "${LEVEL}" = "1" ] || [ "${LEVEL}" = "all" ]; then
    run_check "level1: shellcheck full scan" "${REPO_ROOT}/scripts/tests/level1/run_shellcheck_all.sh"
fi

if [ "${LEVEL}" = "2" ] || [ "${LEVEL}" = "all" ]; then
    for t in "${REPO_ROOT}"/scripts/tests/level2/test_*.sh; do
        [ -f "${t}" ] || continue
        run_check "level2: $(basename "${t}")" "${t}"
    done
fi

if [ "${LEVEL}" = "3" ] || [ "${LEVEL}" = "all" ]; then
    run_check "level3: DAG connectivity" "${REPO_ROOT}/scripts/tests/level3/test_dag_connectivity.sh"
fi

echo ""
echo "=============================================================================="
echo "CI CHECK SUMMARY"
echo "=============================================================================="
OVERALL=0
for i in "${!CHECK_NAMES[@]}"; do
    printf "%-55s %s\n" "${CHECK_NAMES[$i]}" "${CHECK_RESULTS[$i]}"
    if [ "${CHECK_RESULTS[$i]}" = "FAIL" ]; then
        OVERALL=1
    fi
done
echo "=============================================================================="

exit "${OVERALL}"
