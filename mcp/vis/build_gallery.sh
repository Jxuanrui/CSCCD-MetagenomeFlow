#!/usr/bin/env bash
# ==============================================================================
# Script: mcp/vis/build_gallery.sh
# Purpose: One-command README figure gallery — fabricate the synthetic VisDemo
#          project, run every existing pipeline plotting entry, and collect the
#          resulting figures into docs/figures/.
# Usage:   bash mcp/vis/build_gallery.sh [--skip-ml] [--with-ml]
#
# ML (SIAMCAT) is slow (cross-validation); it is SKIPPED by default.  Pass
# --with-ml to include it.  Every step is individually fault-tolerant: a failed
# step is reported in the final summary and does not abort the gallery.
# ==============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${REPO}/envs/rag/bin/python3"
RSCRIPT="${REPO}/envs/r_stat/bin/Rscript"
KT_IMPORT="${REPO}/envs/metawrap/bin/ktImportText"
OUT="${REPO}/Project/VisDemo"
FIGS="${REPO}/docs/figures"
META="${OUT}/result/demo/metadata.csv"  # inside gitignored Project/*/result/

export MGX_FIGURE_FORMATS="pdf,png"
export GROUP_COL="group"

RUN_ML=0
STYLE="cns"
for arg in "$@"; do
    case "$arg" in
        --with-ml) RUN_ML=1 ;;
        --skip-ml) RUN_ML=0 ;;
        --cns) STYLE="cns" ;;
        --orbit0) STYLE="orbit0" ;;
        *) echo "[WARN] unknown flag: $arg" ;;
    esac
done

mkdir -p "${FIGS}"
declare -A STATUS

record() { # record <step> <rc> <figure>
    if [ "$2" -eq 0 ]; then STATUS[$1]="OK"; else STATUS[$1]="FAILED($2)"; fi
    LAST_FIGURE[$1]="$3"
}
declare -A LAST_FIGURE

run_step() { # run_step <name> <figure> <cmd...>
    local name="$1" fig="$2"; shift 2
    echo ""
    echo "=================================================================="
    echo "[gallery] ${name}"
    echo "=================================================================="
    "$@"
    local rc=$?
    record "${name}" "${rc}" "${fig}"
    return 0
}

# --- 0. synthetic demo project ------------------------------------------------
run_step "make_demo" "-" \
    "${PY}" "${REPO}/mcp/vis/make_demo.py" --out "${OUT}"
if [ "${STATUS[make_demo]}" != "OK" ]; then
    echo "[ERROR] demo generation failed; nothing else can run"
    exit 1
fi

# --- 1..9 pipeline plotting entries -------------------------------------------
run_step "91_diversity" "alpha_diversity.png / pcoa.png" \
    bash "${REPO}/scripts/91_stat_diversity.sh" -w "${OUT}" -r "${REPO}" -t 4 \
         -m "${META}" -g group --force

run_step "94_visualization" "composition_barplot.png / composition_heatmap.png" \
    bash "${REPO}/scripts/94_stat_visualization.sh" -w "${OUT}" -r "${REPO}" \
         -m "${META}" --force

run_step "92_differential" "volcano.png" \
    bash "${REPO}/scripts/92_stat_differential.sh" -w "${OUT}" -r "${REPO}" -t 4 \
         -m "${META}" -g group --force

run_step "93_cooccurrence_cross_bac_vir" "cross_dimension_network.png" \
    bash "${REPO}/scripts/93_stat_cooccurrence.sh" -w "${OUT}" -r "${REPO}" -t 4 \
         -m "${META}" -g group -n cross_bac_vir --force

run_step "99b_lefse" "lefse_barplot.png" \
    "${RSCRIPT}" "${REPO}/scripts/99b_lefse.R" \
         -i "${OUT}/result/metaphlan4/merged/taxonomy.tsv" \
         -m "${META}" -o "${OUT}/result/stat/bacteria/lefse" -d bacteria -y taxonomy

