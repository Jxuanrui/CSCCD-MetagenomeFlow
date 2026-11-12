#!/usr/bin/env python3
"""Stage 0 read-only preflight for table-driven metagenome batch runs.

Reads the user-supplied per-dataset .xlsx tables (ENA/SRA "filereport" sheet
plus a "Metadata" sheet) and reports run counts, FASTQ layout, metadata
coverage, group-like metadata columns, alias coverage and blockers. Stage 0
writes nothing and makes no network access; the optional --verify-ena path is
read-only ENA metadata verification only. Workbook parts are read with
zipfile + ElementTree (standard library only).

Usage:
  python3 Project/CRC_PiPiXia/ingest/run_tables.py --tables-dir <dir> [--json] [--dry-run]
  python3 Project/CRC_PiPiXia/ingest/run_tables.py --table <xlsx> [--json] [--dry-run]
  python3 Project/CRC_PiPiXia/ingest/run_tables.py --tables-dir <dir> --verify-ena [--json]

Stage 0 is always offline. `--verify-ena` is an explicit opt-in: it performs one
read-only ENA Portal filereport metadata query per locally READY table and
reconciles the expected run whitelist; it never downloads FASTQ, never writes
files and never touches db/ or Project/. `--dry-run` and `--verify-ena` are
mutually exclusive so an explicit dry-run can never hit the network. The
`--strict-remote-set` option (verify mode only) requires the ENA run set to
equal the table set; the default treats the table as the download whitelist and
reports extra ENA runs as warnings only.

Exit codes: 0 all tables parsed and all requested ENA queries completed; 1 at
least one parse failure or ENA verification failure; 2 CLI error, missing path,
no .xlsx table found, or conflicting flags.
"""

import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

MAIN_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
REL_NS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
PRJ_RE = re.compile(r"PRJ[A-Z]{2}[0-9]+")
MD5_RE = re.compile(r"^[0-9a-fA-F]{32}$")

# Fixed ENA Portal endpoint: the host is never taken from a table cell.
ENA_ENDPOINT = "https://www.ebi.ac.uk/ena/portal/api/filereport"
ENA_FIELDS = ("run_accession,library_strategy,library_layout,"
              "fastq_ftp,fastq_md5,fastq_bytes,base_count")
ENA_TIMEOUT_S = 60
ENA_RETRIES = 2
ENA_RETRY_SLEEP_S = 5
ENA_REQUEST_GAP_S = 1
MAX_BASE_COUNT = 10 ** 13
ALLOWED_STRATEGIES = {"WGS"}
ALLOWED_LAYOUTS = {"PAIRED"}
ALLOWED_FASTQ_HOSTS = {"ftp.sra.ebi.ac.uk"}

# Lower-case substrings that make a metadata column a potential group variable.
GROUP_KEYWORDS = ("response", "disease", "group", "cohort", "condition",
                  "body_site", "site", "period", "timepoint")
FILEREPORT_ALIASES = ("sample_alias", "run_alias")
METADATA_ALIASES = ("sample_alias", "sampleid2", "access_id")
LAYOUT_KEYS = ("paired", "single_file", "multi_file", "no_fastq")


# --- workbook plumbing -----------------------------------------------------

def _column_index(ref):
    """Zero-based column index of an A1-style ref, or -1."""
    index, seen = 0, False
    for char in ref:
        if char.isalpha():
            index, seen = index * 26 + ord(char.upper()) - 64, True
        elif char.isdigit():
            break
        else:
            return -1
    return index - 1 if seen else -1


def _cell_value(cell, shared):
    """Decode one <c> cell: shared string, inline string, numeric or empty."""
    cell_type, value = cell.get("t"), cell.find(MAIN_NS + "v")
    if cell_type == "s":
        if value is None or value.text is None:
            return ""
        try:
            return shared[int(value.text)]
        except (ValueError, IndexError):
            return ""
    inline = cell.find(MAIN_NS + "is")
    if inline is not None:
        return "".join(node.text or "" for node in inline.iter(MAIN_NS + "t"))
    return value.text if value is not None and value.text is not None else ""


def _read_shared_strings(workbook):
    if "xl/sharedStrings.xml" not in workbook.namelist():
        return []
    root = ET.fromstring(workbook.read("xl/sharedStrings.xml"))
    return ["".join(node.text or "" for node in item.iter(MAIN_NS + "t"))
            for item in root.findall(MAIN_NS + "si")]


