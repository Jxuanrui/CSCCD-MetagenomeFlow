# ==============================================================================
# Snakemake Rules: Cross-Cohort Validation
# ==============================================================================

rule crosscohort_validation:
    """
    Cross-cohort validation with local multi-cohort support.
    Generates 8 core visualizations + optional meta-analysis.

    Declared-output contract (P3-U-03/U-04 batch, 2026-09-30): only the
    sentinel + auc_summary.tsv + crosscohort_metrics.tsv are declared. The
    PDF plots (forest/waterfall/roc_overlay/upset/heatmap/pcoa/calibration/
    effect_correlation) are undeclared byproducts: several of them
    (effect_correlation_matrix, calibration_per_cohort, upset, ...) are
    legitimately absent in single-cohort or sparse runs, and declaring them
    caused MissingOutputException false alarms. Upstream 96 SKIPPED =>
    97 writes a SKIPPED sentinel plus header-only tables and exits 0.
    """
    input:
        ml_sentinel = WORKDIR + "/result/stat/bacteria/ml/siamcat_done.txt",
        metadata = WORKDIR + "/metadata.csv",
        abundance = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv"
    output:
        sentinel = WORKDIR + "/result/viz_crosscohort/crosscohort_done.txt",
        auc_summary = WORKDIR + "/result/viz_crosscohort/auc_summary.tsv",
        metrics = WORKDIR + "/result/viz_crosscohort/crosscohort_metrics.tsv"
    params:
        repo = config.get("repo", "~/Course/Maxmetagenome"),
        group_col = config.get("group_col", "Group"),
        source_mode = config.get("crosscohort_source", "local"),
        cohorts = ("--cohorts " + config["crosscohort_cohorts"]) if config.get("crosscohort_cohorts") else "",
        train_cohort = ("--train-cohort " + config["crosscohort_train"]) if config.get("crosscohort_train") else "",
        test_cohorts = ("--test-cohorts " + config["crosscohort_test"]) if config.get("crosscohort_test") else "",
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
            {params.test_cohorts} \
            {params.meta_analysis} \
            {params.force_flag} > {log} 2>&1
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
