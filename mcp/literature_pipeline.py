#!/usr/bin/env python

import argparse
import json
import sys
from pathlib import Path

import chromadb
import sentence_transformers

from cache_dir import get_data_dir
from doc_parser import chunk_text, set_tokenizer
from europepmc_search import search_all_queries
from methods_extractor import extract_all_methods
from pmc_fetch import fetch_all_pmcs
from pubtator_annotate import annotate_all


def warn(message):
    print(f"[literature_pipeline] WARNING {message}", file=sys.stderr)


def find_repo_root(start_path):
    current = start_path.resolve()
    for candidate in [current] + list(current.parents):
        if (candidate / "mcp").is_dir() and (candidate / "docs").is_dir():
            return candidate
    return current


def resolve_repo(repo_arg):
    if repo_arg:
        return Path(repo_arg).expanduser().resolve()
    return find_repo_root(Path.cwd())


def parse_args():
    parser = argparse.ArgumentParser(description="Build the MaxMetagenome literature KB index.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--max-articles", type=int, help="Maximum number of PMC articles to download.")
    parser.add_argument("--update", action="store_true", help="Skip downstream work when no new PMIDs are found.")
    return parser.parse_args()


def sanitize_metadata(metadata):
    sanitized = {}
    for key, value in metadata.items():
        if value is None:
            continue
        if isinstance(value, list):
            sanitized[key] = json.dumps(value, ensure_ascii=False)
        elif isinstance(value, (str, int, float, bool)):
            sanitized[key] = value
        else:
            sanitized[key] = str(value)
    return sanitized


def clear_collection(collection):
    try:
        total = collection.count()
    except Exception:
        total = 0
    if total <= 0:
        return

    offset = 0
    page_size = 1000
    while True:
        try:
            page = collection.get(limit=page_size, offset=offset)
        except Exception as exc:
            warn(f"failed to read collection for cleanup: {exc}")
            return
        ids = page.get("ids") or []
        if not ids:
            return
        try:
            collection.delete(ids=ids)
        except Exception as exc:
            warn(f"failed to delete collection rows: {exc}")
            return
        if len(ids) < page_size:
            return


def _load_jsonl(path):
    rows = []
    file_path = Path(path)
    if not file_path.exists():
        return rows
    for line in file_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except Exception as exc:
            warn(f"skipping invalid JSONL line: {exc}")
    return rows


