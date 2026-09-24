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
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/01_qc_fastp.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"


rule kneaddata:
    """Host decontamination (human genome removal)."""
    input:
        r1 = WORKDIR + "/result/fastp/{sample}/{sample}_1.fastq.gz",
        r2 = WORKDIR + "/result/fastp/{sample}/{sample}_2.fastq.gz",
    output:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata_raw.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata_raw.fastq.gz",
    log:
        WORKDIR + "/logs/kneaddata/{sample}.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/02_qc_kneaddata.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"


rule pair_repair:
    """Strictly re-pair R1/R2 reads (fixes order mismatch found in kneaddata output,
    see 02b_qc_pair_repair.sh header comment). Output overwrites the canonical
    kneaddata path that all 41 downstream rules already reference."""
    input:
        r1_raw = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata_raw.fastq.gz",
        r2_raw = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata_raw.fastq.gz",
    output:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    log:
        WORKDIR + "/logs/pair_repair/{sample}.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/02b_qc_pair_repair.sh "
        "-s {wildcards.sample} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"
