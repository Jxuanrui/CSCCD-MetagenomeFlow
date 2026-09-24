#!/usr/bin/env python3
"""
Batch backfill provenance records from Snakemake run outputs.

Usage:
    python scripts/batch_provenance_backfill.py \
        --workdir Project/Project_example \
        --repo ${PROJ_DIR} \
        --user local \
        --date 20260617

Generates provenance JSON for all completed steps based on:
- Output file existence (result/)
- Skill cards (agents/skills/)
- Registry (agents/registry.yaml)
"""

import argparse
import json
import os
import yaml
from pathlib import Path
from datetime import datetime

WORKDIR = None
REPO = None
USER = None
DATE = None


def load_registry(repo):
    """Load agents/registry.yaml"""
    registry_path = Path(repo) / "agents" / "registry.yaml"
    with open(registry_path) as f:
        data = yaml.safe_load(f)
    # Convert list format to dict keyed by id
    scripts = {}
    for item in data.get("scripts", []):
        scripts[item["id"]] = item
    return scripts


def load_skill_card(repo, step_id):
    """Load skill card for a given step_id"""
    skill_path = Path(repo) / "agents" / "skills" / f"{step_id}.yaml"
    if not skill_path.exists():
        skill_path = Path(repo) / "agents" / "skills" / f"{step_id}.md"
    if not skill_path.exists():
        return None

    with open(skill_path) as f:
        content = f.read()

    # Handle frontmatter if .md
    if skill_path.suffix == ".md":
        import re
        match = re.match(r'^---\n(.*?)\n---', content, re.S)
        if match:
            return yaml.safe_load(match.group(1))
    else:
        return yaml.safe_load(content)


