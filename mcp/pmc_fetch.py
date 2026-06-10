#!/usr/bin/env python

import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import requests


ELINK_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/elink.fcgi"
EFETCH_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
USER_AGENT = "MaxMetagenome/1.0"


def warn(message):
    print(f"[pmc_fetch] WARNING {message}", file=sys.stderr)


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


def _extract_pmcid_from_json(payload):
    if not isinstance(payload, dict):
        return ""
    for linkset in payload.get("linksets") or []:
        for key in ["linksetdbs", "linksetdb"]:
            for link_group in linkset.get(key) or []:
                for link_id in link_group.get("links") or []:
                    pmcid = _normalize_pmcid(link_id)
                    if pmcid:
                        return pmcid
    return ""


def _extract_pmcid_from_xml(text):
    try:
        root = ET.fromstring(text)
    except Exception:
        return ""
    for element in root.iter():
        if str(element.tag).endswith("Id") and element.text:
            pmcid = _normalize_pmcid(element.text)
            if pmcid:
                return pmcid
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


def _resolve_pmcid(pmid):
    response = _safe_get(
        ELINK_URL,
        {
            "dbfrom": "pubmed",
            "db": "pmc",
            "id": pmid,
            "retmode": "json",
        },
        sleep_seconds=1.0,
    )
    if response is None:
        return ""

    try:
        payload = response.json()
        pmcid = _extract_pmcid_from_json(payload)
        if pmcid:
            return pmcid
    except Exception:
        pass

    return _extract_pmcid_from_xml(response.text)


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
        EFETCH_URL,
        {
            "db": "pmc",
            "id": normalized_pmcid,
            "rettype": "xml",
            "retmode": "xml",
        },
        sleep_seconds=1.0,
    )
    if response is None:
        return None

    text = response.text.strip()
    if not text.startswith("<"):
        warn(f"unexpected efetch response for {normalized_pmcid}")
        return None

    xml_path.write_text(text, encoding="utf-8")
    return xml_path


def fetch_all_pmcs(search_results_jsonl, output_dir, max_articles=None):
    rows = _load_jsonl(search_results_jsonl)
    downloaded = []
    seen_pmcids = set()

    for row in rows:
        if max_articles is not None and len(downloaded) >= max_articles:
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

        xml_path = fetch_pmc_xml(pmcid, output_dir)
        if xml_path is None:
            continue
        seen_pmcids.add(pmcid)
        downloaded.append(pmcid)

    _write_jsonl(search_results_jsonl, rows)
    return downloaded
