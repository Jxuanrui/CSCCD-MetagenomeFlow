rule megahit:
    """De novo metagenome assembly (per sample, --presets meta-large)."""
    input:
        r1 = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
    log:
        WORKDIR + "/logs/megahit/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/16_bac_megahit.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule prodigal:
    """Prokaryotic gene prediction in metagenomics mode (-p meta)."""
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
    output:
        faa = WORKDIR + "/result/assembly/prodigal/{sample}/{sample}.faa",
        fna = WORKDIR + "/result/assembly/prodigal/{sample}/{sample}.fna",
        gff = WORKDIR + "/result/assembly/prodigal/{sample}/{sample}.gff",
    log:
        WORKDIR + "/logs/prodigal/{sample}.log",
    threads: 1
    shell:
        "bash {REPO}/scripts/17_bac_prodigal.sh "
        "-s {wildcards.sample} -t 1 "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
