#!/usr/bin/env python

import json
import re
import sys
import time
from pathlib import Path

import requests


SEARCH_QUERIES = [
    {"id": "metagenome_methods", "query": '"shotgun metagenomics" method'},
    {"id": "binning_benchmark", "query": '"metagenomic binning" benchmark'},
    {"id": "humann_methods", "query": '"HUMAnN" metagenomic functional'},
    {"id": "metaphlan_methods", "query": '"MetaPhlAn" microbial profiling'},
    {"id": "kraken_methods", "query": '"Kraken 2" metagenomic classification'},
    {"id": "virus_discovery", "query": '"viral metagenomics" discovery pipeline'},
    {"id": "amr_metagenomics", "query": '"antimicrobial resistance" metagenomics'},
    {"id": "diversity_stats", "query": '"microbiome diversity" statistical method'},
    {"id": "multiomics", "query": '"multi-omics" gut microbiome method'},
    {"id": "batch_correction", "query": '"batch correction" microbiome'},
    {"id": "gwas_microbiome", "query": '"microbiome GWAS" metagenomic'},
    {"id": "assembly_methods", "query": '"metagenomic assembly" evaluation'},
]

SEARCH_URL = "https://www.ncbi.nlm.nih.gov/research/pubtator3-api/search/"
USER_AGENT = "MaxMetagenome/1.0"


def warn(message):
    print(f"[pubtator_search] WARNING {message}", file=sys.stderr)


def _is_blocked_response(text):
    return "WWW Error Blocked Diagnostic" in str(text)


def _safe_get(url, params, sleep_seconds):
    headers = {"User-Agent": USER_AGENT}
    for attempt in range(2):
        try:
            response = requests.get(url, params=params, headers=headers, timeout=60)
            time.sleep(sleep_seconds)
            if response.status_code >= 400:
                raise RuntimeError(f"http {response.status_code}")
            if _is_blocked_response(response.text):
                raise RuntimeError("blocked by NCBI")
            return response
        except Exception as exc:
            if attempt == 0:
                warn(f"request failed ({exc}), retrying in 5s")
                time.sleep(5)
                continue
            warn(f"request failed ({exc})")
            return None
    return None


def _recursive_candidates(payload):
    if isinstance(payload, list):
        for item in payload:
            for candidate in _recursive_candidates(item):
                yield candidate
    elif isinstance(payload, dict):
        if any(key.lower() in {"pmid", "title", "journal", "authors"} for key in payload.keys()):
            yield payload
        for value in payload.values():
            for candidate in _recursive_candidates(value):
                yield candidate


def _normalize_pmcid(value):
    if value is None:
        return ""
    text = str(value).strip()
    if not text:
        return ""
    if text.upper().startswith("PMC"):
        return text.upper()
    if text.isdigit():
        return f"PMC{text}"
    return text


def _normalize_year(value):
    if value is None:
        return ""
    text = str(value).strip()
    match = re.search(r"(19|20)\d{2}", text)
    return match.group(0) if match else text


def _normalize_authors(value):
    if value is None:
        return []
    if isinstance(value, list):
        authors = []
        for item in value:
            if isinstance(item, dict):
                name = item.get("name") or item.get("fullName") or item.get("lastname")
                if name:
                    authors.append(str(name).strip())
            elif str(item).strip():
                authors.append(str(item).strip())
        return authors
    text = str(value).strip()
    if not text:
        return []
    if ";" in text:
        return [part.strip() for part in text.split(";") if part.strip()]
    if "," in text:
        return [part.strip() for part in text.split(",") if part.strip()]
    return [text]


def _normalize_record(candidate):
    pmid = (
        candidate.get("pmid")
        or candidate.get("PMID")
        or candidate.get("uid")
        or candidate.get("id")
        or ""
    )
    pmid = str(pmid).strip()
    if not pmid or not re.search(r"\d", pmid):
        return None

    pmcid = _normalize_pmcid(
        candidate.get("pmcid")
        or candidate.get("PMCID")
        or candidate.get("pmc")
        or candidate.get("PMC")
        or ""
    )
    title = (
        candidate.get("title")
        or candidate.get("Title")
        or candidate.get("articleTitle")
        or ""
    )
    journal = (
        candidate.get("journal")
        or candidate.get("Journal")
        or candidate.get("journalName")
        or candidate.get("source")
        or ""
    )
    year = _normalize_year(
        candidate.get("year")
        or candidate.get("Year")
        or candidate.get("pubDate")
        or candidate.get("date")
        or ""
    )
    authors = _normalize_authors(
        candidate.get("authors")
        or candidate.get("Authors")
        or candidate.get("authorList")
        or candidate.get("author")
        or []
    )
    return {
        "pmid": pmid,
        "pmcid": pmcid,
        "title": str(title).strip(),
        "year": year,
        "journal": str(journal).strip(),
        "authors": authors,
    }


def search_pubtator(query, max_results=20):
    response = _safe_get(
        SEARCH_URL,
        {"text": query, "pageSize": max_results, "page": 1},
        sleep_seconds=0.34,
    )
    if response is None:
        return []

    try:
        payload = response.json()
    except Exception as exc:
        warn(f"failed to decode JSON response: {exc}")
        return []

    records = []
    seen_pmids = set()
    for candidate in _recursive_candidates(payload):
        record = _normalize_record(candidate)
        if record is None:
            continue
        if record["pmid"] in seen_pmids:
            continue
        seen_pmids.add(record["pmid"])
        records.append(record)
    return records[:max_results]


def search_all_queries(output_dir, max_per_query=20):
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    results_path = output_path / "search_results.jsonl"
    timestamp_path = output_path / "last_update.txt"

    merged = {}
    for item in SEARCH_QUERIES:
        query_records = search_pubtator(item["query"], max_results=max_per_query)
        for record in query_records:
            pmid = record["pmid"]
            if pmid not in merged:
                merged[pmid] = dict(record)
                merged[pmid]["query_ids"] = [item["id"]]
                merged[pmid]["queries"] = [item["query"]]
                continue
            if item["id"] not in merged[pmid]["query_ids"]:
                merged[pmid]["query_ids"].append(item["id"])
            if item["query"] not in merged[pmid]["queries"]:
                merged[pmid]["queries"].append(item["query"])
            if not merged[pmid].get("pmcid") and record.get("pmcid"):
                merged[pmid]["pmcid"] = record["pmcid"]

    ordered_records = sorted(
        merged.values(),
        key=lambda row: (
            row.get("year", ""),
            row.get("pmid", ""),
        ),
        reverse=True,
    )

    lines = [json.dumps(record, ensure_ascii=False) for record in ordered_records]
    results_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    timestamp_path.write_text(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), encoding="utf-8")
    return len(ordered_records)
