# MaxMetagenome — Statistics pipeline rules (scripts 91-98)
# ==============================================================================

# Users should edit this placeholder to point at their runtime metadata file.
meta_file = WORKDIR + "/metadata.csv"


rule stat_diversity:
    """Alpha/beta diversity statistics across bacteria, virus, and fungi.
    Also generates PCoA-with-ellipses and rarefaction curves under result/viz_diversity/.
    """
    input:
        bact = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
        vir = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
        fungi_done = expand(
            WORKDIR + "/result/fungi/metaphlan4/{sample}/{sample}_profile.txt",
            sample=SAMPLES,
        ),
    output:
        stats   = WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
        pcoa    = WORKDIR + "/result/viz_diversity/pcoa_ellipses_permanova.pdf",
        rarefac = WORKDIR + "/result/viz_diversity/rarefaction_curves.pdf",
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/91_stat_diversity.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_differential:
    """Differential abundance analysis across supported omics dimensions.
    Also generates volcano plot and LEfSe LDA bar chart under result/viz_differential/.
    """
    input:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
    output:
        stats   = WORKDIR + "/result/stat/diff/diff_summary.tsv",
        volcano = WORKDIR + "/result/viz_differential/volcano_plot.pdf",
        lefse   = WORKDIR + "/result/viz_differential/lefse_lda_bars.pdf",
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/92_stat_differential.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_cooccurrence:
    """Co-occurrence network inference and summary statistics."""
    input:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
    output:
        WORKDIR + "/result/stat/network/network_summary.txt"
    params:
        meta = meta_file
    threads: CPUS
    shell:
        "bash {REPO}/scripts/93_stat_cooccurrence.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta}"


rule stat_visualization:
    """Unified downstream visualization from statistical outputs.
    Also generates grouped composition barplot and genus ComplexHeatmap under result/viz_composition/.
    """
    input:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
        WORKDIR + "/result/stat/diff/diff_summary.tsv",
    output:
        sentinel = WORKDIR + "/result/stat/visualization/plots.done",
        barplot  = WORKDIR + "/result/viz_composition/barplot_composition_by_group.pdf",
        heatmap  = WORKDIR + "/result/viz_composition/heatmap_genus_complexheatmap.pdf",
    params:
        meta = meta_file
    threads: CPUS
    shell:
        "bash {REPO}/scripts/94_stat_visualization.sh "
        "-w {WORKDIR} -r {REPO} -m {params.meta}"


rule stat_batch_correct:
    """Apply supported batch-correction methods to the bacteria matrix."""
    input:
        WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
    output:
        WORKDIR + "/result/stat/batch/corrected_matrices.done"
    params:
        meta = meta_file,
        batch = "batch",
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/95a_stat_batch_correct.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -b {params.batch} -g {params.group}"


rule stat_batch_evaluate:
    """Evaluate corrected matrices and rank batch-correction methods."""
    input:
        WORKDIR + "/result/stat/batch/corrected_matrices.done",
    output:
        WORKDIR + "/result/stat/batch/evaluation_report.tsv"
    params:
        meta = meta_file,
        batch = "batch",
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/95b_stat_batch_evaluate.sh "
        "-w {WORKDIR} -r {REPO} "
        "-m {params.meta} -b {params.batch} -g {params.group}"


rule stat_ml_siamcat:
    """SIAMCAT-based biomarker modeling and evaluation.
    Also generates multi-model ROC overlay and feature importance plots under result/viz_ml/.
    """
    input:
        WORKDIR + "/result/stat/diff/diff_summary.tsv",
    output:
        sentinel   = WORKDIR + "/result/stat/ml/siamcat_done.txt",
        roc_multi  = WORKDIR + "/result/viz_ml/roc_multimodel_comparison.pdf",
        importance = WORKDIR + "/result/viz_ml/feature_importance_with_sd.pdf",
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/96_stat_ml_siamcat.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_curatedMGD:
    """Cross-cohort validation against curatedMetagenomicData cohorts."""
    input:
        WORKDIR + "/result/stat/ml/siamcat_done.txt",
    output:
        WORKDIR + "/result/stat/crosscohort/crosscohort_done.txt"
    params:
        meta = meta_file,
        group = "group",
        condition = "CRC"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/97_stat_curatedMGD.sh "
        "-w {WORKDIR} -r {REPO} "
        "-m {params.meta} -g {params.group} -c {params.condition}"


rule stat_report:
    """Generate a markdown summary snapshot from statistical outputs."""
    input:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
        WORKDIR + "/result/stat/diff/diff_summary.tsv",
        WORKDIR + "/result/stat/ml/siamcat_done.txt",
    output:
        touch(WORKDIR + "/result/stat/report/report.done")
    threads: 1
    shell:
        "bash {REPO}/scripts/98_stat_report.sh -w {WORKDIR} -r {REPO}"


rule bac_integration_tables:
    """Integrate bacterial quantification and annotation outputs into summary tables."""
    input:
        eggnog = WORKDIR + "/result/annotation/eggnog/eggnog.emapper.annotations",
        kegg = WORKDIR + "/result/annotation/kegg/kegg_diamond.tsv",
        salmon = expand(
            WORKDIR + "/result/assembly/salmon/{sample}/quant.sf",
            sample=SAMPLES,
        ),
    output:
        done = touch(WORKDIR + "/result/integration/bacteria/.done")
    params:
        samples = SAMPLES,
        workdir = config["workdir"],
    log:
        WORKDIR + "/logs/integration/bacteria_tables.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98b_bac_integration_tables.sh "
        "-t {threads} -w {params.workdir} -r {REPO} "
        "> {log} 2>&1"


rule vir_integration_tables:
    """Integrate viral abundance and annotation outputs into summary tables."""
    input:
        votu_table = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
        pharokka = WORKDIR + "/result/virus/pharokka/pharokka.gff",
    output:
        done = touch(WORKDIR + "/result/integration/virus/.done")
    params:
        samples = SAMPLES,
        workdir = config["workdir"],
    log:
        WORKDIR + "/logs/integration/virus_tables.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98c_vir_integration_tables.sh "
        "-t {threads} -w {params.workdir} -r {REPO} "
        "> {log} 2>&1"


rule fun_integration_tables:
    """Integrate fungal annotation and abundance outputs into summary tables."""
    input:
        metaeuk = expand(
            WORKDIR + "/result/fungi/metaeuk/{sample}/{sample}.fas",
            sample=SAMPLES,
        ),
        eggnog = WORKDIR + "/result/fungi/eggnog/eggnog.emapper.annotations",
    output:
        done = touch(WORKDIR + "/result/integration/fungi/.done")
    params:
        samples = SAMPLES,
        workdir = config["workdir"],
    log:
        WORKDIR + "/logs/integration/fungi_tables.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98d_fun_integration_tables.sh "
        "-t {threads} -w {params.workdir} -r {REPO} "
        "> {log} 2>&1"
