# MaxMetagenome — Virome pipeline rules (scripts 51-69)
# ==============================================================================


# ── Step 1: Assembly ──────────────────────────────────────────────────────────

rule vir_megahit:
    """Virus assembly from clean reads (meta-large, min 1.5kb contigs)."""
    input:
        r1 = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2 = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
    output:
        contigs = WORKDIR + "/result/virus/assembly/{sample}/{sample}.contigs.fa",
    log:
        WORKDIR + "/logs/virus/megahit/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/51_vir_megahit.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ── Step 2: Virus identification ──────────────────────────────────────────────

rule vir_genomad:
    """Virus/plasmid identification via geNomad (neural network)."""
    input:
        contigs = WORKDIR + "/result/virus/assembly/{sample}/{sample}.contigs.fa",
    output:
        virus_summary = WORKDIR + "/result/virus/genomad/{sample}/{sample}.contigs_summary/{sample}.contigs_virus_summary.tsv",
    log:
        WORKDIR + "/logs/virus/genomad/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/52_vir_genomad.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_virsorter2:
    """Viral contig prediction via VirSorter2 (complement to geNomad)."""
    input:
        contigs = WORKDIR + "/result/virus/assembly/{sample}/{sample}.contigs.fa",
    output:
        viral_boundary = WORKDIR + "/result/virus/virsorter2/{sample}/final-viral-boundary.tsv",
    log:
        WORKDIR + "/logs/virus/virsorter2/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/53_vir_virsorter2.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_checkv_contig:
    """Viral contig quality assessment — merge geNomad + VirSorter2 then run CheckV."""
    input:
        genomad_summary = WORKDIR + "/result/virus/genomad/{sample}/{sample}.contigs_summary/{sample}.contigs_virus_summary.tsv",
        vs2_boundary    = WORKDIR + "/result/virus/virsorter2/{sample}/final-viral-boundary.tsv",
    output:
        quality_summary = WORKDIR + "/result/virus/checkv/{sample}/quality_summary.tsv",
        viruses_fna     = WORKDIR + "/result/virus/checkv/{sample}/viruses.fna",
    log:
        WORKDIR + "/logs/virus/checkv_contig/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/54_vir_checkv_contig.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule checkv_filter:
    """Filter CheckV viral contigs for downstream use."""
    input:
        quality_summary = WORKDIR + "/result/virus/checkv/{sample}/quality_summary.tsv",
    output:
        filtered_fna = WORKDIR + "/result/virus/checkv/{sample}/viruses_filtered.fna",
    log:
        WORKDIR + "/logs/virus/checkv_filter/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/54b_vir_checkv_filter.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_prodigal_gv:
    """Viral gene prediction (Prodigal-gv with genetic code 15)."""
    input:
        viral_contigs = WORKDIR + "/result/virus/checkv/{sample}/viruses.fna",
    output:
        faa = WORKDIR + "/result/virus/prodigal/{sample}/{sample}.faa",
        fna = WORKDIR + "/result/virus/prodigal/{sample}/{sample}.fna",
        gff = WORKDIR + "/result/virus/prodigal/{sample}/{sample}.gff",
    log:
        WORKDIR + "/logs/virus/prodigal/{sample}.log",
    threads: 1
    shell:
        "bash {REPO}/scripts/55_vir_prodigal_gv.sh "
        "-s {wildcards.sample} -t 1 "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ── Step 3: vOTU clustering ───────────────────────────────────────────────────

rule vir_votu_gen:
    """Cross-sample vOTU clustering (vclust, 95% ANI, Leiden, qcov 0.85)."""
    input:
        contigs = expand(
            WORKDIR + "/result/virus/checkv/{sample}/viruses.fna",
            sample=SAMPLES,
        ),
    output:
        representatives = WORKDIR + "/result/virus/votu/votu_representatives.tsv",
        virus_fasta     = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    log:
        WORKDIR + "/logs/virus/votu/gen.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/56_vir_votu_gen.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_votu_genomad:
    """Taxonomic annotation of vOTU representatives (geNomad)."""
    input:
        votu_fasta  = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
        votu_done   = WORKDIR + "/result/virus/votu/votu_representatives.tsv",
    output:
        taxonomy = WORKDIR + "/result/virus/votu/genomad/virus_taxonomy.tsv",
    log:
        WORKDIR + "/logs/virus/votu/genomad.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/57_vir_votu_genomad.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ── Step 4: vOTU abundance ────────────────────────────────────────────────────

