# MaxMetagenome — bacteria binning rules (scripts 32-41)
# Executor: CC (single rules file, deterministic)
#
# Per-sample rules: coverm_depth, metabat2, maxbin2, semibin2, dastool
# Aggregate rules: checkm2, drep, coverm_quant(per-sample), gtdbtk, bakta
#
# DAG flow:
#   megahit → coverm_depth → [metabat2, maxbin2, semibin2] → dastool
#   dastool → checkm2 → drep → [coverm_quant, gtdbtk, bakta]

BINNING = WORKDIR + "/result/binning"

# ─── 32: CoverM depth calculation (per-sample) ──────────────────────────────

rule coverm_depth:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        r1 = WORKDIR + "/temp/qc/kneaddata/{sample}/{sample}_1_kneaddata.fastq.gz",
        r2 = WORKDIR + "/temp/qc/kneaddata/{sample}/{sample}_2_kneaddata.fastq.gz",
    output:
        bam = BINNING + "/coverm/{sample}/{sample}.bam",
        depth = BINNING + "/coverm/{sample}/depth.txt",
    shell:
        "bash {REPO}/scripts/32_bac_coverm_depth.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 33: MetaBAT2 binning (per-sample) ──────────────────────────────────────

rule metabat2:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        depth = BINNING + "/coverm/{sample}/depth.txt",
    output:
        tsv = BINNING + "/metabat2/{sample}/{sample}.tsv",
    shell:
        "bash {REPO}/scripts/33_bac_metabat2.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 34: MaxBin2 binning (per-sample) ───────────────────────────────────────

rule maxbin2:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        depth = BINNING + "/coverm/{sample}/depth.txt",
    output:
        tsv = BINNING + "/maxbin2/{sample}/{sample}.maxbin2.tsv",
    shell:
        "bash {REPO}/scripts/34_bac_maxbin2.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 35: SemiBin2 binning (per-sample) ──────────────────────────────────────

rule semibin2:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        bam = BINNING + "/coverm/{sample}/{sample}.bam",
    output:
        tsv = BINNING + "/semibin2/{sample}/{sample}.semibin2.tsv",
    shell:
        "bash {REPO}/scripts/35_bac_semibin2.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 36: DAS_Tool bin integration (per-sample) ──────────────────────────────

rule dastool:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
        metabat2 = BINNING + "/metabat2/{sample}/{sample}.tsv",
        maxbin2  = BINNING + "/maxbin2/{sample}/{sample}.maxbin2.tsv",
        semibin2 = BINNING + "/semibin2/{sample}/{sample}.semibin2.tsv",
    output:
        contig2bin = BINNING + "/dastool/{sample}/{sample}_DASTool_contig2bin.tsv",
    shell:
        "bash {REPO}/scripts/36_bac_dastool.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 37: CheckM2 MAG quality assessment (aggregate) ─────────────────────────

rule checkm2:
    input:
        # Collect all dastool bins across samples
        bins = expand(BINNING + "/dastool/{sample}/{sample}_DASTool_contig2bin.tsv",
                      sample=SAMPLES),
    output:
        report = BINNING + "/checkm2/quality_report.tsv",
    shell:
        "bash {REPO}/scripts/37_bac_checkm2.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 38: dRep MAG dereplication (aggregate) ─────────────────────────────────

rule drep:
    input:
        report = BINNING + "/checkm2/quality_report.tsv",
    output:
        done = BINNING + "/drep/.done",
    shell:
        "bash {REPO}/scripts/38_bac_drep.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 39: CoverM genome quantification (per-sample) ──────────────────────────

rule coverm_quant:
    input:
        mags = BINNING + "/drep/.done",
        r1 = WORKDIR + "/temp/qc/kneaddata/{sample}/{sample}_1_kneaddata.fastq.gz",
        r2 = WORKDIR + "/temp/qc/kneaddata/{sample}/{sample}_2_kneaddata.fastq.gz",
    output:
        tsv = BINNING + "/coverm_quant/{sample}.tsv",
    shell:
        "bash {REPO}/scripts/39_bac_coverm_quant.sh -s {wildcards.sample}" +
        " -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 40: GTDB-Tk taxonomic classification (aggregate) ───────────────────────

rule gtdbtk:
    input:
        drep_done = BINNING + "/drep/.done",
    output:
        summary = BINNING + "/gtdbtk/classify/gtdbtk.bac120.summary.tsv",
    shell:
        "bash {REPO}/scripts/40_bac_gtdbtk.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 41: Bakta MAG annotation (aggregate batch) ─────────────────────────────

rule bakta:
    input:
        drep_done = BINNING + "/drep/.done",
    output:
        summary = BINNING + "/bakta/bakta_summary.tsv",
    shell:
        "bash {REPO}/scripts/41_bac_bakta.sh -t {CPUS} -w {WORKDIR} -r {REPO}"