def _sheet_targets(workbook):
    """Map sheet names to worksheet parts using the workbook relationships."""
    names = set(workbook.namelist())
    rels = {}
    if "xl/_rels/workbook.xml.rels" in names:
        for rel in ET.fromstring(workbook.read("xl/_rels/workbook.xml.rels")):
            rels[rel.get("Id")] = rel.get("Target", "")
    sheets = ET.fromstring(workbook.read("xl/workbook.xml")).find(MAIN_NS + "sheets")
    targets = []
    for sheet in ([] if sheets is None else sheets.findall(MAIN_NS + "sheet")):
        target = rels.get(sheet.get(REL_NS + "id"), "")
        target = target.lstrip("/") if target.startswith("/") else target
        if target and not target.startswith("xl/"):
            target = "xl/" + target
        if target not in names:
            guess = "xl/worksheets/sheet%d.xml" % (len(targets) + 1)
            target = guess if guess in names else ""
        targets.append((sheet.get("name") or "", target))
    return targets


def _read_sheet(workbook, shared, target):
    """Read a worksheet as padded rows of stripped text, aligned by cell ref."""
    if not target:
        raise ValueError("worksheet part not found in workbook")
    rows = []
    for row in ET.fromstring(workbook.read(target)).iter(MAIN_NS + "row"):
        cells = {}
        for position, cell in enumerate(row.findall(MAIN_NS + "c")):
            column = _column_index(cell.get("r") or "")
            cells[column if column >= 0 else position] = _cell_value(cell, shared).strip()
        if not cells:
            rows.append([])
            continue
        rows.append([cells.get(column, "") for column in range(max(cells) + 1)])
    return rows


def _find_sheet(sheets, keyword, fallback_index):
    """Locate a sheet by name; exact match wins, then substring, then index.

    Returns (name, target, match_kind); match_kind is exact/substring/fallback/
    missing so callers can disclose a silent positional fallback.
    """
    for name, target in sheets:
        if name.strip().lower() == keyword:
            return name, target, "exact"
    for name, target in sheets:
        if keyword in name.lower():
            return name, target, "substring"
    if 0 <= fallback_index < len(sheets):
        name, target = sheets[fallback_index]
        return name, target, "fallback"
    return "", "", "missing"


def _parse_header(rows):
    """Return (header, lower-case name -> index, first data row index)."""
    header, start = [], 0
    for position, row in enumerate(rows):
        if any(row):
            header, start = list(row), position + 1
            break
    named = [position for position, name in enumerate(header) if name]
    header = header[:named[-1] + 1] if named else []
    index = {}
    for position, name in enumerate(header):
        key = name.strip().lower()
        if key and key not in index:
            index[key] = position
    return header, index, start


def _get(row, position):
    if position is None or position < 0 or position >= len(row):
        return ""
    return row[position]


# --- per-table analysis ----------------------------------------------------

def _study_id(source_file, study_sheet):
    """Dataset study accession plus a filename-vs-sheet conflict flag."""
    file_match, sheet_match = PRJ_RE.search(source_file), PRJ_RE.search(study_sheet)
    conflict = bool(file_match and sheet_match
                    and file_match.group(0) != sheet_match.group(0))
    dataset = (file_match or sheet_match)
    return (dataset.group(0) if dataset else "unknown"), conflict


def _fastq_urls(aspera_value):
    """Non-empty FASTQ URLs from a filereport fastq_aspera cell."""
    return [part.strip() for part in aspera_value.split(";") if part.strip()]


def _classify_layout(aspera_value):
    """Classify a run by the number of non-empty FASTQ URLs in fastq_aspera."""
    return {2: "paired", 1: "single_file", 0: "no_fastq"}.get(
        len(_fastq_urls(aspera_value)), "multi_file")


def _group_candidates(header, metadata_by_run):
    """Metadata columns that look like group variables (2..12 values)."""
    found = []
    for position, column in enumerate(header):
        name = column.strip()
        if not name or not any(key in name.lower() for key in GROUP_KEYWORDS):
            continue
        examples, seen = [], set()
        for row in metadata_by_run.values():
            value = _get(row, position)
            if value and value not in seen:
                seen.add(value)
                examples.append(value)
        if 2 <= len(examples) <= 12:
            found.append({"column": name, "distinct": len(examples),
                          "examples": examples[:4]})
    return found


