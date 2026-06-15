# MaxMetagenome — Mycobiome pipeline rules (scripts 71-86)
# ==============================================================================


# ── Step 1: Taxonomy and functional profiling ─────────────────────────────────

rule fun_kraken2:
    """Fungal taxonomic classification and abundance estimation via Kraken2+Bracken."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        out = WORKDIR + "/result/fungi/kraken2/{sample}/{sample}.report",
    log:
        WORKDIR + "/logs/fungi/kraken2/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/71_fun_kraken2_fungi.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_metaphlan4:
    """MetaPhlAn4 eukaryote-only profiling — reuses script 11 mapout (no re-alignment)."""
    input:
        profile = WORKDIR + "/result/metaphlan4/{sample}/{sample}_profile.txt",
    output:
        out = WORKDIR + "/result/fungi/metaphlan4/{sample}/{sample}_profile.txt",
    log:
        WORKDIR + "/logs/fungi/metaphlan4/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/72_fun_metaphlan4_euk.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_humann4:
    """Extract k__Eukaryota pathway contributions from HUMAnN3 stratified output."""
    input:
        stratified = WORKDIR + "/result/humann3/{sample}/stratified/{sample}_pathabundance_relab_stratified.tsv",
    output:
        out = WORKDIR + "/result/fungi/humann4/{sample}/{sample}_fungi_pathabundance.tsv",
    log:
        WORKDIR + "/logs/fungi/humann4/{sample}.log",
    threads: 1
    shell:
        "bash {REPO}/scripts/73_fun_humann4_fungi.sh "
        "-s {wildcards.sample} -t 1 "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_blast_gutdb:
    """DIAMOND blastx search against gut fungal reference database."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        out = WORKDIR + "/result/fungi/blast_gutdb/{sample}/{sample}_blast.tsv",
    log:
        WORKDIR + "/logs/fungi/blast_gutdb/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/74_fun_blast_gutdb.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_funomic:
    """FunOMIC classification with DIAMOND fallback if the tool is unavailable."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        out = WORKDIR + "/result/fungi/funomic/{sample}/{sample}_classification.tsv",
    log:
        WORKDIR + "/logs/fungi/funomic/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/75_fun_funomics.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_microfisher:
    """MicroFisher-style fungal profile derived from Kraken2 classifications."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        out = WORKDIR + "/result/fungi/microfisher/{sample}/{sample}_fungal_profile.tsv",
    log:
        WORKDIR + "/logs/fungi/microfisher/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/77_fun_microfisher.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_megahit:
    """Fungal metagenome assembly via MEGAHIT (meta-sensitive preset)."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        out = WORKDIR + "/result/fungi/assembly/{sample}/{sample}.contigs.fa",
    log:
        WORKDIR + "/logs/fungi/megahit/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/78_fun_megahit.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_eukfinder:
    """Assembly-based eukaryotic contig refinement via Eukfinder."""
    input:
        contigs = WORKDIR + "/result/fungi/assembly/{sample}/{sample}.contigs.fa",
    output:
        out = WORKDIR + "/result/fungi/eukfinder/{sample}/results.txt",
    log:
        WORKDIR + "/logs/fungi/eukfinder/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/79_fun_eukfinder.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_prodigal:
    """Gene prediction on fungal contigs via Prodigal."""
    input:
        contigs = WORKDIR + "/result/fungi/assembly/{sample}/{sample}.contigs.fa",
    output:
        out = WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
    log:
        WORKDIR + "/logs/fungi/prodigal/{sample}.log",
    threads: 1
    shell:
        "bash {REPO}/scripts/80_fun_prodigal.sh "
        "-s {wildcards.sample} -t 1 "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ── Step 2: Aggregate annotation ──────────────────────────────────────────────

rule fun_eggnog:
    """Aggregate eggNOG-mapper annotation across fungal predicted proteins."""
    input:
        faa_files = expand(
            WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/fungi/eggnog/eggnog.emapper.annotations",
    log:
        WORKDIR + "/logs/fungi/eggnog/eggnog.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/81_fun_eggnog.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_kegg:
    """Aggregate KEGG KO annotation across fungal predicted proteins."""
    input:
        faa_files = expand(
            WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/fungi/kegg/kegg_diamond.tsv",
    log:
        WORKDIR + "/logs/fungi/kegg/kegg.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/82_fun_kegg.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_dbcan:
    """Aggregate dbCAN CAZyme annotation across fungal predicted proteins."""
    input:
        faa_files = expand(
            WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/fungi/dbcan/overview.txt",
    log:
        WORKDIR + "/logs/fungi/dbcan/dbcan.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/83_fun_dbcan.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_vfdb:
    """Aggregate VFDB virulence annotation across fungal predicted proteins."""
    input:
        faa_files = expand(
            WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/fungi/vfdb/vfdb_hits.tsv",
    log:
        WORKDIR + "/logs/fungi/vfdb/vfdb.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/84_fun_vfdb.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_amr:
    """Aggregate AMRFinderPlus antifungal resistance annotation."""
    input:
        faa_files = expand(
            WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/fungi/amr/amrfinder_results.tsv",
    log:
        WORKDIR + "/logs/fungi/amr/amr.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/85_fun_amr.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_merops:
    """Aggregate MEROPS protease annotation across fungal predicted proteins."""
    input:
        faa_files = expand(
            WORKDIR + "/result/fungi/prodigal/{sample}/{sample}.faa",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/fungi/merops/merops_hits.tsv",
    log:
        WORKDIR + "/logs/fungi/merops/merops.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/86_fun_merops.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ── CGF Singular+Escrow profiler (Yan et al. 2024 Cell 187) ──────────────────

rule fun_cgf_profiler:
    """Per-sample CGF fungal profiling: DIAMOND blastx + Singular/Escrow assignment."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
        db = REPO + "/db/cgf/cgf_proteins.dmnd",
        smap = REPO + "/db/cgf/cgf_species_map.tsv",
    output:
        out = WORKDIR + "/result/fungi/cgf_profiler/{sample}/{sample}_cgf_abundance.tsv",
    log:
        WORKDIR + "/logs/fungi/cgf_profiler/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/74c_fun_cgf_profiler.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule fun_cgf_aggregate:
    """Aggregate per-sample CGF abundance tables into a species x sample matrix."""
    input:
        per_sample = expand(
            WORKDIR + "/result/fungi/cgf_profiler/{sample}/{sample}_cgf_abundance.tsv",
            sample=SAMPLES,
        ),
    output:
        norm = WORKDIR + "/result/integration/fungi/cgf_species_norm.tsv",
    log:
        WORKDIR + "/logs/fungi/cgf_aggregate/cgf_aggregate.log",
    shell:
        "bash {REPO}/scripts/74d_fun_cgf_aggregate.sh "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
