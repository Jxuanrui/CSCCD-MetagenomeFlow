#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent))

import chromadb
from sentence_transformers import SentenceTransformer

from bm25_index import BM25Index

os.environ["HF_HUB_OFFLINE"] = "1"


DEFAULT_COLLECTION = "experience_kb"
DEFAULT_OUTPUT = Path("mcp/eval/benchmark_results.json")
VALID_MODES = ("hybrid", "dense", "sparse")
QUERY_LIMIT = 20
TOP_K = 5

GOLDEN_QUESTIONS: list[dict[str, Any]] = [
    {
        "id": "metaphlan4_params",
        "query": "MetaPhlAn4 双端样本参数设置 mapout samout",
        "expected_doc_prefixes": ["metaphlan4-parameter-guide"],
        "dimension": "bacteria",
    },
    {
        "id": "humann3_speed",
        "query": "HUMAnN3 速度模式 balanced fast 参数",
        "expected_doc_prefixes": ["humann3-speed-mode", "02_read_based/humann3"],
        "dimension": "bacteria",
    },
    {
        "id": "kraken2_db",
        "query": "Kraken2 数据库选择 Standard PlusPF Standard-8",
        "expected_doc_prefixes": ["kraken2-database-choice"],
        "dimension": "bacteria",
    },
    {
        "id": "megahit_assembly",
        "query": "MEGAHIT 组装 min-contig-len k-mer 参数",
        "expected_doc_prefixes": ["megahit-assembly-strategy"],
        "dimension": "bacteria",
    },
    {
        "id": "fastp_qc",
        "query": "fastp 质控 adapter removal length_required Q20",
        "expected_doc_prefixes": ["fastp-quality-control"],
        "dimension": "bacteria",
    },
    {
        "id": "kneaddata_host",
        "query": "KneadData 去宿主 bowtie2 hg37dec very-sensitive-local",
        "expected_doc_prefixes": ["kneaddata-host-removal", "01_preprocessing/kneaddata"],
        "dimension": "bacteria",
    },
    {
        "id": "metabat2_bin",
        "query": "MetaBAT2 binning depth 最小长度 minCVSum 参数",
        "expected_doc_prefixes": ["metabat2-binning-parameters"],
        "dimension": "bacteria",
    },
    {
        "id": "checkm2_quality",
        "query": "CheckM2 MAG 质量 HQ MQ MIMAG 完整度 污染率",
        "expected_doc_prefixes": ["checkm2-quality-thresholds", "04_binning/checkm2"],
        "dimension": "bacteria",
    },
    {
        "id": "dastool_refine",
        "query": "DAS_Tool 多算法 bin 整合 score_threshold diamond",
        "expected_doc_prefixes": ["dastool-bin-refinement", "04_binning/dastool"],
        "dimension": "bacteria",
    },
    {
        "id": "genomad_virus",
        "query": "geNomad 病毒鉴定 score 阈值 1500bp 最小长度",
        "expected_doc_prefixes": [
            "genomad-virus-identification",
            "genomad-virsorter2-consensus",
        ],
        "dimension": "virome",
    },
    {
        "id": "checkv_viral",
        "query": "CheckV 病毒 completeness 过滤 provirus 修剪",
        "expected_doc_prefixes": ["checkv-virus-quality", "checkv-quality-filter"],
        "dimension": "virome",
    },
    {
        "id": "funomic_fungi",
        "query": "FunOMIC 真菌 marker 数据库 1.6M 肠道真菌",
        "expected_doc_prefixes": ["funomic-fungi-profiling"],
        "dimension": "mycobiome",
    },
    {
        "id": "eukfinder_mag",
        "query": "Eukfinder 真核 MAG binning BUSCO 质量评估",
        "expected_doc_prefixes": ["eukfinder-fungi-mag"],
        "dimension": "mycobiome",
    },
    {
        "id": "batch_correction",
        "query": "批次校正 ConQuR MMUPHin ComBat-seq 多中心",
        "expected_doc_prefixes": ["batch-correction-strategy", "05_stats/batch_correct"],
        "dimension": "statistics",
    },
    {
        "id": "siamcat_ml",
        "query": "SIAMCAT 机器学习 lasso RF 疾病分类器 ROC AUC",
        "expected_doc_prefixes": ["siamcat-ml-disease-classifier", "05_stats/siamcat"],
        "dimension": "statistics",
    },
]


@dataclass(slots=True)
class SearchResult:
    doc_id: str
    source: str
    text: str
    distance: float | None = None


def warn(message: str) -> None:
    print(f"[rag_benchmark] WARNING {message}", file=sys.stderr)


def find_repo_root(start_path: Path) -> Path:
    current = start_path.resolve()
    for candidate in (current, *current.parents):
        if (candidate / "mcp").is_dir():
            return candidate
    return current


