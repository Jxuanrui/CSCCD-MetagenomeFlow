#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level1/run_shellcheck_all.sh
# Purpose: Full-repo shellcheck scan across every scripts/*.sh (not just staged
#          files, unlike the pre-commit hook). Intended for periodic self-audit
#          and for re-tuning .shellcheckrc when the SC-code distribution shifts.
# Usage:   bash scripts/tests/level1/run_shellcheck_all.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SHELLCHECK="${REPO_ROOT}/envs/shellcheck/bin/shellcheck"

if [ ! -x "${SHELLCHECK}" ]; then
    echo "[ERROR] shellcheck not found at ${SHELLCHECK}"
    echo "[HINT]  mamba create -y --prefix \"${REPO_ROOT}/envs/shellcheck\" -c conda-forge \"shellcheck>=0.9\""
    exit 1
fi

cd "${REPO_ROOT}"

mapfile -t ALL_SH < <( { find scripts -maxdepth 1 -name '*.sh' -type f; find scripts/utils scripts/hooks scripts/tests -maxdepth 1 -name '*.sh' -type f; } | sort -u)
echo "[INFO] Scanning ${#ALL_SH[@]} script(s) under scripts/ + utils/hooks/tests (severity=warning)..."
echo ""

FAILED=0
FAIL_COUNT=0
for f in "${ALL_SH[@]}"; do
    if ! "${SHELLCHECK}" --severity=warning "${f}"; then
        FAILED=1
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "=============================================================================="
if [ "${FAILED}" -ne 0 ]; then
    echo "[SUMMARY] ${FAIL_COUNT}/${#ALL_SH[@]} script(s) have shellcheck findings (severity>=warning)."
else
    echo "[SUMMARY] All ${#ALL_SH[@]} scripts pass shellcheck (severity>=warning)."
fi
echo "=============================================================================="

exit "${FAILED}"