def _alias_stats(filereport_index, first_rows, run_order,
                 metadata_index, metadata_by_run):
    """First alias-like column carrying data (filereport before metadata)."""
    for column in FILEREPORT_ALIASES:
        position = filereport_index.get(column)
        if position is not None:
            values = [_get(first_rows[run], position) for run in run_order]
            values = [value for value in values if value]
            if values:
                return column, len(values), len(set(values))
    for column in METADATA_ALIASES:
        position = metadata_index.get(column)
        if position is not None:
            values = [_get(metadata_by_run.get(run, ""), position) for run in run_order]
            values = [value for value in values if value]
            if values:
                return column, len(values), len(set(values))
    return None, 0, 0


def _mentions_16s(source_file, sheets):
    names = [source_file] + [name for name, _ in sheets]
    return any("16s" in text.lower() for text in names)


def parse_table(path):
    """Analyse one .xlsx table. Raises on malformed workbooks."""
    source_file = os.path.basename(path)
    with zipfile.ZipFile(path) as workbook:
        shared, sheets = _read_shared_strings(workbook), _sheet_targets(workbook)
        if not sheets:
            raise ValueError("workbook has no worksheets")
        study_sheet, study_target, study_match = _find_sheet(sheets, "filereport", 0)
        metadata_sheet, metadata_target, metadata_match = _find_sheet(sheets, "metadata", 4)
        filereport_rows = _read_sheet(workbook, shared, study_target)
        metadata_rows = _read_sheet(workbook, shared, metadata_target) if metadata_target else []

    # filereport: unique runs, duplicates and FASTQ layout
    _, fr_index, fr_start = _parse_header(filereport_rows)
    accession_position = fr_index.get("run_accession")
    aspera_position = fr_index.get("fastq_aspera")
    run_order, first_rows, duplicate_runs = [], {}, 0
    missing_run_accession_rows = 0
    for row in filereport_rows[fr_start:]:
        accession = _get(row, accession_position)
        if not accession:
            if any(cell.strip() for cell in row):
                missing_run_accession_rows += 1
            continue
        if accession in first_rows:
            duplicate_runs += 1
            continue
        run_order.append(accession)
        first_rows[accession] = row
    layout_counts = {key: 0 for key in LAYOUT_KEYS}
    duplicate_fastq_urls = 0
    for accession in run_order:
        urls = _fastq_urls(_get(first_rows[accession], aspera_position))
        layout_counts[_classify_layout(";".join(urls))] += 1
        if len(urls) == 2 and urls[0] == urls[1]:
            duplicate_fastq_urls += 1

    # metadata: coverage, duplicate run rows, group-like columns
    md_header, md_index, md_start = _parse_header(metadata_rows)
    md_accession_position = md_index.get("run_accession")
    metadata_by_run, metadata_row_count, metadata_duplicate_runs = {}, 0, 0
    missing_metadata_accession_rows = 0
    for row in metadata_rows[md_start:]:
        accession = _get(row, md_accession_position)
        if not accession:
            if any(cell.strip() for cell in row):
                missing_metadata_accession_rows += 1
            continue
        metadata_row_count += 1
        if accession in metadata_by_run:
            metadata_duplicate_runs += 1
            continue
        metadata_by_run[accession] = row
    runs = len(run_order)
    metadata_matched = sum(1 for accession in run_order if accession in metadata_by_run)
    metadata_missing = runs - metadata_matched
    metadata_join_rate = round(metadata_matched / runs, 4) if runs else 0.0
    alias_source, alias_present, alias_unique = _alias_stats(
        fr_index, first_rows, run_order, md_index, metadata_by_run)
    alias_duplicates = alias_present - alias_unique

    # warnings are visibility-only; they do not relax any blocker below
    dataset_id, study_conflict = _study_id(source_file, study_sheet)
    warnings = []
    if alias_duplicates:
        warnings.append("alias_duplicates")
    if alias_source and alias_present < runs:
        warnings.append("alias_missing")
    if study_match == "fallback":
        warnings.append("filereport_sheet_fallback")
    if metadata_match == "fallback":
        warnings.append("metadata_sheet_fallback")

    # blockers, in a stable reporting order
    blockers = []
    if study_conflict:
        blockers.append("study_id_conflict")
    if dataset_id == "unknown":
        blockers.append("study_id_missing")
    if _mentions_16s(source_file, sheets):
        blockers.append("suspected_16S")
    if layout_counts["single_file"]:
        blockers.append("single_file_layout")
    if layout_counts["multi_file"] or layout_counts["no_fastq"]:
        blockers.append("ambiguous_or_missing_fastq")
    if duplicate_fastq_urls:
        blockers.append("duplicate_fastq_urls")
    if duplicate_runs:
        blockers.append("duplicate_runs")
    if missing_run_accession_rows:
        blockers.append("missing_run_accession")
    if metadata_match == "missing":
        blockers.append("metadata_sheet_missing")
    if metadata_duplicate_runs:
        blockers.append("duplicate_metadata_runs")
    if missing_metadata_accession_rows:
        blockers.append("missing_metadata_accession")
    if runs and metadata_matched == 0:
        blockers.append("no_metadata_join")
    elif metadata_missing:
        # Stage-1 pilot requires full metadata coverage; do not let a
        # partially joined table reach READY and be consumed silently.
        blockers.append("metadata_join_partial")
    if not run_order:
        blockers.append("no_runs")

    return {
        "dataset_id": dataset_id,
        "source_file": source_file,
        "study_sheet": study_sheet,
        "study_sheet_match": study_match,
        "metadata_sheet": metadata_sheet,
        "metadata_sheet_match": metadata_match,
        "runs": runs,
        "paired": layout_counts["paired"],
        "single_file": layout_counts["single_file"],
        "multi_file": layout_counts["multi_file"],
        "no_fastq": layout_counts["no_fastq"],
        "duplicate_fastq_urls": duplicate_fastq_urls,
        "duplicate_runs": duplicate_runs,
        "missing_run_accession_rows": missing_run_accession_rows,
        "metadata_rows": metadata_row_count,
        "metadata_matched": metadata_matched,
        "metadata_missing": metadata_missing,
        "metadata_join_rate": metadata_join_rate,
        "metadata_columns": sum(1 for name in md_header if name),
        "metadata_duplicate_runs": metadata_duplicate_runs,
        "missing_metadata_accession_rows": missing_metadata_accession_rows,
        "alias_source": alias_source,
        "alias_present": alias_present,
        "alias_unique": alias_unique,
        "alias_duplicates": alias_duplicates,
        "group_candidates": _group_candidates(md_header, metadata_by_run),
        "warnings": warnings,
        "expected_runs": run_order,
        "status": "BLOCKED" if blockers else "READY",
        "status_note": ("table-level preflight only; READY does not verify "
                        "shotgun/library layout (stage-1 ENA check required)"),
        "blockers": blockers,
    }


