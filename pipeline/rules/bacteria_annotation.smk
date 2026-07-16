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
    shell:
        "bash {REPO}/scripts/21_bac_eggnog.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 22: KEGG KO annotation ─────────────────────────────────────────────────

rule kegg:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/kegg/kegg_diamond.tsv",
    log:
        WORKDIR + "/logs/annotation/kegg/kegg.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/22_bac_kegg.sh -t {threads} -w {WORKDIR} -r {REPO} > {log} 2>&1"


# ─── 23: AMRFinderPlus antibiotic resistance ─────────────────────────────────

rule amrfinder:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        tsv = WORKDIR + "/result/annotation/amrfinder/amrfinder_results.tsv",
    shell:
        "bash {REPO}/scripts/23_bac_amrfinder.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 24: CARD/RGI resistance gene annotation ─────────────────────────────────

rule card:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        txt = WORKDIR + "/result/annotation/card/rgi_results.txt",
    shell:
        "bash {REPO}/scripts/24_bac_card.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 25: dbCAN3 CAZyme annotation ───────────────────────────────────────────

rule dbcan:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        overview = WORKDIR + "/result/annotation/dbcan/overview.txt",
    shell:
        "bash {REPO}/scripts/25_bac_dbcan.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 26: VFDB virulence factor annotation ───────────────────────────────────

rule vfdb:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/vfdb/vfdb_hits.tsv",
    shell:
        "bash {REPO}/scripts/26_bac_vfdb.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 27: BacMet metal resistance annotation ─────────────────────────────────

rule bacmet:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/bacmet/bacmet_hits.tsv",
    shell:
        "bash {REPO}/scripts/27_bac_bacmet.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 28: antiSMASH BGC prediction (per-sample) ──────────────────────────────

rule antismash:
    input:
        contigs = WORKDIR + "/result/assembly/megahit/{sample}/{sample}.contigs.fa",
    output:
        index = WORKDIR + "/result/annotation/antismash/{sample}/.done",
    shell:
        "bash {REPO}/scripts/28_bac_antismash.sh -s {wildcards.sample} -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 29: DefenseFinder bacterial defense systems ────────────────────────────

rule defense_finder:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        systems = WORKDIR + "/result/annotation/defense_finder/defense_finder_systems.tsv",
    shell:
        "bash {REPO}/scripts/29_bac_defense_finder.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 30: NCyc nitrogen cycling gene annotation ──────────────────────────────

rule ncyc:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/ncyc/ncyc_hits.tsv",
    shell:
        "bash {REPO}/scripts/30_bac_ncyc.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 31: PCyc phosphorus cycling gene annotation ────────────────────────────

rule pcyc:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/pcyc/pcyc_hits.tsv",
    shell:
        "bash {REPO}/scripts/31_bac_pcyc.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 31b: SCyc sulfur cycling gene annotation ───────────────────────────────

rule bac_scyc:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/scyc/scyc_hits.tsv",
    shell:
        "bash {REPO}/scripts/31b_bac_scyc.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 31c: Pfam-A protein domain annotation ──────────────────────────────────

rule bac_pfam:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        tblout = WORKDIR + "/result/annotation/pfam/pfam_hits.tblout",
        domtblout = WORKDIR + "/result/annotation/pfam/pfam_hits.domtblout",
    shell:
        "bash {REPO}/scripts/31c_bac_pfam.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


# ─── 31d: UniProt Swiss-Prot protein annotation ─────────────────────────────

rule bac_uniprot:
    input:
        protein_nr = PROTEIN_NR_PATH,
    output:
        hits = WORKDIR + "/result/annotation/uniprot_sprot/sprot_hits.tsv",
    shell:
        "bash {REPO}/scripts/31d_bac_uniprot.sh -t {CPUS} -w {WORKDIR} -r {REPO}"


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
    shell:
        "bash {REPO}/scripts/31e_bac_fegenie.sh -s NR -t {threads} -w {WORKDIR} -r {REPO} --input-type nr > {log} 2>&1"
