#!/usr/bin/env python

import argparse
import json
import os
import sys
from pathlib import Path


def warn(message):
    print(f"[query] WARNING {message}", file=sys.stderr)


def find_repo_root(start_path):
    current = start_path.resolve()
    for candidate in [current] + list(current.parents):
        if (candidate / "mcp").is_dir():
            return candidate
    return current


def resolve_repo(repo_arg):
    if repo_arg:
        return Path(repo_arg).expanduser().resolve()
    return find_repo_root(Path.cwd())


def parse_args():
    parser = argparse.ArgumentParser(description="Query MaxMetagenome ChromaDB collections.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--query", required=True, help="Query text.")
    parser.add_argument(
        "--collection",
        default="experience_kb",
        choices=["experience_kb", "literature_kb", "signature_kb", "all"],
        help="Collection to search.",
    )
    parser.add_argument("--n-results", type=int, default=5, help="Number of results per collection.")
    parser.add_argument("--filter", help='Chroma where filter JSON, e.g. \'{"tool_name":"metabat2"}\'')
    parser.add_argument("--json", action="store_true", help="Return JSON results.")
    return parser.parse_args()


def safe_score(distance):
    if distance is None:
        return ""
    try:
        return f"{1.0 - float(distance):.4f}"
    except Exception:
        return ""


def preview_text(text, limit=120):
    compact = " ".join(str(text).split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 3] + "..."


def load_filter(filter_arg):
    if not filter_arg:
        return None
    try:
        parsed = json.loads(filter_arg)
        if isinstance(parsed, dict):
            return parsed
        warn("filter must decode to a JSON object; ignoring filter")
        return None
    except Exception as exc:
        warn(f"invalid filter JSON: {exc}")
        return None


def get_collections(client, collection_name):
    collections = []
    if collection_name == "all":
        for name in ["experience_kb", "literature_kb", "signature_kb"]:
            try:
                collections.append(client.get_collection(name))
            except Exception:
                if name == "experience_kb":
                    raise
                warn(f"collection not available: {name}")
    else:
        collections.append(client.get_collection(collection_name))
    return collections


def flatten_results(collection_name, results):
    rows = []
    documents = (results.get("documents") or [[]])[0]
    metadatas = (results.get("metadatas") or [[]])[0]
    distances = (results.get("distances") or [[]])[0]

    for index, document in enumerate(documents):
        metadata = metadatas[index] if index < len(metadatas) else {}
        distance = distances[index] if index < len(distances) else None
        tool_value = (
            metadata.get("tool")
            or metadata.get("tool_name")
            or metadata.get("rule_name")
            or metadata.get("script_id")
            or ""
        )
        row = {
            "collection": collection_name,
            "rank": index + 1,
            "source_type": metadata.get("doc_type") or metadata.get("source_type") or "",
            "tool": tool_value,
            "section": metadata.get("section") or "",
            "author": metadata.get("author") or "",
            "score": safe_score(distance),
            "preview": preview_text(document),
            "metadata": metadata,
            "document": document,
            "distance": distance,
        }
        rows.append(row)
    return rows


def print_table(rows):
    print("\t".join(["rank", "source_type", "tool", "section", "author", "score", "preview"]))
    for row in rows:
        print(
            "\t".join(
                [
                    str(row["rank"]),
                    str(row["source_type"]),
                    str(row["tool"]),
                    str(row["section"]),
                    str(row["author"]),
                    str(row["score"]),
                    str(row["preview"]).replace("\t", " "),
                ]
            )
        )


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    chroma_dir = repo / "mcp" / "chromadb_data"
    if not chroma_dir.exists():
        print(f"[query] ERROR ChromaDB path not found: {chroma_dir}", file=sys.stderr)
        sys.exit(1)

    try:
        import chromadb
    except ImportError as exc:
        print(
            f"[query] ERROR missing dependency in runtime environment: {exc}. "
            "Expected chromadb and sentence-transformers fallback support in the selected Python env.",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        from sentence_transformers import SentenceTransformer

        os.environ["HF_HUB_OFFLINE"] = "1"
        model = SentenceTransformer(os.environ.get("MGX_EMBED_MODEL", "BAAI/bge-small-zh-v1.5"), local_files_only=True)
    except Exception:
        from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

        model = ONNXMiniLM_L6_V2()
    client = chromadb.PersistentClient(str(chroma_dir))

    try:
        collections = get_collections(client, args.collection)
    except Exception as exc:
        print(f"[query] ERROR failed to load collection: {exc}", file=sys.stderr)
        sys.exit(1)

    if hasattr(model, "encode"):
        query_embedding = model.encode([args.query]).tolist()[0]
    else:
        query_embedding = model([args.query])[0]
    where_filter = load_filter(args.filter)

    all_rows = []
    for collection in collections:
        try:
            results = collection.query(
                query_embeddings=[query_embedding],
                n_results=args.n_results,
                where=where_filter,
                include=["documents", "metadatas", "distances"],
            )
        except Exception as exc:
            warn(f"query failed for {collection.name}: {exc}")
            continue
        all_rows.extend(flatten_results(collection.name, results))

    if args.json:
        print(json.dumps(all_rows, ensure_ascii=False, indent=2))
        return

    if args.collection == "all":
        all_rows.sort(key=lambda item: item["distance"] if item["distance"] is not None else 999999)
        for new_rank, row in enumerate(all_rows, start=1):
            row["rank"] = new_rank

    print_table(all_rows)


if __name__ == "__main__":
    main()
