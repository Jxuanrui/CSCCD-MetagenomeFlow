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
#          WC1R2 P0-1: virus input switched to the vOTU_TPM_ columns (full
#          precision; in-block relab conversion is mathematically the 98c
#          RELAB formula without the %.4f loss); six-decimal precision probe
#          in the V fixture proves the retired vOTU_RELAB_ path zeroed it.
#
#          WC1R2 P0-3: sample-set normalization - sample names sorted before
#          use (split order independent of table column order); explicit
#          --combination defaults to --sample-set BVF (the seven protocol
#          runs share the B-V-F three-table intersection); -d fungi / any
#          --combination containing F pins the 98d funomic table (-M only
#          works when explicitly passed, then warns non-protocol).
#
#          WC1R2 P0-4 + P1: P01 domain-filter counts are a STATIC DERIVATION
#          (kept 786 s__-terminal / higher_rank 1582 incl t__ 839 / domain
#          23 - the superseded 1625/743 came from an unanchored "|s__"
#          match counting t__ rows as species); fixture adds a t__ strain
#          row asserting the terminal anchor; F/BF/VF run standalone (all
#          seven groups); FUN| asserted at the exact constructed count 15;
#          the degenerate disclosure also persists in
#          siamcat_disclosure.txt (Q3), regenerated every ML run.
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
#          combination sample intersection; BONLY1 exists only in B (and in
#          metadata, control) - the BVF protocol pool must exclude it while
#          single-block auto mode keeps it; the V table columns are written
#          in a deliberately scrambled order (different from B's order and
#          from the sorted sequence) to prove the sort() normalization.
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

# B table carries the 12 cohort samples + BONLY1 (P0-3: the B-only sample)
SB="H1 H2 H3 H4 H5 H6 D1 D2 D3 D4 D5 D6 BONLY1"
# V/F tables carry the 12 cohort samples + EXTRA1 (no metadata row). The V
# column order is scrambled on purpose (P0-3: sort() must normalize it).
SV="H3 D6 H1 D4 H5 D2 H6 D1 H2 D5 D3 H4 EXTRA1"
# canonical sorted 12-sample intersection (B-V-F pool and B/V pool alike)
EXP12="D1,D2,D3,D4,D5,D6,H1,H2,H3,H4,H5,H6"

fail() {
    echo "[FAIL] $1"
    exit 1
}

# ------------------------------------------------------------------------------
# Fixture block 1: metadata (13 samples: 6 control H + BONLY1 control, 6 case D)
# ------------------------------------------------------------------------------
build_metadata() {
    local dir="$1"
    {
        echo "sample_id,group"
        for i in 1 2 3 4 5 6; do echo "H${i},control"; done
        for i in 1 2 3 4 5 6; do echo "D${i},case"; done
        echo "BONLY1,control"
    } > "${dir}/metadata.csv"
}

