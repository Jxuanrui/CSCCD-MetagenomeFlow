#!/usr/bin/env python3
"""Weekly incremental discovery of new human gut-metagenome WGS samples via the
seqout REST API (https://seqout.org/api-docs).

Pipeline: watermark window -> study discovery (structured tissue search + text
search fallback) -> per-study bundle (enriched samples / experiments / runs) ->
per-sample candidates gated on library_strategy == WGS -> dedupe against
seed_runs (canonical key + run accessions), against incremental_candidates and
within the batch -> insert survivors into incremental_candidates.

Never writes to seed_runs. Stdlib only. Polite rate limits:
search tier >= 2.5 s between calls (30/min), project tier >= 1.5 s (60/min);
on 429/5xx/network errors: 30 s backoff, one retry, then degrade gracefully.
"""

import argparse
import datetime as dt
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
from pathlib import Path

BASE_URL = "https://seqout.org/api"
ORGANISM = "Homo sapiens"
STRATEGY = "WGS"
# ILIKE substrings on enriched per-sample tissue (structured search).
TISSUE_TERMS = ("feces", "faeces", "stool", "gut", "colon")
# Free-text queries via /search (date_from/date_to) as a fallback for studies
# whose samples are not yet ontology-enriched.
TEXT_QUERIES = ("gut metagenome", "fecal metagenome", "stool metagenome")
SOURCE_MAP = {
    "sra": "SRA", "ena": "ENA", "geo": "GEO", "gsa": "GSA",
    "dra": "DRA", "gea": "GEA", "arrayexpress": "ArrayExpress",
}
# Unified search sometimes labels ENA accessions as source "sra"; the
# accession prefix is the reliable archive indicator.
ACCESSION_ARCHIVE = (
    ("ERS", "ENA"), ("ERP", "ENA"), ("ERX", "ENA"), ("ERR", "ENA"),
    ("SRS", "SRA"), ("SRP", "SRA"), ("SRX", "SRA"), ("SRR", "SRA"),
    ("DRS", "DRA"), ("DRP", "DRA"), ("DRX", "DRA"), ("DRR", "DRA"),
    ("GSE", "GEO"), ("GSM", "GEO"),
    ("PRJNA", "SRA"), ("PRJEB", "ENA"), ("PRJDB", "DRA"),
)


def archive_for(accession, source):
    for prefix, archive in ACCESSION_ARCHIVE:
        if accession.startswith(prefix):
            return archive
    return SOURCE_MAP.get((source or "").lower()) or \
        (source.upper() if source else None)
TIER_GAP = {"search": 2.5, "project": 1.5}
RETRY_HTTP = {429, 500, 502, 503, 504}
BACKOFF_S = 30
MAX_PAGES_PER_QUERY = 20
COLUMNS = (
    "canonical_key", "study_accession", "project_accession", "sample_accession",
    "run_accessions", "source_archive", "study_name", "first_public",
    "body_site", "body_site_uberon", "disease", "disease_mondo",
    "age_years", "sex", "country", "platform", "instrument_model",
    "library_strategy", "library_source", "run_count",
    "discovered_at", "source_query", "status",
)

_last_call = {}


class PermanentError(Exception):
    """Non-retryable HTTP failure (e.g. 404)."""


class RetryError(Exception):
    """Retryable failure that persisted after the 30 s backoff + retry."""


def log(msg):
    print(msg, flush=True)


def _throttle(tier):
    gap = TIER_GAP[tier]
    now = time.monotonic()
    wait = _last_call.get(tier, 0) + gap - now
    if wait > 0:
        time.sleep(wait)
    _last_call[tier] = time.monotonic()


def fetch_json(path, params, tier):
    """GET one seqout endpoint, honouring tier rate limits and backoff policy."""
    url = BASE_URL + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    for attempt in (1, 2):
        _throttle(tier)
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "cscmd-incremental/0.1"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in RETRY_HTTP and attempt == 1:
                log(f"[warn] HTTP {e.code} on {path}; backing off {BACKOFF_S}s")
                time.sleep(BACKOFF_S)
                continue
            if e.code in RETRY_HTTP:
                raise RetryError(f"HTTP {e.code} on {path} after retry")
            raise PermanentError(f"HTTP {e.code} on {path}")
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            if attempt == 1:
                log(f"[warn] network error on {path}: {e}; backing off {BACKOFF_S}s")
                time.sleep(BACKOFF_S)
                continue
            raise RetryError(f"{e} on {path} after retry")