def resolve_repo(repo_arg: str | None) -> Path:
    if repo_arg:
        return Path(repo_arg).expanduser().resolve()

    script_root = find_repo_root(Path(__file__).resolve())
    cwd_root = find_repo_root(Path.cwd())
    if (script_root / "mcp").is_dir():
        return script_root
    return cwd_root


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark MaxMetagenome RAG retrieval modes.")
    parser.add_argument("--repo", help="Path to the repository root. Auto-detected by default.")
    parser.add_argument(
        "--mode",
        choices=(*VALID_MODES, "all"),
        default="all",
        help="Retrieval mode to benchmark. Default: all.",
    )
    parser.add_argument(
        "--output-json",
        default=str(DEFAULT_OUTPUT),
        help="Path to write the benchmark JSON results.",
    )
    return parser.parse_args()


def load_dense_model() -> Any:
    try:
        return SentenceTransformer("BAAI/bge-small-zh-v1.5", local_files_only=True)
    except Exception as exc:
        warn(f"local BGE model unavailable, falling back to Chroma ONNX embedder: {exc}")
        from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

        return ONNXMiniLM_L6_V2()


def load_collection(repo: Path, collection_name: str) -> chromadb.Collection:
    chroma_dir = repo / "mcp" / "chromadb_data"
    client = chromadb.PersistentClient(str(chroma_dir))
    return client.get_collection(collection_name)


def load_bm25_index(repo: Path, collection_name: str) -> BM25Index | None:
    bm25_path = repo / "mcp" / "bm25_data" / f"{collection_name}.pkl"
    index = BM25Index()
    try:
        if index.load(bm25_path):
            return index
    except Exception as exc:
        warn(f"failed to load BM25 index from {bm25_path}: {exc}")
        return None
    warn(f"BM25 index missing: {bm25_path}")
    return None


def dedupe_ranked(ids: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for doc_id in ids:
        if doc_id in seen:
            continue
        seen.add(doc_id)
        ordered.append(doc_id)
    return ordered


def reciprocal_rank_fusion(ranked_lists: list[list[str]], k: int = 60) -> list[str]:
    scores: dict[str, float] = {}
    for ranked in ranked_lists:
        for rank, doc_id in enumerate(ranked, start=1):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=lambda doc_id: scores[doc_id], reverse=True)


def encode_query(model: Any, query: str) -> list[float]:
    if hasattr(model, "encode"):
        return model.encode([query]).tolist()[0]
    return model([query])[0]


def dense_search(collection: chromadb.Collection, model: Any, query: str, top_k: int) -> tuple[list[str], dict[str, float]]:
    query_embedding = encode_query(model, query)
    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
        include=["distances"],
    )
    ids = list((results.get("ids") or [[]])[0])
    distances = list((results.get("distances") or [[]])[0])
    distance_by_id: dict[str, float] = {}
    for idx, doc_id in enumerate(ids):
        if idx < len(distances):
            distance_by_id[doc_id] = distances[idx]
    return dedupe_ranked(ids), distance_by_id


def sparse_search(index: BM25Index | None, query: str, top_k: int) -> list[str]:
    if index is None:
        return []
    return dedupe_ranked([doc_id for doc_id, _ in index.search(query, top_k=top_k)])


def fetch_ranked_rows(
    collection: chromadb.Collection,
    ranked_ids: list[str],
    distance_by_id: dict[str, float],
    limit: int,
) -> list[SearchResult]:
    if not ranked_ids:
        return []

    payload = collection.get(ids=ranked_ids, include=["documents", "metadatas"])
    ids = payload.get("ids") or []
    documents = payload.get("documents") or []
    metadatas = payload.get("metadatas") or []
    rows_by_id: dict[str, SearchResult] = {}
    for idx, doc_id in enumerate(ids):
        metadata = metadatas[idx] if idx < len(metadatas) else {}
        document = documents[idx] if idx < len(documents) else ""
        source = ""
        if isinstance(metadata, dict):
            source = str(metadata.get("source_path") or metadata.get("source") or "")
        rows_by_id[doc_id] = SearchResult(
            doc_id=doc_id,
            source=source,
            text=str(document),
            distance=distance_by_id.get(doc_id),
        )

    rows: list[SearchResult] = []
    for doc_id in ranked_ids:
        row = rows_by_id.get(doc_id)
        if row is None:
            continue
        rows.append(row)
        if len(rows) >= limit:
            break
    return rows


def search_mode(
    collection: chromadb.Collection,
    model: Any,
    bm25_index: BM25Index | None,
    query: str,
    mode: str,
    top_k: int = TOP_K,
    query_limit: int = QUERY_LIMIT,
) -> tuple[list[SearchResult], str]:
    dense_ids: list[str] = []
    sparse_ids: list[str] = []
    distance_by_id: dict[str, float] = {}

    use_dense = mode in {"hybrid", "dense"}
    use_sparse = mode in {"hybrid", "sparse"}

    if use_dense or (mode == "sparse" and bm25_index is None):
        dense_ids, distance_by_id = dense_search(collection, model, query, query_limit)

    if use_sparse:
        sparse_ids = sparse_search(bm25_index, query, query_limit)

    effective_mode = mode
    if mode == "hybrid":
        if dense_ids and sparse_ids:
            ranked_ids = reciprocal_rank_fusion([dense_ids, sparse_ids])
        elif dense_ids:
            ranked_ids = dense_ids
            effective_mode = "dense_fallback"
        else:
            ranked_ids = sparse_ids
            effective_mode = "sparse_fallback"
    elif mode == "dense":
        ranked_ids = dense_ids
    else:
        if sparse_ids:
            ranked_ids = sparse_ids
        else:
            ranked_ids = dense_ids
            effective_mode = "dense_fallback"

    return fetch_ranked_rows(collection, ranked_ids, distance_by_id, top_k), effective_mode


