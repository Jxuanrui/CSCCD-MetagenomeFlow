#!/usr/bin/env bash
# validate.sh — Camargo2023_NatBiotechnol geNomad validation

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

echo "=== Camargo2023_NatBiotechnol — geNomad Validation ==="
echo "Repo: ${REPO}"
echo ""

echo "--- geNomad virus identification & taxonomy ---"
check_script scripts/52_vir_genomad.sh
check_script scripts/57_vir_votu_genomad.sh

echo ""
echo "--- Complementary tools (paper comparison) ---"
check_script scripts/53_vir_virsorter2.sh
check_script scripts/54_vir_checkv_contig.sh

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""
echo "=== Check geNomad database installation ==="
if [ -d "${REPO}/db/genomad_db" ]; then
    echo "[OK] geNomad database found at db/genomad_db"
    PASS=$((PASS + 1))
else
    echo "[WARN] geNomad database not found (run: genomad download-database db/)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Key Performance Claims from Paper (reference) ==="
echo "  Virus MCC: 0.953"
echo "  Plasmid MCC: 0.778"
echo "  Outperforms: VirSorter2 (higher recall), VIBRANT (higher MCC), DeepVirFinder (DNN+CRF)"

[ ${FAIL} -eq 0 ] && exit 0 || exit 1