# ---------------------------------------------------------------- discovery --

def paginate(path, base_params, tier="search"):
    """Yield result rows, following the documented cursor pagination."""
    params = dict(base_params)
    rows = []
    for _ in range(MAX_PAGES_PER_QUERY):
        data = fetch_json(path, params, tier)
        batch = data.get("results") or []
        rows.extend(batch)
        cursor = data.get("next_cursor")
        if not cursor or not batch:
            return rows
        params["cursor_rank"] = cursor.get("rank")
        params["cursor_acc"] = cursor.get("accession")
    return rows


def discover_studies(since_str, until_str):
    """Run all discovery queries; return OrderedDict accession -> study info."""
    queries = [("tissue", t) for t in TISSUE_TERMS] + \
              [("text", q) for q in TEXT_QUERIES]
    studies = OrderedDict()
    report = []
    for kind, value in queries:
        label = f"{kind}={value}"
        try:
            if kind == "tissue":
                rows = paginate("/search/structured", {
                    "organism": ORGANISM, "library_strategy": STRATEGY,
                    "sample_tissue": value,
                    "published_after": since_str, "published_before": until_str,
                })
            else:
                rows = paginate("/search", {
                    "q": value, "organism": ORGANISM,
                    "library_strategy": STRATEGY,
                    "date_from": since_str, "date_to": until_str,
                })
        except (RetryError, PermanentError) as e:
            log(f"[warn] discovery query {label} failed: {e}")
            report.append({"kind": kind, "value": value, "studies": 0,
                           "failed": True})
            continue
        new = 0
        for row in rows:
            acc = row.get("accession")
            if not acc:
                continue
            if acc in studies:
                studies[acc]["queries"].append(label)
            else:
                studies[acc] = {"row": row, "queries": [label]}
                new += 1
        report.append({"kind": kind, "value": value, "studies": len(rows),
                       "new": new, "failed": False})
        log(f"[search] {label}: {len(rows)} studies ({new} new)")
    return studies, report


# ------------------------------------------------------------- study bundle --

def fetch_study_bundle(accession):
    """Fetch enriched/experiments/runs for one study.

    Returns the bundle dict; individual keys are None when permanently
    unavailable (404). Raises RetryError when any call failed after backoff.
    """
    bundle = {}
    for key in ("enriched", "experiments", "runs"):
        try:
            bundle[key] = fetch_json(f"/project/{accession}/{key}", None,
                                     "project")
        except PermanentError as e:
            log(f"[study] {accession}: {key} unavailable ({e})")
            bundle[key] = None
    return bundle


def parse_age_years(text):
    if not text:
        return None
    m = re.search(r"([\d.]+)\s*(year|month|week|day)", str(text).lower())
    if not m:
        return None
    value, unit = float(m.group(1)), m.group(2)
    if unit == "year":
        return value
    if unit == "month":
        return round(value / 12.0, 2)
    if unit == "week":
        return round(value / 52.0, 2)
    return round(value / 365.25, 2)  # days


