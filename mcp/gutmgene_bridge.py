# Task 3 bridge output consumed by the future mechanism_kb indexer (Task 4).

import argparse
import csv
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests


MICROBE_METABOLITE_FIELDS = [
    ("gut_microbiota", "Gut Microbiota"),
    ("ncbi_id", "Gut Microbiota NCBI ID"),
    ("rank", "Rank"),
    ("strain", "Strain"),
    ("substrate", "Substrate"),
    ("substrate_cid", "Substrate PubChem CID"),
    ("metabolite", "Metabolite"),
    ("metabolite_cid", "Metabolite PubChem CID"),
    ("metabolite_chebi", "Metabolite ChEBI"),
    ("metabolite_kegg", "Metabolite KEGG"),
    ("associative_mode", "Associative mode"),
    ("species", "human/mouse"),
    ("pmid", "PMID"),
    ("description", "Description"),
]

METABOLITE_GENE_FIELDS = [
    ("metabolite", "Metabolite"),
    ("metabolite_cid", "Metabolite PubChem CID"),
    ("metabolite_chebi", "Metabolite ChEBI"),
    ("metabolite_kegg", "Metabolite KEGG"),
    ("gene", "Gene"),
    ("gene_id", "Gene ID"),
    ("alteration", "Alteration"),
    ("associative_mode", "Associative mode"),
    ("species", "human/mouse"),
    ("pmid", "PMID"),
    ("description", "Description"),
]

MICROBE_GENE_FIELDS = [
    ("gut_microbiota", "Gut Microbiota"),
    ("ncbi_id", "Gut Microbiota NCBI ID"),
    ("rank", "Rank"),
    ("strain", "Strain"),
    ("gene", "Gene"),
    ("gene_id", "Gene ID"),
    ("alteration", "Alteration"),
    ("associative_mode", "Associative mode"),
    ("species", "human/mouse"),
    ("pmid", "PMID"),
    ("description", "Description"),
]

OMNIPATH_URL = "https://omnipathdb.org/interactions"
OMNIPATH_CACHE = {}
OMNIPATH_CACHE_LOCK = threading.Lock()


def warn(message):
    print(f"[gutmgene_bridge] WARNING {message}", file=sys.stderr)


def parse_args():
    parser = argparse.ArgumentParser(description="Build the GutMGene bridge table.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument(
        "--output-dir",
        default="mcp/data/gutmgene_bridge",
        help="Output directory, absolute or relative to repo.",
    )
    parser.add_argument("--no-omnipath", action="store_true", help="Skip OmniPath enrichment.")
    parser.add_argument("--timeout", type=int, default=15, help="Seconds per OmniPath request.")
    parser.add_argument(
        "--species-filter",
        choices=["human", "mouse", "all"],
        default="all",
        help="Filter rows by the GutMGene human/mouse column.",
    )
    return parser.parse_args()


def find_repo_root(start_path):
    current = start_path.expanduser().resolve()
    if current.is_file():
        current = current.parent
    for candidate in [current] + list(current.parents):
        if (candidate / "mcp" / "data" / "gutmgene").is_dir():
            return candidate
    return current


def resolve_repo(repo_arg):
    if repo_arg:
        return find_repo_root(Path(repo_arg))
    return find_repo_root(Path.cwd())


def clean_value(value):
    if value is None:
        return ""
    return str(value).strip()


def check_reader_columns(reader, field_map, csv_path):
    fieldnames = reader.fieldnames or []
    missing = [column for _, column in field_map if column not in fieldnames]
    if missing:
        warn(f"{csv_path} missing expected columns: {', '.join(missing)}")
        return False
    return True


def row_to_dict(row, field_map, critical_fields, csv_path, row_number):
    missing = [column for _, column in field_map if column not in row or row.get(column) is None]
    if missing:
        warn(f"{csv_path}:{row_number} missing expected columns: {', '.join(missing)}")
        return None

    parsed = {}
    for key, column in field_map:
        parsed[key] = clean_value(row.get(column))
    parsed["species"] = parsed["species"].lower()

    empty = [key for key in critical_fields if not parsed.get(key)]
    if empty:
        warn(f"{csv_path}:{row_number} missing critical values: {', '.join(empty)}")
        return None
    return parsed


