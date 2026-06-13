#!/usr/bin/env python

import json
import re
import sys
import time
from pathlib import Path

import requests


EUROPE_PMC_SEARCH_URL = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
EUROPE_PMC_FULLTEXT_URL = "https://www.ebi.ac.uk/europepmc/webservices/rest/{pmcid}/fullTextXML"
USER_AGENT = "MaxMetagenome/1.0"


def warn(message):
    print(f"[pmc_fetch] WARNING {message}", file=sys.stderr)


def _safe_get(url, params, sleep_seconds):
    headers = {"User-Agent": USER_AGENT}
    for attempt in range(2):
        try:
            response = requests.get(url, params=params, headers=headers, timeout=60)
            time.sleep(sleep_seconds)
            if response.status_code == 404:
                # Resource does not exist; no point retrying.
                return None
            if response.status_code >= 400:
                raise RuntimeError(f"http {response.status_code}")
            return response
        except Exception as exc:
            if attempt == 0:
                warn(f"request failed ({exc}), retrying in 5s")
                time.sleep(5)
                continue
            warn(f"request failed ({exc})")
            return None
    return None


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
    match = re.search(r"PMC\d+", text, flags=re.I)
    return match.group(0).upper() if match else text


def _extract_pmcid_from_search(payload):
    if not isinstance(payload, dict):
        return ""
    results = (payload.get("resultList") or {}).get("result") or []
    for result in results:
        pmcid = _normalize_pmcid((result or {}).get("pmcid"))
        if pmcid:
            return pmcid
    return ""


def _resolve_pmcid(pmid):
    response = _safe_get(
        EUROPE_PMC_SEARCH_URL,
        {
            "query": f"EXT_ID:{pmid} AND SRC:MED",
            "resultType": "core",
            "format": "json",
        },
        sleep_seconds=0.5,
    )
    if response is None:
        return ""

    try:
        return _extract_pmcid_from_search(response.json())
    except Exception as exc:
        warn(f"failed to parse Europe PMC search response for PMID {pmid}: {exc}")
    return ""


def _load_jsonl(path):
    rows = []
    file_path = Path(path)
    if not file_path.exists():
        return rows
    for line in file_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except Exception as exc:
            warn(f"skipping invalid JSONL line: {exc}")
    return rows


def _write_jsonl(path, rows):
    file_path = Path(path)
    lines = [json.dumps(row, ensure_ascii=False) for row in rows]
    file_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def fetch_pmc_xml(pmcid, output_dir):
    normalized_pmcid = _normalize_pmcid(pmcid)
    if not normalized_pmcid:
        return None

    pmc_dir = Path(output_dir) / "pmc_xml"
    pmc_dir.mkdir(parents=True, exist_ok=True)
    xml_path = pmc_dir / f"{normalized_pmcid}.xml"
    if xml_path.exists():
        return xml_path

    response = _safe_get(
        EUROPE_PMC_FULLTEXT_URL.format(pmcid=normalized_pmcid),
        None,
        sleep_seconds=0.5,
    )
    if response is None:
        return None

    text = response.text.strip()
    if not text.startswith("<"):
        warn(f"unexpected Europe PMC fullTextXML response for {normalized_pmcid}")
        return None

    xml_path.write_text(text, encoding="utf-8")
    return xml_path


def fetch_all_pmcs(search_results_jsonl, output_dir, max_articles=None):
    rows = _load_jsonl(search_results_jsonl)
    downloaded = []
    seen_pmcids = set()
    new_downloads = 0

    pmc_dir = Path(output_dir) / "pmc_xml"

    for row in rows:
        if max_articles is not None and new_downloads >= max_articles:
            break

        pmcid = _normalize_pmcid(row.get("pmcid"))
        if not pmcid:
            pmid = str(row.get("pmid", "")).strip()
            if pmid:
                pmcid = _resolve_pmcid(pmid)
                if pmcid:
                    row["pmcid"] = pmcid

        if not pmcid or pmcid in seen_pmcids:
            continue

        # Skip if not OA (has_fulltext flag from Europe PMC search)
        if not row.get("has_fulltext"):
            continue

        already_exists = (pmc_dir / f"{pmcid}.xml").exists()
        xml_path = fetch_pmc_xml(pmcid, output_dir)
        if xml_path is None:
            continue
        seen_pmcids.add(pmcid)
        downloaded.append(pmcid)
        if not already_exists:
            new_downloads += 1

    _write_jsonl(search_results_jsonl, rows)
    return downloaded