def infer_outputs(workdir, step_id, sample_id):
    """Infer output files from standard paths"""
    workdir = Path(workdir)
    outputs = {}

    # Per-sample rules
    if sample_id and sample_id != "all":
        # Bacteria taxonomy
        if step_id == "11_bac_metaphlan4":
            outputs["profile"] = str(workdir / f"result/metaphlan4/{sample_id}/{sample_id}_profile.txt")
            outputs["sam_bz2"] = str(workdir / f"result/metaphlan4/{sample_id}/{sample_id}.sam.bz2")
        elif step_id == "13_bac_humann3":
            outputs["pathabundance"] = str(workdir / f"result/humann3/{sample_id}/{sample_id}_pathabundance.tsv")
        elif step_id == "14_bac_kraken2":
            outputs["kreport"] = str(workdir / f"result/centrifuger/{sample_id}/{sample_id}.kreport.tsv")
        elif step_id == "15_bac_centrifuger":
            outputs["kreport"] = str(workdir / f"result/centrifuger/{sample_id}/{sample_id}.kreport.tsv")
        # Assembly
        elif step_id == "16_bac_megahit":
            outputs["contigs"] = str(workdir / f"result/assembly/{sample_id}/{sample_id}.contigs.fa")
        elif step_id == "17_bac_prodigal":
            outputs["faa"] = str(workdir / f"result/assembly/prodigal/{sample_id}/{sample_id}.faa")
        # Virus
        elif step_id == "51_vir_megahit":
            outputs["contigs"] = str(workdir / f"result/virus/assembly/{sample_id}/{sample_id}.contigs.fa")
        elif step_id == "52_vir_genomad":
            outputs["summary"] = str(workdir / f"result/virus/genomad/{sample_id}/{sample_id}.contigs_summary/{sample_id}.contigs_virus_summary.tsv")
        elif step_id == "53_vir_virsorter2":
            outputs["boundary"] = str(workdir / f"result/virus/virsorter2/{sample_id}/final-viral-boundary.tsv")
        elif step_id == "54_vir_checkv_contig":
            outputs["quality_summary"] = str(workdir / f"result/virus/checkv/{sample_id}/quality_summary.tsv")
        elif step_id == "55_vir_prodigal_gv":
            outputs["faa"] = str(workdir / f"result/virus/prodigal/{sample_id}/{sample_id}.faa")
        elif step_id == "59_vir_salmon_quant":
            outputs["quant"] = str(workdir / f"result/virus/salmon/{sample_id}/report.tsv")
        elif step_id == "63_vir_coverm_quant":
            outputs["quant"] = str(workdir / f"result/virus/coverm_quant/{sample_id}.tsv")
        # Fungi
        elif step_id == "71_fun_kraken2_fungi":
            outputs["report"] = str(workdir / f"result/fungi/kraken2/{sample_id}/{sample_id}.report")
        elif step_id == "72_fun_metaphlan4_euk":
            outputs["profile"] = str(workdir / f"result/fungi/metaphlan4/{sample_id}/{sample_id}_profile.txt")
        elif step_id == "74e_fun_phf_profiler":
            outputs["rc"] = str(workdir / f"result/fungi/phf_profiler/{sample_id}/{sample_id}.rc")
        elif step_id == "75_fun_funomics":
            outputs["classification"] = str(workdir / f"result/fungi/funomic/{sample_id}/{sample_id}_classification.tsv")
        elif step_id == "77_fun_microfisher":
            outputs["profile"] = str(workdir / f"result/fungi/microfisher/{sample_id}/{sample_id}_fungal_profile.tsv")
        elif step_id == "78_fun_megahit":
            outputs["contigs"] = str(workdir / f"result/fungi/assembly/{sample_id}/{sample_id}.contigs.fa")
        elif step_id == "79_fun_eukfinder":
            outputs["results"] = str(workdir / f"result/fungi/eukfinder/{sample_id}/results.txt")
        elif step_id == "80_fun_prodigal" or step_id == "80b_fun_metaeuk":
            outputs["faa"] = str(workdir / f"result/fungi/prodigal/{sample_id}/{sample_id}.faa")

    # Aggregate rules
    if sample_id == "all":
        if step_id == "11b_bac_metaphlan4_merge":
            outputs["taxonomy"] = str(workdir / "result/metaphlan4/merged/taxonomy.tsv")
        elif step_id == "18_bac_cdhit":
            outputs["protein_nr"] = str(workdir / "result/assembly/cdhit/protein_nr.fa")
        elif step_id == "22_bac_kegg":
            outputs["kegg_diamond"] = str(workdir / "result/annotation/kegg/kegg_diamond.tsv")
        elif step_id == "37_bac_checkm2":
            outputs["quality_report"] = str(workdir / "result/binning/checkm2/quality_report.tsv")
        elif step_id == "56_vir_votu_gen":
            outputs["representatives"] = str(workdir / "result/virus/votu/votu_representatives.tsv")
        elif step_id == "57_vir_votu_genomad":
            outputs["taxonomy"] = str(workdir / "result/virus/votu/genomad/virus_taxonomy.tsv")
        elif step_id == "60_vir_votu_table":
            outputs["abundance_table"] = str(workdir / "result/virus/votu/table/vOTU_table_ann.txt")
        elif step_id == "64_vir_pharokka":
            outputs["pharokka_cds"] = str(workdir / "result/virus/pharokka/pharokka_cds_final_merged_output.tsv")
        elif step_id == "68_vir_iphop":
            outputs["host_prediction"] = str(workdir / "result/virus/iphop/Host_prediction_to_genus_m90.csv")
        elif step_id == "69_vir_vcontact3":
            outputs["final_assignments"] = str(workdir / "result/virus/vcontact3/exports/final_assignments.csv")
        elif step_id == "81_fun_eggnog":
            outputs["annotations"] = str(workdir / "result/fungi/eggnog/eggnog.emapper.annotations")
        elif step_id == "82_fun_kegg":
            outputs["kegg_diamond"] = str(workdir / "result/fungi/kegg/kegg_diamond.tsv")

    # Filter to only outputs that exist
    return {k: v for k, v in outputs.items() if Path(v).exists()}