def parse_csv_rows(csv_path, field_map, critical_fields):
    rows = []
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if not check_reader_columns(reader, field_map, csv_path):
            return rows
        for row_number, row in enumerate(reader, start=2):
            parsed = row_to_dict(row, field_map, critical_fields, csv_path, row_number)
            if parsed is not None:
                rows.append(parsed)
    return rows


def parse_microbe_metabolite(csv_path):
    return parse_csv_rows(
        csv_path,
        MICROBE_METABOLITE_FIELDS,
        ["gut_microbiota", "metabolite", "species"],
    )


def parse_metabolite_gene(csv_path):
    return parse_csv_rows(
        csv_path,
        METABOLITE_GENE_FIELDS,
        ["metabolite", "gene", "species"],
    )


def parse_microbe_gene(csv_path):
    return parse_csv_rows(
        csv_path,
        MICROBE_GENE_FIELDS,
        ["gut_microbiota", "gene", "species"],
    )


def normalize_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [clean_value(item) for item in value if clean_value(item)]
    if isinstance(value, tuple):
        return [clean_value(item) for item in value if clean_value(item)]
    value = clean_value(value)
    if not value:
        return []
    return [value]


def normalize_omnipath_record(record):
    if not isinstance(record, dict):
        return None

    source = clean_value(record.get("source_genesymbol")) or clean_value(record.get("source"))
    target = clean_value(record.get("target_genesymbol")) or clean_value(record.get("target"))
    if not source or not target:
        return None

    return {
        "source": source,
        "target": target,
        "is_directed": record.get("is_directed"),
        "sources_db": normalize_list(record.get("sources")),
    }


def fetch_omnipath_interactions(gene_symbol, timeout=15):
    gene_symbol = clean_value(gene_symbol)
    if not gene_symbol:
        return []

    with OMNIPATH_CACHE_LOCK:
        if gene_symbol in OMNIPATH_CACHE:
            return OMNIPATH_CACHE[gene_symbol]

    params = {
        "genesymbols": "1",
        "fields": "sources,references",
        "partners": gene_symbol,
        "format": "json",
    }

    try:
        response = requests.get(OMNIPATH_URL, params=params, timeout=timeout)
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            raise ValueError("expected OmniPath JSON list")
        interactions = []
        for record in data:
            normalized = normalize_omnipath_record(record)
            if normalized:
                interactions.append(normalized)
    except Exception as exc:
        warn(f"OmniPath query failed for {gene_symbol}: {exc}")
        interactions = []

    with OMNIPATH_CACHE_LOCK:
        OMNIPATH_CACHE[gene_symbol] = interactions
    return interactions


def fetch_interactions_for_genes(genes, timeout):
    gene_list = sorted(gene for gene in genes if clean_value(gene))
    interactions_by_gene = {}
    if not gene_list:
        return interactions_by_gene

    max_workers = min(8, len(gene_list))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_gene = {
            executor.submit(fetch_omnipath_interactions, gene, timeout): gene
            for gene in gene_list
        }
        for future in as_completed(future_to_gene):
            gene = future_to_gene[future]
            try:
                interactions_by_gene[gene] = future.result()[:20]
            except Exception as exc:
                warn(f"OmniPath query failed for {gene}: {exc}")
                interactions_by_gene[gene] = []
    return interactions_by_gene


def apply_species_filter(rows, species_filter):
    if species_filter == "all":
        return
    rows[:] = [row for row in rows if row.get("species") == species_filter]


