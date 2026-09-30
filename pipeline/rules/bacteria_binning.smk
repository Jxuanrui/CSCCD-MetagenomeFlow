# MaxMetagenome — bacteria binning rules (scripts 32-41)
# Executor: CC (single rules file, deterministic)
#
# Per-sample rules: coverm_depth, metabat2, maxbin2, semibin2, dastool
# Aggregate rules: checkm2, drep, coverm_quant(per-sample), gtdbtk, prokka
#
# DAG flow:
#   megahit → coverm_depth → [metabat2, maxbin2, semibin2] → dastool
#   dastool → checkm2 → drep → [coverm_quant, instrain_map] → instrain_profile → instrain_compare
#   drep → [gtdbtk, prokka]

BINNING = WORKDIR + "/result/binning"

# ─── 32: CoverM depth calculation (per-sample) ──────────────────────────────

rule coverm_depth:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        bam = BINNING + "/coverm/{sample}/{sample}.bam",
        depth = BINNING + "/coverm/{sample}/depth.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/32_bac_coverm_depth.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 33: MetaBAT2 binning (per-sample) ──────────────────────────────────────

rule metabat2:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        depth = BINNING + "/coverm/{sample}/depth.txt",
    output:
        tsv = BINNING + "/metabat2/{sample}/{sample}.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/33_bac_metabat2.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 34: MaxBin2 binning (per-sample) ───────────────────────────────────────

rule maxbin2:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        depth = BINNING + "/coverm/{sample}/depth.txt",
    output:
        tsv = BINNING + "/maxbin2/{sample}/{sample}.maxbin2.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/34_bac_maxbin2.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 35: SemiBin2 binning (per-sample) ──────────────────────────────────────

rule semibin2:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        bam = BINNING + "/coverm/{sample}/{sample}.bam",
    output:
        tsv = BINNING + "/semibin2/{sample}/{sample}.semibin2.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/35_bac_semibin2.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 33b: QuickBin high-fidelity binning (per-sample) ───────────────────────

rule quickbin:
    """QuickBin (BBTools) CPU-only, marker-free binning; standalone (NOT wired into the DAS_Tool ensemble)."""
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        bam = BINNING + "/coverm/{sample}/{sample}.bam",
    output:
        tsv = BINNING + "/quickbin/{sample}/{sample}.quickbin.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/33b_bac_quickbin.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 36: DAS_Tool bin integration (per-sample) ──────────────────────────────

rule dastool:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        metabat2 = BINNING + "/metabat2/{sample}/{sample}.tsv",
        maxbin2  = BINNING + "/maxbin2/{sample}/{sample}.maxbin2.tsv",
        semibin2 = BINNING + "/semibin2/{sample}/{sample}.semibin2.tsv",
    output:
        contig2bin = BINNING + "/dastool/{sample}/{sample}_DASTool_contig2bin.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/36_bac_dastool.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 36b: metaWRAP post-binning reassembly (per-sample) ─────────────────────

rule bin_reassembly:
    input:
        contig2bin = BINNING + "/dastool/{sample}/{sample}_DASTool_contig2bin.tsv",
        reads_1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        reads_2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        done = BINNING + "/reassembly/{sample}/{sample}.reassembly_done.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/36b_bac_bin_reassembly.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 37: CheckM2 MAG quality assessment (aggregate) ─────────────────────────

rule checkm2:
    input:
        # Collect all reassembly sentinels across samples (37 reads reassembled
        # bins when present, falling back to raw dastool bins otherwise)
        reassembly = expand(BINNING + "/reassembly/{sample}/{sample}.reassembly_done.txt",
                             sample=SAMPLES),
    output:
        report = BINNING + "/checkm2/quality_report.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/37_bac_checkm2.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 38: dRep MAG dereplication (aggregate) ─────────────────────────────────

rule drep:
    input:
        report = BINNING + "/checkm2/quality_report.tsv",
    output:
        done = BINNING + "/drep/drep_done.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/38_bac_drep.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 38b: GUNC second-pass MAG QC (aggregate, optional) ─────────────────────

rule gunc:
    """Second-pass MAG QC: detect chimeric / cross-lineage bins via lineage homogeneity (complements CheckM2). Not in rule all; run by requesting a result/binning/gunc/GUNC.*.tsv target."""
    input:
        done = BINNING + "/drep/drep_done.txt",
    output:
        out = BINNING + "/gunc/GUNC.progenomes_2.1.maxCSS_level.tsv",
    log:
        WORKDIR + "/logs/binning/gunc.log",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/38b_bac_gunc.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag} > {log} 2>&1"


# ─── 39: CoverM genome quantification (per-sample) ──────────────────────────

