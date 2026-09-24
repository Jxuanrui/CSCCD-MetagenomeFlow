#!/usr/bin/env bash
# validate.sh — Wacker2026_NatCommun reference package validation

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "${ROOT}" && pwd)"
PKG_REL="skills/replications/statistics/Wacker2026_NatCommun"
PKG_DIR="${ROOT}/${PKG_REL}"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local cmd="$2"
    if eval "${cmd}" > /dev/null 2>&1; then
        echo "[PASS] ${desc}"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] ${desc}"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Wacker2026_NatCommun Validation ==="

check "manifest.yaml exists" "[ -f '${PKG_DIR}/manifest.yaml' ]"
check "method_graph.yaml exists" "[ -f '${PKG_DIR}/method_graph.yaml' ]"
check "params.yaml exists" "[ -f '${PKG_DIR}/params.yaml' ]"
check "README.md exists" "[ -f '${PKG_DIR}/README.md' ]"
check "validate.sh exists" "[ -f '${PKG_DIR}/validate.sh' ]"

check "TOFU-MAaPO GitHub reachable" "git ls-remote https://github.com/ikmb/TOFU-MAaPO.git HEAD"
check "TOFUpaper GitHub reachable" "git ls-remote https://github.com/ikmb/TOFUpaper.git HEAD"

check "reference-only package has no code/original" "[ ! -d '${PKG_DIR}/code/original' ]"
check "reference-only package has no code/adapted" "[ ! -d '${PKG_DIR}/code/adapted' ]"
check "README notes reference-only status" "grep -qi 'reference-only' '${PKG_DIR}/README.md'"
check "README compares TOFU-MAaPO vs CSCCD-MetagenomeFlow" "grep -q 'TOFU-MAaPO vs CSCCD-MetagenomeFlow' '${PKG_DIR}/README.md'"

echo ""
echo "=== Result: ${PASS} passed, ${FAIL} failed ==="
if [ "${FAIL}" -eq 0 ]; then
    echo "ALL PASS — Wacker2026_NatCommun reference package validated"
    exit 0
fi

echo "Some checks failed."
exit 1