rule vir_salmon_build:
    """Build Salmon index for vOTU quantification."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
        cds_files  = expand(
            WORKDIR + "/result/virus/prodigal/{sample}/{sample}.fna",
            sample=SAMPLES,
        ),
    output:
        index_done = WORKDIR + "/result/virus/salmon/index/info.json",
    log:
        WORKDIR + "/logs/virus/salmon/build.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/58_vir_salmon_build.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_salmon_quant:
    """Per-sample vOTU abundance quantification via Salmon."""
    input:
        r1          = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2          = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
        salmon_idx  = WORKDIR + "/result/virus/salmon/index/info.json",
    output:
        quant_batch = WORKDIR + "/result/virus/salmon/{sample}/report.tsv",
    log:
        WORKDIR + "/logs/virus/salmon/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/59_vir_salmon_quant.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_votu_table:
    """Generate vOTU abundance matrix with taxonomic annotations."""
    input:
        salmon_reports = expand(
            WORKDIR + "/result/virus/salmon/{sample}/report.tsv",
            sample=SAMPLES,
        ),
        taxonomy = WORKDIR + "/result/virus/votu/genomad/virus_taxonomy.tsv",
    output:
        abundance_table = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
    log:
        WORKDIR + "/logs/virus/votu/table.log",
    run:
        import os
        os.makedirs(os.path.join(WORKDIR, "logs", "virus", "votu"), exist_ok=True)
        samples_file = os.path.join(WORKDIR, "logs", "virus", "votu", "samples.txt")
        with open(samples_file, "w") as f:
            f.write("\n".join(SAMPLES) + "\n")
        shell(
            "bash " + REPO + "/scripts/60_vir_votu_table.sh "
            "-m " + samples_file + " -w " + WORKDIR + " -r " + REPO + " "
            "> " + str(log) + " 2>&1"
        )


# ── Step 5: vMAG generation ───────────────────────────────────────────────────

rule vir_vmag:
    """vMAG binning via vRhyme (multi-sample coverage + protein features)."""
    input:
        contigs  = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        vmag_done = WORKDIR + "/result/virus/vmag/bins/vmag_done.txt",
    log:
        WORKDIR + "/logs/virus/vmag/vmag.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/61_vir_vmag.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_checkv_mag:
    """vMAG quality assessment via CheckV per-bin."""
    input:
        vmag_done = WORKDIR + "/result/virus/vmag/bins/vmag_done.txt",
    output:
        mag_quality = WORKDIR + "/result/virus/vmag/checkv/quality_summary.tsv",
    log:
        WORKDIR + "/logs/virus/checkv_mag/checkv_mag.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/62_vir_checkv_mag.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_coverm_quant:
    """vMAG abundance quantification (CoverM genome)."""
    input:
        r1          = WORKDIR + "/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz",
        r2          = WORKDIR + "/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz",
        mag_quality = WORKDIR + "/result/virus/vmag/checkv/quality_summary.tsv",
    output:
        quant_tsv = WORKDIR + "/result/virus/coverm_quant/{sample}.tsv",
    log:
        WORKDIR + "/logs/virus/coverm_quant/{sample}.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/63_vir_coverm_quant.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ── Step 6: Annotation ────────────────────────────────────────────────────────

rule vir_pharokka:
    """End-to-end viral genome annotation (PHAROKKA + PHROG)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        pharokka_gff = WORKDIR + "/result/virus/pharokka/pharokka.gff",
        pharokka_cds = WORKDIR + "/result/virus/pharokka/pharokka_cds_final_merged_output.tsv",
        pharokka_faa = WORKDIR + "/result/virus/pharokka/phanotate.faa",
    log:
        WORKDIR + "/logs/virus/pharokka/pharokka.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/64_vir_pharokka.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_phold:
    """Structural dark matter ORF annotation (PHOLD, complements PHAROKKA)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        phold_tsv = WORKDIR + "/result/virus/phold/vOTU_phold.tsv",
    log:
        WORKDIR + "/logs/virus/phold/phold.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/65_vir_phold.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_vog:
    """Cross-species viral HMM scanning (VOGDB)."""
    input:
        pharokka_faa = WORKDIR + "/result/virus/pharokka/phanotate.faa",
    output:
        vog_hits   = WORKDIR + "/result/virus/vog/vog_hits.tsv",
        vog_annot  = WORKDIR + "/result/virus/vog/vog_annot.tsv",
    log:
        WORKDIR + "/logs/virus/vog/vog.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/66_vir_vog.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_bacphlip:
    """Bacteriophage lifestyle prediction (lytic vs temperate)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        bacphlip_tsv = WORKDIR + "/result/virus/bacphlip/bacphlip_results.tsv",
    log:
        WORKDIR + "/logs/virus/bacphlip/bacphlip.log",
    threads: 1
    shell:
        "bash {REPO}/scripts/67_vir_bacphlip.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_iphop:
    """Virus-host association prediction (iPHoP)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        host_tsv = WORKDIR + "/result/virus/iphop/Host_prediction_to_genus_m90.csv",
    log:
        WORKDIR + "/logs/virus/iphop/iphop.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/68_vir_iphop.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule vir_vcontact3:
    """Viral taxonomy via gene-sharing network (vConTACT3)."""
    input:
        votu_fasta  = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
        prodigal_faa = WORKDIR + "/result/virus/pharokka/phanotate.faa",
    output:
        vcontact_overview = WORKDIR + "/result/virus/vcontact3/exports/final_assignments.csv",
    log:
        WORKDIR + "/logs/virus/vcontact3/vcontact3.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/69_vir_vcontact3.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule phabox2:
    """End-to-end viral analysis and taxonomy prediction (PhaBox2)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        phabox2_summary = WORKDIR + "/result/virus/phabox2/phabox2_summary.tsv",
    log:
        WORKDIR + "/logs/virus/phabox2/phabox2.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/70_vir_phabox2.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule dram_v:
    """Viral functional annotation and AMG distillation (DRAM-v)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        dram_annotations = WORKDIR + "/result/virus/dram/DRAM_annotations.tsv",
    log:
        WORKDIR + "/logs/virus/dram/dram.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/71_vir_dram.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule phagcn3:
    """Bacteriophage taxonomy prediction (PhaGCN3)."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        phagcn3_prediction = WORKDIR + "/result/virus/phagcn3/phagcn3_prediction.tsv",
    log:
        WORKDIR + "/logs/virus/phagcn3/phagcn3.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/72_vir_phagcn3.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# Lifestyle prediction cross-check (ProkBERT-PhaStyle vs BACPHLIP 67). Deliberately
# NOT in rule all — verification layer, like the metax/metaspades rules; run by
# requesting a result/virus/phastyle/phastyle_done.txt target.
rule phastyle:
    """Phage lifestyle prediction cross-check (ProkBERT-PhaStyle, third vote vs 67 BACPHLIP). Opt-in verification layer, not in rule all."""
    input:
        votu_fasta = WORKDIR + "/result/virus/votu/contigs/virus.fasta",
    output:
        phastyle_tsv = WORKDIR + "/result/virus/phastyle/phastyle_results.tsv",
        sentinel = WORKDIR + "/result/virus/phastyle/phastyle_done.txt",
    log:
        WORKDIR + "/logs/virus/phastyle/phastyle.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/67b_vir_phastyle.sh "
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