# --- Stage 1a: read-only ENA verification ----------------------------------

class VerifyError(Exception):
    """A bounded ENA query could not be completed or parsed."""


def _ena_url(study):
    """Fixed-host ENA Portal filereport URL for one study (read-only)."""
    query = urllib.parse.urlencode({
        "accession": study,
        "result": "read_run",
        "fields": ENA_FIELDS,
        "format": "json",
    })
    return ENA_ENDPOINT + "?" + query


def _ssl_context():
    """Prefer the system CA bundle; the migrated conda env points at a dead
    /home/labuser path, so the default OpenSSL cafile can be missing."""
    cafile = os.environ.get("SSL_CERT_FILE")
    if not cafile:
        for candidate in ("/etc/ssl/certs/ca-certificates.crt",
                          "/etc/pki/tls/certs/ca-bundle.crt"):
            if os.path.isfile(candidate):
                cafile = candidate
                break
    try:
        return (ssl.create_default_context(cafile=cafile) if cafile
                else ssl.create_default_context())
    except (OSError, ssl.SSLError):
        return ssl.create_default_context()


def _http_fetch_json(url):
    """Fetch one URL with fixed timeout and bounded retries; no writes."""
    request = urllib.request.Request(
        url, headers={"User-Agent": "CSCCD-MetagenomeFlow/stage1a"})
    context = _ssl_context()
    last_error = None
    for attempt in range(ENA_RETRIES + 1):
        try:
            with urllib.request.urlopen(request, timeout=ENA_TIMEOUT_S,
                                        context=context) as response:
                body = response.read().decode("utf-8", errors="replace")
            return json.loads(body)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError,
                OSError, ValueError) as exc:
            last_error = exc
            if attempt < ENA_RETRIES:
                time.sleep(ENA_RETRY_SLEEP_S * (attempt + 1))
    raise VerifyError("%s: %s" % (type(last_error).__name__, last_error))


