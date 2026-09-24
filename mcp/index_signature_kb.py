#!/usr/bin/env python
# Index the BugSigDB bridge table into the signature_kb RAG collection.
# One chunk per signature (~8k chunks for the default human-gut filter).

import argparse
import json
import os
import re
import sys
from pathlib import Path

from indexer import clear_collection, get_existing_sources, rebuild_bm25, resolve_repo, sanitize_metadata


SOURCE_PATH = "mcp/data/bugsigdb_bridge/bridge_table.json"
COLLECTION = "signature_kb"


def parse_args():
    parser = argparse.ArgumentParser(description="Build the MaxMetagenome signature_kb index.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--force", action="store_true", help="Delete and rebuild the signature_kb collection.")
    parser.add_argument("--incremental", action="store_true", help="Only rebuild when the bridge table changed.")
    parser.add_argument("--batch-size", type=int, default=64, help="Embedding batch size.")
    args = parser.parse_args()
    if args.force and args.incremental:
        parser.error("cannot use --force and --incremental together")
    return args


def warn(message):
    print(f"[index_signature_kb] WARNING {message}", file=sys.stderr)


def field(record, key):
    value = record.get(key, "")
    if value is None:
        return ""
    if isinstance(value, list):
        return value
    return str(value)


def part(value, default="unspecified"):
    """Render a scalar field for chunk text, blanking NA/empty placeholders."""
    value = str(value or "").strip()
    if not value or value.lower() in {"na", "n/a"}:
        return default
    return value


def lineage_summary(lineages, max_names=6):
    """Short taxon summary: species/genus leaf names, capped for chunk brevity."""
    names = []
    seen = set()
    for lineage in lineages or []:
        leaf = str(lineage).split("|")[-1]
        leaf = re.sub(r"^[a-z]__", "", leaf).strip()
        if not leaf or leaf.lower() in {"na", ""} or leaf.lower() in seen:
            continue
        seen.add(leaf.lower())
        names.append(leaf)
    if not names:
        return "unspecified taxa"
    if len(names) > max_names:
        return f"{len(names)} taxa (e.g. {', '.join(names[:max_names])})"
    return ", ".join(names)


def chunk_signature(record, source_mtime=None):
    condition = part(record.get("condition"))
    body_site = part(record.get("body_site"))
    host_species = part(record.get("host_species"))
    direction = part(record.get("direction"), "direction-unspecified")
    group1_name = part(record.get("group1_name"), "group 1")
    group0_name = part(record.get("group0_name"), "group 0")
    study_design = part(record.get("study_design"))
    pmid = part(record.get("pmid"), "")
    summary = lineage_summary(field(record, "taxon_lineage"))
    size1 = part(record.get("group1_size"), "?")
    size0 = part(record.get("group0_size"), "?")

    pmid_part = f"PMID:{pmid}. " if pmid else ""
    text = (
        f"In {condition} ({body_site}, {host_species}), {summary} was {direction} "
        f"in {group1_name} (n={size1}) vs {group0_name} (n={size0}); {study_design}. "
        f"{pmid_part}Source: BugSigDB {record.get('bsdb_id', '')} (associative evidence)."
    )
    metadata = {
        "doc_type": "signature",
        "bsdb_id": field(record, "bsdb_id"),
        "condition": part(record.get("condition"), ""),
        "body_site": part(record.get("body_site"), ""),
        "direction": part(record.get("direction"), ""),
        "pmid": part(record.get("pmid"), ""),
        "state": field(record, "state"),
        "source": field(record, "source"),
        "source_path": SOURCE_PATH,
    }
    if source_mtime is not None:
        metadata["source_mtime"] = source_mtime
    return text, sanitize_metadata(metadata)


