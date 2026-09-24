#!/usr/bin/env bash
# validate.sh — Jie2026_NatGenet replication validation
# Level 1: verify CSCCD-MetagenomeFlow scripts that implement this paper's pipeline exist
# Level 2: (informational) list parameter deviations between paper and project

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

echo "=== Jie2026_NatGenet — CSCCD-MetagenomeFlow Pipeline Validation ==="
echo "Repo: ${REPO}"
echo ""

echo "--- QC & Host Removal ---"
check_script scripts/01_qc_fastp.sh
check_script scripts/02_qc_kneaddata.sh

echo "--- Assembly ---"
check_script scripts/16_bac_megahit.sh
# Note: metaSPAdes (paired-end assembly in paper) not in CSCCD-MetagenomeFlow

echo "--- Gene Prediction ---"
check_script scripts/17_bac_prodigal.sh
check_script scripts/18_bac_cdhit.sh

echo "--- Binning ---"
check_script scripts/32_bac_coverm_depth.sh
check_script scripts/33_bac_metabat2.sh
check_script scripts/34_bac_maxbin2.sh
check_script scripts/36_bac_dastool.sh
# Note: CONCOCT (3rd binning tool in paper) replaced by SemiBin2 in CSCCD-MetagenomeFlow

echo "--- MAG Quality & Taxonomy ---"
check_script scripts/37_bac_checkm2.sh
check_script scripts/38_bac_drep.sh
check_script scripts/40_bac_gtdbtk.sh

echo "--- Functional Annotation ---"
check_script scripts/22_bac_kegg.sh
check_script scripts/25_bac_dbcan.sh
check_script scripts/26_bac_vfdb.sh
check_script scripts/23_bac_amrfinder.sh

echo "--- Virome (paper uses geNomad+DeepVirFinder+VIBRANT) ---"
check_script scripts/52_vir_genomad.sh
check_script scripts/54_vir_checkv_contig.sh

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""
echo "=== Known Parameter Deviations (informational) ==="
echo "  fastp --length_required: Paper=51bp; CSCCD-MetagenomeFlow default=15bp"
echo "  dRep ANI: Paper=99%; CSCCD-MetagenomeFlow=97%"
echo "  Assembly: Paper uses metaSPAdes for PE; CSCCD-MetagenomeFlow uses MEGAHIT only"
echo "  Binning: Paper uses CONCOCT; CSCCD-MetagenomeFlow uses SemiBin2"
echo "  Virome: Paper uses VIBRANT; CSCCD-MetagenomeFlow uses VirSorter2"

[ ${FAIL} -eq 0 ] && exit 0 || exit 1
