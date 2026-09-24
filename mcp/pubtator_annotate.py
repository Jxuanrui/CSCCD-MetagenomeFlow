#!/usr/bin/env python

import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import requests


ANNOTATION_URL = "https://www.ncbi.nlm.nih.gov/research/pubtator3-api/annotations/retrieve"
USER_AGENT = "MaxMetagenome/1.0"


def warn(message):
    print(f"[pubtator_annotate] WARNING {message}", file=sys.stderr)


def _is_blocked_response(text):
    return "WWW Error Blocked Diagnostic" in str(text)


def _safe_get(url, sleep_seconds):
    headers = {"User-Agent": USER_AGENT}
    for attempt in range(2):
        try:
            response = requests.get(url, headers=headers, timeout=60)
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


def _local_name(tag):
    return str(tag).rsplit("}", 1)[-1].lower()


def _parse_json_entities(payload):
    counts = {}

    def visit(node):
        if isinstance(node, list):
            for item in node:
                visit(item)
            return
        if not isinstance(node, dict):
            return

        mention = (
            node.get("text")
            or node.get("mention")
            or node.get("name")
            or node.get("obj")
            or ""
        )
        entity_type = (
            node.get("type")
            or node.get("obj")
            or node.get("concept")
            or ""
        )
        if mention and entity_type:
            key = (str(entity_type).strip(), str(mention).strip())
            counts[key] = counts.get(key, 0) + 1

        for value in node.values():
            visit(value)

    visit(payload)
    return [
        {"type": entity_type, "name": name, "mentions": mentions}
        for (entity_type, name), mentions in sorted(counts.items(), key=lambda item: (-item[1], item[0][0], item[0][1]))
    ]


def _parse_pubtator_text(text):
    counts = {}
    for line in str(text).splitlines():
        if "\t" not in line:
            continue
        fields = line.split("\t")
        if len(fields) < 5:
            continue
        name = fields[3].strip()
        entity_type = fields[4].strip()
        if not name or not entity_type:
            continue
        key = (entity_type, name)
        counts[key] = counts.get(key, 0) + 1

    return [
        {"type": entity_type, "name": name, "mentions": mentions}
        for (entity_type, name), mentions in sorted(counts.items(), key=lambda item: (-item[1], item[0][0], item[0][1]))
    ]


def _extract_pmid_from_xml(pmcid, pmc_xml_dir):
    xml_path = Path(pmc_xml_dir) / f"{pmcid}.xml"
    if not xml_path.exists():
        return ""
    try:
        root = ET.parse(xml_path).getroot()
    except Exception as exc:
        warn(f"failed to parse XML {xml_path}: {exc}")
        return ""
    for element in root.iter():
        if _local_name(element.tag) != "article-id":
            continue
        if str(element.attrib.get("pub-id-type", "")).lower() == "pmid":
            return str(element.text or "").strip()
    return ""


def annotate_text(text, pmcid, output_dir, pmid=None):
    _ = text
    annotations_dir = Path(output_dir)
    annotations_dir.mkdir(parents=True, exist_ok=True)
    output_path = annotations_dir / f"{pmcid}.json"

    if output_path.exists():
        try:
            cached = json.loads(output_path.read_text(encoding="utf-8"))
            return cached.get("entities") or []
        except Exception:
            pass

    resolved_pmid = str(pmid or "").strip()
    if not resolved_pmid and str(text).strip().isdigit():
        resolved_pmid = str(text).strip()
    if not resolved_pmid:
        warn(f"missing PMID for {pmcid}; skipping annotation")
        return []

    url = f"{ANNOTATION_URL}/{resolved_pmid}?concepts=Gene,Species,Disease,Chemical"
    response = _safe_get(url, sleep_seconds=0.34)
    if response is None:
        return []

    entities = []
    try:
        entities = _parse_json_entities(response.json())
    except Exception:
        entities = _parse_pubtator_text(response.text)

    payload = {
        "pmcid": pmcid,
        "pmid": resolved_pmid,
        "entities": entities,
    }
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return entities


def annotate_all(pmcid_list, output_dir, pmc_xml_dir, methods_dir):
    results = {}
    methods_path = Path(methods_dir)

    for pmcid in pmcid_list:
        methods_file = methods_path / f"{pmcid}.txt"
        methods_text = methods_file.read_text(encoding="utf-8").strip() if methods_file.exists() else ""
        pmid = _extract_pmid_from_xml(pmcid, pmc_xml_dir)
        entities = annotate_text(methods_text, pmcid, output_dir, pmid=pmid)
        results[pmcid] = {
            "pmid": pmid,
            "entities": entities,
            "methods_text": methods_text,
        }

    return results
