#!/usr/bin/env python3
"""Step validation gate: checks not just completion, but correctness.

Called after each step completes. Returns 0 (pass) or 1 (fail with details).
Integrates with the MGX monitor event stream for audit trail.

Usage: python3 scripts/utils/validate_step.py <step_id> <sample> <workdir> [--repo <repo>]
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def count_fasta_headers(path):
    """Count FASTA headers, returning 0 for missing/empty files."""
    if not os.path.isfile(path):
        return -1  # missing = different from empty
    count = 0
    try:
        with open(path) as f:
            for line in f:
                if line.startswith(">"):
                    count += 1
    except Exception:
        return -1
    return count


def count_tsv_data_rows(path, skip_header=True):
    """Count non-empty data rows in a TSV."""
    if not os.path.isfile(path):
        return -1
    count = 0
    try:
        with open(path) as f:
            for i, line in enumerate(f):
                if skip_header and i == 0:
                    continue
                if line.strip():
                    count += 1
    except Exception:
        return -1
    return count


def check_fastq_pair_consistency(r1_path, r2_path):
    """Check that paired FASTQ files have the same number of reads."""
    # Quick check: compare file sizes (not exact but catches gross mismatch)
    s1 = os.path.getsize(r1_path) if os.path.isfile(r1_path) else -1
    s2 = os.path.getsize(r2_path) if os.path.isfile(r2_path) else -1
    if s1 < 0 or s2 < 0:
        return False, "paired file missing"
    if s1 == 0 and s2 == 0:
        return True, "both empty (legal)"
    ratio = max(s1, s2) / max(1, min(s1, s2))
    if ratio > 1.5:
        return False, f"size mismatch: R1={s1} R2={s2} ratio={ratio:.1f}"
    return True, "ok"


# Validation rules per step: each entry is (check_name, check_function, description)
VALIDATION_RULES = {
    "01_qc_fastp": [
        ("json_exists", lambda w, s: os.path.isfile(f"{w}/result/fastp/{s}/{s}.json"),
         "fastp JSON report exists"),
        ("json_nonempty", lambda w, s: count_tsv_data_rows(f"{w}/result/fastp/{s}/{s}.json", skip_header=False) > 0,
         "fastp JSON has content"),
        ("clean_reads_exist", lambda w, s: os.path.isfile(f"{w}/result/fastp/{s}/{s}_1.fastq.gz"),
         "clean R1 output exists"),
        ("pair_consistency", lambda w, s: check_fastq_pair_consistency(
            f"{w}/result/fastp/{s}/{s}_1.fastq.gz",
            f"{w}/result/fastp/{s}/{s}_2.fastq.gz")[0],
         "paired output sizes consistent"),
    ],
    "02_qc_kneaddata": [
        ("report_exists", lambda w, s: os.path.isfile(f"{w}/result/kneaddata/{s}/kneaddata.log"),
         "kneaddata log exists"),
        ("clean_output", lambda w, s: os.path.isfile(f"{w}/result/kneaddata/{s}/{s}_1.kneaddata.fastq.gz"),
         "clean R1 output exists"),
    ],
    "02b_qc_pair_repair": [
        ("paired_output", lambda w, s: os.path.isfile(f"{w}/result/kneaddata/{s}/{s}_1.kneaddata.fastq.gz"),
         "paired output exists"),
        ("sentinel", lambda w, s: os.path.isfile(f"{w}/result/kneaddata/{s}/{s}.pair_repair_done.txt"),
         "pair repair sentinel exists"),
    ],
    "11_bac_metaphlan4": [
        ("profile_exists", lambda w, s: os.path.isfile(f"{w}/result/metaphlan4/{s}/{s}_profile.txt"),
         "MetaPhlAn4 profile exists"),
        ("profile_has_species", lambda w, s: count_tsv_data_rows(f"{w}/result/metaphlan4/{s}/{s}_profile.txt") > 0,
         "profile has at least one species"),
    ],
    "13_bac_humann3": [
        ("pathabundance", lambda w, s: os.path.isfile(f"{w}/result/humann3/{s}/{s}_pathabundance.tsv"),
         "pathabundance exists"),
        ("pathabundance_rows", lambda w, s: count_tsv_data_rows(f"{w}/result/humann3/{s}/{s}_pathabundance.tsv") > 0,
         "pathabundance has data rows"),
    ],
    "14_bac_kraken2": [
        ("report", lambda w, s: os.path.isfile(f"{w}/result/kraken2/{s}/{s}.report"),
         "kraken2 report exists"),
    ],
    "51_vir_megahit": [
        ("contigs", lambda w, s: os.path.isfile(f"{w}/result/virus/assembly/{s}/{s}.contigs.fa"),
         "contigs file exists"),
        ("contigs_nonempty", lambda w, s: count_fasta_headers(f"{w}/result/virus/assembly/{s}/{s}.contigs.fa") > 0,
         "contigs has sequences"),
    ],
    "53_vir_virsorter2": [
        ("viral_seq", lambda w, s: os.path.isfile(f"{w}/result/virus/virsorter2/{s}/final-viral-combined.fa"),
         "viral sequences file exists"),
    ],
    "54_vir_checkv_contig": [
        ("quality_summary", lambda w, s: os.path.isfile(f"{w}/result/virus/checkv/{s}/quality_summary.tsv"),
         "quality summary exists"),
        ("call_stats", lambda w, s: os.path.isfile(f"{w}/result/virus/checkv/{s}/call_stats.tsv"),
         "call_stats.tsv exists (audit trail)"),
        ("virus_contigs", lambda w, s: os.path.isfile(f"{w}/result/virus/checkv/{s}/virus_contigs.fasta"),
         "virus contigs file exists (even if empty)"),
    ],
    "78_fun_megahit": [
        ("contigs", lambda w, s: os.path.isfile(f"{w}/result/fungi/assembly/{s}/{s}.contigs.fa"),
         "fungal contigs exists"),
    ],
    "79_fun_eukfinder": [
        ("results", lambda w, s: os.path.isfile(f"{w}/result/fungi/eukfinder/{s}/results.txt"),
         "eukfinder results exist"),
    ],
    "21_bac_eggnog": [
        ("annotations_exist", lambda w, s: os.path.isfile(f"{w}/result/annotation/eggnog/eggnog.emapper.annotations"),
         "eggNOG annotation table exists"),
        ("annotations_nonempty", lambda w, s: count_tsv_data_rows(f"{w}/result/annotation/eggnog/eggnog.emapper.annotations", skip_header=False) > 100000,  # applicability: expect ~886K eggNOG hits for 1M-protein catalog; smaller inputs may have fewer
         "eggNOG annotations substantial (>100K; expect ~886K hits)"),
        ("id_provenance", lambda w, s: _eggnog_id_provenance(w),
         "every eggNOG query ID is from protein_nr.fa (identity consistency, P3-8)"),
    ],
    "18_bac_cdhit": [
        ("nr_nucleotide", lambda w, s: os.path.isfile(f"{w}/result/assembly/cdhit/nucleotide_nr.fa"),
         "non-redundant nucleotide catalog exists"),
        ("nr_protein", lambda w, s: os.path.isfile(f"{w}/result/assembly/cdhit/protein_nr.fa"),
         "non-redundant protein catalog exists"),
        ("protein_lt_nucleotide", lambda w, s: _protein_lt_nuc(w),
         "protein catalog ≤ nucleotide catalog (expected: seqkit translate filters empty)"),
    ],
    "20_bac_salmon_quant": [
        ("quant_files", lambda w, s: all(os.path.isfile(f"{w}/result/assembly/salmon/{sid}/quant.sf") for sid in _get_samples(w)),
         "all 6 sample quant.sf files exist"),
        ("quant_rows_consistent", lambda w, s: _salmon_rows_consistent(w),
         "all samples have same transcript count"),
    ],
    "24c_bac_amr_harmonize": [
        ("afp_table", lambda w, s: os.path.isfile(f"{w}/result/annotation/amr_harmonized/hamronized_amrfinder.tsv"),
         "harmonized AMRFinderPlus table exists"),
        ("rgi_table", lambda w, s: os.path.isfile(f"{w}/result/annotation/amr_harmonized/hamronized_rgi.tsv"),
         "harmonized RGI table exists"),
        ("reconciliation", lambda w, s: os.path.isfile(f"{w}/result/annotation/amr_harmonized/reconciliation.json"),
         "no-loss reconciliation JSON exists"),
    ],
    # Default: just check exit code was 0 (no additional validation)
    "_default": [],
    # ── 质量审核终审 2026-10-15 P1-6：高价值不变式（只给"错了会静默污染下游"的步骤）──
    "38_bac_drep": [
        ("genomes_present", lambda w, s: len(list(Path(f"{w}/result/binning/drep/dereplicated_genomes").glob("*.fa"))) > 0,
         "dereplicated MAG FASTAs exist"),
        ("count_closure", lambda w, s: _drep_count_closed(w),
         "dereplicated_genomes count == dRep Cdb cluster count"),
    ],
    "40_bac_gtdbtk": [
        ("summary_rows", lambda w, s: _tsv_data_rows(f"{w}/result/binning/gtdbtk/gtdbtk.bac120.summary.tsv") > 0,
         "GTDB-Tk summary has classified MAGs"),
        ("count_closure", lambda w, s: _gtdbtk_count_closed(w),
         "GTDB-Tk summary rows == dereplicated MAG count"),
    ],
    "74f_fun_phf_aggregate": [
        ("merged_exists", lambda w, s: os.path.isfile(f"{w}/result/fungi/phf_profiler/merged_abundance.tsv"),
         "merged PHF abundance table exists"),
        ("cluster_closure", lambda w, s: _phf_cluster_closed(w),
         "merged rows == unique clusters across per-sample .rc (catches header-misdetection line drops)"),
    ],
    "60_vir_votu_table": [
        ("table_exists", lambda w, s: os.path.isfile(f"{w}/result/virus/votu/votu_table.tsv"),
         "canonical vOTU table exists"),
        ("join_closure", lambda w, s: _votu_join_closed(w),
         "votu_join_stats failed_contig_rows == 0 and canonical == representative count"),
        ("tpm_conservation", lambda w, s: _votu_tpm_sums_ok(w),
         "each sample's vOTU TPM sums to 1e6 (index EM-split regression guard)"),
        ("column_shape", lambda w, s: _votu_columns_ok(w),
         "columns are votu,length,<sample>_tpm/_count pairs[,lineage,annotation_status]"),
    ],
    "22_bac_kegg": [
        ("diamond_tsv_exists", lambda w, s: os.path.isfile(f"{w}/result/annotation/kegg/kegg_diamond.tsv"),
         "KEGG diamond result table exists"),
        ("diamond_rows", lambda w, s: count_tsv_data_rows(f"{w}/result/annotation/kegg/kegg_diamond.tsv", skip_header=False) > 1000,  # applicability: expect ~900K for 1M-protein catalog; smaller catalogs may legitimately have fewer
         "KEGG hits present (>1000; expect ~900K for 1M-protein catalog)"),
        ("diamond_cols", lambda w, s: _first_ncols_ok(f"{w}/result/annotation/kegg/kegg_diamond.tsv", 12),
         "KEGG rows have 12 diamond outfmt-6 columns"),
    ],
    "36_bac_dastool": [
        ("c2b_tsv_exists", lambda w, s: os.path.isfile(f"{w}/result/binning/dastool/{s}/{s}_DASTool_contig2bin.tsv"),
         "DASTool contig2bin table exists"),
        ("c2b_rows", lambda w, s: count_tsv_data_rows(f"{w}/result/binning/dastool/{s}/{s}_DASTool_contig2bin.tsv", skip_header=False) > 0,
         "contig2bin table has assignments"),
        ("bins_present", lambda w, s: len(list(Path(f"{w}/result/binning/dastool/{s}/{s}_DASTool_bins").glob("*.fa"))) > 0,
         "integrated bin FASTAs extracted"),
        ("bin_contig_ids_consistent", lambda w, s: _dastool_ids_consistent(w, s),
         "every bin contig ID appears in contig2bin table (same source)"),
    ],
    # ── Peptide branch steps 44-50 (contract: docs/plans/peptide_contract.md) ──
    "44_pep_smorf_catalog": [
        ("done_sentinel", lambda w, s: os.path.isfile(f"{w}/result/peptide/smorf/smorf_catalog.done"),
         "smorf_catalog.done sentinel exists"),
        ("stats_md_six_samples", lambda w, s: _pep_smorf_stats_ok(w),
         "stats.md lists all 6 sample rows and total == summed TSV data rows"),
        ("tsv_faa_count_closure", lambda w, s: _pep_smorf_counts_closed(w),
         "per-sample TSV data rows == per-sample FAA headers (all 6 samples)"),
        ("length_bounds_20_99", lambda w, s: _pep_smorf_bad("len", w) == 0,
         "every length_aa is within the 20-99 aa candidate window"),
        ("partial_whitelist", lambda w, s: _pep_smorf_bad("partial", w) == 0,
         "partial values are within {complete, partial_g3, partial_g5, partial_both}"),
    ],
    "45_pep_ref_registry": [
        ("registry_json_parses", lambda w, s: isinstance(_pep_registry(w), dict),
         "refs/registry.json exists and parses as JSON"),
        ("miprobe_api_version_nonempty", lambda w, s: bool((_pep_registry(w) or {}).get("miProbe", {}).get("api_version")),
         "miProbe.api_version is recorded and non-empty"),
    ],
    "46_pep_smorf_screen": [
        ("screen_done_sentinel", lambda w, s: os.path.isfile(f"{w}/result/peptide/screen/screen.done"),
         "screen.done sentinel exists"),
        ("batch_files_match_state", lambda w, s: _pep_screen_state_closed(w),
         "per-endpoint batch_*.json count == state.json done_batches length"),
        ("batch_counts_pilot_baseline", lambda w, s: _pep_screen_baseline_ok(w),
         "batch counts hit the pilot baseline (bioactivity 1667 / amp 500 / phychem 500)"),
        ("no_unrecovered_batch_errors", lambda w, s: _pep_screen_error_count(w) == 0,
         "no unrecovered batch_*.error files in any endpoint dir"),
    ],
    "47_pep_smorf_nn": [
        ("nn_done_sentinel", lambda w, s: os.path.isfile(f"{w}/result/peptide/nn/nn.done"),
         "nn.done sentinel exists"),
        ("cursor_at_pilot_target", lambda w, s: _pep_nn_cursor(w) == 5000,
         "nn_cursor.txt == 5000 (pilot target, closure G4)"),
        ("nn_results_row_count", lambda w, s: _tsv_data_rows(f"{w}/result/peptide/nn/nn_results.tsv") == 15000,
         "nn_results.tsv has 15000 data rows + header (5000 queries x 3 hits)"),
        ("no_err_rows", lambda w, s: _pep_nn_err_rows(w) == 0,
         "no ERR rows in nn_results.tsv (col2 != ERR)"),
    ],
    "49a_pep_antismash_harvest": [
        ("antismash_done_sentinel", lambda w, s: os.path.isfile(f"{w}/result/peptide/broute/broute_antismash.done"),
         "broute_antismash.done sentinel exists"),
        ("precursor_tsv_faa_closure", lambda w, s: 0 < count_tsv_data_rows(f"{w}/result/peptide/broute/antismash_precursors.tsv")
         == count_fasta_headers(f"{w}/result/peptide/broute/antismash_precursors.faa"),
         "antismash_precursors.tsv rows == antismash_precursors.faa headers"),
        ("precursor_aa_alphabet", lambda w, s: _pep_aa_bad_chars(f"{w}/result/peptide/broute/antismash_precursors.faa") == 0,
         "precursor FAA has no non-canonical AA chars (* excluded from violations)"),
    ],
    "49b_pep_macrel": [
        ("macrel_done_sentinel", lambda w, s: os.path.isfile(f"{w}/result/peptide/broute/macrel.done"),
         "macrel.done sentinel exists"),
        ("candidate_ids_unique", lambda w, s: _pep_macrel_audit(w)["rows_unique_ok"],
         "macrel_precursors.tsv rows > 0 and peptide_id unique"),
        ("candidates_traced_to_raw_faa", lambda w, s: _pep_macrel_audit(w)["ids_in_raw_faa"],
         "every candidate peptide_id exists in macrel_raw/macrel.out.smorfs.faa "
         "(macrel emits no curated FAA; candidates are a subset of the raw scan)"),
        ("macrel_aa_alphabet", lambda w, s: _pep_macrel_audit(w)["alphabet_ok"],
         "candidate sequence column and raw smorfs FAA have no non-canonical AA chars (* excluded)"),
    ],
    "50_pep_smorf_integrate": [
        ("integration_nine_files", lambda w, s: _pep_integration_files_ok(w),
         "all 9 integration files present (7 data TSVs + qc_summary.md + integrate.done)"),
        ("peptide_main_pk_unique", lambda w, s: _pep_pk_unique(f"{w}/result/peptide/integration/peptide_main.tsv"),
         "peptide_main.tsv peptide_id primary key is non-empty and unique"),
        ("candidate_evidence_contract", lambda w, s: _pep_candidate_evidence_ok(w),
         "candidate_evidence.tsv contract points hold when present (candidate_id unique, "
         "source_tool in {antismash,macrel}, remap_status in 5-state set, evidence_type mapping; "
         "49c is stage-2 so absence passes)"),
        ("nn_status_full_coverage", lambda w, s: _pep_nn_status_ok(w),
         "nn_status.tsv has 450320 unique keys, all values in the 6-state vocabulary, "
         "and queried_complete_representative count == pilot cursor"),
        ("bioactivity_has_unfiltered_rows", lambda w, s: _pep_filter_usable_false_rows(w) > 0,
         "bioactivity_predictions.tsv keeps filter_usable=false model rows (contract point 5)"),
        ("prediction_rows_match_pilot", lambda w, s: _pep_prediction_rows_match_pilot(w),
         "amp/phychem rows == cursor, nn_hits distinct queries == cursor, "
         "peptide_main rows == pilot5000.faa headers (counts consistent with batch products)"),
    ],
}


def _tsv_data_rows(path):
    """Non-empty data rows in a TSV (header assumed)."""
    return count_tsv_data_rows(path)


def _drep_count_closed(w):
    try:
        genomes = len(list(Path(f"{w}/result/binning/drep/dereplicated_genomes").glob("*.fa")))
        clusters = set()
        for line in open(f"{w}/result/binning/drep/data_tables/Cdb.csv"):
            p = line.rstrip("\n").split(",")
            if len(p) > 1 and p[0] != "genome":
                clusters.add(p[1])
        return genomes == len(clusters) and genomes > 0
    except Exception:
        return False


def _gtdbtk_count_closed(w):
    try:
        rows = _tsv_data_rows(f"{w}/result/binning/gtdbtk/gtdbtk.bac120.summary.tsv")
        genomes = len(list(Path(f"{w}/result/binning/drep/dereplicated_genomes").glob("*.fa")))
        return rows == genomes and rows > 0
    except Exception:
        return False


def _phf_cluster_closed(w):
    try:
        merged = count_tsv_data_rows(f"{w}/result/fungi/phf_profiler/merged_abundance.tsv")
        clusters = set()
        for rc in Path(f"{w}/result/fungi/phf_profiler").glob("*/*.rc"):
            for line in open(rc):
                if line.startswith("#") or not line.strip():
                    continue
                cid = line.split("\t")[0]
                if cid:
                    clusters.add(cid)
        return merged == len(clusters) and merged > 0
    except Exception:
        return False


def _votu_join_closed(w):
    try:
        stats = {}
        for line in open(f"{w}/result/virus/votu/table/votu_join_stats.tsv"):
            p = line.rstrip("\n").split("\t")
            if len(p) == 2:
                stats[p[0]] = p[1]
        reps = count_tsv_data_rows(f"{w}/result/virus/votu/votu_representatives.tsv", skip_header=False)
        return (int(stats.get("failed_contig_rows", -1)) == 0
                and int(stats.get("canonical_votus", -1)) == reps > 0)
    except Exception:
        return False


def _votu_tpm_sums_ok(w):
    try:
        with open(f"{w}/result/virus/votu/votu_table.tsv") as f:
            header = f.readline().rstrip("\n").split("\t")
            tpm_idx = [i for i, c in enumerate(header) if c.endswith("_tpm")]
            sums = [0.0] * len(tpm_idx)
            for line in f:
                p = line.rstrip("\n").split("\t")
                for k, i in enumerate(tpm_idx):
                    try:
                        sums[k] += float(p[i])
                    except (ValueError, IndexError):
                        pass
        return bool(tpm_idx) and all(abs(s - 1e6) < 1.0 for s in sums)
    except Exception:
        return False


def _votu_columns_ok(w):
    try:
        header = open(f"{w}/result/virus/votu/votu_table.tsv").readline().rstrip("\n").split("\t")
        if header[:2] != ["votu", "length"]:
            return False
        mid = header[2:]
        if mid and mid[-1] in ("lineage", "annotation_status"):
            mid = mid[:-2] if mid[-2:-1] == ["lineage"] or (len(mid) >= 2 and mid[-2] == "lineage") else mid
        return all(c.endswith("_tpm") or c.endswith("_count") for c in mid)
    except Exception:
        return False



def _eggnog_id_provenance(w):
    """Every eggNOG query ID must be from protein_nr.fa."""
    try:
        prot_ids = set()
        for line in open(f"{w}/result/assembly/cdhit/protein_nr.fa"):
            if line.startswith('>'):
                prot_ids.add(line[1:].split()[0])
        eggnog_ids = set()
        for line in open(f"{w}/result/annotation/eggnog/eggnog.emapper.annotations", encoding='utf-8', errors='replace'):
            if not line.startswith('#') and line.strip():
                eggnog_ids.add(line.split('\t')[0])
        return eggnog_ids.issubset(prot_ids)
    except Exception:
        return False


def _protein_lt_nuc(w):
    """Protein catalog should be ≤ nucleotide catalog count."""
    try:
        nuc = count_fasta_headers(f"{w}/result/assembly/cdhit/nucleotide_nr.fa")
        prot = count_fasta_headers(f"{w}/result/assembly/cdhit/protein_nr.fa")
        return 0 < prot <= nuc
    except Exception:
        return False


def _salmon_rows_consistent(w):
    """All salmon quant.sf files should have the same number of transcripts."""
    try:
        counts = set()
        for sid in _get_samples(w):
            n = count_tsv_data_rows(f"{w}/result/assembly/salmon/{sid}/quant.sf", skip_header=True)
            counts.add(n)
        return len(counts) == 1 and counts.pop() > 0
    except Exception:
        return False


def _get_samples(w):
    """Dynamically load sample IDs from metadata.csv or samples.txt."""
    import csv as _csv
    meta = os.path.join(w, "metadata.csv")
    if os.path.isfile(meta):
        with open(meta) as f:
            r = _csv.DictReader(f)
            col = "sample_id" if "sample_id" in r.fieldnames else r.fieldnames[0]
            return [row[col] for row in r]
    samples_txt = os.path.join(w, "samples.txt")
    if os.path.isfile(samples_txt):
        return [l.strip() for l in open(samples_txt) if l.strip()]
    return []

def _first_ncols_ok(path, ncols):
    """First data line of a TSV has exactly ncols tab-separated columns."""
    try:
        with open(path) as f:
            for line in f:
                if line.strip():
                    return len(line.rstrip("\n").split("\t")) == ncols
    except Exception:
        pass
    return False


def _dastool_ids_consistent(w, s):
    """All contigs inside extracted bins are declared in the contig2bin table."""
    c2b_path = f"{w}/result/binning/dastool/{s}/{s}_DASTool_contig2bin.tsv"
    bins_dir = Path(f"{w}/result/binning/dastool/{s}/{s}_DASTool_bins")
    if not os.path.isfile(c2b_path) or not bins_dir.is_dir():
        return False
    declared = set()
    with open(c2b_path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if parts:
                declared.add(parts[0])
    for fa in bins_dir.glob("*.fa"):
        with open(fa) as f:
            for line in f:
                if line.startswith(">"):
                    cid = line[1:].split()[0] if line[1:].split() else ""
                    if cid and cid not in declared:
                        return False
    return bool(declared)


# ── Peptide branch (44-50) helpers. Frozen pilot baselines follow
#    docs/plans/peptide_contract.md and docs/plans/peptide_phase1_closure.md.
#    All checks are local file reads only (no API/network calls).
_PEP_SMORF_SAMPLES = tuple(f"Harbin{n}" for n in (1, 2, 3, 4, 10, 11))  # real pilot sample IDs
_PEP_SMORF_PARTIAL_WHITELIST = {"complete", "partial_g3", "partial_g5", "partial_both"}
_PEP_SMORF_LEN_MIN, _PEP_SMORF_LEN_MAX = 20, 99
_PEP_SCREEN_ENDPOINTS = ("bioactivity", "amp", "phychem")
_PEP_SCREEN_BATCH_BASELINE = {"bioactivity": 1667, "amp": 500, "phychem": 500}
_PEP_NN_STATUS_TOTAL = 450320  # contract point 6: full-candidate coverage
_PEP_NN_STATUS_STATES = {
    "queried_complete_representative", "error", "not_in_tier_tables",
    "not_queried_outside_pilot", "not_queried_representative_mapped",
    "not_queried_partial_policy",
}
_PEP_REMAP_STATES = {"exact_mapped", "contained_mapped", "ambiguous",
                     "unmapped_only_candidate", "not_attempted"}
_PEP_EVIDENCE_BY_TOOL = {"macrel": "model_prediction", "antismash": "annotation_rule"}
_PEP_INTEGRATION_TSVS = ("peptide_main.tsv", "bioactivity_predictions.tsv",
                         "amp_predictions.tsv", "phychem_properties.tsv",
                         "nn_hits.tsv", "nn_status.tsv", "abundance.tsv")


def _pep_smorf_audit(w):
    """One pass over the 6 smorf TSVs: row counts, length bounds, partial values."""
    audit = {"samples": {}, "bad_len": 0, "bad_partial": 0, "total_tsv": 0}
    for sid in _PEP_SMORF_SAMPLES:
        tsv = f"{w}/result/peptide/smorf/{sid}.smorf.tsv"
        if not os.path.isfile(tsv):
            return None
        rows = bad_len = bad_partial = 0
        try:
            with open(tsv) as f:
                next(f)  # header: gene_id contig_id start end strand partial length_aa ...
                for line in f:
                    if not line.strip():
                        continue
                    p = line.rstrip("\n").split("\t")
                    if len(p) < 7:
                        return None
                    rows += 1
                    try:
                        n = int(p[6])
                    except ValueError:
                        return None
                    if not (_PEP_SMORF_LEN_MIN <= n <= _PEP_SMORF_LEN_MAX):
                        bad_len += 1
                    if p[5] not in _PEP_SMORF_PARTIAL_WHITELIST:
                        bad_partial += 1
        except Exception:
            return None
        audit["samples"][sid] = rows
        audit["total_tsv"] += rows
        audit["bad_len"] += bad_len
        audit["bad_partial"] += bad_partial
    return audit


def _pep_smorf_bad(kind, w):
    audit = _pep_smorf_audit(w)
    return -1 if audit is None else audit[f"bad_{kind}"]


def _pep_smorf_counts_closed(w):
    """Per-sample TSV data rows == per-sample FAA headers, total > 0."""
    audit = _pep_smorf_audit(w)
    if audit is None or audit["total_tsv"] == 0:
        return False
    for sid, rows in audit["samples"].items():
        faa_n = count_fasta_headers(f"{w}/result/peptide/smorf/{sid}.smorf.faa")
        if faa_n != rows:
            return False
    return True


def _pep_smorf_stats_ok(w):
    """stats.md carries all 6 sample rows and its total equals summed TSV rows."""
    audit = _pep_smorf_audit(w)
    if audit is None:
        return False
    path = f"{w}/result/peptide/smorf/smorf_catalog.stats.md"
    if not os.path.isfile(path):
        return False
    try:
        text = open(path).read()
    except Exception:
        return False
    for sid in _PEP_SMORF_SAMPLES:
        if f"| {sid} " not in text:
            return False
    for line in text.splitlines():
        if "合计" in line:
            m = [t.strip("*| ") for t in line.split("|")]
            nums = [t for t in m if t.isdigit()]
            return bool(nums) and int(nums[0]) == audit["total_tsv"]
    return False


def _pep_registry(w):
    """Parsed refs/registry.json, or None on missing/invalid JSON."""
    path = f"{w}/result/peptide/refs/registry.json"
    if not os.path.isfile(path):
        return None
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def _pep_screen_audit(w):
    """Per-endpoint batch file count, state.json cursor length, error file count."""
    base = f"{w}/result/peptide/screen"
    state_path = f"{base}/state.json"
    if not os.path.isfile(state_path):
        return None
    try:
        with open(state_path) as f:
            state = json.load(f)
    except Exception:
        return None
    audit = {}
    for ep in _PEP_SCREEN_ENDPOINTS:
        ep_dir = f"{base}/{ep}"
        if not os.path.isdir(ep_dir) or not isinstance(state.get(ep), dict):
            return None
        audit[ep] = {
            "files": len(list(Path(ep_dir).glob("batch_*.json"))),
            "state": len(state[ep].get("done_batches", [])),
            "errors": len(list(Path(ep_dir).glob("batch_*.error"))),
        }
    return audit


def _pep_screen_state_closed(w):
    audit = _pep_screen_audit(w)
    return bool(audit) and all(v["files"] == v["state"] > 0 for v in audit.values())


def _pep_screen_baseline_ok(w):
    audit = _pep_screen_audit(w)
    return bool(audit) and all(v["files"] == _PEP_SCREEN_BATCH_BASELINE[ep]
                               for ep, v in audit.items())


def _pep_screen_error_count(w):
    audit = _pep_screen_audit(w)
    return -1 if audit is None else sum(v["errors"] for v in audit.values())


def _pep_nn_cursor(w):
    path = f"{w}/result/peptide/nn/nn_cursor.txt"
    try:
        return int(open(path).read().strip())
    except Exception:
        return -1


def _pep_nn_err_rows(w):
    """Count nn_results.tsv rows whose col2 == ERR (47 writer failure marker)."""
    path = f"{w}/result/peptide/nn/nn_results.tsv"
    if not os.path.isfile(path):
        return -1
    errs = 0
    try:
        with open(path) as f:
            next(f)
            for line in f:
                if line.strip() and line.rstrip("\n").split("\t")[1] == "ERR":
                    errs += 1
    except Exception:
        return -1
    return errs


_AA_CANONICAL = set("ACDEFGHIKLMNPQRSTVWY")


def _pep_aa_bad_chars(path):
    """Non-canonical AA characters in a FASTA, excluding '*'. -1 if unreadable."""
    if not os.path.isfile(path):
        return -1
    bad = 0
    try:
        with open(path) as f:
            for line in f:
                if line.startswith(">"):
                    continue
                bad += sum(1 for c in line.strip() if c != "*" and c not in _AA_CANONICAL)
    except Exception:
        return -1
    return bad


def _pep_macrel_audit(w):
    """Macrel candidate table consistency against the raw smorfs FAA.

    macrel emits no curated candidate FAA (unlike antiSMASH), so closure is:
    candidate TSV rows are unique and every peptide_id appears in the raw scan.
    """
    audit = {"rows_unique_ok": False, "ids_in_raw_faa": False, "alphabet_ok": False}
    tsv = f"{w}/result/peptide/broute/macrel_precursors.tsv"
    raw_faa = f"{w}/result/peptide/broute/macrel_raw/macrel.out.smorfs.faa"
    if not os.path.isfile(tsv) or not os.path.isfile(raw_faa):
        return audit
    ids, bad_chars = [], 0
    try:
        with open(tsv) as f:
            header = f.readline().rstrip("\n").split("\t")
            seq_idx = header.index("sequence") if "sequence" in header else -1
            id_idx = header.index("peptide_id") if "peptide_id" in header else -1
            if id_idx < 0:
                return audit
            for line in f:
                if not line.strip():
                    continue
                p = line.rstrip("\n").split("\t")
                if len(p) <= id_idx:
                    return audit
                ids.append(p[id_idx])
                if seq_idx >= 0 and len(p) > seq_idx:
                    bad_chars += sum(1 for c in p[seq_idx]
                                     if c != "*" and c not in _AA_CANONICAL)
    except Exception:
        return audit
    audit["rows_unique_ok"] = len(ids) > 0 and len(set(ids)) == len(ids)
    raw_ids = set()
    try:
        with open(raw_faa) as f:
            for line in f:
                if line.startswith(">"):
                    raw_ids.add(line[1:].split()[0])
    except Exception:
        return audit
    audit["ids_in_raw_faa"] = set(ids).issubset(raw_ids)
    audit["alphabet_ok"] = bad_chars == 0 and _pep_aa_bad_chars(raw_faa) == 0
    return audit


def _pep_integration_files_ok(w):
    """Nine-file baseline: 7 data TSVs + qc_summary.md non-empty, sentinel exists."""
    out = f"{w}/result/peptide/integration"
    for fn in _PEP_INTEGRATION_TSVS:
        if not os.path.isfile(f"{out}/{fn}") or os.path.getsize(f"{out}/{fn}") == 0:
            return False
    qc = f"{out}/qc_summary.md"
    return os.path.isfile(qc) and os.path.getsize(qc) > 0 \
        and os.path.isfile(f"{out}/integrate.done")


def _pep_pk_unique(path):
    """First column (primary key) is non-empty and unique across data rows."""
    if not os.path.isfile(path):
        return False
    ids = []
    try:
        with open(path) as f:
            next(f)
            for line in f:
                if not line.strip():
                    continue
                pk = line.rstrip("\n").split("\t")[0]
                if not pk:
                    return False
                ids.append(pk)
    except Exception:
        return False
    return len(ids) > 0 and len(set(ids)) == len(ids)


def _pep_candidate_evidence_ok(w):
    """Contract points for candidate_evidence.tsv (49c, stage-2).

    Absence passes (phase-1 pilot scope); when present, enforce: candidate_id
    non-empty and unique, source_tool in {antismash, macrel}, remap_status in
    the 5-state set, evidence_type consistent with source_tool.
    """
    path = f"{w}/result/peptide/integration/candidate_evidence.tsv"
    if not os.path.isfile(path):
        return True
    need = ("candidate_id", "source_tool", "remap_status", "evidence_type")
    ids = []
    try:
        with open(path) as f:
            header = f.readline().rstrip("\n").split("\t")
            idx = {c: i for i, c in enumerate(header)}
            if not all(c in idx for c in need):
                return False
            for line in f:
                if not line.strip():
                    continue
                p = line.rstrip("\n").split("\t")
                if len(p) < len(header):
                    return False
                cid = p[idx["candidate_id"]]
                if not cid:
                    return False
                ids.append(cid)
                tool = p[idx["source_tool"]]
                if tool not in _PEP_EVIDENCE_BY_TOOL:
                    return False
                if p[idx["remap_status"]] not in _PEP_REMAP_STATES:
                    return False
                if p[idx["evidence_type"]] != _PEP_EVIDENCE_BY_TOOL[tool]:
                    return False
    except Exception:
        return False
    return len(ids) > 0 and len(set(ids)) == len(ids)


def _pep_nn_status_ok(w):
    """450320 unique keys, 6-state vocabulary only, queried count == cursor."""
    path = f"{w}/result/peptide/integration/nn_status.tsv"
    if not os.path.isfile(path):
        return False
    keys, states = set(), {}
    try:
        with open(path) as f:
            next(f)
            for line in f:
                if not line.strip():
                    continue
                p = line.rstrip("\n").split("\t")
                if len(p) < 2:
                    return False
                keys.add(p[0])
                states[p[1]] = states.get(p[1], 0) + 1
    except Exception:
        return False
    if len(keys) != _PEP_NN_STATUS_TOTAL or not set(states) <= _PEP_NN_STATUS_STATES:
        return False
    return states.get("queried_complete_representative", 0) == _pep_nn_cursor(w)


def _pep_filter_usable_false_rows(w):
    """Rows in bioactivity_predictions.tsv with filter_usable=false (contract pt 5)."""
    path = f"{w}/result/peptide/integration/bioactivity_predictions.tsv"
    if not os.path.isfile(path):
        return -1
    try:
        with open(path) as f:
            header = f.readline().rstrip("\n").split("\t")
            if "filter_usable" not in header:
                return -1
            col = header.index("filter_usable")
            n = 0
            for line in f:
                p = line.rstrip("\n").split("\t")
                if len(p) > col and p[col] == "false":
                    n += 1
    except Exception:
        return -1
    return n


def _pep_prediction_rows_match_pilot(w):
    """Integration row counts are consistent with batch/pilot products.

    amp/phychem carry one row per pilot candidate (== cursor), nn_hits covers
    every pilot query, peptide_main rows == pilot5000.faa headers.
    """
    out = f"{w}/result/peptide/integration"
    cursor = _pep_nn_cursor(w)
    if cursor <= 0:
        return False
    if _tsv_data_rows(f"{out}/amp_predictions.tsv") != cursor:
        return False
    if _tsv_data_rows(f"{out}/phychem_properties.tsv") != cursor:
        return False
    hits_path = f"{out}/nn_hits.tsv"
    if not os.path.isfile(hits_path):
        return False
    try:
        queries = {line.split("\t", 1)[0] for line in open(hits_path).readlines()[1:]
                   if line.strip()}
    except Exception:
        return False
    if len(queries) != cursor:
        return False
    main_rows = _tsv_data_rows(f"{out}/peptide_main.tsv")
    pilot_headers = count_fasta_headers(f"{w}/result/peptide/cluster_test/pilot5000.faa")
    return main_rows == pilot_headers > 0


def validate(step_id, sample, workdir, repo):
    """Run validation checks for a step. Returns (passed, results)."""
    rules = VALIDATION_RULES.get(step_id)
    if rules is None:
        # review 18th B1: unknown step -> UNVERIFIED, not PASS
        # (an empty _default that returns PASS is a false positive for AI consumers)
        return False, [{"check": "_rules", "passed": False,
                        "description": "no validation rules registered for this step"}], "UNVERIFIED"
    results = []
    all_passed = True

    for check_name, check_fn, description in rules:
        try:
            passed = bool(check_fn(workdir, sample))
        except Exception as e:
            passed = False
            description = f"{description} (error: {e})"
        results.append({
            "check": check_name,
            "passed": passed,
            "description": description,
        })
        if not passed:
            all_passed = False

    return all_passed, results, "PASS" if all_passed else "FAIL"


def main():
    parser = argparse.ArgumentParser(description="Validate step correctness (not just completion)")
    parser.add_argument("step_id", help="Step ID (e.g., 01_qc_fastp)")
    parser.add_argument("sample", help="Sample ID (or 'all' for aggregate steps)")
    parser.add_argument("workdir", help="Project workdir")
    parser.add_argument("--repo", default=None, help="Repository root")
    args = parser.parse_args()

    workdir = os.path.abspath(args.workdir)
    repo = os.path.abspath(args.repo) if args.repo else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    passed, results, verdict_str = validate(args.step_id, args.sample, workdir, repo)

    # Output JSON verdict
    verdict = {
        "step_id": args.step_id,
        "verdict_type": verdict_str,
        "sample": args.sample,
        "workdir": workdir,
        "timestamp": __import__("time").strftime("%Y-%m-%dT%H:%M:%S%z"),
        "verdict": "PASS" if passed else "FAIL",
        "checks": results,
    }
    print(json.dumps(verdict, indent=2))

    # Write to validation log (append)
    val_log = os.path.join(workdir, "logs", "validation_log.jsonl")
    os.makedirs(os.path.dirname(val_log), exist_ok=True)
    with open(val_log, "a") as f:
        f.write(json.dumps(verdict) + "\n")

    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
