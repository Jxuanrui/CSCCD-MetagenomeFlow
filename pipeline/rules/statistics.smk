# MaxMetagenome — Statistics pipeline rules (scripts 91-98)
# ==============================================================================

# Users should edit this placeholder to point at their runtime metadata file.
meta_file = WORKDIR + "/metadata.csv"


rule stat_diversity:
    """Alpha/beta diversity statistics across bacteria, virus, and fungi."""
    input:
        bact = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
        vir = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
        fungi_done = expand(
            WORKDIR + "/result/fungi/metaphlan4/{sample}/{sample}_profile.txt",
            sample=SAMPLES,
        ),
    output:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv"
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/91_stat_diversity.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_differential:
    """Differential abundance analysis across supported omics dimensions."""
    input:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
    output:
        WORKDIR + "/result/stat/diff/diff_summary.tsv"
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
    """Unified downstream visualization from statistical outputs."""
    input:
        WORKDIR + "/result/stat/diversity/alpha_diversity.tsv",
        WORKDIR + "/result/stat/diff/diff_summary.tsv",
    output:
        WORKDIR + "/result/stat/visualization/plots.done"
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
    """SIAMCAT-based biomarker modeling and evaluation."""
    input:
        WORKDIR + "/result/stat/diff/diff_summary.tsv",
    output:
        WORKDIR + "/result/stat/ml/siamcat_done.txt"
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