def _build_article_lookup(rows):
    lookup = {}
    for row in rows:
        pmcid = str(row.get("pmcid", "")).strip()
        if pmcid:
            lookup[pmcid] = row
    return lookup


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    if not repo.exists():
        print(f"[literature_pipeline] ERROR repo not found: {repo}", file=sys.stderr)
        sys.exit(1)

    data_dir = get_data_dir(repo)
    pmc_dir = data_dir / "pmc_xml"
    methods_dir = data_dir / "methods"
    annotations_dir = data_dir / "annotations"
    for directory in [data_dir, pmc_dir, methods_dir, annotations_dir]:
        directory.mkdir(parents=True, exist_ok=True)

    search_results_path = data_dir / "search_results.jsonl"
    previous_text = search_results_path.read_text(encoding="utf-8") if search_results_path.exists() else ""
    previous_rows = _load_jsonl(search_results_path)
    previous_pmids = {str(row.get("pmid", "")).strip() for row in previous_rows if row.get("pmid")}

    total_found = search_all_queries(data_dir, max_per_query=20)
    current_rows = _load_jsonl(search_results_path)
    current_pmids = {str(row.get("pmid", "")).strip() for row in current_rows if row.get("pmid")}

    if not current_pmids and previous_pmids and previous_text:
        warn("search returned no PMIDs; restoring previous search_results.jsonl")
        search_results_path.write_text(previous_text, encoding="utf-8")
        current_rows = previous_rows
        current_pmids = previous_pmids
        total_found = len(current_rows)

    new_pmids = current_pmids.difference(previous_pmids)
    if args.update and previous_pmids and not new_pmids:
        print("No new PMIDs found; skipping update.")
        return

    downloaded_pmcids = fetch_all_pmcs(search_results_path, data_dir, max_articles=args.max_articles)
    extracted_methods = extract_all_methods(pmc_dir, methods_dir)
    # Skip PubTator annotation on this server (NCBI IP blocked)
    annotations = {}

    updated_rows = _load_jsonl(search_results_path)
    article_lookup = _build_article_lookup(updated_rows)
    downloaded_pmcid_set = set(downloaded_pmcids)

    model = None
    if extracted_methods:
        try:
            import os
            os.environ['HF_HUB_OFFLINE'] = '1'
            model = sentence_transformers.SentenceTransformer("BAAI/bge-small-zh-v1.5", local_files_only=True)
            if hasattr(model, "tokenizer"):
                set_tokenizer(model.tokenizer)
        except Exception as exc:
            print(
                "[literature_pipeline] ERROR failed to load embedding model "
                f"BAAI/bge-small-zh-v1.5: {exc}",
                file=sys.stderr,
            )
            sys.exit(1)

    chunk_rows = []
    processed_articles = 0
    for pmcid, methods_text in extracted_methods:
        if downloaded_pmcid_set and pmcid not in downloaded_pmcid_set:
            continue
        article = article_lookup.get(pmcid, {})
        entities = []
        annotation_entry = annotations.get(pmcid) or {}
        if annotation_entry.get("entities"):
            entities = annotation_entry["entities"]

        chunks = chunk_text(methods_text, chunk_size=512, overlap=80)
        if not chunks:
            continue

        processed_articles += 1
        title = str(article.get("title") or pmcid).strip()
        for index, chunk in enumerate(chunks, start=1):
            document = f"# {title}\nPMCID: {pmcid}\n\n{chunk}".strip()
            metadata = sanitize_metadata(
                {
                    "doc_type": "literature_methods",
                    "source_type": "literature_methods",
                    "pmcid": pmcid,
                    "pmid": article.get("pmid") or annotation_entry.get("pmid") or "",
                    "title": article.get("title") or "",
                    "year": article.get("year") or "",
                    "journal": article.get("journal") or "",
                    "cited_by": article.get("cited_by") or 0,
                    "has_fulltext": bool(article.get("has_fulltext") or False),
                    "entities": entities,
                    "chunk_index": index,
                }
            )
            chunk_rows.append((f"lit_{pmcid}_{index}", document, metadata))

    if not chunk_rows:
        print(
            f"Literature KB summary: pmids_found={total_found}, articles_processed=0, chunks_indexed=0, skipped_articles={len(downloaded_pmcids)}"
        )
        return

    chroma_dir = repo / "mcp" / "chromadb_data"
    chroma_dir.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(str(chroma_dir))
    collection = client.get_or_create_collection(
        "literature_kb",
        metadata={"hnsw:space": "cosine"},
    )
    clear_collection(collection)

    batch_size = 32
    for start in range(0, len(chunk_rows), batch_size):
        batch = chunk_rows[start:start + batch_size]
        ids = [item[0] for item in batch]
        texts = [item[1] for item in batch]
        metadatas = [item[2] for item in batch]
        embeddings = model.encode(texts, batch_size=batch_size).tolist()
        collection.add(
            ids=ids,
            embeddings=embeddings,
            documents=texts,
            metadatas=metadatas,
        )

    from bm25_index import BM25Index

    bm25_path = repo / "mcp" / "bm25_data" / "literature_kb.pkl"
    bm25_documents = [(doc_id, document) for doc_id, document, _ in chunk_rows]
    bm25_idx = BM25Index()
    bm25_idx.build(bm25_documents)
    bm25_idx.save(bm25_path)
    print(f"BM25 index saved: {len(bm25_documents)} docs -> {bm25_path}")

    skipped_articles = max(0, len(set(downloaded_pmcids)) - processed_articles)
    print(
        f"Literature KB summary: pmids_found={total_found}, articles_processed={processed_articles}, chunks_indexed={len(chunk_rows)}, skipped_articles={skipped_articles}"
    )


if __name__ == "__main__":
    main()
