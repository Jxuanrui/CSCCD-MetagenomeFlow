#!/usr/bin/env python
"""Build the BugSigDB signature_kb bridge table.

Downloads (or reuses the /tmp cache of) the BugSigDB full dump CSV
(hourly-refreshed export, CC BY 4.0), keeps Complete curated signatures and
emits {"signature": [records]} at mcp/data/bugsigdb_bridge/bridge_table.json.

Default filter: human gut signatures (host species human AND body site
gut/fecal/intestinal-like). Pass --all to keep every Complete signature.

Usage: envs/rag/bin/python3 mcp/bugsigdb_bridge.py [--all] [--refresh]
"""

import argparse
import csv
import io
import json
import sys
from pathlib import Path

import requests

DUMP_URL = "https://raw.githubusercontent.com/waldronlab/BugSigDBExports/devel/full_dump.csv"
CACHE_PATH = Path("/tmp/bugsigdb_full_dump.csv")
OUT_PATH = Path("mcp/data/bugsigdb_bridge/bridge_table.json")

GUT_SITE_TERMS = ("gut", "feces", "fecal", "intestin", "colon", "bowel", "rectum", "rectal", "stool", "cecum")
DIRECTIONS = {"increased", "decreased"}


def parse_args():
    parser = argparse.ArgumentParser(description="Build the BugSigDB signature bridge table.")
    parser.add_argument("--all", action="store_true", help="Keep all body sites/hosts, not just human gut.")
    parser.add_argument("--refresh", action="store_true", help="Re-download the dump even if the cache exists.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    return parser.parse_args()


def warn(message):
    print(f"[bugsigdb_bridge] WARNING {message}", file=sys.stderr)


def resolve_repo(repo_arg):
    repo = Path(repo_arg).resolve() if repo_arg else Path(__file__).resolve().parent.parent
    if not (repo / "mcp").is_dir():
        print(f"[bugsigdb_bridge] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)
    return repo


def fetch_dump(refresh):
    if CACHE_PATH.is_file() and not refresh:
        print(f"[bugsigdb_bridge] reusing cached dump: {CACHE_PATH}")
        return CACHE_PATH
    print(f"[bugsigdb_bridge] downloading {DUMP_URL}")
    try:
        response = requests.get(DUMP_URL, timeout=300)
        response.raise_for_status()
    except Exception as exc:
        if CACHE_PATH.is_file():
            warn(f"download failed ({exc}); falling back to cached dump")
            return CACHE_PATH
        print(f"[bugsigdb_bridge] ERROR download failed and no cache: {exc}", file=sys.stderr)
        sys.exit(1)
    CACHE_PATH.write_bytes(response.content)
    print(f"[bugsigdb_bridge] saved dump: {CACHE_PATH} ({len(response.content)} bytes)")
    return CACHE_PATH


def read_rows(dump_path):
    """Parse the dump, skipping '#' comment header lines."""
    text = "\n".join(
        line for line in dump_path.read_text(encoding="utf-8").splitlines()
        if not line.startswith("#")
    )
    return list(csv.DictReader(io.StringIO(text)))


def is_human(row):
    return "homo sapiens" in (row.get("Host species") or "").lower()


def is_gut_site(row):
    site = (row.get("Body site") or "").lower()
    return any(term in site for term in GUT_SITE_TERMS)


def split_pairs(row):
    """MetaPhlAn lineages are comma-separated; NCBI taxid groups are ';'-separated (aligned)."""
    lineages = [
        lineage.strip()
        for lineage in (row.get("MetaPhlAn taxon names") or "").split(",")
        if lineage.strip() and lineage.strip().lower() != "na"
    ]
    taxids = [
        group.strip()
        for group in (row.get("NCBI Taxonomy IDs") or "").split(";")
        if group.strip() and group.strip().lower() != "na"
    ]
    if len(taxids) != len(lineages):
        taxids = taxids[:len(lineages)] + [""] * (len(lineages) - len(taxids))
    return lineages, taxids


def clean(value):
    value = (value or "").strip()
    return "" if value.lower() == "na" else value


def convert_row(row):
    lineages, taxids = split_pairs(row)
    return {
        "bsdb_id": clean(row.get("BSDB ID")),
        "taxon_lineage": lineages,
        "ncbi_ids": taxids,
        "direction": (row.get("Abundance in Group 1") or "").strip().lower(),
        "condition": clean(row.get("Condition")),
        "efo_id": clean(row.get("EFO ID")),
        "body_site": clean(row.get("Body site")),
        "host_species": clean(row.get("Host species")),
        "pmid": clean(row.get("PMID")),
        "doi": clean(row.get("DOI")),
        "study_design": clean(row.get("Study design")),
        "group1_name": clean(row.get("Group 1 name")),
        "group0_name": clean(row.get("Group 0 name")),
        "group1_size": clean(row.get("Group 1 sample size")),
        "group0_size": clean(row.get("Group 0 sample size")),
        "state": (row.get("State") or "").strip(),
        "source": "bugsigdb",
    }


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)

    dump_path = fetch_dump(args.refresh)
    rows = read_rows(dump_path)
    stats = {"total_rows": len(rows), "comment_lines_skipped": 1}

    records = []
    for row in rows:
        if (row.get("State") or "").strip() != "Complete":
            stats["not_complete"] = stats.get("not_complete", 0) + 1
            continue
        stats["complete"] = stats.get("complete", 0) + 1
        if not args.all and not (is_human(row) and is_gut_site(row)):
            stats["skipped_not_human_gut"] = stats.get("skipped_not_human_gut", 0) + 1
            continue
        stats["human_gut_complete"] = stats.get("human_gut_complete", 0) + 1
        record = convert_row(row)
        if record["direction"] not in DIRECTIONS:
            stats["skipped_no_direction"] = stats.get("skipped_no_direction", 0) + 1
            continue
        if not record["taxon_lineage"]:
            stats["skipped_no_taxa"] = stats.get("skipped_no_taxa", 0) + 1
            continue
        records.append(record)

    stats["emitted"] = len(records)
    directions = {}
    for record in records:
        directions[record["direction"]] = directions.get(record["direction"], 0) + 1
    stats["directions"] = directions
    print(f"[bugsigdb_bridge] filter stats: {json.dumps(stats, ensure_ascii=False)}")

    out_path = repo / OUT_PATH
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps({"signature": records}, ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    print(f"[bugsigdb_bridge] wrote {len(records)} signatures -> {out_path}")


if __name__ == "__main__":
    main()
