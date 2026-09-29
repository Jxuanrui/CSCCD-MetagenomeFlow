rule megahit:
    """De novo metagenome assembly (per sample, --presets meta-large)."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
    log:
        WORKDIR + "/logs/megahit/{sample}.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/16_bac_megahit.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"


# Assembler cross-check (metaSPAdes + QUAST vs MEGAHIT). Deliberately NOT in
# rule all — verification layer, like the metax rule; run by requesting a
# result/assembly_metaspades/{sample}/{sample}.metaspades_done.txt target.
rule metaspades:
    """metaSPAdes assembly + QUAST comparison vs MEGAHIT (per sample). Opt-in verification layer, not in rule all."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        sentinel = WORKDIR + "/result/assembly_metaspades/{sample}/{sample}.metaspades_done.txt",
    log:
        WORKDIR + "/logs/metaspades/{sample}.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/16b_bac_metaspades.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
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
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: 1
    shell:
        "bash {REPO}/scripts/17_bac_prodigal.sh "
        "-s {wildcards.sample} -t 1 "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"


rule cdhit:
    """Cross-sample non-redundant gene catalog (CD-HIT-EST, 95% identity, 90% coverage)."""
    input:
        fna_files = expand(
            WORKDIR + "/result/assembly/prodigal/{sample}/{sample}.fna",
            sample=SAMPLES,
        ),
    output:
        nr_fna = WORKDIR + "/result/assembly/cdhit/nucleotide_nr.fa",
        nr_faa = WORKDIR + "/result/assembly/cdhit/protein_nr.fa",
    log:
        WORKDIR + "/logs/cdhit/cdhit.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/18_bac_cdhit.sh "
        "-t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"


rule salmon_build:
    """Build Salmon quasi-mapping index from NR gene catalog (runs once)."""
    input:
        nr_fna = WORKDIR + "/result/assembly/cdhit/nucleotide_nr.fa",
    output:
        index_info = WORKDIR + "/result/assembly/salmon/index/info.json",
    log:
        WORKDIR + "/logs/salmon/build.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/19_bac_salmon_build.sh "
        "-t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"


rule salmon_quant:
    """Per-sample gene abundance quantification (TPM + NumReads) using Salmon."""
    input:
        r1         = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2         = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
        index_info = WORKDIR + "/result/assembly/salmon/index/info.json",
    output:
        quant_sf = WORKDIR + "/result/assembly/salmon/{sample}/quant.sf",
    log:
        WORKDIR + "/logs/salmon/{sample}.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/20_bac_salmon_quant.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "
        "> {log} 2>&1"
