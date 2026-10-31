#!/usr/bin/env python

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SECTION_KEYWORDS = [
    "methods",
    "method",
    "materials and methods",
    "experimental procedures",
    "bioinformatic",
    "data analysis",
    "computational methods",
    "statistical analysis",
]


def warn(message):
    print(f"[methods_extractor] WARNING {message}", file=sys.stderr)


def _local_name(tag):
    return str(tag).rsplit("}", 1)[-1].lower()


def _clean_text(text):
    cleaned = re.sub(r"\$.*?\$", " ", text, flags=re.S)
    cleaned = re.sub(r"\\\(.+?\\\)", " ", cleaned, flags=re.S)
    cleaned = re.sub(r"[ \t]+", " ", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _matches_methods_title(title):
    lowered = str(title or "").strip().lower()
    if not lowered:
        return False
    return any(keyword in lowered for keyword in SECTION_KEYWORDS)


def _child_text(element, child_name):
    for child in list(element):
        if _local_name(child.tag) == child_name:
            return " ".join("".join(child.itertext()).split())
    return ""


def _extract_list_text(list_element):
    items = []
    for child in list(list_element):
        if _local_name(child.tag) == "list-item":
            text = " ".join("".join(child.itertext()).split())
            if text:
                items.append(f"- {text}")
    if items:
        return "\n".join(items)
    return " ".join("".join(list_element.itertext()).split())


def _collect_section_content(sec_element):
    blocks = []
    section_title = _child_text(sec_element, "title")
    if section_title:
        blocks.append(section_title)

    for child in list(sec_element):
        child_tag = _local_name(child.tag)
        if child_tag == "p":
            text = " ".join("".join(child.itertext()).split())
            if text:
                blocks.append(text)
        elif child_tag == "list":
            text = _extract_list_text(child)
            if text:
                blocks.append(text)
        elif child_tag == "sec":
            nested_text = _collect_section_content(child)
            if nested_text:
                blocks.append(nested_text)

    return "\n\n".join([block for block in blocks if block.strip()]).strip()


def _extract_article_id(root, id_type):
    for element in root.iter():
        if _local_name(element.tag) != "article-id":
            continue
        if str(element.attrib.get("pub-id-type", "")).lower() == id_type.lower():
            return str(element.text or "").strip()
    return ""


def extract_methods(xml_path):
    try:
        root = ET.parse(xml_path).getroot()
    except Exception as exc:
        warn(f"failed to parse XML {xml_path}: {exc}")
        return ""

    blocks = []
    for element in root.iter():
        if _local_name(element.tag) != "sec":
            continue
        title = _child_text(element, "title")
        if not _matches_methods_title(title):
            continue
        section_text = _collect_section_content(element)
        if section_text:
            blocks.append(section_text)

    if not blocks:
        return ""

    combined = "\n\n".join(blocks)
    return _clean_text(combined)


def extract_all_methods(pmc_dir, methods_dir):
    pmc_path = Path(pmc_dir)
    methods_path = Path(methods_dir)
    methods_path.mkdir(parents=True, exist_ok=True)
    skipped_entries = []
    extracted = []

    for xml_file in sorted(pmc_path.glob("*.xml")):
        pmcid = xml_file.stem
        methods_text = extract_methods(xml_file)
        if methods_text:
            output_file = methods_path / f"{pmcid}.txt"
            output_file.write_text(methods_text + "\n", encoding="utf-8")
            extracted.append((pmcid, methods_text))
            continue

        try:
            root = ET.parse(xml_file).getroot()
            pmid = _extract_article_id(root, "pmid") or pmcid
        except Exception:
            pmid = pmcid
        skipped_entries.append(pmid)

    skipped_path = methods_path.parent / "skipped_no_methods.txt"
    skipped_path.write_text(
        "\n".join(skipped_entries) + ("\n" if skipped_entries else ""),
        encoding="utf-8",
    )
    return extracted
