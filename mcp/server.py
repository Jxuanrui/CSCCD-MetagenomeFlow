#!/usr/bin/env python

import argparse
import json
import os
import sys
from pathlib import Path


_CLIENT = None
_MODEL = None
_BM25_INDEXES = {}
_BM25_IMPORT_WARNING_SHOWN = False


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


def _load_runtime(repo, load_model=True):
    global _CLIENT, _MODEL
    if _CLIENT is None:
        import chromadb

        chroma_dir = repo / "mcp" / "chromadb_data"
        chroma_dir.mkdir(parents=True, exist_ok=True)
        _CLIENT = chromadb.PersistentClient(str(chroma_dir))
    if load_model and _MODEL is None:
        try:
            from sentence_transformers import SentenceTransformer

            os.environ["HF_HUB_OFFLINE"] = "1"
            _MODEL = SentenceTransformer("BAAI/bge-small-zh-v1.5", local_files_only=True)
        except Exception:
            from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

            _MODEL = ONNXMiniLM_L6_V2()


def _load_bm25(repo, collection_name):
    """懒加载 BM25 索引；索引不存在或依赖不可用时返回 None。"""
    global _BM25_IMPORT_WARNING_SHOWN
    if collection_name in _BM25_INDEXES:
        return _BM25_INDEXES[collection_name]

    try:
        from bm25_index import BM25Index
    except Exception as exc:
        if not _BM25_IMPORT_WARNING_SHOWN:
            warn(f"BM25 unavailable, falling back to dense retrieval: {exc}")
            _BM25_IMPORT_WARNING_SHOWN = True
        return None

    bm25_path = repo / "mcp" / "bm25_data" / f"{collection_name}.pkl"
    idx = BM25Index()
    try:
        if idx.load(bm25_path):
            _BM25_INDEXES[collection_name] = idx
            return idx
    except Exception as exc:
        warn(f"failed to load BM25 index for {collection_name}: {exc}")
    return None


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


def _dedupe_ranked(ids):
    seen = set()
    deduped = []
    for doc_id in ids:
        if doc_id in seen:
            continue
        seen.add(doc_id)
        deduped.append(doc_id)
    return deduped


def _fuse_ranked_ids(ranked_lists):
    try:
        from bm25_index import reciprocal_rank_fusion

        return reciprocal_rank_fusion(ranked_lists)
    except Exception as exc:
        warn(f"RRF unavailable, using rank concatenation: {exc}")
        merged = []
        for ranked in ranked_lists:
            merged.extend(ranked)
        return _dedupe_ranked(merged)


def _fetch_ranked_rows(collections, ranked_ids, where_filter, distance_by_id, limit):
    if not ranked_ids or limit <= 0:
        return []

    rows_by_id = {}
    for collection in collections:
        try:
            get_kwargs = {
                "ids": ranked_ids,
                "include": ["documents", "metadatas"],
            }
            if where_filter:
                get_kwargs["where"] = where_filter
            got = collection.get(**get_kwargs)
        except Exception as exc:
            warn(f"get failed for {collection.name}: {exc}")
            continue

        ids = got.get("ids") or []
        documents = got.get("documents") or []
        metadatas = got.get("metadatas") or []
        for index, doc_id in enumerate(ids):
            if doc_id in rows_by_id:
                continue
            document = documents[index] if index < len(documents) else ""
            metadata = metadatas[index] if index < len(metadatas) else {}
            rows_by_id[doc_id] = {
                "collection": collection.name,
                "document": _trim_document(document),
                "metadata": metadata,
                "distance": distance_by_id.get(doc_id),
            }

    rows = []
    for doc_id in ranked_ids:
        row = rows_by_id.get(doc_id)
        if not row:
            continue
        row["rank"] = len(rows) + 1
        rows.append(row)
        if len(rows) >= limit:
            break
    return rows


def _handle_search(repo, params):
    query_text = str(params.get("query") or "").strip()
    if not query_text:
        raise ValueError("query is required")

    retrieval_mode = str(params.get("retrieval_mode") or "hybrid").strip().lower()
    if retrieval_mode not in {"hybrid", "dense", "sparse"}:
        raise ValueError(f"unsupported retrieval_mode: {retrieval_mode}")

    _load_runtime(repo, load_model=retrieval_mode in {"hybrid", "dense"})
    collection_name = str(params.get("collection") or "experience_kb").strip()
    n_results = int(params.get("n_results") or 5)
    where_filter = params.get("filters")
    collections = _get_collections(collection_name)
    query_limit = max(20, n_results)

    dense_ids = []
    sparse_ids = []
    distance_by_id = {}

    if retrieval_mode in {"hybrid", "dense"}:
        if hasattr(_MODEL, "encode"):
            query_embedding = _MODEL.encode([query_text]).tolist()[0]
        else:
            query_embedding = _MODEL([query_text])[0]

        for collection in collections:
            try:
                results = collection.query(
                    query_embeddings=[query_embedding],
                    n_results=query_limit,
                    where=where_filter,
                    include=["distances"],
                )
            except Exception as exc:
                warn(f"query failed for {collection.name}: {exc}")
                continue
            ids = (results.get("ids") or [[]])[0]
            distances = (results.get("distances") or [[]])[0]
            dense_ids.extend(ids)
            for index, doc_id in enumerate(ids):
                if index < len(distances):
                    distance_by_id[doc_id] = distances[index]

    if retrieval_mode in {"hybrid", "sparse"}:
        for collection in collections:
            bm25_idx = _load_bm25(repo, collection.name)
            if not bm25_idx:
                continue
            hits = bm25_idx.search(query_text, top_k=query_limit)
            sparse_ids.extend(doc_id for doc_id, _ in hits)

    dense_ids = _dedupe_ranked(dense_ids)
    sparse_ids = _dedupe_ranked(sparse_ids)
    if retrieval_mode == "hybrid" and dense_ids and sparse_ids:
        fused_ids = _fuse_ranked_ids([dense_ids, sparse_ids])
    elif dense_ids:
        fused_ids = dense_ids
    else:
        fused_ids = sparse_ids

    rows = _fetch_ranked_rows(collections, fused_ids, where_filter, distance_by_id, n_results)
    return {"results": rows, "retrieval_mode": retrieval_mode}


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
