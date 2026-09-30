#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_96_stat_ml_input_governance.sh
# Purpose: Regression test for the B3-PREQ①-R input-governance change order in
#          96_stat_ml_siamcat.sh (wc1r_script96_input_governance.md):
#            #1 virus input = 98c votu_annotation_matrix_relab.tsv RELAB cols
#            #2 per-block relative-abundance prefilter (FUN| not crushed)
#            #3 BAC| k__Bacteria s__-level domain filter
#            #4 --combination B|V|F|BV|BF|VF|BVF shared-sample intersection
#            #5 repeats>1 degenerate disclosure
#
#          Supervisor P1-2: fixtures use REAL producer formats, not invented
#          ones - B block = MetaPhlAn merged taxonomy layout (header,
#          "#metaphlan4" comment line, UNCLASSIFIED, multi-rank k__Bacteria
#          rows, k__Eukaryota/k__Archaea lineages), V block = 98c
#          votu_annotation_matrix_relab.tsv layout (vOTU_name +
#          vOTU_TPM_<sample> + vOTU_RELAB_<sample> + 10 annotation columns,
#          several numeric), F block = 98d funomic_species_relab.tsv layout
#          (species + sample relab columns). 12 shared cohort samples across
#          all three blocks; EXTRA1 exists only in the V/F tables (not in
#          metadata, not in B) to exercise the unmatched-column WARN and the
#          combination sample intersection.
# Usage:   bash scripts/tests/level2/test_96_stat_ml_input_governance.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="$(mktemp -d /tmp/test_96_input_governance.XXXXXX)"
PROJ="${FIXTURE}/Project"

cleanup() {
    rm -rf "${FIXTURE}"
}
trap cleanup EXIT

S12="H1 H2 H3 H4 H5 H6 D1 D2 D3 D4 D5 D6"
SV="H1 H2 H3 H4 H5 H6 D1 D2 D3 D4 D5 D6 EXTRA1"

fail() {
    echo "[FAIL] $1"
    exit 1
}

# ------------------------------------------------------------------------------
# Fixture block 1: metadata (12 samples, 6 control / 6 case)
# ------------------------------------------------------------------------------
build_metadata() {
    local dir="$1"
    {
        echo "sample_id,group"
        for i in 1 2 3 4 5 6; do echo "H${i},control"; done
        for i in 1 2 3 4 5 6; do echo "D${i},case"; done
    } > "${dir}/metadata.csv"
}

# ------------------------------------------------------------------------------
# Fixture block 2 (B): MetaPhlAn merged taxonomy REAL format.
#   line 1 header (ID + samples), line 2 "#metaphlan4" comment, UNCLASSIFIED
#   row, k__Bacteria kingdom + 2 phylum higher-rank rows, 24 full-chain
#   species rows (i=1..8 class-shifted markers, 9..24 noise), then
#   non-bacteria domain lineages: 4 k__Eukaryota rows (1 higher-rank + 3
#   species) and 3 k__Archaea rows (1 higher-rank + 2 species).
#   => domain filter expectation: kept_s_species=24, dropped_domain=7,
#      dropped_unranked=1 (UNCLASSIFIED), dropped_higher_rank=3.
# ------------------------------------------------------------------------------
build_bac_taxonomy() {
    local dir="$1"
    mkdir -p "${dir}/result/metaphlan4/merged"
    awk -v s12="${S12}" 'BEGIN{
        ns = split(s12, S, " ")
        printf "ID"; for (j = 1; j <= ns; j++) printf "\t%s", S[j]; print ""
        print "#metaphlan4"
        printf "UNCLASSIFIED"
        for (j = 1; j <= ns; j++) printf "\t%.6f", 20 + (j * 7) % 5; print ""
        printf "k__Bacteria"
        for (j = 1; j <= ns; j++) printf "\t%.6f", 74 + (j * 3) % 6; print ""
        printf "k__Bacteria|p__Firmicutes"
        for (j = 1; j <= ns; j++) printf "\t%.6f", 52 + (j * 5) % 9; print ""
        printf "k__Bacteria|p__Bacteroidetes"
        for (j = 1; j <= ns; j++) printf "\t%.6f", 18 + (j * 11) % 7; print ""
        for (i = 1; i <= 24; i++) {
            printf "k__Bacteria|p__P|c__C|o__O|f__F|g__G%d|s__species%d", i, i
            for (j = 1; j <= ns; j++) {
                if (i <= 8) {
                    if (j <= 6) v = 10 + (i * 3 + j * 5) % 7
                    else        v = 40 + (i * 7 + j * 3) % 11
                } else {
                    v = 5 + (i * 11 + j * 7) % 13
                }
                printf "\t%.6f", v
            }
            print ""
        }
        printf "k__Eukaryota"
        for (j = 1; j <= ns; j++) printf "\t%.6f", 0.5 + (j % 3) * 0.1; print ""
        euks[1] = "k__Eukaryota|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|f__Saccharomycetaceae|g__Candida|s__Candida_albicans"
        euks[2] = "k__Eukaryota|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|f__Saccharomycetaceae|g__Aspergillus|s__Aspergillus_fumigatus"
        euks[3] = "k__Eukaryota|p__Basidiomycota|c__Tremellomycetes|o__Tremellales|f__Tremellaceae|g__Cryptococcus|s__Cryptococcus_neoformans"
        for (e = 1; e <= 3; e++) {
            printf "%s", euks[e]
            for (j = 1; j <= ns; j++) printf "\t%.6f", 0.2 + (e * 7 + j * 3) % 5 * 0.1
            print ""
        }
        printf "k__Archaea"
        for (j = 1; j <= ns; j++) printf "\t%.6f", 0.4 + (j % 2) * 0.1; print ""
        archs[1] = "k__Archaea|p__Euryarchaeota|c__Methanobacteria|o__Methanobacteriales|f__Methanobacteriaceae|g__Methanobrevibacter|s__Methanobrevibacter_smithii"
        archs[2] = "k__Archaea|p__Euryarchaeota|c__Methanomicrobia|o__Methanosarcinales|f__Methanosarcinaceae|g__Methanosarcina|s__Methanosarcina_barkeri"
        for (a = 1; a <= 2; a++) {
            printf "%s", archs[a]
            for (j = 1; j <= ns; j++) printf "\t%.6f", 0.1 + (a * 5 + j * 2) % 4 * 0.1
            print ""
        }
    }' > "${dir}/result/metaphlan4/merged/taxonomy.tsv"
}

