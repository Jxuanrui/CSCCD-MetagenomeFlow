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
        ("diamond_rows", lambda w, s: count_tsv_data_rows(f"{w}/result/annotation/kegg/kegg_diamond.tsv", skip_header=False) > 1000,
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


def validate(step_id, sample, workdir, repo):
    """Run validation checks for a step. Returns (passed, results)."""
    rules = VALIDATION_RULES.get(step_id, VALIDATION_RULES["_default"])
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

    return all_passed, results


def main():
    parser = argparse.ArgumentParser(description="Validate step correctness (not just completion)")
    parser.add_argument("step_id", help="Step ID (e.g., 01_qc_fastp)")
    parser.add_argument("sample", help="Sample ID (or 'all' for aggregate steps)")
    parser.add_argument("workdir", help="Project workdir")
    parser.add_argument("--repo", default=None, help="Repository root")
    args = parser.parse_args()

    workdir = os.path.abspath(args.workdir)
    repo = os.path.abspath(args.repo) if args.repo else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    passed, results = validate(args.step_id, args.sample, workdir, repo)

    # Output JSON verdict
    verdict = {
        "step_id": args.step_id,
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