def _valid_fastq_url(value):
    """Accept only ENA SRA FASTQ URLs under the fixed /vol1/ tree."""
    raw = str(value or "").strip()
    candidate = raw if "://" in raw else "https://" + raw
    try:
        parts = urllib.parse.urlsplit(candidate)
    except ValueError:
        return False
    if parts.scheme not in ("http", "https", "ftp"):
        return False
    if parts.netloc.lower() not in ALLOWED_FASTQ_HOSTS:
        return False
    path = parts.path.lower()
    if not path.startswith("/vol1/"):
        return False
    return path.endswith(".fastq.gz") or path.endswith(".fq.gz")


def _verify_run_fields(entry):
    """Return field-level problems for one remote run (empty list = valid)."""
    problems = []
    strategy = str(entry.get("library_strategy") or "").strip()
    if strategy not in ALLOWED_STRATEGIES:
        problems.append(("strategy_not_allowed", strategy or "<empty>"))
    layout = str(entry.get("library_layout") or "").strip()
    if layout not in ALLOWED_LAYOUTS:
        problems.append(("layout_not_allowed", layout or "<empty>"))

    urls = [part.strip() for part in str(entry.get("fastq_ftp") or "").split(";")
            if part.strip()]
    if len(urls) != 2:
        problems.append(("fastq_url_count", str(len(urls))))
    elif urls[0] == urls[1]:
        problems.append(("duplicate_fastq_urls", urls[0]))
    elif not all(_valid_fastq_url(url) for url in urls):
        problems.append(("fastq_url_invalid", ";".join(urls)))

    md5s = [part.strip() for part in str(entry.get("fastq_md5") or "").split(";")
            if part.strip()]
    if len(md5s) != 2 or any(not MD5_RE.match(value) for value in md5s):
        problems.append(("md5_invalid", ";".join(md5s) or "<empty>"))

    base_text = str(entry.get("base_count") or "").strip()
    try:
        base_count = int(base_text)
        if base_count < 0 or base_count > MAX_BASE_COUNT:
            raise ValueError
    except (TypeError, ValueError):
        problems.append(("base_count_invalid", base_text or "<empty>"))
    return problems