# ------------------------------------------------------------------------------
# Fixture block 3 (V): 98c votu_annotation_matrix_relab.tsv REAL format.
#   vOTU_name + vOTU_TPM_<sample> x13 (12 cohort + EXTRA1) +
#   vOTU_RELAB_<sample> x13 + 10 annotation columns (vOTU_length,
#   checkv_quality, checkv_completeness, PHROG_category, BACPHLIP_lifestyle,
#   BACPHLIP_virulent_prob, host_genus, host_confidence, viral_family,
#   VOG_IDs). RELAB = TPM / per-sample column sum, mirroring 98c fmt_float
#   (4 digits). vOTUs 1..20 dense (all samples), 21..22 sparse (present in
#   H1-H3 only, prevalence 3/12 = 0.25).
# ------------------------------------------------------------------------------
build_vir_98c_relab() {
    local dir="$1"
    mkdir -p "${dir}/result/integration/virus"
    awk -v sv="${SV}" 'BEGIN{
        ns = split(sv, S, " ")
        nv = 22
        for (i = 1; i <= nv; i++) {
            votu[i] = sprintf("vOTU_k127_%03d", i)
            for (j = 1; j <= ns; j++) {
                if (i <= 20)      tpm[i, j] = 500 + (i * 137 + j * 89) % 1500
                else if (j <= 3)  tpm[i, j] = 400 + i * 11
                else              tpm[i, j] = 0
            }
        }
        for (j = 1; j <= ns; j++) {
            sc[j] = 0
            for (i = 1; i <= nv; i++) sc[j] += tpm[i, j]
        }
        printf "vOTU_name"
        for (j = 1; j <= ns; j++) printf "\tvOTU_TPM_%s", S[j]
        for (j = 1; j <= ns; j++) printf "\tvOTU_RELAB_%s", S[j]
        print "\tvOTU_length\tcheckv_quality\tcheckv_completeness\tPHROG_category\tBACPHLIP_lifestyle\tBACPHLIP_virulent_prob\thost_genus\thost_confidence\tviral_family\tVOG_IDs"
        for (i = 1; i <= nv; i++) {
            printf "%s", votu[i]
            for (j = 1; j <= ns; j++) printf "\t%.4f", tpm[i, j]
            for (j = 1; j <= ns; j++) printf "\t%.4f", (sc[j] > 0 ? tpm[i, j] / sc[j] : 0)
            printf "\t%d\tComplete\t%.2f\tconnector\tTemperate\t%.4f\tStreptococcus\t%.2f\tSiphoviridae\tVOG%06di\n",
                   42000 + i * 13, 82.5 + i % 5, 0.27 + i % 7 * 0.01, 0.78 + i % 4 * 0.01, i
        }
    }' > "${dir}/result/integration/virus/votu_annotation_matrix_relab.tsv"
}

