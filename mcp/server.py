#!/usr/bin/env python

import argparse
import json
import sys
from pathlib import Path


_CLIENT = None
_MODEL = None


def warn(message):
    print(f"[server] WARNING {message}", file=sys.stderr)


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
    parser = argparse.ArgumentParser(description="MaxMetagenome stdio JSON-RPC search server.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    return parser.parse_args()


def _load_runtime(repo):
    global _CLIENT, _MODEL
    if _CLIENT is None:
        import chromadb

        chroma_dir = repo / "mcp" / "chromadb_data"
        chroma_dir.mkdir(parents=True, exist_ok=True)
        _CLIENT = chromadb.PersistentClient(str(chroma_dir))
    if _MODEL is None:
        from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

        _MODEL = ONNXMiniLM_L6_V2()


def _trim_document(text, limit=500):
    compact = " ".join(str(text).split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 3] + "..."


def _get_collections(collection_name):
    if collection_name not in {"experience_kb", "literature_kb", "all"}:
        raise ValueError(f"unsupported collection: {collection_name}")

    collections = []
    if collection_name == "all":
        for name in ["experience_kb", "literature_kb"]:
            try:
                collections.append(_CLIENT.get_collection(name))
            except Exception:
                if name == "experience_kb":
                    raise
                warn(f"collection not available: {name}")
        return collections
    return [_CLIENT.get_collection(collection_name)]


def _flatten_results(collection_name, results):
    rows = []
    documents = (results.get("documents") or [[]])[0]
    metadatas = (results.get("metadatas") or [[]])[0]
    distances = (results.get("distances") or [[]])[0]

    for index, document in enumerate(documents):
        metadata = metadatas[index] if index < len(metadatas) else {}
        distance = distances[index] if index < len(distances) else None
        rows.append(
            {
                "rank": index + 1,
                "collection": collection_name,
                "document": _trim_document(document),
                "metadata": metadata,
                "distance": distance,
            }
        )
    return rows


def _handle_search(repo, params):
    _load_runtime(repo)
    query_text = str(params.get("query") or "").strip()
    if not query_text:
        raise ValueError("query is required")

    collection_name = str(params.get("collection") or "experience_kb").strip()
    n_results = int(params.get("n_results") or 5)
    where_filter = params.get("filters")
    collections = _get_collections(collection_name)
    query_embedding = _MODEL([query_text])[0]

    rows = []
    for collection in collections:
        try:
            results = collection.query(
                query_embeddings=[query_embedding],
                n_results=n_results,
                where=where_filter,
                include=["documents", "metadatas", "distances"],
            )
        except Exception as exc:
            warn(f"query failed for {collection.name}: {exc}")
            continue
        rows.extend(_flatten_results(collection.name, results))

    if collection_name == "all":
        rows.sort(key=lambda item: item["distance"] if item["distance"] is not None else 999999)
        for rank, row in enumerate(rows, start=1):
            row["rank"] = rank

    return {"results": rows}


def _write_response(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue

        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            method = request.get("method")

            if method == "meta-server_rag_search":
                result = _handle_search(repo, request.get("params") or {})
                _write_response({"id": request_id, "result": result})
                continue

            if method in {"ping", "initialize"}:
                _write_response({"id": request_id, "result": {"ok": True}})
                continue

            raise ValueError(f"unsupported method: {method}")
        except Exception as exc:
            _write_response(
                {
                    "id": request_id,
                    "error": {
                        "message": str(exc),
                    },
                }
            )


if __name__ == "__main__":
    main()
