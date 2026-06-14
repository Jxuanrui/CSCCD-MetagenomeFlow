rule metaphlan4:
    """Bacterial taxonomic profiling (strain-level, MetaPhlAn4)."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        profile = WORKDIR + "/result/metaphlan4/{sample}/{sample}_profile.txt",
        sam_bz2 = WORKDIR + "/result/metaphlan4/{sample}/{sample}.sam.bz2",
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
            WORKDIR + "/result/metaphlan4/{sample}/{sample}_profile.txt",
            sample=SAMPLES,
        ),
    output:
        merged = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
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
            WORKDIR + "/result/metaphlan4/{sample}/{sample}.sam.bz2",
            sample=SAMPLES,
        ),
    output:
        markers_done = WORKDIR + "/result/strainphlan4/consensus_markers/.done",
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
        r1      = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2      = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
        profile = WORKDIR + "/result/metaphlan4/{sample}/{sample}_profile.txt",
        euk_profile = ancient(WORKDIR + "/result/fungi/metaphlan4/{sample}/{sample}_profile.txt"),
    output:
        pathabundance = WORKDIR + "/result/humann3/{sample}/{sample}_pathabundance.tsv",
        pathabundance_relab = WORKDIR + "/result/humann3/{sample}/{sample}_pathabundance_relab.tsv",
        pathcoverage  = WORKDIR + "/result/humann3/{sample}/{sample}_pathcoverage.tsv",
        genefamilies  = WORKDIR + "/result/humann3/{sample}/{sample}_genefamilies.tsv",
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
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        report          = WORKDIR + "/result/kraken2/{sample}/{sample}.report",
        bracken_species = WORKDIR + "/result/kraken2/{sample}/bracken/{sample}_S.bracken",
        bracken_genus   = WORKDIR + "/result/kraken2/{sample}/bracken/{sample}_G.bracken",
        bracken_phylum  = WORKDIR + "/result/kraken2/{sample}/bracken/{sample}_P.bracken",
    log:
        WORKDIR + "/logs/kraken2/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/14_bac_kraken2.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule centrifuger:
    """Protein-level taxonomic classification (Centrifuger + GTDB R226 + RefSeq)."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        kreport         = WORKDIR + "/result/centrifuger/{sample}/{sample}.kreport.tsv",
        classifications = WORKDIR + "/result/centrifuger/{sample}/{sample}.classifications.tsv.gz",
    log:
        WORKDIR + "/logs/centrifuger/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/15_bac_centrifuger.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule humann3_merge:
    """Merge per-sample HUMAnN3 unstratified tables into community matrices."""
    input:
        paths = expand(
            WORKDIR + "/result/humann3/{sample}/{sample}_pathabundance_relab.tsv",
            sample=SAMPLES,
        ),
    output:
        pathabundance = WORKDIR + "/result/humann3/merged/pathabundance_relab.tsv",
        genefamilies = WORKDIR + "/result/humann3/merged/genefamilies_relab.tsv",
    log:
        WORKDIR + "/logs/humann3/merge.log",
    shell:
        "bash {REPO}/scripts/13b_bac_humann3_merge.sh "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule kraken2_merge:
    """Merge per-sample Bracken abundance tables into community matrices."""
    input:
        bracken = expand(
            WORKDIR + "/result/kraken2/{sample}/bracken/{sample}_S.bracken",
            sample=SAMPLES,
        ),
    output:
        bracken_s = WORKDIR + "/result/kraken2/merged/bracken_S.tsv",
        bracken_g = WORKDIR + "/result/kraken2/merged/bracken_G.tsv",
        bracken_p = WORKDIR + "/result/kraken2/merged/bracken_P.tsv",
    log:
        WORKDIR + "/logs/kraken2/merge.log",
    shell:
        "bash {REPO}/scripts/14b_bac_kraken2_merge.sh "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule centrifuger_merge:
    """Merge per-sample Centrifuger kreport tables into community matrices."""
    input:
        kreports = expand(
            WORKDIR + "/result/centrifuger/{sample}/{sample}.kreport.tsv",
            sample=SAMPLES,
        ),
    output:
        kreport_s = WORKDIR + "/result/centrifuger/merged/kreport_S.tsv",
        kreport_g = WORKDIR + "/result/centrifuger/merged/kreport_G.tsv",
        kreport_p = WORKDIR + "/result/centrifuger/merged/kreport_P.tsv",
    log:
        WORKDIR + "/logs/centrifuger/merge.log",
    shell:
        "bash {REPO}/scripts/15b_bac_centrifuger_merge.sh "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
