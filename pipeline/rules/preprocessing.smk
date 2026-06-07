rule fastp_qc:
    """Quality control: adapter trimming and low-quality base removal."""
    input:
        r1 = WORKDIR + "/data/{sample}_1.fastq.gz",
        r2 = WORKDIR + "/data/{sample}_2.fastq.gz",
    output:
        r1   = WORKDIR + "/result/fastp/{sample}/{sample}_1.fastq.gz",
        r2   = WORKDIR + "/result/fastp/{sample}/{sample}_2.fastq.gz",
        json = WORKDIR + "/result/fastp/{sample}/{sample}.json",
        html = WORKDIR + "/result/fastp/{sample}/{sample}.html",
    log:
        WORKDIR + "/logs/fastp/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/01_qc_fastp.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule kneaddata:
    """Host decontamination (human genome removal)."""
    input:
        r1 = WORKDIR + "/result/fastp/{sample}/{sample}_1.fastq.gz",
        r2 = WORKDIR + "/result/fastp/{sample}/{sample}_2.fastq.gz",
    output:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    log:
        WORKDIR + "/logs/kneaddata/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/02_qc_kneaddata.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
