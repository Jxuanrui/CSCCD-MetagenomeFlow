#!/usr/bin/env bash
# validate.sh — BlancoMiguez2023_NatBiotechnol MetaPhlAn4 validation

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

echo "=== BlancoMiguez2023_NatBiotechnol — MetaPhlAn4 Validation ==="
echo "Repo: ${REPO}"
echo ""

echo "--- MetaPhlAn4 bacterial profiling ---"
check_script scripts/11_bac_metaphlan4.sh
check_script scripts/11b_bac_metaphlan4_merge.sh

echo "--- MetaPhlAn4 eukaryote profiling ---"
check_script scripts/72_fun_metaphlan4_euk.sh

echo "--- Strain-level profiling (StrainPhlAn4) ---"
check_script scripts/12_bac_strainphlan4.sh

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""
echo "=== Check MetaPhlAn4 database installation ==="
DB_FOUND=0
for db_path in "${REPO}/db/metaphlan4" "${HOME}/.local/share/metaphlan4" "/data/metaphlan"; do
    if [ -d "${db_path}" ]; then
        echo "[OK] MetaPhlAn4 database found at ${db_path}"
        DB_FOUND=1
        PASS=$((PASS + 1))
        break
    fi
done
if [ ${DB_FOUND} -eq 0 ]; then
    echo "[WARN] MetaPhlAn4 database not found (run: metaphlan --install)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Key Performance Claims from Paper (reference) ==="
echo "  Gut read assignment gain: +20% over MetaPhlAn 3"
echo "  Rumen/soil read assignment gain: >40%"
echo "  Total SGBs: 26,970 (21,978 kSGBs + 4,992 uSGBs)"
echo "  Reference genomes: 1.6M (including MAGs)"
echo "  Note: NOT backward compatible with MetaPhlAn 3"

[ ${FAIL} -eq 0 ] && exit 0 || exit 1
