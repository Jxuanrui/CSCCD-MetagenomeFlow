#!/usr/bin/env bash
# validate.sh — Beghini2021_eLife HUMAnN3 validation

REPO="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PASS=0; FAIL=0

check_script() {
    local script="$1"
    if [ -f "${REPO}/${script}" ] && [ -x "${REPO}/${script}" ]; then
        echo "[OK]   ${script}"
        PASS=$((PASS + 1))
    elif [ -f "${REPO}/${script}" ]; then
        echo "[WARN] ${script} exists but not executable"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] ${script} not found"
        FAIL=$((FAIL + 1))
    fi
}

check_db() {
    local db="$1"
    if [ -d "${REPO}/${db}" ]; then
        echo "[OK]   ${db}"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] ${db} not found"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Beghini2021_eLife — HUMAnN3 Validation ==="
echo "Repo: ${REPO}"
echo ""

echo "--- HUMAnN functional profiling integration ---"
check_script scripts/13_bac_humann3.sh
check_script scripts/73_fun_humann4_fungi.sh

echo ""
echo "--- Upstream taxonomy dependency ---"
check_script scripts/11_bac_metaphlan4.sh

echo ""
echo "--- HUMAnN databases ---"
check_db db/humann4/chocophlan
check_db db/humann4/uniref

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""
echo "=== Key Performance Claims from Paper (reference) ==="
echo "  95% of pathways quantified in <1 hour/sample with 16 cores"
echo "  Stratified output retains species contributors to pathways"
echo "  Core workflow: MetaPhlAn prescreen -> ChocoPhlAn/UniRef90 -> MinPath"

[ ${FAIL} -eq 0 ] && exit 0 || exit 1