# ------------------------------------------------------------------------------
# Fixture block 2 (B): MetaPhlAn merged taxonomy REAL format.
#   line 1 header (ID + 13 samples = 12 cohort + BONLY1), line 2 "#metaphlan4"
#   comment, UNCLASSIFIED row, k__Bacteria kingdom + 2 phylum higher-rank
#   rows, 24 full-chain species rows (i=1..8 class-shifted markers, 9..24
#   noise), 1 t__ strain row (k__Bacteria|...|s__species1|t__SGB00001 - s__
#   mid-chain, NOT species-terminal; WC1R2 P0-4), then non-bacteria domain
#   lineages: 4 k__Eukaryota rows (1 higher-rank + 3 species) and 3
#   k__Archaea rows (1 higher-rank + 2 species).
#   => domain filter expectation: kept_s_species=24, dropped_domain=7,
#      dropped_unranked=1 (UNCLASSIFIED), dropped_higher_rank=4
#      (kingdom + 2 phyla + 1 t__ strain row).
# ------------------------------------------------------------------------------
build_bac_taxonomy() {
    local dir="$1"
    mkdir -p "${dir}/result/metaphlan4/merged"
    awk -v s12="${SB}" 'BEGIN{
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
        # WC1R2 P0-4: t__ strain row - carries s__ mid-chain, so the
        # species-terminal regex \|s__[^|]*$ must NOT keep it (an unanchored
        # "|s__" containment match would; that is exactly the miscount that
        # produced the superseded "P01 kept 1625" figure: 786 s__-terminal
        # + 839 t__-terminated rows). Class-shifted values so a leak would
        # also survive the prefilter and shift the kept count.
        printf "k__Bacteria|p__P|c__C|o__O|f__F|g__G1|s__species1|t__SGB00001"
        for (j = 1; j <= ns; j++) {
            if (j <= 6) v = 11 + (j * 3) % 7
            else        v = 41 + (j * 3) % 11
            printf "\t%.6f", v
        }
        print ""
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
#   VOG_IDs). RELAB = TPM / per-sample column sum, rendered like 98c fmt_float
#   (%.4f). vOTUs 1..20 dense (all samples), 21..22 sparse (H1-H3 only,
#   prevalence 3/12 = 0.25), vOTU 23 = six-decimal precision probe (TPM 0.15
#   in every sample vs a ~25k column sum -> true relab ~6.0e-6, i.e. sixth
#   decimal). WC1R2 P0-1 arithmetic: %.4f(6.0e-6) = "0.0000" in EVERY RELAB
#   cell of vOTU 23 (rounding floor 0.00005), so the retired vOTU_RELAB_
#   read path dropped the row at load (rowSums == 0) - the same static
#   zeroing that hits 28,349/42,137 vOTUs in P01. The vOTU_TPM_ path keeps
#   the nonzero row through load + relab conversion (n_features = 23); the
#   1e-4 prefilter then judges it at FULL precision (dropped: mean relab
#   ~6e-6 < 1e-4) instead of the 4-decimal formatter making the call.
# ------------------------------------------------------------------------------
build_vir_98c_relab() {
    local dir="$1"
    mkdir -p "${dir}/result/integration/virus"
    awk -v sv="${SV}" 'BEGIN{
        ns = split(sv, S, " ")
        nv = 23
        for (i = 1; i <= nv; i++) {
            votu[i] = sprintf("vOTU_k127_%03d", i)
            for (j = 1; j <= ns; j++) {
                if (i <= 20)      tpm[i, j] = 500 + (i * 137 + j * 89) % 1500
                else if (j <= 3)  tpm[i, j] = 400 + i * 11
                else              tpm[i, j] = 0
            }
        }
        # six-decimal precision probe: sub-integer TPM survives %.4f, its
        # relab (~6e-6) does not
        for (j = 1; j <= ns; j++) tpm[23, j] = 0.15
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

echo "[INFO] A4: vOTU_RELAB_ read path retired from code..."
if grep -q 'read_vir_relab_matrix' "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh"; then
    fail "96_stat_ml_siamcat.sh still defines/calls read_vir_relab_matrix"
fi
if grep -q 'grep("^vOTU_RELAB_"' "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh"; then
    fail "96_stat_ml_siamcat.sh still selects columns by the ^vOTU_RELAB_ regex"
fi
grep -q 'grep("^vOTU_TPM_", names(raw), value = TRUE)' "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    || fail "96_stat_ml_siamcat.sh no longer selects columns by the ^vOTU_TPM_ prefix"
grep -q 'read_vir_tpm_matrix' "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    || fail "96_stat_ml_siamcat.sh lacks read_vir_tpm_matrix"
echo "[OK] A4: column selection is ^vOTU_TPM_ (read_vir_tpm_matrix); ^vOTU_RELAB_ read path fully retired"

echo "[INFO] A5: TPM-column precision probe - the six-decimal vOTU survives the load..."
# vOTU_k127_023: TPM 0.15 per sample vs ~25k column sum -> true relab ~6.0e-6.
# 98c-style %.4f renders every vOTU_RELAB_ cell "0.0000" (floor 0.00005), so
# the retired RELAB path dropped the row at load (rowSums == 0); the TPM path
# keeps it nonzero through load + in-block relab conversion -> n_features 23.
VIR_NFEAT="$(sed -n 's/^relab_convert_VIR	OK	n_features=\([0-9]*\) .*/\1/p' "${VIR_ML}/siamcat_status.tsv")"
[ "${VIR_NFEAT}" = "23" ] \
    || fail "relab_convert_VIR n_features=${VIR_NFEAT}, expected 23 (the six-decimal vOTU must survive the TPM load; the old RELAB path read 22 - row all-zero at %.4f)"
VIR_PRE="$(sed -n 's/^prefilter_VIR	OK	features_after=\([0-9]*\)\/\([0-9]*\).*/\1 \2/p' "${VIR_ML}/siamcat_status.tsv")"
[ "${VIR_PRE}" = "22 23" ] \
    || fail "prefilter_VIR features_after=${VIR_PRE}, expected '22 23' (probe loaded nonzero, then judged at full TPM precision: mean relab ~6e-6 < 1e-4)"
echo "[OK] A5: TPM load keeps the six-decimal vOTU (n_features=23); prefilter drops it at full TPM precision (22/23), not at the %.4f rounding floor"

# ==============================================================================
# Section B (#2): per-block relative-abundance prefilter (FUN| must survive)
# ==============================================================================

echo "[INFO] B1: -d all end-to-end on the three real-format blocks..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group -d all --force --skip-shap

ALL_ML="${PROJ}/result/stat/ml"
[ -s "${ALL_ML}/siamcat_done.txt" ] || fail "-d all run sentinel missing"
[ -s "${ALL_ML}/siamcat_status.tsv" ] || fail "-d all run status table missing"

echo "[INFO] B2: asserting per-block relab conversion + FUN| survival in siamcat_status.tsv..."
for blk in BAC VIR FUN; do
    grep -q "^relab_convert_${blk}	OK	" "${ALL_ML}/siamcat_status.tsv" \
        || fail "status.tsv lacks relab_convert_${blk} OK row (per-block conversion)"
done
FUN_SURV="$(sed -n 's/^prefilter_FUN	OK	features_after=\([0-9]*\)\/\([0-9]*\).*/\1 \2/p' "${ALL_ML}/siamcat_status.tsv")"
FUN_AFTER="$(echo "${FUN_SURV}" | cut -d' ' -f1)"
FUN_TOTAL="$(echo "${FUN_SURV}" | cut -d' ' -f2)"
[ -n "${FUN_AFTER}" ] || fail "status.tsv lacks prefilter_FUN row with features_after"
# P1: EXACT count - the fixture constructs 15 funomic species and per-block
# relab must keep every one (0 pre-fix; anything != 15 is a scale regression)
[ "${FUN_AFTER}" = "15" ] && [ "${FUN_TOTAL}" = "15" ] \
    || fail "FUN| block survived ${FUN_AFTER}/${FUN_TOTAL} features, expected exactly 15/15 (fixture constructs 15; per-block relab must keep them all)"
for blk in BAC VIR; do
    grep -q "^prefilter_${blk}	OK	features_after=" "${ALL_ML}/siamcat_status.tsv" \
        || fail "status.tsv lacks prefilter_${blk} surviving-count row"
done
grep -q "^relab_convert_BAC	OK	" "${ALL_ML}/siamcat_status.tsv" \
    || fail "BAC| block was not relab-converted (single-scale drift risk)"
echo "[OK] B2: per-block relab rows present; FUN| survived exactly ${FUN_AFTER}/${FUN_TOTAL} (was 0 pre-fix)"

# ==============================================================================
# Section C (#3 + P0-4): BAC| domain filter drop counts (same -d all run as B)
#   Fixture constructs 7 non-bacteria domain rows (4 k__Eukaryota + 3
#   k__Archaea), 1 UNCLASSIFIED row, 3 higher-rank bacteria rows, 1
#   t__-terminated strain row (s__ mid-chain; WC1R2 P0-4) and 24 k__Bacteria
#   s__-terminal species rows. The t__ row verifies the TERMINAL anchor of
#   the species regex: an unanchored "|s__" containment match would keep it
#   (kept would read 25) - the miscount behind the superseded P01 figure
#   "kept 1625" (= 786 s__-terminal + 839 t__ rows); corrected static
#   derivation: kept 786 / higher_rank 1582 (incl t__ 839) / domain 23,
#   all "static derivation" wording, never "measured".
# ==============================================================================
DD_ROW="$(sed -n 's/^bac_domain_filter	OK	kept_s_species=\([0-9]*\) dropped_domain=\([0-9]*\) dropped_unranked=\([0-9]*\) dropped_higher_rank=\([0-9]*\)$/\1 \2 \3 \4/p' "${ALL_ML}/siamcat_status.tsv")"
[ -n "${DD_ROW}" ] || fail "status.tsv lacks bac_domain_filter counts row"
set -- ${DD_ROW}
DD_KEPT="$1"; DD_DOM="$2"; DD_UNR="$3"; DD_RANK="$4"
[ "${DD_KEPT}" = "24" ] || fail "domain filter kept ${DD_KEPT} s__ rows, expected 24"
[ "${DD_DOM}" = "7" ] || fail "domain filter dropped_domain=${DD_DOM}, expected 7 (4 Eukaryota + 3 Archaea rows constructed)"
[ "${DD_UNR}" = "1" ] || fail "domain filter dropped_unranked=${DD_UNR}, expected 1 (UNCLASSIFIED)"
[ "${DD_RANK}" = "4" ] || fail "domain filter dropped_higher_rank=${DD_RANK}, expected 4 (k__Bacteria + 2 phyla + the t__ strain row)"
grep -q "BAC| domain filter: kept 24 k__Bacteria s__-terminal row(s) (t__-terminated strain rows count as higher rank); dropped 7 non-bacteria-domain" \
    "${PROJ}/logs/stat/ml/96_stat_ml_siamcat.log" \
    || fail "domain filter counts (s__-terminal wording) missing from the run log"
echo "[OK] C1: domain filter counts kept=24 dropped_domain=7 dropped_unranked=1 dropped_higher_rank=4 (t__ strain row dropped via the terminal anchor; matches constructed fixture)"

# ==============================================================================
# Section D (#4 + P0-3): --combination block selection + shared sample
#   intersection. EXP12 is the canonical SORTED sequence: the B table column
#   order is H1..H6,D1..D6,BONLY1 and the V table order is scrambled, so a
#   byte-identical combo_samples line across the BVF and BV runs proves the
#   sort() normalization (neither table's order leaks into the manifest).
# ==============================================================================

echo "[INFO] D1: the -d all run (section B) derived combination=BVF in its manifest..."
[ "$(sed -n 's/^combination=//p' "${ALL_ML}/split_manifest.txt")" = "BVF" ] \
    || fail "-d all did not record combination=BVF in split_manifest.txt"
[ "$(sed -n 's/^sample_set=//p' "${ALL_ML}/split_manifest.txt")" = "auto" ] \
    || fail "-d all (no explicit --combination) did not default to sample_set=auto"
[ "$(sed -n 's/^combo_n_samples=//p' "${ALL_ML}/split_manifest.txt")" = "12" ] \
    || fail "-d all combo_n_samples != 12"

echo "[INFO] D2: explicit --combination BVF run (defaults to sample_set=BVF; same output dir as -d all)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination BVF --force --skip-shap
BVF_MANIFEST="${ALL_ML}/split_manifest.txt"
[ -s "${ALL_ML}/siamcat_done.txt" ] || fail "--combination BVF run sentinel missing"
[ "$(sed -n 's/^combination=//p' "${BVF_MANIFEST}")" = "BVF" ] || fail "BVF manifest combination != BVF"
[ "$(sed -n 's/^sample_set=//p' "${BVF_MANIFEST}")" = "BVF" ] \
    || fail "explicit --combination BVF did not default to sample_set=BVF"
[ "$(sed -n 's/^combo_samples=//p' "${BVF_MANIFEST}")" = "${EXP12}" ] \
    || fail "BVF combo_samples != sorted 12-sample intersection (EXTRA1 and BONLY1 must be excluded)"
[ "$(sed -n 's/^n_samples=//p' "${BVF_MANIFEST}")" = "12" ] || fail "BVF n_samples != 12"
echo "[OK] D2: --combination BVF: sample_set=BVF default, sorted 12-sample intersection, EXTRA1+BONLY1 excluded"

echo "[INFO] D3: --combination BV run (own output dir, FUN| block absent)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination BV --force --skip-shap
BV_ML="${PROJ}/result/stat/ml_BV"
[ -s "${BV_ML}/siamcat_done.txt" ] || fail "--combination BV sentinel missing under result/stat/ml_BV/"
BV_MANIFEST="${BV_ML}/split_manifest.txt"
[ "$(sed -n 's/^combination=//p' "${BV_MANIFEST}")" = "BV" ] || fail "BV manifest combination != BV"
[ "$(sed -n 's/^sample_set=//p' "${BV_MANIFEST}")" = "BVF" ] \
    || fail "explicit --combination BV did not default to sample_set=BVF (protocol: same pool as BVF)"
[ "$(sed -n 's/^combo_samples=//p' "${BV_MANIFEST}")" = "${EXP12}" ] \
    || fail "BV combo_samples != the same sorted intersection as the BVF run (B/V column orders differ; sort must normalize)"
[ "$(sed -n 's/^n_samples=//p' "${BV_MANIFEST}")" = "12" ] || fail "BV n_samples != 12"
grep -q "^prefilter_BAC	" "${BV_ML}/siamcat_status.tsv" || fail "BV status lacks prefilter_BAC"
grep -q "^prefilter_VIR	" "${BV_ML}/siamcat_status.tsv" || fail "BV status lacks prefilter_VIR"
if grep -q "^prefilter_FUN	" "${BV_ML}/siamcat_status.tsv"; then
    fail "BV status contains prefilter_FUN - the FUN block must NOT be loaded for --combination BV"
fi
echo "[OK] D3: --combination BV: sample_set=BVF, byte-identical sorted combo_samples to the BVF run, FUN| block absent, own dir result/stat/ml_BV/"

echo "[INFO] D4: invalid combination rejected; --combination takes precedence over -d..."
set +e
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination X --force --skip-shap \
    > "${FIXTURE}/badcombo.out" 2>&1
RC_BAD=$?
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${MISSING_DIR}" -r "${REPO_ROOT}" -t 2 \
    -m "${MISSING_DIR}/metadata.csv" -g group -d bacteria --combination V --force --skip-shap \
    > "${FIXTURE}/precedence.out" 2>&1
RC_PREC=$?
set -e
[ "${RC_BAD}" -ne 0 ] || fail "--combination X was accepted (rc=0)"
grep -q "Invalid --combination: X" "${FIXTURE}/badcombo.out" || fail "missing Invalid --combination error text"
[ "${RC_PREC}" -ne 0 ] || fail "-d bacteria --combination V unexpectedly succeeded"
grep -q "98c_vir_integration_tables.sh" "${FIXTURE}/precedence.out" \
    || fail "--combination V did not take precedence over -d bacteria (virus gate never fired)"
echo "[OK] D4: invalid combination rejected; --combination precedes -d (V gate fired with -d bacteria)"

# ==============================================================================
# Section E (#5): repeats>1 degenerate disclosure + --repeats 1 compatibility
# ==============================================================================

echo "[INFO] E1: --repeats 2 run (B block)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group -d bacteria --repeats 2 --force --skip-shap
B_ML="${PROJ}/result/stat/bacteria/ml"
[ -s "${B_ML}/siamcat_done.txt" ] || fail "--repeats 2 run sentinel missing"
[ -s "${B_ML}/siamcat_repeats_detail.tsv" ] || fail "--repeats 2 did not write siamcat_repeats_detail.tsv"
R2_HDR="$(head -1 "${B_ML}/siamcat_auc_summary.tsv")"
grep -qw "n_degenerate" <<<"${R2_HDR}" || fail "repeats>1 summary lacks n_degenerate column"
grep -qw "auc_stderr" <<<"${R2_HDR}" || fail "repeats>1 summary lacks auc_stderr column"
DET_HDR="$(head -1 "${B_ML}/siamcat_repeats_detail.tsv")"
for col in rep seed model auc degenerate; do
    grep -qw "${col}" <<<"${DET_HDR}" || fail "siamcat_repeats_detail.tsv lacks column ${col}"
done
N_DET_ROWS="$(( $(wc -l < "${B_ML}/siamcat_repeats_detail.tsv") - 1 ))"
[ "${N_DET_ROWS}" -ge 2 ] || fail "siamcat_repeats_detail.tsv has ${N_DET_ROWS} row(s), expected >=2 (2 repeats x >=1 model)"
grep -q "^repeats=2$" "${B_ML}/split_manifest.txt" || fail "split_manifest lacks repeats=2"
grep -q "^seed_rep1=" "${B_ML}/split_manifest.txt" || fail "split_manifest lacks seed_rep1"
grep -q "^seed_rep2=" "${B_ML}/split_manifest.txt" || fail "split_manifest lacks seed_rep2"
grep -qE "INCLUDE degenerate repeats|n_degenerate=0 for every model" "${B_ML}/siamcat_done.txt" \
    || fail "siamcat_done.txt lacks the repeats>1 degenerate-disclosure note line"
# WC1R2 Q3: the disclosure also persists in its own file (regenerated every
# ML run; independent of the sentinel that 96_ml_visualization.R overwrites)
[ -s "${B_ML}/siamcat_disclosure.txt" ] \
    || fail "--repeats 2 run did not write siamcat_disclosure.txt"
grep -q "regenerated by every ML run" "${B_ML}/siamcat_disclosure.txt" \
    || fail "siamcat_disclosure.txt lacks the persistence header"
grep -qE "^NOTE: |^none: " "${B_ML}/siamcat_disclosure.txt" \
    || fail "siamcat_disclosure.txt lacks a NOTE/none disclosure line"
echo "[OK] E1: repeats>1 summary has n_degenerate + auc_stderr; detail rows=${N_DET_ROWS}; disclosure note present (sentinel + persistent siamcat_disclosure.txt)"

echo "[INFO] E2: --repeats 1 stays compatible with the pre-change single-pass format..."
# --force only bypasses the sentinel; clear the repeats=2 artifacts first so
# the assertion checks what THIS run writes, not the previous run's leftovers.
rm -f "${B_ML}/siamcat_repeats_detail.tsv"
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group -d bacteria --repeats 1 --force --skip-shap
R1_HDR="$(head -1 "${B_ML}/siamcat_auc_summary.tsv")"
[ "${R1_HDR}" = "model	auc	degenerate	aligned_by" ] \
    || fail "--repeats 1 summary header changed: ${R1_HDR}"
[ ! -f "${B_ML}/siamcat_repeats_detail.tsv" ] \
    || fail "--repeats 1 unexpectedly wrote siamcat_repeats_detail.tsv"
if grep -q "^repeats=" "${B_ML}/split_manifest.txt"; then
    fail "--repeats 1 split_manifest unexpectedly carries a repeats= line"
fi
grep -q "^combination=B$" "${B_ML}/split_manifest.txt" \
    || fail "-d bacteria manifest lacks combination=B"
# P0-3 assertion (a), auto half: single-block auto mode keeps the B-only
# sample (13 = 12 cohort + BONLY1); the BVF protocol pool excludes it (F1)
N_AUTO="$(sed -n 's/^n_samples=//p' "${B_ML}/split_manifest.txt")"
[ "${N_AUTO}" = "13" ] \
    || fail "sample_set=auto single-block B analyzed ${N_AUTO} samples, expected 13 (BONLY1 is in B and in metadata - auto keeps it)"
# WC1R2 Q3: the repeats=1 rerun regenerated the persistent disclosure file
[ -s "${B_ML}/siamcat_disclosure.txt" ] \
    || fail "--repeats 1 run did not regenerate siamcat_disclosure.txt"
grep -qE "^NOTE: |^none: " "${B_ML}/siamcat_disclosure.txt" \
    || fail "regenerated siamcat_disclosure.txt lacks a NOTE/none line"
echo "[OK] E2: --repeats 1 byte-compatible single-run summary, no repeats artifacts; auto single-block n_samples=13 (BONLY1 kept); disclosure file regenerated"

# ==============================================================================
# Section F (P0-3): sample-set normalization (sort + BVF protocol pool +
# pinned 98d fungi source). Fixture premises: BONLY1 sits in B+metadata only
# (assertion (a)); B column order = H1..H6,D1..D6,BONLY1, V column order
# scrambled (assertion (b) via byte-identical sorted combo_samples).
# ==============================================================================

echo "[INFO] F1: --combination B (explicit) defaults to sample_set=BVF, excludes the B-only sample..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination B --force --skip-shap
B_MANIFEST="${B_ML}/split_manifest.txt"
[ -s "${B_ML}/siamcat_done.txt" ] || fail "--combination B sentinel missing"
[ "$(sed -n 's/^combination=//p' "${B_MANIFEST}")" = "B" ] || fail "--combination B manifest combination != B"
[ "$(sed -n 's/^sample_set=//p' "${B_MANIFEST}")" = "BVF" ] \
    || fail "explicit --combination B did not default to sample_set=BVF"
[ "$(sed -n 's/^combo_n_samples=//p' "${B_MANIFEST}")" = "12" ] \
    || fail "--combination B (BVF pool) combo_n_samples != 12"
[ "$(sed -n 's/^combo_samples=//p' "${B_MANIFEST}")" = "${EXP12}" ] \
    || fail "--combination B (BVF pool) combo_samples != sorted 12-sample B-V-F intersection (BONLY1 must be excluded: absent from V/F)"
[ "$(sed -n 's/^n_samples=//p' "${B_MANIFEST}")" = "12" ] \
    || fail "--combination B (BVF pool) n_samples != 12 (BONLY1 excluded; contrast with auto=13 in E2)"
grep -q "sample_set=BVF" "${PROJ}/logs/stat/ml/96_stat_ml_siamcat.log" \
    || fail "run log lacks the sample_set=BVF contract line"
grep -q "shared sample pool n=12" "${PROJ}/logs/stat/ml/96_stat_ml_siamcat.log" \
    || fail "run log lacks the BVF pool intersection size"
grep -q "protocol-pinned 98d" "${PROJ}/logs/stat/ml/96_stat_ml_siamcat.log" \
    || fail "run log lacks the protocol-pinned 98d fungi input line"
if grep -q "^prefilter_VIR	\|^prefilter_FUN	" "${B_ML}/siamcat_status.tsv"; then
    fail "--combination B status carries VIR/FUN prefilter rows (pool reads must not load feature blocks)"
fi
echo "[OK] F1: --combination B: sample_set=BVF default, 12-sample pool (BONLY1 excluded vs auto's 13), VIR/FUN not feature-loaded"

echo "[INFO] F2: cheap negatives - invalid --sample-set, BVF pool gates, <10 intersection, -M override..."
NEG_BVF="${FIXTURE}/NegBVF"
mkdir -p "${NEG_BVF}"
{
    echo "sample_id,group"
    for i in 1 2 3 4 5 6; do echo "H${i},control"; done
    for i in 1 2 3 4 5 6; do echo "D${i},case"; done
    for i in 1 2 3 4; do echo "M${i},case"; done
} > "${NEG_BVF}/metadata.csv"
build_bac_taxonomy "${NEG_BVF}"
build_fun_98d_funomic "${NEG_BVF}"
# V table: only 9 canonical samples overlap B/F; M1-M4 pad the metadata
# overlap past the defensive >=10 assertion so the failure is the BVF
# INTERSECTION check itself (pools: B=13, V=13, F=13 -> intersection 9)
mkdir -p "${NEG_BVF}/result/integration/virus"
awk 'BEGIN{
    ns = split("H1 H2 H3 H4 H5 H6 D1 D2 D3 M1 M2 M3 M4", S, " ")
    nv = 22
    printf "vOTU_name"
    for (j = 1; j <= ns; j++) printf "\tvOTU_TPM_%s", S[j]
    for (j = 1; j <= ns; j++) printf "\tvOTU_RELAB_%s", S[j]
    print "\tvOTU_length\tcheckv_quality\tcheckv_completeness\tPHROG_category\tBACPHLIP_lifestyle\tBACPHLIP_virulent_prob\thost_genus\thost_confidence\tviral_family\tVOG_IDs"
    for (i = 1; i <= nv; i++) {
        printf "vOTU_k127_%03d", i
        for (j = 1; j <= ns; j++) printf "\t%.4f", 500 + (i * 137 + j * 89) % 1500
        for (j = 1; j <= ns; j++) printf "\t%.4f", 0.001
        printf "\t%d\tComplete\t%.2f\tconnector\tTemperate\t%.4f\tStreptococcus\t%.2f\tSiphoviridae\tVOG%06di\n", 42000 + i * 13, 82.5, 0.27, 0.78, i
    }
}' > "${NEG_BVF}/result/integration/virus/votu_annotation_matrix_relab.tsv"
set +e
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --sample-set X --force --skip-shap \
    > "${FIXTURE}/badset.out" 2>&1
RC_SET=$?
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${MISSING_DIR}" -r "${REPO_ROOT}" -t 2 \
    -m "${MISSING_DIR}/metadata.csv" -g group -d bacteria --sample-set BVF --force --skip-shap \
    > "${FIXTURE}/bvf98c.out" 2>&1
RC_BVF98C=$?
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${NEG_BVF}" -r "${REPO_ROOT}" -t 2 \
    -m "${NEG_BVF}/metadata.csv" -g group --combination B --sample-set BVF --force --skip-shap \
    > "${FIXTURE}/negbvf.out" 2>&1
RC_NEG=$?
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group -d fungi -M phf --force --skip-shap \
    > "${FIXTURE}/mphf.out" 2>&1
RC_MPHF=$?
set -e
[ "${RC_SET}" -ne 0 ] || fail "invalid --sample-set X was accepted (rc=0)"
grep -q "Invalid --sample-set: X" "${FIXTURE}/badset.out" || fail "missing Invalid --sample-set error text"
[ "${RC_BVF98C}" -ne 0 ] || fail "--sample-set BVF without 98c table unexpectedly succeeded"
grep -q "98c_vir_integration_tables.sh" "${FIXTURE}/bvf98c.out" \
    || fail "BVF pool gate did not name 98c (V table required for the pool even with -d bacteria)"
[ "${RC_NEG}" -ne 0 ] || fail "BVF intersection <10 unexpectedly succeeded"
grep -q "sample_set=BVF combination B: input-table sample intersection = 9" "${FIXTURE}/negbvf.out" \
    || fail "negative BVF run lacks the intersection=9 error"
grep -q "Per-table sample counts: B=13, V=13, F=13" "${FIXTURE}/negbvf.out" \
    || fail "negative BVF run lacks the per-table sample counts"
[ "${RC_MPHF}" -ne 0 ] || fail "-d fungi -M phf (no PHF table) unexpectedly succeeded"
grep -q "non-protocol fungi source" "${FIXTURE}/mphf.out" \
    || fail "-M phf run lacks the non-protocol WARN"
grep -q "PHF fungi abundance table not found" "${FIXTURE}/mphf.out" \
    || fail "-M phf run lacks the PHF table-not-found error"
echo "[OK] F2: --sample-set validated; BVF pool gates name 98c; <10 intersection errors with per-table counts; -M explicit warns non-protocol"

# ==============================================================================
# Section G (P1): the remaining protocol combinations run standalone - with
#   F/BF/VF all seven groups are exercised end-to-end (B=E2/F1, V=A3,
#   BV=D3, BVF=D2). Every explicit --combination run shares the same sorted
#   12-sample BVF pool; FUN| is the pinned 98d arm everywhere (15/15).
# ==============================================================================

echo "[INFO] G1: --combination F (single-block protocol; pinned 98d source)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination F --force --skip-shap
F_ML="${PROJ}/result/stat/fungi/ml"
[ -s "${F_ML}/siamcat_done.txt" ] || fail "--combination F sentinel missing under result/stat/fungi/ml/"
F_MANIFEST="${F_ML}/split_manifest.txt"
[ "$(sed -n 's/^combination=//p' "${F_MANIFEST}")" = "F" ] || fail "F manifest combination != F"
[ "$(sed -n 's/^sample_set=//p' "${F_MANIFEST}")" = "BVF" ] \
    || fail "explicit --combination F did not default to sample_set=BVF"
[ "$(sed -n 's/^combo_samples=//p' "${F_MANIFEST}")" = "${EXP12}" ] \
    || fail "F combo_samples != the shared sorted 12-sample BVF pool"
[ "$(sed -n 's/^n_samples=//p' "${F_MANIFEST}")" = "12" ] || fail "F n_samples != 12"
F_PRE="$(sed -n 's/^prefilter_FUN	OK	features_after=\([0-9]*\)\/\([0-9]*\).*/\1 \2/p' "${F_ML}/siamcat_status.tsv")"
[ "${F_PRE}" = "15 15" ] \
    || fail "--combination F prefilter_FUN=${F_PRE}, expected '15 15' (pinned 98d funomic source)"
if grep -q "^prefilter_BAC	\|^prefilter_VIR	" "${F_ML}/siamcat_status.tsv"; then
    fail "--combination F status carries BAC/VIR prefilter rows"
fi
[ -s "${F_ML}/siamcat_disclosure.txt" ] || fail "--combination F did not write siamcat_disclosure.txt"
echo "[OK] G1: --combination F: BVF pool 12 samples, FUN| 15/15 from the pinned 98d source, own dir result/stat/fungi/ml/"

echo "[INFO] G2: --combination BF (own dir; BAC+FUN arms, VIR absent)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination BF --force --skip-shap
BF_ML="${PROJ}/result/stat/ml_BF"
[ -s "${BF_ML}/siamcat_done.txt" ] || fail "--combination BF sentinel missing under result/stat/ml_BF/"
BF_MANIFEST="${BF_ML}/split_manifest.txt"
[ "$(sed -n 's/^combination=//p' "${BF_MANIFEST}")" = "BF" ] || fail "BF manifest combination != BF"
[ "$(sed -n 's/^sample_set=//p' "${BF_MANIFEST}")" = "BVF" ] \
    || fail "explicit --combination BF did not default to sample_set=BVF"
[ "$(sed -n 's/^combo_samples=//p' "${BF_MANIFEST}")" = "${EXP12}" ] \
    || fail "BF combo_samples != the shared sorted 12-sample BVF pool"
[ "$(sed -n 's/^n_samples=//p' "${BF_MANIFEST}")" = "12" ] || fail "BF n_samples != 12"
grep -q "^prefilter_BAC	" "${BF_ML}/siamcat_status.tsv" || fail "BF status lacks prefilter_BAC"
grep -q "^prefilter_FUN	" "${BF_ML}/siamcat_status.tsv" || fail "BF status lacks prefilter_FUN"
if grep -q "^prefilter_VIR	" "${BF_ML}/siamcat_status.tsv"; then
    fail "BF status contains prefilter_VIR - the VIR block must NOT be loaded for --combination BF"
fi
echo "[OK] G2: --combination BF: BVF pool 12 samples, BAC+FUN arms present, VIR| absent, own dir result/stat/ml_BF/"

echo "[INFO] G3: --combination VF (own dir; VIR+FUN arms, BAC absent)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
    -m "${PROJ}/metadata.csv" -g group --combination VF --force --skip-shap
VF_ML="${PROJ}/result/stat/ml_VF"
[ -s "${VF_ML}/siamcat_done.txt" ] || fail "--combination VF sentinel missing under result/stat/ml_VF/"
VF_MANIFEST="${VF_ML}/split_manifest.txt"
[ "$(sed -n 's/^combination=//p' "${VF_MANIFEST}")" = "VF" ] || fail "VF manifest combination != VF"
[ "$(sed -n 's/^sample_set=//p' "${VF_MANIFEST}")" = "BVF" ] \
    || fail "explicit --combination VF did not default to sample_set=BVF"
[ "$(sed -n 's/^combo_samples=//p' "${VF_MANIFEST}")" = "${EXP12}" ] \
    || fail "VF combo_samples != the shared sorted 12-sample BVF pool"
[ "$(sed -n 's/^n_samples=//p' "${VF_MANIFEST}")" = "12" ] || fail "VF n_samples != 12"
grep -q "^prefilter_VIR	" "${VF_ML}/siamcat_status.tsv" || fail "VF status lacks prefilter_VIR"
grep -q "^prefilter_FUN	" "${VF_ML}/siamcat_status.tsv" || fail "VF status lacks prefilter_FUN"
if grep -q "^prefilter_BAC	" "${VF_ML}/siamcat_status.tsv"; then
    fail "VF status contains prefilter_BAC - the BAC block must NOT be loaded for --combination VF"
fi
echo "[OK] G3: --combination VF: BVF pool 12 samples, VIR+FUN arms present, BAC| absent, own dir result/stat/ml_VF/"

# WC1R2-C2 regression: sentinel from a different input regime must NOT be
# silently reused. Premise: E2 left a completed bacteria/ml run with
# combination=B / sample_set=auto; requesting the same dir under
# --combination B (defaults sample_set=BVF) must error.
C2_LOG="$(mktemp)"
# Restore the auto regime first (F1 rebuilt the same dir under BVF, so the
# current manifest matches --combination B; re-stamp it as auto to create
# the mismatch this regression guards against).
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
        -m "${PROJ}/metadata.csv" -g group \
        -d bacteria --repeats 1 --force --skip-shap > /dev/null 2>&1
if bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
        -m "${PROJ}/metadata.csv" -g group \
        --combination B > "${C2_LOG}" 2>&1; then
    rm -f "${C2_LOG}"
    fail "C2: regime-mismatched resume silently reused the sentinel"
fi
grep -q "different input regime" "${C2_LOG}" \
    || { rm -f "${C2_LOG}"; fail "C2: expected regime-mismatch error naming both regimes"; }
rm -f "${C2_LOG}"
echo "[OK] C2: mismatched-regime resume errors out (regime names in log)"

# C2 positive path: regime-MATCHED resume must exit 0 with regime-match log
C2OK_LOG="$(mktemp)"
if ! bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
        -m "${PROJ}/metadata.csv" -g group \
        -d bacteria --repeats 1 --skip-shap > "${C2OK_LOG}" 2>&1; then
    rm -f "${C2OK_LOG}"; fail "C2: regime-matched resume unexpectedly failed"
fi
grep -q "regime match" "${C2OK_LOG}" \
    || { rm -f "${C2OK_LOG}"; fail "C2: matched resume lacked regime-match log line"; }
rm -f "${C2OK_LOG}"
echo "[OK] C2: regime-matched resume exits 0 with regime-match log"

# fungi_method audit value must be the REAL source (funomic), not the
# env-default auto (supervisor re-review: the audit line wrote a fake value)
grep -q "^fungi_method=funomic$" "${B_ML}/split_manifest.txt" \
    || fail "manifest fungi_method is not the real source (expected funomic)"
echo "[OK] manifest fungi_method=funomic (real value, not env default)"

# -M (non-protocol) result must NOT be silently reused by a protocol resume
C2M_LOG="$(mktemp)"
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
        -m "${PROJ}/metadata.csv" -g group \
        -d bacteria --repeats 1 --force --skip-shap > /dev/null 2>&1
sed -i 's/^fungi_method=funomic$/fungi_method=phf/' "${B_ML}/split_manifest.txt"
if bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${PROJ}" -r "${REPO_ROOT}" -t 2 \
        -m "${PROJ}/metadata.csv" -g group \
        -d bacteria --repeats 1 --skip-shap > "${C2M_LOG}" 2>&1; then
    rm -f "${C2M_LOG}"; fail "C2: fungi_method-mismatched resume silently reused"
fi
grep -q "fungi_method=phf" "${C2M_LOG}" \
    || { rm -f "${C2M_LOG}"; fail "C2: expected fungi_method in mismatch error"; }
rm -f "${C2M_LOG}"
echo "[OK] C2: fungi_method mismatch (phf vs funomic) blocks resume"

# SKIPPED-path contract: 10 samples 5/class => SIAMCAT per-class refusal,
# and resuming that sentinel (no --force) exits 0 (supervisor P1).
SK_DIR="$(mktemp -d)"
mkdir -p "${SK_DIR}/result/metaphlan4/merged"
python3 - "${SK_DIR}" <<'PYSKIP'
import sys
d = sys.argv[1]
ss = ["H1","H2","H3","H4","H5","D1","D2","D3","D4","D5"]  # 10 total, 5/class -> SIAMCAT refuses
with open(f"{d}/result/metaphlan4/merged/taxonomy.tsv","w") as f:
    f.write("ID\t" + "\t".join(ss) + "\n#metaphlan4\n")
    for i in range(6):
        f.write(f"k__Bacteria|p__P{i}|c__C|o__O|f__F|g__G|s__S{i}\t" + "\t".join(str(1.0+(j%3)) for j in range(10)) + "\n")
with open(f"{d}/metadata.csv","w") as f:
    f.write("sample_id,group\n")
    for s in ss: f.write(f"{s},{'Healthy' if s.startswith('H') else 'Tumor'}\n")
PYSKIP
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${SK_DIR}" -r "${REPO_ROOT}" -t 2 \
        -m "${SK_DIR}/metadata.csv" -g group -d bacteria --skip-shap \
        > /dev/null 2>&1
SK_ML="${SK_DIR}/result/stat/bacteria/ml"
grep -q "^SKIPPED" "${SK_ML}/siamcat_done.txt" \
    || { rm -rf "${SK_DIR}"; fail "SKIPPED: sentinel not written for insufficient-per-class"; }
grep -q "^combination=B$" "${SK_ML}/split_manifest.txt" \
    || { rm -rf "${SK_DIR}"; fail "SKIPPED: minimal manifest missing combination=B"; }
grep -q "^sample_set=auto$" "${SK_ML}/split_manifest.txt" \
    || { rm -rf "${SK_DIR}"; fail "SKIPPED: manifest missing sample_set=auto"; }
grep -q "^fungi_method=funomic$" "${SK_ML}/split_manifest.txt" \
    || { rm -rf "${SK_DIR}"; fail "SKIPPED: manifest missing fungi_method=funomic"; }
if ! bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
        -w "${SK_DIR}" -r "${REPO_ROOT}" -t 2 \
        -m "${SK_DIR}/metadata.csv" -g group -d bacteria --skip-shap \
        > /dev/null 2>&1; then
    rm -rf "${SK_DIR}"; fail "SKIPPED: regime-matched SKIPPED resume did not exit 0"
fi
rm -rf "${SK_DIR}"
echo "[OK] SKIPPED: sentinel + minimal manifest; matched resume exits 0"
echo "[PASS] 96 input governance sections A-G + C2 (#1 98c TPM source, #2 per-block relab, #3 domain filter, #4 combination, #5 degenerate disclosure, P0-1 TPM precision, P0-3 sample-set, P0-4 P01 static-derivation counts + Q3 persistent disclosure + C2 regime-guarded resume)"

cleanup
