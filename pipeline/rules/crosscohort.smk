# ==============================================================================
# Snakemake Rules: Cross-Cohort Validation
# ==============================================================================

rule crosscohort_validation:
    """
    Cross-cohort validation with local multi-cohort support.
    Generates 8 core visualizations + optional meta-analysis.
    """
    input:
        ml_sentinel = WORKDIR + "/result/stat/bacteria/ml/siamcat_done.txt",
        metadata = WORKDIR + "/metadata.csv",
        abundance = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv"
    output:
        sentinel = WORKDIR + "/result/viz_crosscohort/crosscohort_done.txt",
        auc_summary = WORKDIR + "/result/viz_crosscohort/auc_summary.tsv",
        forest_plot = WORKDIR + "/result/viz_crosscohort/forest_plot_auc.pdf",
        waterfall = WORKDIR + "/result/viz_crosscohort/waterfall_auc.pdf",
        roc_overlay = WORKDIR + "/result/viz_crosscohort/roc_overlay_all_cohorts.pdf",
        upset = WORKDIR + "/result/viz_crosscohort/upset_shared_features.pdf",
        stability_heatmap = WORKDIR + "/result/viz_crosscohort/heatmap_feature_stability.pdf",
        pcoa_batch = WORKDIR + "/result/viz_crosscohort/pcoa_batch_effect.pdf",
        calibration = WORKDIR + "/result/viz_crosscohort/calibration_per_cohort.pdf",
        effect_corr = WORKDIR + "/result/viz_crosscohort/effect_correlation_matrix.pdf"
    params:
        repo = config.get("repo", "~/Course/Maxmetagenome"),
        group_col = config.get("group_col", "Group"),
        source_mode = config.get("crosscohort_source", "local"),
        cohorts = config.get("crosscohort_cohorts", ""),
        train_cohort = config.get("crosscohort_train", ""),
        meta_analysis = "--meta-analysis" if config.get("crosscohort_meta_analysis", False) else "",
        force_flag = config.get("force", False) and "--force" or "",
    threads: 1
    log:
        WORKDIR + "/logs/stat/crosscohort/97_crosscohort.log"
    shell:
        """
        bash {params.repo}/scripts/97_stat_crosscohort.sh \
            -w {WORKDIR} \
            -r {params.repo} \
            -m {input.metadata} \
            -g {params.group_col} \
            --source {params.source_mode} \
            {params.cohorts} \
            {params.train_cohort} \
            {params.meta_analysis} \
            {params.force_flag}
        """

# Optional: aggregate rule for statistics module
rule viz_statistics_all:
    """
    Generate all statistics visualizations including cross-cohort validation.
    """
    input:
        ml = WORKDIR + "/result/stat/bacteria/ml/siamcat_done.txt",
        crosscohort = WORKDIR + "/result/viz_crosscohort/crosscohort_done.txt"
    output:
        sentinel = WORKDIR + "/result/viz_statistics_all_done.txt"
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        """
        echo "All statistics visualizations completed" > {output.sentinel}
        echo "Timestamp: $(date)" >> {output.sentinel}
        """