# ------------------------------------------------------------------------------
# Fixture block 4 (F): 98d funomic_species_relab.tsv REAL format.
#   species column ("g__<genus>.s__<species>", space inside names) + sample
#   relab columns (12 cohort + EXTRA1), per-sample column sums ~0.6.
# ------------------------------------------------------------------------------
build_fun_98d_funomic() {
    local dir="$1"
    mkdir -p "${dir}/result/integration/fungi/normalized"
    awk -v sv="${SV}" 'BEGIN{
        ns = split(sv, S, " ")
        nf = 15
        printf "species"
        for (j = 1; j <= ns; j++) printf "\t%s", S[j]
        print ""
        for (i = 1; i <= nf; i++) {
            printf "g__Fungus%d.s__Fungus species%d", i, i
            for (j = 1; j <= ns; j++) {
                v = 20 + (i * 29 + j * 13) % 40
                printf "\t%.5f", v / 1000
            }
            print ""
        }
    }' > "${dir}/result/integration/fungi/normalized/funomic_species_relab.tsv"
}

# ==============================================================================
# Section A (#1): virus input source = 98c, old 60-path retired
# ==============================================================================

echo "[INFO] Building real-format fixture (B MetaPhlAn / V 98c relab / F 98d funomic)..."
mkdir -p "${PROJ}"
build_metadata "${PROJ}"
build_bac_taxonomy "${PROJ}"
build_vir_98c_relab "${PROJ}"
build_fun_98d_funomic "${PROJ}"

echo "[INFO] A1: asserting zero residue of the old script-60 virus table path..."
if grep -n "result/virus/votu/votu_table.tsv" "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh"; then
    fail "96_stat_ml_siamcat.sh still references the retired 60-path result/virus/votu/votu_table.tsv"
fi
echo "[OK] A1: no reference to result/virus/votu/votu_table.tsv in 96_stat_ml_siamcat.sh"

echo "[INFO] A2: missing 98c table fails fast and names 98c..."
MISSING_DIR="${FIXTURE}/Missing98c"
mkdir -p "${MISSING_DIR}"
build_metadata "${MISSING_DIR}"
set +e
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${MISSING_DIR}" -r "${REPO_ROOT}" -t 2 \
    -m "${MISSING_DIR}/metadata.csv" -g group -d virus --force --skip-shap \
    > "${FIXTURE}/missing98c.out" 2>&1
RC=$?
set -e
[ "${RC}" -ne 0 ] || fail "missing 98c table did not fail (rc=0)"
grep -q "98c_vir_integration_tables.sh" "${FIXTURE}/missing98c.out" \
    || fail "missing-98c error does not name scripts/98c_vir_integration_tables.sh"
grep -q "votu_annotation_matrix_relab.tsv" "${FIXTURE}/missing98c.out" \
    || fail "missing-98c error does not name the expected 98c table"
echo "[OK] A2: -d virus without 98c output fails fast naming 98c (rc=${RC})"

echo "[INFO] A3: -d virus end-to-end on the 98c real-format table..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group -d virus --force --skip-shap

VIR_ML="${PROJ}/result/stat/virus/ml"
[ -s "${VIR_ML}/siamcat_done.txt" ] || fail "virus run sentinel missing"
N_SAMPLES="$(sed -n 's/^n_samples=//p' "${VIR_ML}/split_manifest.txt")"
[ "${N_SAMPLES}" = "12" ] \
    || fail "virus run analyzed ${N_SAMPLES} samples, expected 12 (EXTRA1 and annotation columns must not leak in as samples)"
if grep -q "EXTRA1\|vOTU_length\|checkv_completeness" "${VIR_ML}/siamcat_repeats_detail.tsv" \
        "${VIR_ML}/siamcat_metrics.tsv" 2>/dev/null; then
    fail "annotation column or EXTRA1 leaked into the virus feature/sample space"
fi
grep -q "VIR block: 1 sample column(s) not present in metadata" "${PROJ}/logs/stat/ml/96_stat_ml_siamcat.log" \
    || fail "expected WARN for EXTRA1 (V table sample not in metadata) in the run log"
echo "[OK] A3: -d virus: 12/12 metadata samples analyzed, EXTRA1 WARNed, no annotation-column leak"

echo "[PASS] 96 input governance section A (#1 virus source = 98c)"
