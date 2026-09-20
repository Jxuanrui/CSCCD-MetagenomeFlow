#!/usr/bin/env python

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


def warn(message):
    print(f"[indexer] WARNING {message}", file=sys.stderr)


def find_repo_root(start_path):
    current = start_path.resolve()
    for candidate in [current] + list(current.parents):
        if (candidate / "mcp").is_dir() and (candidate / "docs").is_dir():
            return candidate
    return current


def resolve_repo(repo_arg):
    if repo_arg:
        repo = Path(repo_arg).expanduser().resolve()
    else:
        repo = find_repo_root(Path.cwd())
    return repo


def parse_args():
    parser = argparse.ArgumentParser(description="Build the MaxMetagenome experience KB index.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--force", action="store_true", help="Delete and rebuild the experience_kb collection.")
    parser.add_argument("--incremental", action="store_true", help="Only rebuild changed source files.")
    parser.add_argument("--batch-size", type=int, default=32, help="Embedding batch size.")
    args = parser.parse_args()
    if args.force and args.incremental:
        parser.error("cannot use --force and --incremental together")
    return args


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


def load_registry_chunk(registry_path, source_mtime=None):
    try:
        import yaml

        registry_data = yaml.safe_load(registry_path.read_text(encoding="utf-8")) or {}
        metadata = {
            "doc_type": "registry",
            "source_path": str(registry_path),
            "last_updated": str(registry_data.get("last_updated", "")),
        }
        if source_mtime is not None:
            metadata["source_mtime"] = source_mtime
        chunk_text = json.dumps(registry_data, ensure_ascii=False, indent=2)
        return [(chunk_text, metadata)]
    except Exception as exc:
        warn(f"failed to read registry {registry_path}: {exc}")
        return []


def get_existing_sources(collection):
    try:
        payload = collection.get(include=["metadatas"])
    except Exception as exc:
        warn(f"failed to read existing metadata for incremental indexing: {exc}")
        return {}

    existing_sources = {}
    for metadata in payload.get("metadatas") or []:
        if not metadata:
            continue
        source_path = metadata.get("source_path")
        if not source_path:
            continue
        existing_sources[source_path] = metadata.get("source_mtime", 0)
    return existing_sources


def delete_source_chunks(collection, source_path):
    try:
        collection.delete(where={"source_path": source_path})
    except Exception as exc:
        warn(f"failed to delete chunks for {source_path}: {exc}")


def stable_chunk_id(prefix, source_path, chunk_index):
    digest = hashlib.sha1(str(source_path).encode("utf-8")).hexdigest()
    return f"{prefix}_{digest}_{chunk_index}"


def stable_chunk_ids(prefix, chunks):
    source_counts = {}
    ids = []
    for index, item in enumerate(chunks):
        metadata = item[1] if len(item) > 1 else {}
        source_path = metadata.get("source_path", index)
        chunk_index = source_counts.get(source_path, 0)
        source_counts[source_path] = chunk_index + 1
        ids.append(stable_chunk_id(prefix, source_path, chunk_index))
    return ids


def collect_existing_documents(collection):
    documents = []
    offset = 0
    page_size = 1000
    while True:
        try:
            page = collection.get(include=["documents"], limit=page_size, offset=offset)
        except Exception as exc:
            warn(f"failed to read collection documents for BM25 rebuild: {exc}")
            return documents
        ids = page.get("ids") or []
        texts = page.get("documents") or []
        if not ids:
            break
        for index, doc_id in enumerate(ids):
            text = texts[index] if index < len(texts) else ""
            if text:
                documents.append((doc_id, text))
        if len(ids) < page_size:
            break
        offset += len(ids)
    return documents


def rebuild_bm25(collection, bm25_path):
    from bm25_index import BM25Index

    bm25_documents = collect_existing_documents(collection)
    bm25_idx = BM25Index()
    if bm25_documents:
        bm25_idx.build(bm25_documents)
    bm25_idx.save(bm25_path)
    print(f"BM25 index saved: {len(bm25_documents)} docs -> {bm25_path}")


def load_embedding_model(set_tokenizer):
    try:
        from sentence_transformers import SentenceTransformer

        import os
        os.environ['HF_HUB_OFFLINE'] = '1'
        model = SentenceTransformer(os.environ.get("MGX_EMBED_MODEL", "BAAI/bge-small-zh-v1.5"), local_files_only=True)
        if hasattr(model, "tokenizer"):
            set_tokenizer(model.tokenizer)
        else:
            set_tokenizer(None)
        return model
    except Exception:
        from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

        set_tokenizer(None)
        return ONNXMiniLM_L6_V2()


def source_unchanged(filepath, existing_sources):
    source_path = str(filepath)
    if source_path not in existing_sources:
        return False
    try:
        indexed_mtime = float(existing_sources[source_path])
    except Exception:
        return False
    return abs(indexed_mtime - filepath.stat().st_mtime) < 0.000001


