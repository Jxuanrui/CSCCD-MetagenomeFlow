rule metaphlan4:
    """Bacterial taxonomic profiling (strain-level, MetaPhlAn4)."""
    input:
        r1 = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        profile = WORKDIR + "/result/taxonomy/metaphlan4/{sample}/{sample}_profile.txt",
        sam_bz2 = WORKDIR + "/result/taxonomy/metaphlan4/{sample}/{sample}.sam.bz2",
    log:
        WORKDIR + "/logs/metaphlan4/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/11_bac_metaphlan4.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule metaphlan4_merge:
    """Merge per-sample MetaPhlAn4 profiles into a community matrix."""
    input:
        profiles = expand(
            WORKDIR + "/result/taxonomy/metaphlan4/{sample}/{sample}_profile.txt",
            sample=SAMPLES,
        ),
    output:
        merged = WORKDIR + "/result/taxonomy/metaphlan4/merged/taxonomy.tsv",
    log:
        WORKDIR + "/logs/metaphlan4_merge/merge.log",
    shell:
        "bash {REPO}/scripts/11b_bac_metaphlan4_merge.sh "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule strainphlan4:
    """Strain-level phylogeny across all samples (aggregate rule)."""
    input:
        sam_files = expand(
            WORKDIR + "/result/taxonomy/metaphlan4/{sample}/{sample}.sam.bz2",
            sample=SAMPLES,
        ),
    output:
        markers_done = WORKDIR + "/result/taxonomy/strainphlan4/consensus_markers/.done",
    log:
        WORKDIR + "/logs/strainphlan4/strainphlan4.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/12_bac_strainphlan4.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "> {log} 2>&1 && "
        "touch {output.markers_done}"


rule humann3:
    """Functional pathway quantification (HUMAnN3)."""
    input:
        r1      = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2      = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
        profile = WORKDIR + "/result/taxonomy/metaphlan4/{sample}/{sample}_profile.txt",
    output:
        pathabundance = WORKDIR + "/result/functional/humann3/{sample}/{sample}_pathabundance.tsv",
        pathcoverage  = WORKDIR + "/result/functional/humann3/{sample}/{sample}_pathcoverage.tsv",
        genefamilies  = WORKDIR + "/result/functional/humann3/{sample}/{sample}_genefamilies.tsv",
    log:
        WORKDIR + "/logs/humann3/{sample}.log",
    threads: CPUS
    params:
        speed = config["humann_speed"],
    shell:
        "bash {REPO}/scripts/13_bac_humann3.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "--speed-mode {params.speed} "
        "> {log} 2>&1"


rule kraken2:
    """Fast k-mer taxonomic classification + Bracken abundance reestimation (S/G/P)."""
    input:
        r1 = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/qc/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        report          = WORKDIR + "/result/taxonomy/kraken2/{sample}/{sample}.report",
        bracken_species = WORKDIR + "/result/taxonomy/kraken2/{sample}/bracken/{sample}_S.bracken",
        bracken_genus   = WORKDIR + "/result/taxonomy/kraken2/{sample}/bracken/{sample}_G.bracken",
        bracken_phylum  = WORKDIR + "/result/taxonomy/kraken2/{sample}/bracken/{sample}_P.bracken",
    log:
        WORKDIR + "/logs/kraken2/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/14_bac_kraken2.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