def verify_dataset(dataset, fetcher=None, strict_remote_set=False):
    """Verify one locally READY dataset against ENA; never downloads data.

    The table's expected runs are the download whitelist. All expected runs
    must be present and valid; remote extra runs are reported but never added
    or downloaded. `strict_remote_set=True` additionally requires exact set
    equality (useful only when the table is meant to be a complete study).
    Local Stage 0 blockers are never overwritten; query/parse failures are
    kept distinct from a completed query that found unusable data.
    """
    study = dataset.get("dataset_id") or ""
    expected = list(dataset.get("expected_runs") or [])
    result = {
        "local_status": dataset.get("status"),
        "query_study": study,
        "verify_status": "NOT_RUN",
        "final_status": dataset.get("status"),
        "remote_runs": 0,
        "verify_blockers": [],
        "verify_warnings": [],
        "verify_details": {},
    }

    # Local blockers are authoritative: never query around them.
    if dataset.get("status") != "READY":
        result["verify_status"] = "SKIPPED_LOCAL_BLOCKED"
        result["final_status"] = "BLOCKED_LOCAL"
        result["verify_blockers"] = ["local_preflight_blocked"]
        return result

    if not PRJ_RE.fullmatch(study):
        result["verify_status"] = "VERIFY_FAILED"
        result["final_status"] = "VERIFY_FAILED"
        result["verify_blockers"] = ["invalid_study_accession"]
        return result
    if not expected:
        result["verify_status"] = "VERIFY_FAILED"
        result["final_status"] = "VERIFY_FAILED"
        result["verify_blockers"] = ["empty_expected_runs"]
        return result
    if len(expected) != len(set(expected)):
        result["verify_status"] = "VERIFY_FAILED"
        result["final_status"] = "VERIFY_FAILED"
        result["verify_blockers"] = ["duplicate_expected_runs"]
        return result

    fetch = fetcher or _http_fetch_json
    try:
        payload = fetch(_ena_url(study))
    except Exception as exc:  # bounded query failure: not a data verdict
        result["verify_status"] = "VERIFY_FAILED"
        result["final_status"] = "VERIFY_FAILED"
        result["verify_blockers"] = ["query_failed"]
        result["verify_details"]["query_error"] = str(exc)[:300]
        return result

    if not isinstance(payload, list):
        result["verify_status"] = "VERIFY_FAILED"
        result["final_status"] = "VERIFY_FAILED"
        result["verify_blockers"] = ["invalid_response"]
        return result

    required = ("run_accession", "library_strategy", "library_layout",
                "fastq_ftp", "fastq_md5", "base_count")
    remote, duplicate_remote, missing_fields = {}, 0, set()
    for entry in payload:
        if not isinstance(entry, dict):
            result["verify_status"] = "VERIFY_FAILED"
            result["final_status"] = "VERIFY_FAILED"
            result["verify_blockers"] = ["invalid_response"]
            return result
        missing = [field for field in required if field not in entry]
        if missing:
            missing_fields.update(missing)
            continue
        run = str(entry.get("run_accession") or "").strip()
        if not run:
            result["verify_status"] = "VERIFY_FAILED"
            result["final_status"] = "VERIFY_FAILED"
            result["verify_blockers"] = ["empty_remote_run_accession"]
            return result
        if run in remote:
            duplicate_remote += 1
            continue
        remote[run] = entry

    if missing_fields:
        result["verify_status"] = "VERIFY_FAILED"
        result["final_status"] = "VERIFY_FAILED"
        result["verify_blockers"] = ["missing_required_fields"]
        result["verify_details"]["missing_fields"] = sorted(missing_fields)
        return result

    expected_set, remote_set = set(expected), set(remote)
    missing_runs = sorted(expected_set - remote_set)
    extra_runs = sorted(remote_set - expected_set)
    result["remote_runs"] = len(remote)
    issues = {}
    for run in expected:
        entry = remote.get(run)
        if entry is None:
            continue
        for problem, value in _verify_run_fields(entry):
            issues.setdefault(problem, []).append([run, value])

    blockers = []
    if not remote:
        blockers.append("no_remote_runs")
    if missing_runs:
        blockers.append("missing_remote_runs")
    if extra_runs:
        if strict_remote_set:
            blockers.append("extra_remote_runs")
        else:
            # The user's tables are curated subsets of the study. Extra ENA
            # runs are never added to the download whitelist; report them.
            result["verify_warnings"].append("extra_remote_runs")
    if duplicate_remote:
        blockers.append("duplicate_remote_runs")
    for name in ("strategy_not_allowed", "layout_not_allowed",
                 "fastq_url_count", "duplicate_fastq_urls", "fastq_url_invalid",
                 "md5_invalid", "base_count_invalid"):
        if issues.get(name):
            blockers.append(name)

    details = {
        "expected_runs": len(expected),
        "remote_runs": len(remote),
        "missing_runs": len(missing_runs),
        "extra_runs": len(extra_runs),
        "duplicate_remote_runs": duplicate_remote,
        "failed_runs": len({row[0] for rows in issues.values() for row in rows}),
        "missing_examples": missing_runs[:10],
        "extra_examples": extra_runs[:10],
        "field_issue_counts": {name: len(rows) for name, rows in issues.items()},
        "field_issue_examples": {name: rows[:5] for name, rows in issues.items()},
    }
    result["verify_details"] = details

    if blockers:
        result["verify_status"] = "BLOCKED"
        result["final_status"] = "BLOCKED_VERIFY"
        result["verify_blockers"] = blockers
        return result

    result["verify_status"] = "VERIFIED"
    result["final_status"] = "VERIFIED"
    return result


# --- batch report ----------------------------------------------------------