def load_chunks(repo, source_mtime=None):
    bridge_path = repo / SOURCE_PATH
    if not bridge_path.is_file():
        print(
            f"[index_signature_kb] ERROR missing bridge table: {bridge_path}. "
            "Run mcp/bugsigdb_bridge.py first.",
            file=sys.stderr,
        )
        sys.exit(1)
    try:
        data = json.loads(bridge_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"[index_signature_kb] ERROR failed to read bridge table: {exc}", file=sys.stderr)
        sys.exit(1)
    records = data.get("signature", []) if isinstance(data, dict) else []
    if not isinstance(records, list):
        print(f"[index_signature_kb] ERROR invalid bridge table section: signature", file=sys.stderr)
        sys.exit(1)

    chunks = []
    for index, record in enumerate(records):
        try:
            text, metadata = chunk_signature(record, source_mtime)
            chunks.append((str(text).strip(), metadata))
        except Exception as exc:
            warn(f"skipping malformed record at index {index}: {exc}")
    return chunks


def load_embedding_model():
    try:
        from sentence_transformers import SentenceTransformer

        os.environ["HF_HUB_OFFLINE"] = "1"
        return SentenceTransformer(os.environ.get("MGX_EMBED_MODEL", "BAAI/bge-small-zh-v1.5"), local_files_only=True)
    except Exception as first_exc:
        try:
            from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

            return ONNXMiniLM_L6_V2()
        except Exception as second_exc:
            print(
                f"[index_signature_kb] ERROR failed to load embedding model: "
                f"{first_exc}; fallback failed: {second_exc}",
                file=sys.stderr,
            )
            sys.exit(1)


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    if not repo.exists() or not (repo / "mcp").is_dir():
        print(f"[index_signature_kb] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)

    try:
        import chromadb
    except ImportError as exc:
        print(
            f"[index_signature_kb] ERROR missing dependency in runtime environment: {exc}. "
            "Expected chromadb and sentence-transformers fallback support in the selected Python env.",
            file=sys.stderr,
        )
        sys.exit(1)

    chroma_dir = repo / "mcp" / "chromadb_data"
    chroma_dir.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(str(chroma_dir))

    if args.force:
        try:
            client.delete_collection(COLLECTION)
        except Exception:
            pass

    collection = client.get_or_create_collection(
        COLLECTION,
        metadata={"hnsw:space": "cosine"},
    )

    bridge_path = repo / SOURCE_PATH
    bridge_mtime = bridge_path.stat().st_mtime if bridge_path.is_file() else 0

    if args.incremental:
        existing_sources = get_existing_sources(collection)
        if abs(float(existing_sources.get(SOURCE_PATH, 0)) - bridge_mtime) < 0.000001:
            print("Bridge table unchanged, skipping reindex")
            return

    chunks = load_chunks(repo, bridge_mtime)
    if not chunks:
        print(f"Indexed 0 chunks into {COLLECTION}")
        return

    model = load_embedding_model()
    clear_collection(collection)

    batch_size = max(1, args.batch_size)
    for batch_start in range(0, len(chunks), batch_size):
        batch = chunks[batch_start:batch_start + batch_size]
        ids = [f"sigkb_{index}" for index in range(batch_start, batch_start + len(batch))]
        texts = [item[0] for item in batch]
        metadatas = [item[1] for item in batch]
        if hasattr(model, "encode"):
            embeddings = model.encode(texts).tolist()
        else:
            embeddings = model(texts)
        collection.add(
            ids=ids,
            embeddings=embeddings,
            documents=texts,
            metadatas=metadatas,
        )

    bm25_path = repo / "mcp" / "bm25_data" / f"{COLLECTION}.pkl"
    rebuild_bm25(collection, bm25_path)

    print(f"Indexed {len(chunks)} chunks into {COLLECTION}")


if __name__ == "__main__":
    main()

    try:
        import subprocess
        subprocess.run(["bash", str(Path(__file__).resolve().parent.parent / "scripts/utils/check_rag_drift.sh")],
                       timeout=120, capture_output=True)
    except Exception:
        pass