def attach_omnipath(metabolite_gene, skip_omnipath, timeout):
    if skip_omnipath:
        for row in metabolite_gene:
            row["omnipath_interactions"] = None
        return

    genes = set(row.get("gene") for row in metabolite_gene)
    interactions_by_gene = fetch_interactions_for_genes(genes, timeout)
    for row in metabolite_gene:
        row["omnipath_interactions"] = interactions_by_gene.get(row.get("gene"), [])


def output_path(repo, output_dir):
    path = Path(output_dir).expanduser()
    if not path.is_absolute():
        path = repo / path
    return path.resolve()


def write_json(output_dir, microbe_metabolite, metabolite_gene, microbe_gene):
    data = {
        "microbe_metabolite": microbe_metabolite,
        "metabolite_gene": metabolite_gene,
        "microbe_gene": microbe_gene,
    }
    with open(output_dir / "bridge_table.json", "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def write_tsv_section(fh, section_name, rows, fields):
    writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
    fh.write(f"# {section_name}\n")
    writer.writerow(fields)
    for row in rows:
        writer.writerow([row.get(field, "") for field in fields])


def write_metabolite_gene_tsv_section(fh, rows):
    writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
    fields = [key for key, _ in METABOLITE_GENE_FIELDS] + ["omnipath_interaction_count"]
    fh.write("# metabolite_gene\n")
    writer.writerow(fields)
    for row in rows:
        interactions = row.get("omnipath_interactions")
        if interactions is None:
            interaction_count = 0
        else:
            interaction_count = len(interactions)
        writer.writerow([row.get(field, "") for field in fields[:-1]] + [interaction_count])


def write_tsv(output_dir, microbe_metabolite, metabolite_gene, microbe_gene):
    with open(output_dir / "bridge_table.tsv", "w", newline="", encoding="utf-8") as fh:
        write_tsv_section(
            fh,
            "microbe_metabolite",
            microbe_metabolite,
            [key for key, _ in MICROBE_METABOLITE_FIELDS],
        )
        fh.write("\n")
        write_metabolite_gene_tsv_section(fh, metabolite_gene)
        fh.write("\n")
        write_tsv_section(
            fh,
            "microbe_gene",
            microbe_gene,
            [key for key, _ in MICROBE_GENE_FIELDS],
        )


def ensure_input_files(paths):
    missing = [path for path in paths if not path.is_file()]
    if missing:
        for path in missing:
            print(f"[gutmgene_bridge] ERROR missing input CSV: {path}", file=sys.stderr)
        sys.exit(1)


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    marker = repo / "mcp" / "data" / "gutmgene"
    if not marker.is_dir():
        print(f"[gutmgene_bridge] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)

    microbe_metabolite_path = marker / "gut_microbe_metabolite.csv"
    metabolite_gene_path = marker / "metabolite_host_gene.csv"
    microbe_gene_path = marker / "gut_microbe_host_gene.csv"
    ensure_input_files([microbe_metabolite_path, metabolite_gene_path, microbe_gene_path])

    microbe_metabolite = parse_microbe_metabolite(microbe_metabolite_path)
    metabolite_gene = parse_metabolite_gene(metabolite_gene_path)
    microbe_gene = parse_microbe_gene(microbe_gene_path)

    apply_species_filter(microbe_metabolite, args.species_filter)
    apply_species_filter(metabolite_gene, args.species_filter)
    apply_species_filter(microbe_gene, args.species_filter)

    if not microbe_metabolite and not metabolite_gene and not microbe_gene:
        warn("all GutMGene bridge tables are empty after parsing and filtering")

    attach_omnipath(metabolite_gene, args.no_omnipath, args.timeout)

    output_dir = output_path(repo, args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir, microbe_metabolite, metabolite_gene, microbe_gene)
    write_tsv(output_dir, microbe_metabolite, metabolite_gene, microbe_gene)

    print(
        f"Bridge table written: {len(microbe_metabolite)} microbe-metabolite, "
        f"{len(metabolite_gene)} metabolite-gene, {len(microbe_gene)} microbe-gene -> {output_dir}"
    )


if __name__ == "__main__":
    main()
