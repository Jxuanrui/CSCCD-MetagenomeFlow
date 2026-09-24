#!/usr/bin/env python

import argparse
import sys

from indexer import (
    add_source_mtime,
    clear_collection,
    delete_source_chunks,
    get_existing_sources,
    load_embedding_model,
    rebuild_bm25,
    resolve_repo,
    sanitize_metadata,
    source_unchanged,
    stable_chunk_ids,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Build the MaxMetagenome skill design KB index.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--force", action="store_true", help="Delete and rebuild the skill_design_kb collection.")
    parser.add_argument("--incremental", action="store_true", help="Only rebuild changed source files.")
    parser.add_argument("--batch-size", type=int, default=32, help="Embedding batch size.")
    args = parser.parse_args()
    if args.force and args.incremental:
        parser.error("cannot use --force and --incremental together")
    return args


def warn(message):
    print(f"[index_skill_design_kb] WARNING {message}", file=sys.stderr)


def collect_chunks(repo, parse_agent_skill_doc, existing_sources=None, return_tracking=False, scan_only=False):
    all_chunks = []
    existing_sources = existing_sources or {}
    seen_sources = set()
    skipped_sources = set()
    changed_sources = set()
    skills_dir = repo / ".claude" / "skills"
    if skills_dir.is_dir():
        for filepath in sorted(skills_dir.glob("*.md")):
            seen_sources.add(str(filepath))
            mtime = filepath.stat().st_mtime
            if source_unchanged(filepath, existing_sources):
                skipped_sources.add(str(filepath))
                continue
            changed_sources.add(str(filepath))
            if scan_only:
                continue
            all_chunks.extend(add_source_mtime(parse_agent_skill_doc(filepath), mtime))
    else:
        warn(f"missing directory: {skills_dir}")

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


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    if not repo.exists():
        print(f"[index_skill_design_kb] ERROR repo not found: {repo}", file=sys.stderr)
        sys.exit(1)

    if not (repo / "mcp").is_dir():
        print(f"[index_skill_design_kb] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)

    try:
        import chromadb
        from doc_parser import parse_agent_skill_doc, set_tokenizer
    except ImportError as exc:
        print(
            f"[index_skill_design_kb] ERROR missing dependency in runtime environment: {exc}. "
            "Expected chromadb, sentence-transformers fallback support, and yaml support in the selected Python env.",
            file=sys.stderr,
        )
        sys.exit(1)

    chroma_dir = repo / "mcp" / "chromadb_data"
    chroma_dir.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(str(chroma_dir))

    if args.force:
        try:
            client.delete_collection("skill_design_kb")
        except Exception:
            pass

    collection = client.get_or_create_collection(
        "skill_design_kb",
        metadata={"hnsw:space": "cosine"},
    )

    if args.incremental:
        existing_sources = get_existing_sources(collection)
    else:
        existing_sources = {}

    if args.incremental:
        all_chunks, seen_sources, skipped_sources, changed_sources = collect_chunks(
            repo,
            parse_agent_skill_doc,
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
            f"Incremental skill_design_kb: skipped {len(skipped_sources)} files, "
            f"reindexed {len(changed_sources)} files, deleted {len(deleted_sources)} files"
        )
        if changed_sources:
            model = load_embedding_model(set_tokenizer)
            all_chunks, _, _, _ = collect_chunks(
                repo,
                parse_agent_skill_doc,
                existing_sources,
                return_tracking=True,
            )
    else:
        model = load_embedding_model(set_tokenizer)
        all_chunks, seen_sources, skipped_sources, changed_sources = collect_chunks(
            repo,
            parse_agent_skill_doc,
            existing_sources,
            return_tracking=True,
        )

    if not all_chunks and not args.incremental:
        print("Indexed 0 chunks into skill_design_kb")
        return

    if not args.incremental:
        clear_collection(collection)

    all_ids = stable_chunk_ids("skill", all_chunks) if args.incremental else []
    for batch_start in range(0, len(all_chunks), max(1, args.batch_size)):
        batch = all_chunks[batch_start:batch_start + max(1, args.batch_size)]
        if args.incremental:
            ids = all_ids[batch_start:batch_start + len(batch)]
        else:
            ids = [f"skill_{index}" for index in range(batch_start, batch_start + len(batch))]
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

    bm25_path = repo / "mcp" / "bm25_data" / "skill_design_kb.pkl"
    rebuild_bm25(collection, bm25_path)

    print(f"Indexed {len(all_chunks)} chunks into skill_design_kb")


if __name__ == "__main__":
    main()