run_step "99a_core_microbiome" "core_microbiome.pdf" \
    "${RSCRIPT}" "${REPO}/scripts/99a_core_microbiome.R" \
         -i "${OUT}/result/metaphlan4/merged/taxonomy.tsv" \
         -m "${OUT}/result/demo/metadata_case_control.csv" \
         -o "${OUT}/result/stat/bacteria/core" -d bacteria

run_step "96b_pathway_activity" "pathway_activity.pdf" \
    "${RSCRIPT}" "${REPO}/scripts/96b_pathway_activity.R" \
         --humann3-dir "${OUT}/result/humann3" -m "${META}" \
         -o "${OUT}/result/stat/bacteria/pathway" -d bacteria

run_step "96c_functional_redundancy" "functional_redundancy.pdf" \
    "${RSCRIPT}" "${REPO}/scripts/96c_functional_redundancy.R" \
         -f "${OUT}/result/integration/bacteria/kegg_ko_abundance.tsv" \
         -t "${OUT}/result/demo/bacteria_species_abundance.tsv" \
         -o "${OUT}/result/stat/bacteria/functional_redundancy" \
         -d bacteria -y kegg_ko

run_step "96_functional_network" "functional_network.png" \
    bash "${REPO}/scripts/96_functional_network.sh" -w "${OUT}" -r "${REPO}" \
         -d bacteria --force

if [ "${RUN_ML}" -eq 1 ]; then
    run_step "96_stat_ml_siamcat" "ml_roc.pdf / ml_feature_weights.pdf" \
        bash "${REPO}/scripts/96_stat_ml_siamcat.sh" -w "${OUT}" -r "${REPO}" -t 4 \
             -m "${META}" -g group -d bacteria --force
else
    STATUS[96_stat_ml_siamcat]="SKIPPED (--with-ml to enable)"
    echo "[gallery] 96_stat_ml_siamcat SKIPPED by default (slow cross-validation)"
fi

# --- 10. krona ------------------------------------------------------------------
run_step "krona" "krona_plot.html" \
    env PATH="${REPO}/envs/metawrap/bin:${PATH}" \
    "${KT_IMPORT}" -o "${OUT}/result/demo/krona_plot.html" \
         "${OUT}/result/demo/krona_counts.tsv"

# --- 11. multiqc ----------------------------------------------------------------
run_step "multiqc" "multiqc_report.html" \
    bash "${REPO}/scripts/00_multiqc_report.sh" -p "${OUT}"

