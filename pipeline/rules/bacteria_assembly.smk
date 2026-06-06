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