def build_candidates(accession, info, bundle, window_label):
    """Turn one study bundle into per-sample candidate dicts (WGS-gated)."""
    row = info["row"]
    source = (row.get("source") or "").lower()
    first_public = row.get("updated_at")
    if not first_public and row.get("rank"):
        try:  # structured-search rank is the release-date epoch
            first_public = dt.datetime.fromtimestamp(
                int(row["rank"]), dt.timezone.utc).strftime("%Y-%m-%d")
        except (ValueError, OverflowError, OSError):
            first_public = None
    country = (row.get("countries") or [None])[0]
    source_query = ";".join(info["queries"]) + f";window={window_label}"

    enriched = {}
    for s in (bundle.get("enriched") or {}).get("samples") or []:
        if s.get("sample"):
            enriched[s["sample"]] = s

    exp_runs = {}  # experiment accession -> [run accessions]
    for r in (bundle.get("runs") or {}).get("runs") or []:
        exp = r.get("experiment_accession")
        if exp and r.get("run_accession"):
            exp_runs.setdefault(exp, []).append(r["run_accession"])

    sample_exps = {}  # sample accession -> WGS experiment rows
    experiments = bundle.get("experiments") or []
    all_exp_samples = set()  # samples with any experiment record at all
    for exp in experiments:
        for samp in exp.get("samples") or []:
            all_exp_samples.add(samp)
        if str(exp.get("library_strategy", "")).upper() != STRATEGY:
            continue
        for samp in exp.get("samples") or []:
            sample_exps.setdefault(samp, []).append(exp)

    samples = list(dict.fromkeys(list(enriched) + list(sample_exps)))
    candidates = []
    for samp in samples:
        exps = sample_exps.get(samp)
        if not exps and samp in all_exp_samples:
            continue  # every known experiment for this sample is non-WGS
        runs = sorted({r for e in exps or []
                       for r in exp_runs.get(e.get("accession"), [])})
        en = enriched.get(samp) or {}
        first_exp = exps[0] if exps else {}
        candidates.append({
            "canonical_key": samp,
            "study_accession": accession,
            "project_accession": accession if accession.startswith("PRJ") else None,
            "sample_accession": samp,
            "run_accessions": json.dumps(runs),
            "source_archive": archive_for(accession, source),
            "study_name": row.get("title"),
            "first_public": first_public,
            "body_site": en.get("tissue"),
            "body_site_uberon": en.get("tissue_ontology_id"),
            "disease": en.get("disease"),
            "disease_mondo": en.get("disease_ontology_id"),
            "age_years": parse_age_years(en.get("age")),
            "sex": en.get("sex"),
            "country": country,
            "platform": first_exp.get("platform") or
                        (row.get("instrument_models") or [None])[0],
            "instrument_model": first_exp.get("instrument_model"),
            "library_strategy": STRATEGY,
            "library_source": first_exp.get("library_source"),
            "run_count": len(runs),
            "source_query": source_query,
        })
    return candidates


# -------------------------------------------------------------------- store --

DDL = """
CREATE TABLE IF NOT EXISTS incremental_candidates (
    canonical_key       TEXT PRIMARY KEY,
    study_accession     TEXT,
    project_accession   TEXT,
    sample_accession    TEXT,
    run_accessions      TEXT,
    source_archive      TEXT,
    study_name          TEXT,
    first_public        TEXT,
    body_site           TEXT,
    body_site_uberon    TEXT,
    disease             TEXT,
    disease_mondo       TEXT,
    age_years           REAL,
    sex                 TEXT,
    country             TEXT,
    platform            TEXT,
    instrument_model    TEXT,
    library_strategy    TEXT,
    library_source      TEXT,
    run_count           INTEGER,
    discovered_at       TEXT NOT NULL,
    source_query        TEXT,
    status              TEXT NOT NULL DEFAULT 'new'
)
"""


def open_db(path, read_only):
    if read_only:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    else:
        con = sqlite3.connect(path)
        con.execute(DDL)
        con.execute("CREATE INDEX IF NOT EXISTS idx_inc_candidates_study "
                    "ON incremental_candidates(study_accession)")
        con.commit()
    return con


def load_run_set(rows):
    runs = set()
    for (blob,) in rows:
        if not blob:
            continue
        try:
            values = json.loads(blob)
        except (ValueError, TypeError):
            continue
        if isinstance(values, list):
            runs.update(v for v in values if isinstance(v, str))
    return runs


def load_seed_index(con):
    keys = set()
    for key, samp in con.execute(
            "SELECT canonical_key, sample_accession FROM seed_runs"):
        keys.add(key)
        if samp:
            keys.add(samp)
    runs = load_run_set(
        con.execute("SELECT run_accessions FROM seed_runs"))
    return keys, runs


def load_candidate_index(con):
    try:
        keys = {r[0] for r in con.execute(
            "SELECT canonical_key FROM incremental_candidates")}
        runs = load_run_set(
            con.execute("SELECT run_accessions FROM incremental_candidates"))
    except sqlite3.OperationalError:  # table absent in read-only dry-run
        keys, runs = set(), set()
    return keys, runs


