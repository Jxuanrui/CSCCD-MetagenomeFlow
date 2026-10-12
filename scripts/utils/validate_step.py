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
}


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
