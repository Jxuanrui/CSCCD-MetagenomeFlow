#!/usr/bin/env python
"""Ingest the microbiome-fm PMC QA corpus into literature_kb (task E2).

Source: HF dataset microbiome-fm/microbiome-training-pmc_extracted_methods_batch_0
(QA markdown rows: "## Question" / "## Answer" / "## References"). Gates applied
in order: schema/answer filter, EuropePMC license map, gut-microbiome keyword
relevance, skip-list of PMCIDs already covered by literature_pipeline sources.
Embedding and BM25 rebuild reuse the mcp/indexer.py entry points.

Usage:
  envs/rag/bin/python3 mcp/ingest_literature_qa.py \
      --parquet /tmp/litqa_train.parquet \
      --license-map mcp/data/literature/qa_license_map.json
"""

import argparse
import json
import re
import sys
from pathlib import Path

# Gut-microbiome relevance gate (task E2 step 4): keep rows matching any term.
RELEVANCE_RE = re.compile(r"(?i)microbiom|16S|metagenom|gut flora|shotgun sequenc|amplicon")

# License gate (task E2 step 3): keep open CC licenses; drop NoDerivs variants
# (cc by-nd / cc by-nc-nd), closed/empty and unverified (not found in EuropePMC).
def license_allowed(license_value):
    license_norm = str(license_value or "").strip().lower()
    return license_norm.startswith("cc") and "-nd" not in license_norm


def warn(message):
    print(f"[ingest_literature_qa] WARNING {message}", file=sys.stderr)


def find_repo_root(start_path):
    current = start_path.resolve()
    for candidate in [current] + list(current.parents):
        if (candidate / "mcp").is_dir() and (candidate / "docs").is_dir():
            return candidate
    return current


def parse_args():
    parser = argparse.ArgumentParser(description="Ingest microbiome-fm PMC QA corpus into literature_kb.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--parquet", default="/tmp/litqa_train.parquet", help="Downloaded dataset parquet file.")
    parser.add_argument(
        "--license-map",
        default=None,
        help="JSON mapping PMCID -> EuropePMC license. Default: mcp/data/literature/qa_license_map.json.",
    )
    parser.add_argument("--batch-size", type=int, default=32, help="Embedding batch size.")
    return parser.parse_args()


def normalize_pmcid(raw):
    digits = re.search(r"(\d+)", str(raw or ""))
    return "PMC" + digits.group(1) if digits else None


def split_qa(text):
    """Return (question, answer_body) from a QA markdown row."""
    question_match = re.search(r"^## Question\s*\n(.+?)\s*\n", text, re.M)
    answer_match = re.search(r"## Answer\s*\n(.*?)(?:\n## References|\Z)", text, re.S)
    question = question_match.group(1).strip() if question_match else ""
    answer = answer_match.group(1).strip() if answer_match else ""
    return question, answer


def load_parquet_rows(parquet_path):
    import pyarrow.parquet as pq

    table = pq.read_table(str(parquet_path)).to_pydict()
    rows = []
    for raw_text, raw_pmcid in zip(table["text"], table["pmcid"]):
        text = str(raw_text or "")
        if not text.strip() or "## Answer" not in text:
            continue
        pmcid = normalize_pmcid(raw_pmcid)
        if pmcid:
            rows.append((pmcid, text))
    return rows


def load_skip_pmcids(repo):
    skip = set()
    search_results = repo / "mcp" / "data" / "literature" / "search_results.jsonl"
    if not search_results.exists():
        warn(f"missing {search_results}; skip-list empty")
        return skip
    for line in search_results.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            pmcid = str(json.loads(line).get("pmcid") or "").strip()
        except Exception as exc:
            warn(f"skipping invalid JSONL line: {exc}")
            continue
        if pmcid:
            skip.add(pmcid)
    return skip


def main():
    args = parse_args()
    repo = (Path(args.repo).expanduser().resolve() if args.repo else find_repo_root(Path.cwd()))
    if not (repo / "mcp").is_dir():
        print(f"[ingest_literature_qa] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)

    license_map_path = Path(args.license_map) if args.license_map else repo / "mcp" / "data" / "literature" / "qa_license_map.json"
    try:
        license_map = json.loads(license_map_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"[ingest_literature_qa] ERROR cannot read license map {license_map_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    rows = load_parquet_rows(args.parquet)
    licensed = [(pmcid, text) for pmcid, text in rows if license_allowed(license_map.get(pmcid))]
    relevant = [(pmcid, text) for pmcid, text in licensed if RELEVANCE_RE.search(text)]
    skip_pmcids = load_skip_pmcids(repo)
    selected = [(pmcid, text) for pmcid, text in relevant if pmcid not in skip_pmcids]
    print(
        f"Rows: parquet_filtered={len(rows)}, license_pass={len(licensed)}, "
        f"keyword_pass={len(relevant)}, skipped_existing_pmcid={len(relevant) - len(selected)}, "
        f"selected={len(selected)}"
    )
    if not selected:
        print("Nothing to index into literature_kb")
        return

    sys.path.insert(0, str(repo / "mcp"))
    import chromadb
    from doc_parser import chunk_text, set_tokenizer
    from indexer import load_embedding_model, rebuild_bm25, sanitize_metadata

    chroma_dir = repo / "mcp" / "chromadb_data"
    chroma_dir.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(str(chroma_dir))
    collection = client.get_or_create_collection(
        "literature_kb",
        metadata={"hnsw:space": "cosine"},
    )

    model = load_embedding_model(set_tokenizer)

    chunk_rows = []
    for pmcid, text in selected:
        question, answer = split_qa(text)
        if not answer:
            continue
        title = question or pmcid
        for index, chunk in enumerate(chunk_text(answer, chunk_size=512, overlap=80), start=1):
            document = f"# {title}\nPMCID: {pmcid}\n\n{chunk}".strip()
            metadata = sanitize_metadata(
                {
                    "doc_type": "literature_methods_qa",
                    "source_type": "microbiome-fm_pmc_qa",
                    "pmcid": pmcid,
                    "title": title,
                }
            )
            chunk_rows.append((f"litqa_{pmcid}_{index}", document, metadata))

    # Idempotent reruns: drop any previous ingest from this source, keep lit_* chunks.
    try:
        collection.delete(where={"source_type": "microbiome-fm_pmc_qa"})
    except Exception as exc:
        warn(f"failed to delete previous litqa chunks: {exc}")

    for start in range(0, len(chunk_rows), args.batch_size):
        batch = chunk_rows[start:start + args.batch_size]
        ids = [item[0] for item in batch]
        texts = [item[1] for item in batch]
        metadatas = [item[2] for item in batch]
        embeddings = model.encode(texts, batch_size=args.batch_size).tolist()
        collection.add(ids=ids, embeddings=embeddings, documents=texts, metadatas=metadatas)

    bm25_path = repo / "mcp" / "bm25_data" / "literature_kb.pkl"
    rebuild_bm25(collection, bm25_path)

    print(
        f"Literature QA KB summary: qa_rows_selected={len(selected)}, chunks_indexed={len(chunk_rows)}, "
        f"literature_kb_total={collection.count()}"
    )


if __name__ == "__main__":
    main()