rule coverm_quant:
    input:
        mags = BINNING + "/drep/drep_done.txt",
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        tsv = BINNING + "/coverm_quant/{sample}.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/39_bac_coverm_quant.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 39b: inStrain read mapping to dereplicated MAGs (per-sample) ───────────

rule instrain_map:
    input:
        mags = BINNING + "/drep/drep_done.txt",
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        bam = BINNING + "/instrain_map/{sample}/{sample}.sorted.bam",
        bai = BINNING + "/instrain_map/{sample}/{sample}.sorted.bam.bai",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/39b_bac_instrain_map.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 39c: inStrain microdiversity profiling (per-sample) ────────────────────

rule instrain_profile:
    input:
        bam = BINNING + "/instrain_map/{sample}/{sample}.sorted.bam",
        bai = BINNING + "/instrain_map/{sample}/{sample}.sorted.bam.bai",
    output:
        genome_info = BINNING + "/instrain_profile/{sample}/output/{sample}_genome_info.tsv",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/39c_bac_instrain_profile.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 39d: inStrain cross-sample popANI comparison (aggregate) ───────────────

rule instrain_compare:
    input:
        profiles = expand(BINNING + "/instrain_profile/{sample}/output/{sample}_genome_info.tsv",
                          sample=SAMPLES),
    output:
        compare = BINNING + "/instrain_compare/output/instrain_compare_comparisonsTable.tsv",
        summary = BINNING + "/instrain_compare/output/strain_comparison_summary.tsv",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/39d_bac_instrain_compare.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 40: GTDB-Tk taxonomic classification (aggregate) ───────────────────────

rule gtdbtk:
    input:
        drep_done = BINNING + "/drep/drep_done.txt",
    output:
        summary = BINNING + "/gtdbtk/classify/gtdbtk.bac120.summary.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/40_bac_gtdbtk.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 41: Prokka MAG annotation (aggregate batch) ────────────────────────────

rule prokka:
    input:
        drep_done = BINNING + "/drep/drep_done.txt",
    output:
        summary = BINNING + "/prokka/prokka_summary.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/41_bac_prokka.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 41b: MLST typing of dereplicated MAGs (aggregate) ──────────────────────

rule bac_mlst:
    input:
        drep_done = BINNING + "/drep/drep_done.txt",
    output:
        tsv = WORKDIR + "/result/wgs/mlst/mlst.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/41b_bac_mlst.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 41c: Pan-genome analysis of MAG annotations (aggregate) ────────────────

rule bac_pangenome:
    input:
        prokka_summary = BINNING + "/prokka/prokka_summary.tsv",
    output:
        summary = WORKDIR + "/result/wgs/pangenome/summary_statistics.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/41c_bac_pangenome.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 41d: SNP/InDel analysis of dereplicated MAGs (aggregate) ───────────────

rule bac_snippy:
    input:
        drep_done = BINNING + "/drep/drep_done.txt",
    output:
        core_tsv = WORKDIR + "/result/wgs/snippy/core.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/41d_bac_snippy.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 42: MGE comprehensive annotation (per-sample) ──────────────────────────

rule bac_mge:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        proteins = WORKDIR + "/result/assembly/prodigal/{sample}/{sample}.faa",
        nr_proteins = WORKDIR + "/result/assembly/cdhit/protein_nr.fa",
    output:
        isfinder = WORKDIR + "/result/mge/isfinder/{sample}/isfinder_hits.tsv",
        iceberg = WORKDIR + "/result/mge/iceberg/{sample}/iceberg_hits.tsv",
        integrall = WORKDIR + "/result/mge/integrall/{sample}/integrall_hits.tsv",
        transposase = WORKDIR + "/result/mge/transposase/{sample}/transposase_hits.tsv",
    log:
        WORKDIR + "/temp/logs/mge/mge_{sample}.log"
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: 16
    shell:
        "bash {REPO}/scripts/42_bac_mge.sh -s {wildcards.sample} -t {threads} -w {WORKDIR} -r {REPO} {params.force_flag} > {log} 2>&1"


# ─── 42b: PlasmidFinder plasmid identification (per-sample) ─────────────────

rule bac_plasmidfinder:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
    output:
        results = WORKDIR + "/result/mge/plasmidfinder/{sample}/results_tab.tsv",
    log:
        WORKDIR + "/temp/logs/plasmidfinder/plasmidfinder_{sample}.log"
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: 4
    shell:
        "bash {REPO}/scripts/42b_bac_plasmidfinder.sh -s {wildcards.sample} -t {threads} -w {WORKDIR} -r {REPO} {params.force_flag} > {log} 2>&1"