def insert_candidates(con, candidates, discovered_at):
    inserted = 0
    placeholders = ",".join("?" * len(COLUMNS))
    for cand in candidates:
        row = dict(cand)
        row["discovered_at"] = discovered_at
        row["status"] = "new"
        cur = con.execute(
            f"INSERT OR IGNORE INTO incremental_candidates "
            f"({','.join(COLUMNS)}) VALUES ({placeholders})",
            [row.get(c) for c in COLUMNS])
        inserted += cur.rowcount
    con.commit()
    return inserted


def index_freshness():
    """Oldest per-source ingestion date (seqout lags archives by days/weeks).

    The watermark must not advance past this, or studies released after it but
    ingested later would be skipped forever. Returns None when unavailable.
    """
    try:
        data = fetch_json("/stats/last-updated", None, "project")
        dates = [str(v)[:10] for v in (data.get("by_source") or {}).values()
                 if v]
        return min(dates) if dates else None
    except (RetryError, PermanentError, ValueError) as e:
        log(f"[warn] could not determine index freshness: {e}")
        return None


# ------------------------------------------------------------------- state --

def load_state(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def write_json(path, payload):
    Path(path).write_text(json.dumps(payload, indent=2) + "\n")


# -------------------------------------------------------------------- main --

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Weekly incremental gut-metagenome discovery via seqout.")
    parser.add_argument("--since", metavar="YYYY-MM-DD",
                        help="override the watermark start date")
    parser.add_argument("--dry-run", action="store_true",
                        help="query and dedupe only; no DB writes")
    parser.add_argument("--max-candidates", type=int, default=200,
                        metavar="N",
                        help="stop after N surviving candidates (default 200)")
    args = parser.parse_args(argv)

    here = Path(__file__).resolve().parent
    db_path = here / "seed_registry.sqlite"
    state_path = here / "incremental_state.json"
    report_path = here / "incremental_last_run.json"

    today = dt.date.today()
    state = load_state(state_path)
    if args.since:
        try:
            since = dt.date.fromisoformat(args.since)
        except ValueError:
            parser.error(f"invalid --since date: {args.since}")
    elif state.get("last_check"):
        since = dt.date.fromisoformat(state["last_check"])
    else:
        since = today - dt.timedelta(days=7)
    until = today + dt.timedelta(days=1)  # inclusive day-granularity bound

    log(f"window: {since} .. {today}  dry_run={args.dry_run}  "
        f"max_candidates={args.max_candidates}")

    con = open_db(db_path, read_only=args.dry_run)
    seed_before = con.execute("SELECT COUNT(*) FROM seed_runs").fetchone()[0]
    seed_keys, seed_runs = load_seed_index(con)
    cand_keys, cand_runs = load_candidate_index(con)
    log(f"seed index: {len(seed_keys)} keys, {len(seed_runs)} runs; "
        f"existing candidates: {len(cand_keys)} keys, {len(cand_runs)} runs")

    discovered_at = dt.datetime.now(dt.timezone.utc).isoformat(
        timespec="seconds")
    counters = {"seed_canonical": 0, "seed_run": 0, "existing_candidate": 0,
                "within_batch": 0}
    survivors = []
    batch_keys = set()   # canonical keys accepted in this run
    batch_runs = set()   # run accessions accepted in this run
    pending = list(state.get("pending_studies") or [])
    pending_done = []
    failed_pending = []
    study_failures = 0

    # Pending studies from a previous degraded run, retried with stored rows.
    pending_set = {p["accession"] for p in pending}
    ordered = [(p["accession"], {"row": p.get("row") or {},
                                  "queries": ["retry"]}) for p in pending]
    studies, query_report = discover_studies(str(since), str(until))
    for acc in list(studies):
        if acc not in pending_set:
            ordered.append((acc, studies[acc]))
    log(f"distinct studies in window: {len(ordered) - len(pending)} "
        f"(+{len(pending)} pending retries)")

    window_label = f"{since}..{today}"
    capped = False
    studies_processed = 0
    for acc, info in ordered:
        if len(survivors) >= args.max_candidates:
            capped = True
            break
        try:
            bundle = fetch_study_bundle(acc)
        except RetryError as e:
            log(f"[study] {acc} failed after retry -> pending: {e}")
            study_failures += 1
            failed_pending.append({"accession": acc, "row": info.get("row") or {}})
            continue
        studies_processed += 1
        candidates = build_candidates(acc, info, bundle, window_label)
        kept = 0
        for cand in candidates:
            runs = set(json.loads(cand["run_accessions"]))
            key = cand["canonical_key"]
            if key in seed_keys:
                counters["seed_canonical"] += 1
            elif runs & seed_runs:
                counters["seed_run"] += 1
            elif key in cand_keys or runs & cand_runs:
                counters["existing_candidate"] += 1
            elif key in batch_keys or runs & batch_runs:
                counters["within_batch"] += 1
            else:
                survivors.append(cand)
                batch_keys.add(key)
                batch_runs |= runs
                kept += 1
        log(f"[study] {acc}: {len(candidates)} samples, {kept} kept")
        if acc in pending_set:
            pending_done.append(acc)

    deferred = max(0, len(survivors) - args.max_candidates)
    survivors = survivors[:args.max_candidates]
    candidates_found = len(survivors) + deferred + sum(counters.values())
    deduped_away = sum(counters.values())

    inserted = 0
    if not args.dry_run:
        inserted = insert_candidates(con, survivors, discovered_at)
    seed_after = con.execute("SELECT COUNT(*) FROM seed_runs").fetchone()[0]
    con.close()

    projects = {}
    for cand in survivors:
        entry = projects.setdefault(cand["study_accession"],
                                    {"title": cand["study_name"], "n": 0})
        entry["n"] += 1
    top_projects = [
        {"study_accession": acc, "title": info["title"], "new_samples": info["n"]}
        for acc, info in sorted(projects.items(),
                                key=lambda kv: -kv[1]["n"])[:10]
    ]

    log("\n=== summary ===")
    log(f"studies processed : {studies_processed}"
        f"{' (capped by --max-candidates)' if capped else ''}")
    log(f"candidates found  : {candidates_found}")
    log(f"deduped away      : {deduped_away} "
        f"(seed_key={counters['seed_canonical']}, "
        f"seed_run={counters['seed_run']}, "
        f"existing={counters['existing_candidate']}, "
        f"batch={counters['within_batch']}; "
        f"deferred_by_cap={deferred})")
    log(f"inserted          : {inserted}{' (dry-run, nothing written)' if args.dry_run else ''}")
    for proj in top_projects:
        log(f"  {proj['study_accession']}: {proj['new_samples']} new samples "
            f"| {str(proj['title'])[:70]}")
    log(f"seed_runs rows    : {seed_before} -> {seed_after} (must be equal)")

    if args.dry_run:
        return 0

    new_pending = failed_pending + [p for p in pending
                                    if p["accession"] not in pending_done]
    fresh_through = index_freshness()
    write_json(report_path, {
        "run_at": discovered_at,
        "dry_run": False,
        "window": {"from": str(since), "to": str(today)},
        "queries": query_report,
        "studies_seen": len(ordered),
        "candidates_found": candidates_found,
        "deduped_away": deduped_away,
        "dedupe_breakdown": counters,
        "deferred_by_cap": deferred,
        "inserted": inserted,
        "capped": capped,
        "study_failures": study_failures,
        "index_fresh_through": fresh_through,
        "pending_studies": new_pending,
        "top_projects": top_projects,
    })
    # Advance the watermark only when the whole window was processed cleanly,
    # and never past the seqout index coverage (late-ingested studies must
    # stay inside a future window); dedupe absorbs the resulting overlap.
    if not capped and not study_failures and not any(
            q.get("failed") for q in query_report):
        target = min(str(today), fresh_through or str(today))
        new_check = max(str(since), target)
        write_json(state_path, {
            "last_check": new_check,
            "pending_studies": new_pending,
            "updated_at": discovered_at,
            "index_fresh_through": fresh_through,
        })
        log(f"watermark advanced to {new_check} "
            f"(index fresh through {fresh_through})")
    else:
        write_json(state_path, {
            "last_check": str(since),
            "pending_studies": new_pending,
            "updated_at": discovered_at,
            "index_fresh_through": fresh_through,
        })
        log("watermark NOT advanced "
            f"(capped={capped}, study_failures={study_failures})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