def is_relevant(result: SearchResult, expected_doc_prefixes: list[str]) -> bool:
    haystacks = [result.source, result.doc_id, result.text]
    return any(prefix in haystack for prefix in expected_doc_prefixes for haystack in haystacks if haystack)


def compute_metrics(results: list[SearchResult], expected_doc_prefixes: list[str]) -> dict[str, float]:
    recall_at_1 = 1.0 if any(is_relevant(result, expected_doc_prefixes) for result in results[:1]) else 0.0
    recall_at_3 = 1.0 if any(is_relevant(result, expected_doc_prefixes) for result in results[:3]) else 0.0
    recall_at_5 = 1.0 if any(is_relevant(result, expected_doc_prefixes) for result in results[:5]) else 0.0

    mrr_at_5 = 0.0
    for rank, result in enumerate(results[:5], start=1):
        if is_relevant(result, expected_doc_prefixes):
            mrr_at_5 = 1.0 / rank
            break

    return {
        "recall_at_1": recall_at_1,
        "recall_at_3": recall_at_3,
        "recall_at_5": recall_at_5,
        "mrr_at_5": mrr_at_5,
    }


def aggregate_mode(per_query: list[dict[str, Any]]) -> dict[str, Any]:
    count = len(per_query)
    return {
        "recall_at_1": sum(item["recall_at_1"] for item in per_query) / count,
        "recall_at_3": sum(item["recall_at_3"] for item in per_query) / count,
        "recall_at_5": sum(item["recall_at_5"] for item in per_query) / count,
        "mrr_at_5": sum(item["mrr_at_5"] for item in per_query) / count,
        "mean_latency_ms": sum(item["latency_ms"] for item in per_query) / count,
        "per_query": per_query,
    }


def print_markdown_table(mode_results: dict[str, dict[str, Any]], mode_order: list[str]) -> None:
    print("| Mode    | R@1  | R@3  | R@5  | MRR@5 | Latency(ms) |")
    print("|---------|------|------|------|-------|-------------|")
    for mode in mode_order:
        summary = mode_results[mode]
        print(
            f"| {mode:<7} | "
            f"{summary['recall_at_1']:.2f} | "
            f"{summary['recall_at_3']:.2f} | "
            f"{summary['recall_at_5']:.2f} | "
            f"{summary['mrr_at_5']:.3f} | "
            f"{summary['mean_latency_ms']:.1f}ms |"
        )


def run_benchmark(repo: Path, modes: list[str]) -> dict[str, Any]:
    collection = load_collection(repo, DEFAULT_COLLECTION)
    model = load_dense_model()
    bm25_index = load_bm25_index(repo, DEFAULT_COLLECTION)

    mode_results: dict[str, dict[str, Any]] = {}
    for mode in modes:
        per_query: list[dict[str, Any]] = []
        for question in GOLDEN_QUESTIONS:
            start = time.time()
            results, effective_mode = search_mode(collection, model, bm25_index, question["query"], mode)
            latency_ms = (time.time() - start) * 1000.0
            metrics = compute_metrics(results, question["expected_doc_prefixes"])
            per_query.append(
                {
                    "id": question["id"],
                    "query": question["query"],
                    "dimension": question["dimension"],
                    "expected_doc_prefixes": question["expected_doc_prefixes"],
                    "effective_mode": effective_mode,
                    "recall_at_1": metrics["recall_at_1"],
                    "recall_at_3": metrics["recall_at_3"],
                    "recall_at_5": metrics["recall_at_5"],
                    "mrr_at_5": metrics["mrr_at_5"],
                    "latency_ms": round(latency_ms, 3),
                    "top_results": [
                        {
                            "rank": rank,
                            "doc_id": result.doc_id,
                            "source": result.source,
                            "distance": result.distance,
                            "snippet": result.text[:240],
                        }
                        for rank, result in enumerate(results, start=1)
                    ],
                }
            )
        mode_results[mode] = aggregate_mode(per_query)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "n_questions": len(GOLDEN_QUESTIONS),
        "modes": mode_results,
    }


def save_results(payload: dict[str, Any], output_json: Path) -> None:
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    repo = resolve_repo(args.repo)
    output_json = Path(args.output_json).expanduser()
    if not output_json.is_absolute():
        output_json = (repo / output_json).resolve()

    modes = list(VALID_MODES) if args.mode == "all" else [args.mode]
    results = run_benchmark(repo, modes)
    print_markdown_table(results["modes"], modes)
    save_results(results, output_json)
    try:
        rel_output = output_json.relative_to(repo)
        print(f"Saved: {rel_output.as_posix()}")
    except ValueError:
        print(f"Saved: {output_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
