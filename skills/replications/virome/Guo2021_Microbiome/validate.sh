#!/usr/bin/env bash
# validate.sh — Guo2021_Microbiome VirSorter2 validation

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

echo "=== Guo2021_Microbiome — VirSorter2 Validation ==="
echo "Repo: ${REPO}"
echo ""

echo "--- VirSorter2 integration ---"
check_script scripts/53_vir_virsorter2.sh

echo ""
echo "--- Consensus/downstream QC partners ---"
check_script scripts/52_vir_genomad.sh
check_script scripts/54_vir_checkv_contig.sh

echo ""
echo "--- VirSorter2 database installation ---"
check_db db/virsorter2

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""
echo "=== Key Performance Claims from Paper (reference) ==="
echo "  dsDNA phage recall: 95.4%"
echo "  dsDNA phage precision: 90.1%"
echo "  Higher recall than DeepVirFinder for RNA and ssDNA viruses"

[ ${FAIL} -eq 0 ] && exit 0 || exit 1
