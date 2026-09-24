#!/usr/bin/env python
# Task 4 output: index Task 3's GutMGene bridge table into the mechanism_kb RAG collection.

import argparse
import json
import os
import sys

from indexer import clear_collection, get_existing_sources, rebuild_bm25, resolve_repo, sanitize_metadata


SOURCE_PATH = "mcp/data/gutmgene_bridge/bridge_table.json"
DOC_TYPES = ["microbe_metabolite", "metabolite_gene", "microbe_gene"]


def parse_args():
    parser = argparse.ArgumentParser(description="Build the MaxMetagenome mechanism KB index.")
    parser.add_argument("--repo", help="Path to the MaxMetagenome repository root.")
    parser.add_argument("--force", action="store_true", help="Delete and rebuild the mechanism_kb collection.")
    parser.add_argument("--incremental", action="store_true", help="Only rebuild changed source files.")
    parser.add_argument("--batch-size", type=int, default=32, help="Embedding batch size.")
    args = parser.parse_args()
    if args.force and args.incremental:
        parser.error("cannot use --force and --incremental together")
    return args


def warn(message):
    print(f"[index_mechanism_kb] WARNING {message}", file=sys.stderr)


def empty_bridge_data():
    return {
        "microbe_metabolite": [],
        "metabolite_gene": [],
        "microbe_gene": [],
    }


SOURCES = [
    "mcp/data/gutmgene_bridge/bridge_table.json",
    "mcp/data/microbiomekg_bridge/bridge_table.json",
]


def load_bridge_table(repo):
    """Load every available source; each source file is {doc_type: [records]}."""
    bridge_data = empty_bridge_data()
    for source in SOURCES:
        bridge_path = repo / source
        if not bridge_path.is_file():
            if source == SOURCES[0]:
                warn(f"missing bridge table: {bridge_path}")
            continue
        try:
            data = json.loads(bridge_path.read_text(encoding="utf-8"))
        except Exception as exc:
            warn(f"failed to read bridge table {bridge_path}: {exc}")
            continue
        for doc_type in DOC_TYPES:
            records = data.get(doc_type, []) if isinstance(data, dict) else []
            if not isinstance(records, list):
                warn(f"invalid bridge table section: {doc_type} in {source}")
                records = []
            bridge_data[doc_type].extend(records)
    return bridge_data