def build_report(table_paths, tables_dir, verify_ena=False, fetcher=None,
                 strict_remote_set=False):
    datasets, errors = [], []
    for path in table_paths:
        try:
            datasets.append(parse_table(path))
        except Exception as exc:  # one malformed table must not stop the batch
            errors.append({"source_file": os.path.basename(path),
                           "error": "%s: %s" % (type(exc).__name__, exc)})

    if verify_ena:
        for item in datasets:
            item["verification"] = verify_dataset(
                item, fetcher=fetcher, strict_remote_set=strict_remote_set)
            if item["status"] == "READY":
                # one polite gap per actual query; local-blocked datasets
                # never touch the network and therefore never sleep
                time.sleep(ENA_REQUEST_GAP_S)

    ready = [item for item in datasets if item["status"] == "READY"]
    blocked = [item for item in datasets if item["status"] == "BLOCKED"]
    verified = [item for item in datasets
                if (item.get("verification") or {}).get("verify_status") == "VERIFIED"]
    verify_failed = [item for item in datasets
                     if (item.get("verification") or {}).get("verify_status")
                     == "VERIFY_FAILED"]
    verify_blocked = [item for item in datasets
                      if (item.get("verification") or {}).get("verify_status")
                      == "BLOCKED"]
    skipped = [item for item in datasets
               if (item.get("verification") or {}).get("verify_status")
               == "SKIPPED_LOCAL_BLOCKED"]
    summary = {
        "files_scanned": len(table_paths),
        "total_runs": sum(item["runs"] for item in datasets),
        "total_paired": sum(item["paired"] for item in datasets),
        "total_single_file": sum(item["single_file"] for item in datasets),
        "total_ready": len(ready),
        "total_blocked": len(blocked),
        "total_ready_runs": sum(item["runs"] for item in ready),
        "total_blocked_runs": sum(item["runs"] for item in blocked),
        "verified": len(verified),
        "verify_failed": len(verify_failed),
        "verify_blocked": len(verify_blocked),
        "skipped_local_blocked": len(skipped),
        "verify_warnings": sum(
            1 for item in datasets
            if (item.get("verification") or {}).get("verify_warnings")),
        "ready_for_pilot": [{"dataset_id": item["dataset_id"],
                             "runs": item["runs"]} for item in verified],
        "ready": [{"dataset_id": item["dataset_id"], "source_file": item["source_file"],
                   "runs": item["runs"]} for item in ready],
        "blocked": [{"dataset_id": item["dataset_id"], "source_file": item["source_file"],
                     "runs": item["runs"], "blockers": item["blockers"]} for item in blocked],
    }
    report = {"mode": "verify-ena" if verify_ena else "dry-run",
              "tables_dir": tables_dir, "datasets": datasets,
              "summary": summary, "errors": errors}
    exit_code = 1 if errors else 0
    if verify_ena and verify_failed:
        exit_code = 1
    return report, exit_code


def format_human(report):
    if report["mode"] == "verify-ena":
        lines = ["Table-driven batch preflight + read-only ENA verification (stage 1a)"]
    else:
        lines = ["Table-driven batch preflight (stage 0, read-only, dry-run)"]
    if report["tables_dir"]:
        lines.append("tables dir: %s" % report["tables_dir"])
    lines.append("")
    for item in report["datasets"]:
        lines.append("[%s] %s  %s" % (item["status"], item["dataset_id"], item["source_file"]))
        lines.append("  sheet=%s runs=%d paired=%d single_file=%d multi_file=%d "
                     "no_fastq=%d duplicates=%d"
                     % (item["study_sheet"], item["runs"], item["paired"],
                        item["single_file"], item["multi_file"], item["no_fastq"],
                        item["duplicate_runs"]))
        lines.append("  metadata=%d rows, %d/%d runs joined (%.1f%%), %d columns, "
                     "%d duplicate run rows"
                     % (item["metadata_rows"], item["metadata_matched"], item["runs"],
                        100.0 * item["metadata_join_rate"], item["metadata_columns"],
                        item["metadata_duplicate_runs"]))
        if item["alias_source"]:
            lines.append("  alias=%s present=%d unique=%d duplicates=%d"
                         % (item["alias_source"], item["alias_present"],
                            item["alias_unique"], item["alias_duplicates"]))
        else:
            lines.append("  alias=none")
        if item["group_candidates"]:
            for candidate in item["group_candidates"]:
                lines.append("  group-like %s: %d distinct e.g. %s"
                             % (candidate["column"], candidate["distinct"],
                                ", ".join(candidate["examples"])))
        else:
            lines.append("  group-like: none")
        if item["warnings"]:
            lines.append("  warnings: %s" % ", ".join(item["warnings"]))
        if item["blockers"]:
            lines.append("  blockers: %s" % ", ".join(item["blockers"]))
        verification = item.get("verification")
        if verification:
            details = verification.get("verify_details") or {}
            lines.append("  verify=%s final=%s remote_runs=%d"
                         % (verification["verify_status"],
                            verification["final_status"],
                            verification.get("remote_runs", 0)))
            if verification.get("verify_blockers"):
                lines.append("  verify blockers: %s"
                             % ", ".join(verification["verify_blockers"]))
            if verification.get("verify_warnings"):
                lines.append("  verify warnings: %s"
                             % ", ".join(verification["verify_warnings"]))
            if details:
                lines.append("  verify details: expected=%s remote=%s missing=%s "
                             "extra=%s duplicate_remote=%s failed_runs=%s"
                             % (details.get("expected_runs"),
                                details.get("remote_runs"),
                                details.get("missing_runs"),
                                details.get("extra_runs"),
                                details.get("duplicate_remote_runs"),
                                details.get("failed_runs")))
        lines.append("")
    for error in report["errors"]:
        lines.append("ERROR %s: %s" % (error["source_file"], error["error"]))
    if report["errors"]:
        lines.append("")

    summary = report["summary"]
    lines.append("Batch summary")
    lines.append("  files scanned    : %d" % summary["files_scanned"])
    lines.append("  total runs       : %d" % summary["total_runs"])
    lines.append("  total paired     : %d" % summary["total_paired"])
    lines.append("  total single_file: %d" % summary["total_single_file"])
    lines.append("  READY            : %d datasets, %d runs"
                 % (summary["total_ready"], summary["total_ready_runs"]))
    lines.append("  BLOCKED          : %d datasets, %d runs"
                 % (summary["total_blocked"], summary["total_blocked_runs"]))
    lines.append("  READY   (%d): %s" % (
        len(summary["ready"]),
        ", ".join("%s(%d)" % (item["dataset_id"], item["runs"]) for item in summary["ready"])))
    lines.append("  BLOCKED (%d): %s" % (
        len(summary["blocked"]),
        ", ".join("%s(%d)" % (item["dataset_id"], item["runs"]) for item in summary["blocked"])))
    if report["mode"] == "verify-ena":
        lines.append("  VERIFIED             : %d datasets, %d runs"
                     % (summary["verified"],
                        sum(item["runs"] for item in summary["ready_for_pilot"])))
        lines.append("  VERIFY_FAILED        : %d datasets" % summary["verify_failed"])
        lines.append("  BLOCKED_BY_VERIFY    : %d datasets" % summary["verify_blocked"])
        lines.append("  SKIPPED_LOCAL_BLOCKED: %d datasets"
                     % summary["skipped_local_blocked"])
        lines.append("  ready_for_pilot      : %s" % (
            ", ".join("%s(%d)" % (item["dataset_id"], item["runs"])
                      for item in summary["ready_for_pilot"]) or "none"))
        lines.append("  note: VERIFIED means read-only ENA metadata checks passed; "
                     "it is not a download or write authorization")
    else:
        lines.append("  note: READY is table-level only; stage 1 must verify ENA "
                     "library_strategy/layout before any download")
    return "\n".join(lines)


