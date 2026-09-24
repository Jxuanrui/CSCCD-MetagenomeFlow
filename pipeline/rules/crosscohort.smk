# ==============================================================================
# Snakemake Rules: Cross-Cohort Validation
# ==============================================================================

rule crosscohort_validation:
    """
    Cross-cohort validation with local multi-cohort support.
    Generates 8 core visualizations + optional meta-analysis.
    """
    input:
        ml_model = "{workdir}/result/stat/ml/siamcat_lasso.rds",
        metadata = "{workdir}/metadata.csv",
        abundance = "{workdir}/result/metaphlan4/merged/taxonomy.tsv"
    output:
        sentinel = "{workdir}/result/viz_crosscohort/crosscohort_done.txt",
        auc_summary = "{workdir}/result/viz_crosscohort/auc_summary.tsv",
        forest_plot = "{workdir}/result/viz_crosscohort/forest_plot_auc.pdf",
        waterfall = "{workdir}/result/viz_crosscohort/waterfall_auc.pdf",
        roc_overlay = "{workdir}/result/viz_crosscohort/roc_overlay_all_cohorts.pdf",
        upset = "{workdir}/result/viz_crosscohort/upset_shared_features.pdf",
        stability_heatmap = "{workdir}/result/viz_crosscohort/heatmap_feature_stability.pdf",
        pcoa_batch = "{workdir}/result/viz_crosscohort/pcoa_batch_effect.pdf",
        calibration = "{workdir}/result/viz_crosscohort/calibration_per_cohort.pdf",
        effect_corr = "{workdir}/result/viz_crosscohort/effect_correlation_matrix.pdf"
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
        "{workdir}/logs/stat/crosscohort/97_crosscohort.log"
    shell:
        """
        bash {params.repo}/scripts/97_stat_crosscohort.sh \
            -w {wildcards.workdir} \
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
        diversity = "{workdir}/result/stat/diversity_done.txt",
        differential = "{workdir}/result/stat/diff_done.txt",
        network = "{workdir}/result/stat/network_done.txt",
        ml = "{workdir}/result/stat/ml/siamcat_done.txt",
        crosscohort = "{workdir}/result/viz_crosscohort/crosscohort_done.txt"
    output:
        sentinel = "{workdir}/result/viz_statistics_all_done.txt"
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        """
        echo "All statistics visualizations completed" > {output.sentinel}
        echo "Timestamp: $(date)" >> {output.sentinel}
        """