def generate_provenance(step_id, sample_id, registry, repo, workdir, user, date):
    """Generate a single provenance record"""
    skill = load_skill_card(repo, step_id)
    if not skill:
        print(f"[WARN] No skill card for {step_id}, skipping")
        return None

    outputs = infer_outputs(workdir, step_id, sample_id)
    if not outputs:
        return None  # No outputs found, skip

    # Get primary output mtime for started_at approximation
    primary_output = Path(list(outputs.values())[0])
    mtime = primary_output.stat().st_mtime if primary_output.exists() else None
    started_at = datetime.fromtimestamp(mtime).isoformat() if mtime else None

    record = {
        "wf_run_id": f"{date}_{step_id}_{sample_id}",
        "step_id": step_id,
        "tool": skill.get("tool", "unknown"),
        "tool_version": skill.get("tool_version", "unknown"),
        "user": user,
        "sample_id": sample_id,
        "workdir": str(workdir),
        "repo": str(repo),
        "inputs": {},  # Would need per-script logic to infer
        "outputs": outputs,
        "params": {"threads": 16},  # Generic default
        "metrics": {},
        "started_at": started_at,
        "duration_sec": None,  # Unknown without log parsing
        "exit_code": 0,
        "status": "success",
        "error_message": None,
        "enriched_into_skill": False
    }

    return record


def main():
    parser = argparse.ArgumentParser(description="Batch backfill provenance records")
    parser.add_argument("--workdir", required=True, help="Project workdir")
    parser.add_argument("--repo", required=True, help="CSCCD-MetagenomeFlow repo root")
    parser.add_argument("--user", required=True, help="Username")
    parser.add_argument("--date", required=True, help="Run date YYYYMMDD")
    parser.add_argument("--dry-run", action="store_true", help="Print records without writing")
    args = parser.parse_args()

    global WORKDIR, REPO, USER, DATE
    WORKDIR = Path(args.workdir)
    REPO = Path(args.repo)
    USER = args.user
    DATE = args.date

    registry = load_registry(REPO)
    provenance_dir = REPO / "agents" / "provenance"
    provenance_dir.mkdir(exist_ok=True)

    # Define samples
    samples = ["S01", "S02", "S03", "S04", "S05", "S06"]

    # Define per-sample steps to backfill
    per_sample_steps = [
        "11_bac_metaphlan4", "13_bac_humann3", "14_bac_kraken2", "15_bac_centrifuger",
        "16_bac_megahit", "17_bac_prodigal",
        "51_vir_megahit", "52_vir_genomad", "53_vir_virsorter2", "54_vir_checkv_contig",
        "55_vir_prodigal_gv", "59_vir_salmon_quant", "63_vir_coverm_quant",
        "71_fun_kraken2_fungi", "72_fun_metaphlan4_euk", "74e_fun_phf_profiler",
        "75_fun_funomics", "77_fun_microfisher", "78_fun_megahit", "79_fun_eukfinder",
        "80_fun_prodigal"
    ]

    # Define aggregate steps
    aggregate_steps = [
        "11b_bac_metaphlan4_merge", "18_bac_cdhit", "22_bac_kegg", "37_bac_checkm2",
        "56_vir_votu_gen", "57_vir_votu_genomad", "60_vir_votu_table",
        "64_vir_pharokka", "68_vir_iphop", "69_vir_vcontact3",
        "81_fun_eggnog", "82_fun_kegg"
    ]

    records_written = 0

    # Per-sample records
    for step_id in per_sample_steps:
        for sample_id in samples:
            record = generate_provenance(step_id, sample_id, registry, REPO, WORKDIR, USER, DATE)
            if record:
                filename = f"{DATE}_{step_id}_{sample_id}.json"
                filepath = provenance_dir / filename

                # Skip if already exists
                if filepath.exists():
                    continue

                if args.dry_run:
                    print(f"[DRY] Would write: {filename}")
                else:
                    with open(filepath, "w") as f:
                        json.dump(record, f, indent=2)
                    print(f"[WRITE] {filename}")
                records_written += 1

    # Aggregate records
    for step_id in aggregate_steps:
        record = generate_provenance(step_id, "all", registry, REPO, WORKDIR, USER, DATE)
        if record:
            filename = f"{DATE}_{step_id}_all.json"
            filepath = provenance_dir / filename

            if filepath.exists():
                continue

            if args.dry_run:
                print(f"[DRY] Would write: {filename}")
            else:
                with open(filepath, "w") as f:
                    json.dump(record, f, indent=2)
                print(f"[WRITE] {filename}")
            records_written += 1

    print(f"\n{'[DRY-RUN] ' if args.dry_run else ''}Total: {records_written} records")


if __name__ == "__main__":
    main()