# --- CLI -------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Stage 0 offline preflight and optional Stage 1a read-only ENA "
                    "verification for table-driven metagenome batch runs.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--tables-dir", help="directory of per-dataset .xlsx tables")
    source.add_argument("--table", help="single .xlsx table to inspect")
    parser.add_argument("--json", action="store_true",
                        help="print only a JSON document to stdout")
    parser.add_argument("--dry-run", action="store_true",
                        help="offline preflight only (default); cannot be combined with --verify-ena")
    parser.add_argument("--verify-ena", action="store_true",
                        help="explicit opt-in: one read-only ENA filereport query per locally READY dataset")
    parser.add_argument("--strict-remote-set", action="store_true",
                        help="require the ENA run set to equal the table run set "
                             "(default: table is the whitelist; extra ENA runs are reported only)")
    args = parser.parse_args(argv)
    if args.dry_run and args.verify_ena:
        parser.error("--dry-run and --verify-ena are mutually exclusive")
    if args.strict_remote_set and not args.verify_ena:
        parser.error("--strict-remote-set requires --verify-ena")

    if args.tables_dir:
        if not os.path.isdir(args.tables_dir):
            print("error: tables dir not found: %s" % args.tables_dir, file=sys.stderr)
            return 2
        try:
            names = sorted(os.listdir(args.tables_dir))
        except OSError as exc:
            print("error: cannot read tables dir %s: %s" % (args.tables_dir, exc),
                  file=sys.stderr)
            return 2
        table_paths = [os.path.join(args.tables_dir, name) for name in names
                       if name.lower().endswith(".xlsx") and not name.startswith("~$")
                       and os.path.isfile(os.path.join(args.tables_dir, name))]
        if not table_paths:
            print("error: no .xlsx tables found in %s" % args.tables_dir, file=sys.stderr)
            return 2
    else:
        if not os.path.isfile(args.table):
            print("error: table not found: %s" % args.table, file=sys.stderr)
            return 2
        table_paths = [args.table]

    report, exit_code = build_report(table_paths, args.tables_dir,
                                     verify_ena=args.verify_ena,
                                     strict_remote_set=args.strict_remote_set)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(format_human(report))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
