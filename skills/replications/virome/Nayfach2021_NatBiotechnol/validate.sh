#!/usr/bin/env bash
# validate.sh — Nayfach2021_NatBiotechnol CheckV validation

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

echo "=== Nayfach2021_NatBiotechnol — CheckV Validation ==="
echo "Repo: ${REPO}"
echo ""

echo "--- CheckV quality-filter integration ---"
check_script scripts/54_vir_checkv_contig.sh
check_script scripts/62_vir_checkv_mag.sh

echo ""
echo "--- Upstream viral callers used before CheckV ---"
check_script scripts/52_vir_genomad.sh
check_script scripts/53_vir_virsorter2.sh

echo ""
echo "--- CheckV database installation ---"
check_db db/checkv

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""
echo "=== Key Performance Claims from Paper (reference) ==="
echo "  Completeness estimation: 92% sensitivity, 99.7% specificity"
echo "  Provirus detection recall: 90%"
echo "  CSCCD-MetagenomeFlow HQ threshold: completeness >=50% and contamination <5%"

[ ${FAIL} -eq 0 ] && exit 0 || exit 1
