#!/usr/bin/env python

import argparse
import json
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
    parser.add_argument("--batch-size", type=int, default=32, help="Embedding batch size.")
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


def load_registry_chunk(registry_path):
    try:
        import yaml

        registry_data = yaml.safe_load(registry_path.read_text(encoding="utf-8")) or {}
        chunk_text = json.dumps(registry_data, ensure_ascii=False, indent=2)
        return [
            (
                chunk_text,
                {
                    "doc_type": "registry",
                    "source_path": str(registry_path),
                    "last_updated": str(registry_data.get("last_updated", "")),
                },
            )
        ]
    except Exception as exc:
        warn(f"failed to read registry {registry_path}: {exc}")
        return []


def collect_chunks(
    repo,
    parse_experience_doc,
    parse_tool_doc,
    parse_script_header,
    parse_skill_card,
    parse_snakemake_rule,
):
    all_chunks = []

    experience_dir = repo / "docs" / "experience"
    if experience_dir.is_dir():
        for filepath in sorted(experience_dir.glob("*.md")):
            if filepath.name == "TEMPLATE.md":
                continue
            all_chunks.extend(parse_experience_doc(filepath))
    else:
        warn(f"missing directory: {experience_dir}")

    docs_dir = repo / "docs"
    if docs_dir.is_dir():
        for filepath in sorted(docs_dir.rglob("*.md")):
            if "experience" in filepath.parts:
                continue
            all_chunks.extend(parse_tool_doc(filepath))
    else:
        warn(f"missing directory: {docs_dir}")

    scripts_dir = repo / "scripts"
    if scripts_dir.is_dir():
        for filepath in sorted(scripts_dir.glob("*.sh")):
            all_chunks.extend(parse_script_header(filepath))
    else:
        warn(f"missing directory: {scripts_dir}")

    skills_dir = repo / "agents" / "skills"
    if skills_dir.is_dir():
        for filepath in sorted(skills_dir.glob("*.yaml")):
            if filepath.name.startswith("_"):
                continue
            all_chunks.extend(parse_skill_card(filepath))
    else:
        warn(f"missing directory: {skills_dir}")

    rules_dir = repo / "pipeline" / "rules"
    if rules_dir.is_dir():
        for filepath in sorted(rules_dir.glob("*.smk")):
            all_chunks.extend(parse_snakemake_rule(filepath))
    else:
        warn(f"missing directory: {rules_dir}")

    registry_path = repo / "agents" / "registry.yaml"
    if registry_path.is_file():
        all_chunks.extend(load_registry_chunk(registry_path))
    else:
        warn(f"missing registry: {registry_path}")

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

    try:
        from sentence_transformers import SentenceTransformer

        import os
        os.environ['HF_HUB_OFFLINE'] = '1'
        model = SentenceTransformer("BAAI/bge-small-zh-v1.5", local_files_only=True)
        if hasattr(model, "tokenizer"):
            set_tokenizer(model.tokenizer)
        else:
            set_tokenizer(None)
    except Exception:
        from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

        model = ONNXMiniLM_L6_V2()
        set_tokenizer(None)

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

    all_chunks = collect_chunks(
        repo,
        parse_experience_doc,
        parse_tool_doc,
        parse_script_header,
        parse_skill_card,
        parse_snakemake_rule,
    )

    if not all_chunks:
        print("Indexed 0 chunks into experience_kb")
        return

    clear_collection(collection)

    for batch_start in range(0, len(all_chunks), max(1, args.batch_size)):
        batch = all_chunks[batch_start:batch_start + max(1, args.batch_size)]
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

    from bm25_index import BM25Index

    bm25_path = repo / "mcp" / "bm25_data" / "experience_kb.pkl"
    bm25_documents = [
        (f"exp_{index}", text)
        for index, (text, _) in enumerate(all_chunks)
    ]
    bm25_idx = BM25Index()
    bm25_idx.build(bm25_documents)
    bm25_idx.save(bm25_path)
    print(f"BM25 index saved: {len(bm25_documents)} docs -> {bm25_path}")

    print(f"Indexed {len(all_chunks)} chunks into experience_kb")


if __name__ == "__main__":
    main()
