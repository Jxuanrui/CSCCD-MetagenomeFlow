# MaxMetagenome — bacteria annotation rules (scripts 21-31)
# Executor: CC (single rules file, deterministic)
#
# Aggregate rules (run once across all samples, depend on protein_nr.fa from cdhit):
#   eggnog, kegg, amrfinder, card, dbcan, vfdb, bacmet, defense_finder, ncyc, pcyc,
#   bac_scyc, bac_pfam, bac_uniprot, fegenie
#
# Per-sample rules (one job per sample, depend on contigs.fa from megahit):
#   antismash

PROTEIN_NR_PATH = WORKDIR + "/result/assembly/cdhit/protein_nr.fa"


# ─── 21: eggNOG comprehensive annotation ────────────────────────────────────

rule eggnog:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        annotations = WORKDIR + "/result/annotation/eggnog/eggnog.emapper.annotations",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/21_bac_eggnog.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 22: KEGG KO annotation ─────────────────────────────────────────────────

rule kegg:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/kegg/kegg_diamond.tsv",
    log:
        WORKDIR + "/logs/annotation/kegg/kegg.log",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/22_bac_kegg.sh -t {threads} -w {WORKDIR} -r {REPO} {params.force_flag} > {log} 2>&1"


# ─── 23: AMRFinderPlus antibiotic resistance ─────────────────────────────────

rule amrfinder:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        tsv = WORKDIR + "/result/annotation/amrfinder/amrfinder_results.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/23_bac_amrfinder.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 24: CARD/RGI resistance gene annotation ─────────────────────────────────

rule card:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        txt = WORKDIR + "/result/annotation/card/rgi_results.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/24_bac_card.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


rule card_summary:
    """Confidence-tier + drug-class + SNP-evidence summary of the CARD/RGI output (no new tool, pure aggregation)."""
    input:
        rgi = WORKDIR + "/result/annotation/card/rgi_results.txt",
    output:
        report = WORKDIR + "/result/annotation/card/summary/card_summary_report.txt",
    log:
        WORKDIR + "/logs/card_summary/summary.log",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/24b_bac_card_summary.sh  {params.force_flag}"
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ─── 25: dbCAN3 CAZyme annotation ───────────────────────────────────────────

rule dbcan:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        overview = WORKDIR + "/result/annotation/dbcan/overview.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/25_bac_dbcan.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 26: VFDB virulence factor annotation ───────────────────────────────────

rule vfdb:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/vfdb/vfdb_hits.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/26_bac_vfdb.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 27: BacMet metal resistance annotation ─────────────────────────────────

rule bacmet:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/bacmet/bacmet_hits.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/27_bac_bacmet.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 28: antiSMASH BGC prediction (per-sample) ──────────────────────────────

rule antismash:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
    output:
        index = WORKDIR + "/result/annotation/antismash/{sample}/antismash_done.txt",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/28_bac_antismash.sh -s {wildcards.sample} -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


rule bac_bgc_novelty:
    """BGC 新颖度评分：对 28 号 antiSMASH 产出的每个 region 提取 CDS 蛋白，
    DIAMOND 比对 antiSMASH 自带的 MIBiG 3.1 库，按最佳匹配 cluster 的 CDS
    命中比例计算 novelty_score（复用 clustercompare/mibig 目录下现成 DIAMOND
    库，不重跑 antiSMASH，不新建数据库/环境）。
    """
    input:
        antismash_done = WORKDIR + "/result/annotation/antismash/{sample}/antismash_done.txt",
    output:
        novelty = WORKDIR + "/result/annotation/antismash/{sample}/{sample}.bgc_novelty.tsv",
    log:
        WORKDIR + "/logs/annotation/bac_bgc_novelty/{sample}.log",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/28b_bac_bgc_novelty.sh  {params.force_flag}"
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


# ─── 29: DefenseFinder bacterial defense systems ────────────────────────────

rule defense_finder:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        systems = WORKDIR + "/result/annotation/defense_finder/defense_finder_systems.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/29_bac_defense_finder.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 30: NCyc nitrogen cycling gene annotation ──────────────────────────────

rule ncyc:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/ncyc/ncyc_hits.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/30_bac_ncyc.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 31: PCyc phosphorus cycling gene annotation ────────────────────────────

rule pcyc:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/pcyc/pcyc_hits.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/31_bac_pcyc.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 31b: SCyc sulfur cycling gene annotation ───────────────────────────────

rule bac_scyc:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/scyc/scyc_hits.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/31b_bac_scyc.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 31c: Pfam-A protein domain annotation ──────────────────────────────────

rule bac_pfam:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        tblout = WORKDIR + "/result/annotation/pfam/pfam_hits.tblout",
        domtblout = WORKDIR + "/result/annotation/pfam/pfam_hits.domtblout",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/31c_bac_pfam.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 31d: UniProt Swiss-Prot protein annotation ─────────────────────────────

rule bac_uniprot:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/uniprot_sprot/sprot_hits.tsv",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/31d_bac_uniprot.sh -t {CPUS} -w {WORKDIR} -r {REPO} {params.force_flag}"


# ─── 31e: FeGenie iron metabolism gene prediction ───────────────────────────

rule fegenie:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        summary = WORKDIR + "/result/annotation/fegenie/FeGenie-geneSummary.csv",
        presence = WORKDIR + "/result/annotation/fegenie/FeGenie-presenceAbsence.csv",
    log:
        WORKDIR + "/temp/logs/fegenie/fegenie.log"
    threads: 8
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/31e_bac_fegenie.sh -s NR -t {threads} -w {WORKDIR} -r {REPO} --input-type nr {params.force_flag} > {log} 2>&1"