# --- 12. collect figures into docs/figures --------------------------------------
# copy_fig <gallery_name> <source_under-OUT-or-REPO>
copy_fig() {
    local dest="$1" src="$2" abs
    case "${src}" in
        /*) abs="${src}" ;;
        *)  abs="${OUT}/${src}" ;;
    esac
    if [ -s "${abs}" ]; then
        cp -f "${abs}" "${FIGS}/${dest}"
        COPIED+=("${dest}")
    else
        MISSING+=("${dest}  <-  ${src}")
    fi
}

# copy_fig_pair <name_noext> <src_noext>: collect BOTH pdf and png (the gallery
# keeps every visualization in the two formats).
copy_fig_pair() {
    copy_fig "$1.pdf" "$2.pdf"
    copy_fig "$1.png" "$2.png"
}

COPIED=(); MISSING=()
copy_fig_pair composition_barplot      result/stat/bacteria/composition/barplot_composition_by_group
copy_fig_pair composition_heatmap      result/stat/bacteria/composition/heatmap_genus
copy_fig_pair alpha_diversity          result/stat/bacteria/diversity/alpha_diversity_boxplot
copy_fig_pair pcoa                     result/stat/bacteria/diversity/pcoa_beta_scatter
copy_fig_pair volcano                  result/stat/bacteria/differential/volcano_deseq2
copy_fig_pair lefse_barplot            result/stat/bacteria/lefse/lefse_barplot
copy_fig_pair core_microbiome          result/stat/bacteria/core/core_abundance_barplot
copy_fig_pair pathway_activity         result/stat/bacteria/pathway/scatter_activity_composition
copy_fig_pair cross_dimension_network  result/stat/network/cross_bac_vir/network
copy_fig_pair functional_network       result/stat/bacteria/functional/network/figures/network_bacteria
copy_fig_pair ml_roc                   result/stat/bacteria/ml/roc_multimodel_comparison
copy_fig_pair ml_feature_weights       result/stat/bacteria/ml/feature_importance_with_sd
copy_fig_pair shap_summary             result/stat/bacteria/ml/randomForest_shap_summary
copy_fig krona_plot.html              result/demo/krona_plot.html
copy_fig multiqc_report.html          result/qc_report/multiqc_report.html
copy_fig_pair mining_attrs            "${REPO}/mining/vis/mining_attrs"
copy_fig_pair mining_overlap          "${REPO}/mining/vis/mining_overlap"

# --- summary ---------------------------------------------------------------------
echo ""
echo "==================== build_gallery summary ===================="
printf "%-28s %-12s %s\n" "STEP" "STATUS" "FIGURE"
for key in make_demo 91_diversity 94_visualization 92_differential \
           93_cooccurrence_cross_bac_vir 99b_lefse 99a_core_microbiome \
           96b_pathway_activity 96c_functional_redundancy 96_functional_network \
           96_stat_ml_siamcat krona multiqc; do
    printf "%-28s %-12s %s\n" "${key}" "${STATUS[$key]:-?}" "${LAST_FIGURE[$key]:-}"
done
echo "---------------------------------------------------------------"
echo "Gallery files written to ${FIGS}:"
for f in "${COPIED[@]:-}"; do [ -n "$f" ] && echo "  $f"; done
if [ "${#MISSING[@]}" -gt 0 ] 2>/dev/null; then
    echo "Missing gallery files (step failed or produced no such output):"
    for f in "${MISSING[@]}"; do echo "  $f"; done
fi
# --- 13. CNS-style re-render (mcp/vis/cns) ---------------------------------------
# Redraws the 18 gallery figures through the shared CNS design system
# (mcp/vis/cns/theme_cns.R), overwriting the orbit-0 outputs in docs/figures
# under the same names. Requires the orbit-0 steps above (RDS/ML objects).
if [ "${STYLE}" = "cns" ]; then
    echo "[gallery] style=cns: re-rendering figures via mcp/vis/cns"
    CNS_FIGS="composition_barplot composition_heatmap alpha_diversity pcoa volcano \
lefse_barplot core_microbiome pathway_activity \
cross_dimension_network ml_roc \
ml_feature_weights shap mining_attrs mining_overlap"
    for fig in ${CNS_FIGS}; do
        fig_workdir="${OUT}"
        case "${fig}" in mining_*) fig_workdir="${REPO}" ;; esac
        if "${RSCRIPT}" "${REPO}/mcp/vis/cns/fig_${fig}.R" "${fig_workdir}" "${FIGS}" \
            > "${FIGS}/.cns_${fig}.log" 2>&1; then
            echo "  cns OK   ${fig}"
        else
            echo "  cns FAIL ${fig} (see ${FIGS}/.cns_${fig}.log)"
            tail -3 "${FIGS}/.cns_${fig}.log" 2>/dev/null
        fi
        rm -f "${FIGS}/.cns_${fig}.log"
    done
fi

echo "Note: 99a/96b/96c figures are PNG when MGX_FIGURE_FORMATS includes png;"
echo "installed on this host, so those gallery entries are stored as PDF."
echo "krona_plot is an interactive HTML (a static PNG screenshot is not"
echo "producible headlessly); it is kept as krona_plot.html."
echo "==============================================================="