def add_source_mtime(chunks, mtime):
    updated_chunks = []
    for text, metadata in chunks:
        metadata = dict(metadata or {})
        metadata["source_mtime"] = mtime
        updated_chunks.append((text, metadata))
    return updated_chunks


def collect_file_chunks(filepath, parser, existing_sources, seen_sources, skipped_sources, changed_sources, scan_only):
    seen_sources.add(str(filepath))
    mtime = filepath.stat().st_mtime
    if source_unchanged(filepath, existing_sources):
        skipped_sources.add(str(filepath))
        return []
    changed_sources.add(str(filepath))
    if scan_only:
        return []
    return add_source_mtime(parser(filepath), mtime)


def collect_chunks(
    repo,
    parse_experience_doc,
    parse_tool_doc,
    parse_script_header,
    parse_skill_card,
    parse_snakemake_rule,
    existing_sources=None,
    return_tracking=False,
    scan_only=False,
):
    all_chunks = []
    existing_sources = existing_sources or {}
    seen_sources = set()
    skipped_sources = set()
    changed_sources = set()

    experience_dir = repo / "docs" / "experience"
    if experience_dir.is_dir():
        for filepath in sorted(experience_dir.glob("*.md")):
            if filepath.name == "TEMPLATE.md":
                continue
            all_chunks.extend(
                collect_file_chunks(
                    filepath,
                    parse_experience_doc,
                    existing_sources,
                    seen_sources,
                    skipped_sources,
                    changed_sources,
                    scan_only,
                )
            )
    else:
        warn(f"missing directory: {experience_dir}")

    docs_dir = repo / "docs"
    if docs_dir.is_dir():
        for filepath in sorted(docs_dir.rglob("*.md")):
            if "experience" in filepath.parts:
                continue
            all_chunks.extend(
                collect_file_chunks(
                    filepath,
                    parse_tool_doc,
                    existing_sources,
                    seen_sources,
                    skipped_sources,
                    changed_sources,
                    scan_only,
                )
            )
    else:
        warn(f"missing directory: {docs_dir}")

    scripts_dir = repo / "scripts"
    if scripts_dir.is_dir():
        for filepath in sorted(scripts_dir.glob("*.sh")):
            all_chunks.extend(
                collect_file_chunks(
                    filepath,
                    parse_script_header,
                    existing_sources,
                    seen_sources,
                    skipped_sources,
                    changed_sources,
                    scan_only,
                )
            )
    else:
        warn(f"missing directory: {scripts_dir}")

    skills_dir = repo / "agents" / "skills"
    if skills_dir.is_dir():
        for filepath in sorted(skills_dir.glob("*.yaml")):
            if filepath.name.startswith("_"):
                continue
            all_chunks.extend(
                collect_file_chunks(
                    filepath,
                    parse_skill_card,
                    existing_sources,
                    seen_sources,
                    skipped_sources,
                    changed_sources,
                    scan_only,
                )
            )
    else:
        warn(f"missing directory: {skills_dir}")

    rules_dir = repo / "pipeline" / "rules"
    if rules_dir.is_dir():
        for filepath in sorted(rules_dir.glob("*.smk")):
            all_chunks.extend(
                collect_file_chunks(
                    filepath,
                    parse_snakemake_rule,
                    existing_sources,
                    seen_sources,
                    skipped_sources,
                    changed_sources,
                    scan_only,
                )
            )
    else:
        warn(f"missing directory: {rules_dir}")

    registry_path = repo / "agents" / "registry.yaml"
    if registry_path.is_file():
        seen_sources.add(str(registry_path))
        registry_mtime = registry_path.stat().st_mtime
        if source_unchanged(registry_path, existing_sources):
            skipped_sources.add(str(registry_path))
        else:
            changed_sources.add(str(registry_path))
            if not scan_only:
                all_chunks.extend(load_registry_chunk(registry_path, registry_mtime))
    else:
        warn(f"missing registry: {registry_path}")

    # Index literature skill packages: README.md and params.yaml per replication
    replications_dir = repo / "skills" / "replications"
    if replications_dir.is_dir():
        for filepath in sorted(replications_dir.rglob("README.md")):
            all_chunks.extend(
                collect_file_chunks(
                    filepath,
                    parse_tool_doc,
                    existing_sources,
                    seen_sources,
                    skipped_sources,
                    changed_sources,
                    scan_only,
                )
            )
        for filepath in sorted(replications_dir.rglob("params.yaml")):
            seen_sources.add(str(filepath))
            mtime = filepath.stat().st_mtime
            if source_unchanged(filepath, existing_sources):
                skipped_sources.add(str(filepath))
                continue
            changed_sources.add(str(filepath))
            if scan_only:
                continue
            try:
                import yaml as _yaml
                data = _yaml.safe_load(filepath.read_text(encoding="utf-8")) or {}
                text = filepath.read_text(encoding="utf-8").strip()
                if text:
                    all_chunks.append((
                        text,
                        {
                            "doc_type": "replication_params",
                            "source_path": str(filepath),
                            "replication_id": filepath.parent.name,
                            "source_mtime": mtime,
                        },
                    ))
            except Exception as exc:
                warn(f"failed to read params {filepath}: {exc}")

    normalized_chunks = []
    for index, chunk in enumerate(all_chunks):
        if not isinstance(chunk, tuple) or len(chunk) != 2:
            warn(f"invalid chunk at index {index}")
            continue
        text, metadata = chunk
        if not text or not str(text).strip():
            continue
        metadata = sanitize_metadata(metadata or {})
        metadata.setdefault("source_type", metadata.get("doc_type", "unknown"))
        normalized_chunks.append((str(text).strip(), metadata))
    if return_tracking:
        return normalized_chunks, seen_sources, skipped_sources, changed_sources
    return normalized_chunks


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
            warn(f"failed to read existing ids for cleanup: {exc}")
            return
        ids = page.get("ids") or []
        if not ids:
            break
        try:
            collection.delete(ids=ids)
        except Exception as exc:
            warn(f"failed to delete existing ids: {exc}")
            return
        if len(ids) < page_size:
            break


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    if not repo.exists():
        print(f"[indexer] ERROR repo not found: {repo}", file=sys.stderr)
        sys.exit(1)

    if not (repo / "mcp").is_dir():
        print(f"[indexer] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)

    try:
        import chromadb
        from doc_parser import (
            parse_experience_doc,
            parse_script_header,
            parse_skill_card,
            parse_snakemake_rule,
            parse_tool_doc,
            set_tokenizer,
        )
    except ImportError as exc:
        print(
            f"[indexer] ERROR missing dependency in runtime environment: {exc}. "
            "Expected chromadb, sentence-transformers fallback support, and yaml support in the selected Python env.",
            file=sys.stderr,
        )
        sys.exit(1)

    chroma_dir = repo / "mcp" / "chromadb_data"
    chroma_dir.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(str(chroma_dir))

    if args.force:
        try:
            client.delete_collection("experience_kb")
        except Exception:
            pass

    collection = client.get_or_create_collection(
        "experience_kb",
        metadata={"hnsw:space": "cosine"},
    )

    if args.incremental:
        existing_sources = get_existing_sources(collection)
    else:
        existing_sources = {}

    if args.incremental:
        all_chunks, seen_sources, skipped_sources, changed_sources = collect_chunks(
            repo,
            parse_experience_doc,
            parse_tool_doc,
            parse_script_header,
            parse_skill_card,
            parse_snakemake_rule,
            existing_sources,
            return_tracking=True,
            scan_only=True,
        )
        deleted_sources = set(existing_sources.keys()) - seen_sources
        for deleted_source in sorted(deleted_sources):
            delete_source_chunks(collection, deleted_source)
        for source_path in sorted(changed_sources):
            delete_source_chunks(collection, source_path)
        print(
            f"Incremental experience_kb: skipped {len(skipped_sources)} files, "
            f"reindexed {len(changed_sources)} files, deleted {len(deleted_sources)} files"
        )
        if changed_sources:
            model = load_embedding_model(set_tokenizer)
            all_chunks, _, _, _ = collect_chunks(
                repo,
                parse_experience_doc,
                parse_tool_doc,
                parse_script_header,
                parse_skill_card,
                parse_snakemake_rule,
                existing_sources,
                return_tracking=True,
            )
    else:
        model = load_embedding_model(set_tokenizer)
        all_chunks, seen_sources, skipped_sources, changed_sources = collect_chunks(
            repo,
            parse_experience_doc,
            parse_tool_doc,
            parse_script_header,
            parse_skill_card,
            parse_snakemake_rule,
            existing_sources,
            return_tracking=True,
        )

    if not all_chunks and not args.incremental:
        print("Indexed 0 chunks into experience_kb")
        return

    if not args.incremental:
        clear_collection(collection)

    all_ids = stable_chunk_ids("exp", all_chunks) if args.incremental else []
    for batch_start in range(0, len(all_chunks), max(1, args.batch_size)):
        batch = all_chunks[batch_start:batch_start + max(1, args.batch_size)]
        if args.incremental:
            ids = all_ids[batch_start:batch_start + len(batch)]
        else:
            ids = [f"exp_{index}" for index in range(batch_start, batch_start + len(batch))]
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

    bm25_path = repo / "mcp" / "bm25_data" / "experience_kb.pkl"
    rebuild_bm25(collection, bm25_path)

    print(f"Indexed {len(all_chunks)} chunks into experience_kb")


if __name__ == "__main__":
    main()

    try:
        import subprocess
        subprocess.run(["bash", str(Path(__file__).resolve().parent.parent / "scripts/utils/check_rag_drift.sh")],
                       timeout=120, capture_output=True)
    except Exception:
        pass