def field(record, key):
    value = record.get(key, "")
    if value is None:
        return ""
    if isinstance(value, (list, dict)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def omnipath_summary(record):
    interactions = record.get("omnipath_interactions") or []
    gene = field(record, "gene")
    if not isinstance(interactions, list) or not interactions:
        return "none"

    targets = []
    for interaction in interactions:
        if isinstance(interaction, dict):
            target = interaction.get("target", "")
        else:
            target = interaction
        target = "" if target is None else str(target)
        if target:
            targets.append(target)
        if len(targets) >= 5:
            break

    target_text = ", ".join(targets)
    return f"{len(interactions)} interactions: {gene} -> {target_text}"


def omnipath_interaction_count(record):
    interactions = record.get("omnipath_interactions") or []
    if isinstance(interactions, list):
        return len(interactions)
    return 0


def chunk_microbe_metabolite(record, source_mtime=None):
    text = (
        f"{field(record, 'gut_microbiota')} (NCBI:{field(record, 'ncbi_id')}, {field(record, 'rank')}) "
        f"produces metabolite {field(record, 'metabolite')} "
        f"(ChEBI:{field(record, 'metabolite_chebi')}, KEGG:{field(record, 'metabolite_kegg')}, "
        f"PubChem:{field(record, 'metabolite_cid')}) from substrate {field(record, 'substrate')}. "
        f"Mode: {field(record, 'associative_mode')}. Description: {field(record, 'description')}"
    )
    metadata = {
        "doc_type": "microbe_metabolite",
        "gut_microbiota": field(record, "gut_microbiota"),
        "ncbi_id": field(record, "ncbi_id"),
        "rank": field(record, "rank"),
        "metabolite": field(record, "metabolite"),
        "metabolite_chebi": field(record, "metabolite_chebi"),
        "metabolite_kegg": field(record, "metabolite_kegg"),
        "metabolite_cid": field(record, "metabolite_cid"),
        "substrate": field(record, "substrate"),
        "associative_mode": field(record, "associative_mode"),
        "species": field(record, "species"),
        "pmid": field(record, "pmid"),
        "source_path": SOURCE_PATH,
    }
    if source_mtime is not None:
        metadata["source_mtime"] = source_mtime
    return text, sanitize_metadata(metadata)


def chunk_metabolite_gene(record, source_mtime=None):
    text = (
        f"Metabolite {field(record, 'metabolite')} "
        f"(ChEBI:{field(record, 'metabolite_chebi')}, KEGG:{field(record, 'metabolite_kegg')}, "
        f"PubChem:{field(record, 'metabolite_cid')}) {field(record, 'alteration')} "
        f"host gene {field(record, 'gene')} (Gene ID:{field(record, 'gene_id')}). "
        f"Mode: {field(record, 'associative_mode')}. Description: {field(record, 'description')}. "
        f"OmniPath downstream interactions: {omnipath_summary(record)}."
    )
    metadata = {
        "doc_type": "metabolite_gene",
        "metabolite": field(record, "metabolite"),
        "metabolite_chebi": field(record, "metabolite_chebi"),
        "metabolite_kegg": field(record, "metabolite_kegg"),
        "metabolite_cid": field(record, "metabolite_cid"),
        "gene": field(record, "gene"),
        "gene_id": field(record, "gene_id"),
        "alteration": field(record, "alteration"),
        "associative_mode": field(record, "associative_mode"),
        "species": field(record, "species"),
        "pmid": field(record, "pmid"),
        "omnipath_interaction_count": omnipath_interaction_count(record),
        "source_path": SOURCE_PATH,
    }
    if source_mtime is not None:
        metadata["source_mtime"] = source_mtime
    return text, sanitize_metadata(metadata)


def chunk_microbe_gene(record, source_mtime=None):
    text = (
        f"{field(record, 'gut_microbiota')} (NCBI:{field(record, 'ncbi_id')}, {field(record, 'rank')}) "
        f"directly {field(record, 'alteration')} host gene {field(record, 'gene')} "
        f"(Gene ID:{field(record, 'gene_id')}). Mode: {field(record, 'associative_mode')}. "
        f"Description: {field(record, 'description')}"
    )
    metadata = {
        "doc_type": "microbe_gene",
        "gut_microbiota": field(record, "gut_microbiota"),
        "ncbi_id": field(record, "ncbi_id"),
        "rank": field(record, "rank"),
        "gene": field(record, "gene"),
        "gene_id": field(record, "gene_id"),
        "alteration": field(record, "alteration"),
        "associative_mode": field(record, "associative_mode"),
        "species": field(record, "species"),
        "pmid": field(record, "pmid"),
        "source_path": SOURCE_PATH,
    }
    if source_mtime is not None:
        metadata["source_mtime"] = source_mtime
    return text, sanitize_metadata(metadata)


def chunk_bridge_records(bridge_data, source_mtime=None):
    if not bridge_data:
        return []

    chunks = []
    chunkers = {
        "microbe_metabolite": chunk_microbe_metabolite,
        "metabolite_gene": chunk_metabolite_gene,
        "microbe_gene": chunk_microbe_gene,
    }

    for doc_type in DOC_TYPES:
        records = bridge_data.get(doc_type) or []
        if not isinstance(records, list):
            warn(f"invalid records for {doc_type}")
            continue
        for index, record in enumerate(records):
            try:
                text, metadata = chunkers[doc_type](record, source_mtime)
                chunks.append((str(text).strip(), metadata))
            except Exception as exc:
                warn(f"skipping malformed record at index {index}: {exc}")
                continue
    return chunks


def load_embedding_model():
    try:
        from sentence_transformers import SentenceTransformer

        os.environ['HF_HUB_OFFLINE'] = '1'
        return SentenceTransformer("BAAI/bge-small-zh-v1.5", local_files_only=True)
    except Exception as first_exc:
        try:
            from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

            return ONNXMiniLM_L6_V2()
        except Exception as second_exc:
            print(
                f"[index_mechanism_kb] ERROR failed to load embedding model: "
                f"{first_exc}; fallback failed: {second_exc}",
                file=sys.stderr,
            )
            sys.exit(1)


def main():
    args = parse_args()
    repo = resolve_repo(args.repo)
    if not repo.exists():
        print(f"[index_mechanism_kb] ERROR repo not found: {repo}", file=sys.stderr)
        sys.exit(1)

    if not (repo / "mcp").is_dir():
        print(f"[index_mechanism_kb] ERROR invalid repo root: {repo}", file=sys.stderr)
        sys.exit(1)

    try:
        import chromadb
    except ImportError as exc:
        print(
            f"[index_mechanism_kb] ERROR missing dependency in runtime environment: {exc}. "
            "Expected chromadb and sentence-transformers fallback support in the selected Python env.",
            file=sys.stderr,
        )
        sys.exit(1)

    chroma_dir = repo / "mcp" / "chromadb_data"
    chroma_dir.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(str(chroma_dir))

    if args.force:
        try:
            client.delete_collection("mechanism_kb")
        except Exception:
            pass

    collection = client.get_or_create_collection(
        "mechanism_kb",
        metadata={"hnsw:space": "cosine"},
    )

    # source fingerprint: newest mtime across all SOURCES
    source_mtimes = [(repo / s).stat().st_mtime for s in SOURCES if (repo / s).is_file()]
    bridge_mtime = max(source_mtimes) if source_mtimes else 0

    if args.incremental:
        existing_sources = get_existing_sources(collection)
        bridge_unchanged = all(
            abs(float(existing_sources.get(s, 0)) - ((repo / s).stat().st_mtime if (repo / s).is_file() else 0)) < 0.000001
            for s in SOURCES
            if (repo / s).is_file()
        )
        if bridge_unchanged:
            print("Bridge table unchanged, skipping reindex")
            return

    bridge_data = load_bridge_table(repo)
    chunks = chunk_bridge_records(bridge_data, bridge_mtime)

    if not chunks:
        print("Indexed 0 chunks into mechanism_kb")
        return

    model = load_embedding_model()

    clear_collection(collection)

    batch_size = max(1, args.batch_size)
    for batch_start in range(0, len(chunks), batch_size):
        batch = chunks[batch_start:batch_start + batch_size]
        ids = [f"mech_{index}" for index in range(batch_start, batch_start + len(batch))]
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

    bm25_path = repo / "mcp" / "bm25_data" / "mechanism_kb.pkl"
    rebuild_bm25(collection, bm25_path)

    print(f"Indexed {len(chunks)} chunks into mechanism_kb")


if __name__ == "__main__":
    main()

    try:
        import subprocess
        subprocess.run(["bash", str(Path(__file__).resolve().parent.parent / "scripts/utils/check_rag_drift.sh")],
                       timeout=120, capture_output=True)
    except Exception:
        pass
