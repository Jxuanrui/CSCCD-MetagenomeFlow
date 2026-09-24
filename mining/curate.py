#!/usr/bin/env python3
"""Curation engine: seed_registry free-text -> ontology-anchored curation.sqlite.

Cohorts
  inherited    seed_registry.seed_runs (short curated labels; ontology cols
               empty).  Route: zooma_map (UBERON/MONDO) -> GLM label
               normalization (OLS4-validated) -> review_queue.
  incremental  seed_registry.incremental_candidates (raw seqout/BioSample
               text).  Route: GLM extraction of tissue/disease/age/sex short
               phrases -> zooma normalization of the extracted phrases.

Artifacts (all under mining/):
  curation.sqlite            tables: curation, review_queue, batches, glm_cache
  curation_run.jsonl         one JSON line per batch + summary/stop events
  snapshots/                 curation_snapshot.csv.gz (every 10 batches + end)
                             api_cache/  ZOOMA/OLS4 disk cache (zooma_map)

Resumable: canonical_keys already present in `curation` are skipped unless a
method column says 'pending' (GLM outage -> retried next run).  Exit codes:
0 = finished, 3 = token budget stop (current batch finishes + stop recorded).

Method vocabulary: absent | healthy_rule | zooma | ols4_exact (deterministic
exact-label normalization via zooma_map.ols4_search_exact) | glm | '+'-joined
mixes | review | glm_pending; incremental fields carry a 'glm_extract+'
prefix.  condition_group heuristic: healthy/normal/control variants ->
'healthy'; any non-healthy disease text -> 'case'; no usable disease text ->
NULL.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent          # mining/
sys.path.insert(0, str(ROOT / "blindtest"))
import zooma_map as zm                           # noqa: E402  (reusable mapper)

SEED_DB = ROOT / "seed_registry.sqlite"
OUT_DB = ROOT / "curation.sqlite"
RUN_LOG = ROOT / "curation_run.jsonl"
SNAP_DIR = ROOT / "snapshots"
CACHE_DIR = SNAP_DIR / "api_cache"

GLM_URL = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
GLM_MODEL = "glm-5.3-flash"
GLM_KEY_FILE = Path.home() / ".glm_router_api_key"

CURIE_RE = re.compile(r"\b(MONDO|UBERON)[:_](\d+)\b", re.I)

CURATION_COLS = [
    "canonical_key", "cohort", "body_site_label", "body_site_uberon",
    "body_site_method", "body_site_confidence", "disease_label",
    "disease_mondo", "disease_method", "disease_confidence",
    "condition_group", "age_years", "sex", "country", "bmi", "medication",
    "curated_at", "batch_id",
]

DDL = """
CREATE TABLE IF NOT EXISTS curation (
  canonical_key         TEXT PRIMARY KEY,
  cohort                TEXT NOT NULL CHECK (cohort IN ('inherited','incremental')),
  body_site_label       TEXT,
  body_site_uberon      TEXT,
  body_site_method      TEXT,
  body_site_confidence  TEXT,
  disease_label         TEXT,
  disease_mondo         TEXT,
  disease_method        TEXT,
  disease_confidence    TEXT,
  condition_group       TEXT CHECK (condition_group IS NULL
                          OR condition_group IN ('case','healthy')),
  age_years             REAL,
  sex                   TEXT,
  country               TEXT,
  bmi                   REAL,
  medication            TEXT,
  curated_at            TEXT,
  batch_id              TEXT
);
CREATE TABLE IF NOT EXISTS review_queue (
  canonical_key TEXT NOT NULL,
  field         TEXT NOT NULL,
  raw_value     TEXT,
  reason        TEXT,
  PRIMARY KEY (canonical_key, field, raw_value)
);
CREATE TABLE IF NOT EXISTS batches (
  batch_id    TEXT PRIMARY KEY,
  scope       TEXT,
  n_processed INTEGER,
  n_ok        INTEGER,
  zooma_hits  INTEGER,
  glm_calls   INTEGER,
  glm_tokens  INTEGER,
  started     TEXT,
  finished    TEXT
);
CREATE TABLE IF NOT EXISTS glm_cache (
  kind   TEXT NOT NULL,
  key    TEXT NOT NULL,
  answer TEXT NOT NULL,
  PRIMARY KEY (kind, key)
);
"""

SRC = {
    "inherited": ("seed.seed_runs",
                  "canonical_key, body_site, disease, age_years, sex, "
                  "country, bmi, medication"),
    "incremental": ("seed.incremental_candidates",
                    "canonical_key, study_name, body_site, source_query"),
}

PENDING = {"pending": True}


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def warn(msg: str) -> None:
    print(f"[curate] {msg}", file=sys.stderr)


def log_line(obj: dict) -> None:
    obj = dict(obj)
    obj.setdefault("ts", utcnow())
    with open(RUN_LOG, "a") as fh:
        fh.write(json.dumps(obj, ensure_ascii=True) + "\n")


# -- CURIE helpers -----------------------------------------------------------

def iri_to_curie(iri: str) -> str | None:
    m = re.match(r".*/obo/([A-Za-z]+)_(\d+)$", iri or "")
    return f"{m.group(1).upper()}:{m.group(2)}" if m else None


def curie_to_iri(curie: str) -> str:
    pfx, num = curie.split(":", 1)
    return f"http://purl.obolibrary.org/obo/{pfx}_{num}"


def usable(text: str) -> bool:
    return zm.norm_label(text) not in zm.PLACEHOLDER_VALUES and len(text) >= 2


# -- GLM client ---------------------------------------------------------------

class GlmUnavailable(Exception):
    """GLM unreachable after retries (or no API key) -> mark pending."""


class Glm:
    def __init__(self, key: str | None):
        self.key = key
        self.calls = 0
        self.tokens = 0
        self._last = 0.0
        self.disabled = False       # latched on non-transient auth failures

    @property
    def enabled(self) -> bool:
        return bool(self.key) and not self.disabled

    def chat(self, system: str, user: str, max_tokens: int = 512) -> str:
        if not self.enabled:
            raise GlmUnavailable("glm disabled (no key or auth failure)")
        pause = 1.0 - (time.monotonic() - self._last)   # 1s politeness
        if pause > 0:
            time.sleep(pause)
        body = json.dumps({
            "model": GLM_MODEL, "max_tokens": max_tokens, "temperature": 0,
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": user}],
        }).encode("utf-8")
        last_err: Exception | None = None
        for attempt in range(3):
            req = urllib.request.Request(GLM_URL, data=body, headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.key}",
                "User-Agent": zm.USER_AGENT})
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    blob = json.loads(resp.read().decode("utf-8"))
                self._last = time.monotonic()
                self.calls += 1
                self.tokens += int((blob.get("usage") or {})
                                   .get("total_tokens") or 0)
                return (((blob.get("choices") or [{}])[0])
                        .get("message") or {}).get("content") or ""
            except urllib.error.HTTPError as e:
                last_err = e
                if e.code == 429 or 500 <= e.code:
                    warn(f"GLM HTTP {e.code}; backoff 20s "
                         f"(attempt {attempt + 1}/3)")
                    time.sleep(20)
                    continue
                # non-transient (401/403/...): disable for this whole run so
                # ZOOMA-only degradation proceeds without repeated backoffs
                self.disabled = True
                raise GlmUnavailable(f"GLM HTTP {e.code}") from e
            except (urllib.error.URLError, TimeoutError, OSError,
                    ValueError) as e:
                last_err = e
                warn(f"GLM {type(e).__name__}; backoff 20s "
                     f"(attempt {attempt + 1}/3)")
                time.sleep(20)
        raise GlmUnavailable(f"GLM unreachable: {type(last_err).__name__}")


def load_glm_key() -> str | None:
    key = os.environ.get("GLM_API_KEY", "").strip()
    if key:
        return key
    try:
        return GLM_KEY_FILE.read_text().strip() or None
    except OSError:
        return None


def glm_cached(db, glm: Glm, kind: str, key: str, fn):
    """Persistent answer cache; the PENDING sentinel is never cached."""
    row = db.execute("SELECT answer FROM glm_cache WHERE kind=? AND key=?",
                     (kind, key)).fetchone()
    if row:
        return json.loads(row[0])
    try:
        val = fn()
    except GlmUnavailable:
        return PENDING
    db.execute("INSERT OR REPLACE INTO glm_cache VALUES (?,?,?)",
               (kind, key, json.dumps(val, ensure_ascii=True)))
    return val


NORM_SYS = ("You map free-text biomedical terms to ontology IDs. Reply with "
            "exactly 'ID|label' where ID is a real {onto} term, or 'NONE'. "
            "No other text.")

EXTRACT_SYS = (
    "You extract sample metadata from messy sequencing-archive records. "
    "Reply with strict JSON only, no other text, schema "
    '{"body_site": "", "disease": "", "age_years": "", "sex": ""}. '
    "body_site: short anatomical label (e.g. \"feces\", \"gut\", \"oral "
    "cavity\"), \"\" if unknown. disease: short standard disease label or "
    "\"healthy\"; \"\" if unknown. age_years: number or \"\". sex: "
    "\"male\"/\"female\"/\"\".")


def glm_normalize(db, glm: Glm, term: str, ontology: str):
    """Free-text term -> {'curie','label'} | {'curie': None} | PENDING.

    GLM-proposed IDs are accepted only when they resolve in OLS4 (which also
    yields the canonical label); hallucinated IDs become NONE -> review.
    """
    def run():
        role = "disease" if ontology == "mondo" else "body-site"
        onto = ontology.upper()
        want = "MONDO" if ontology == "mondo" else "UBERON"
        content = glm.chat(NORM_SYS.format(onto=onto),
                           f"Map this {role} term to a {onto} ontology ID; "
                           f"return ID|label or NONE. Term: {term}")
        curie = next((f"{p.upper()}:{n}" for p, n in
                      CURIE_RE.findall(content or "") if p.upper() == want),
                     None)
        if not curie:
            return {"curie": None}
        try:
            label = zm.ols4_label(curie_to_iri(curie), str(CACHE_DIR))
        except zm.HttpError:
            return {"curie": curie, "label": None, "unvalidated": True}
        if not label:
            return {"curie": None, "rejected_id": curie}
        return {"curie": curie, "label": label}

    return glm_cached(db, glm, f"norm:{ontology}", term.lower(), run)


def glm_extract(db, glm: Glm, study_name: str, body_site: str,
                source_query: str):
    def run():
        content = glm.chat(
            EXTRACT_SYS,
            f"study_name: {study_name}\nbody_site: {body_site or ''}\n"
            f"source_query: {source_query or ''}")
        m = re.search(r"\{.*\}", content or "", re.S)
        if not m:
            return {}
        try:
            got = json.loads(m.group(0))
        except ValueError:
            return {}
        out = {}
        for k in ("body_site", "disease", "sex"):
            v = got.get(k)
            out[k] = v.strip() if isinstance(v, str) else ""
        try:
            out["age_years"] = float(got.get("age_years"))
        except (TypeError, ValueError):
            out["age_years"] = None
        return out

    key = json.dumps([study_name, body_site or "", source_query or ""])
    return glm_cached(db, glm, "extract", key, run)


# -- field resolution ladder ---------------------------------------------------

class Res:
    """Resolution of one field value (or one ';'-part of a disease label)."""

    def __init__(self, method, curie=None, label=None, confidence=None,
                 healthy=False, reason=None, raw=None):
        self.method = method    # absent|healthy_rule|zooma|glm|review|glm_pending
        self.curie = curie
        self.label = label
        self.confidence = confidence
        self.healthy = healthy
        self.reason = reason
        self.raw = raw


def resolve_term(db, glm: Glm, term: str, ontology: str, stats: dict) -> Res:
    term = zm.clean_value(term)
    if not usable(term):
        return Res("absent")
    if ontology == "mondo" and zm.is_healthy_text(term):
        return Res("healthy_rule", label="healthy", healthy=True, raw=term)
    try:
        r = zm.map_text(term, ontology, str(CACHE_DIR))
    except Exception as e:                       # zooma_map degrades; be safe
        warn(f"zooma error for {term!r}: {e}")
        r = {"status": "no_hit"}
    if r["status"] == "hit":
        stats["zooma_hits"] += 1
        return Res("zooma", curie=iri_to_curie(r["term_iri"]),
                   label=r["term_label"], confidence=r["confidence"], raw=term)
    # deterministic exact-label normalization (zooma_map gold path) before
    # spending GLM tokens: rescues exact synonyms ZOOMA ranks poorly.
    # Guard: OLS4 search does not strictly honor the ontology filter (e.g.
    # 'Homo Sapiens' -> NCBITAXON:9606), so only accept target-prefix IRIs.
    try:
        iri = zm.ols4_search_exact(term, ontology, str(CACHE_DIR))
    except zm.HttpError as e:
        warn(f"ols4 unreachable for {term!r}: {e}")
        iri = None
    if iri and (c := iri_to_curie(iri)) and c.startswith(
            ontology.upper() + ":"):
        stats["ols4_hits"] += 1
        return Res("ols4_exact", curie=c,
                   label=zm.ols4_label(iri, str(CACHE_DIR)),
                   confidence="EXACT", raw=term)
    g = glm_normalize(db, glm, term, ontology)
    if g is PENDING:
        return Res("glm_pending", raw=term)
    if g.get("curie"):
        return Res("glm", curie=g["curie"], label=g.get("label"),
                   confidence="MEDIUM", raw=term)
    why = "zooma_ambiguous" if r["status"] == "ambiguous" else "zooma_no_hit"
    if g.get("rejected_id"):
        why += f"_glm_id_rejected"
    why += "_glm_none"
    return Res("review", reason=why, raw=term)


def resolve_field(db, glm: Glm, raw, ontology: str, stats: dict,
                  prefix: str = ""):
    """Whole field: single term (body_site) or ';'-composite (disease).

    Returns (Res, condition_group, [(part_text, Res), ...]) — parts only
    carry per-part Res objects when the composite needs human review.
    """
    raw_text = zm.clean_value(raw or "")
    parts = [p for p in (zm.clean_value(x) for x in raw_text.split(";"))
             if usable(p)]
    if not parts:
        return Res("absent"), None, []
    results = [resolve_term(db, glm, p, ontology, stats) for p in parts]
    curies = [r.curie for r in results if r.curie]
    labels = [r.label for r in results if r.label]
    methods = {r.method for r in results}
    if "glm_pending" in methods:
        method = "glm_pending"
    elif "review" in methods:
        method = "review"
    else:
        fams = [f for f in ("zooma", "ols4_exact", "glm") if f in methods]
        method = "+".join(fams) if fams else "healthy_rule"
    if prefix and method != "absent":
        method = prefix + method
    res = Res(method, curie=";".join(curies) or None,
              label=";".join(labels) or None, raw=raw_text)
    for r in results:
        if r.confidence:
            res.confidence = ((res.confidence + ";" + r.confidence)
                              if res.confidence else r.confidence)
    condition = None
    if any(not r.healthy for r in results):
        condition = "case"
    elif any(r.healthy for r in results):
        condition = "healthy"
    return res, condition, list(zip(parts, results))


# -- sample curation -----------------------------------------------------------

def curate_inherited(db, glm: Glm, row, batch_id: str, stats: dict):
    key = row["canonical_key"]
    bs, _, _ = resolve_field(db, glm, row["body_site"], "uberon", stats)
    dis, cond, parts = resolve_field(db, glm, row["disease"], "mondo", stats)
    reviews = []
    if "review" in (bs.method,):
        reviews.append(("body_site", bs.raw, bs.reason))
    for part_text, r in parts:
        if r.method == "review":
            reviews.append(("disease", part_text, r.reason))
    passthrough = {k: row[k] for k in
                   ("age_years", "sex", "country", "bmi", "medication")}
    crow = (key, "inherited",
            None if bs.method == "absent" else bs.raw,
            bs.curie, bs.method, bs.confidence,
            None if dis.method == "absent" else dis.raw,
            dis.curie, dis.method, dis.confidence, cond,
            passthrough["age_years"], passthrough["sex"],
            passthrough["country"], passthrough["bmi"],
            passthrough["medication"], utcnow(), batch_id)
    return crow, reviews


def curate_incremental(db, glm: Glm, row, batch_id: str, stats: dict):
    key = row["canonical_key"]
    ex = glm_extract(db, glm, row["study_name"], row["body_site"],
                     row["source_query"])
    reviews = []
    if ex is PENDING:
        # GLM outage: still map the raw body_site column via ZOOMA (zooma-only
        # degradation); everything needing extraction stays pending.
        bs, _, _ = resolve_field(db, glm, row["body_site"], "uberon", stats)
        dis, cond = Res("glm_pending"), None
        age = sex = None
    else:
        bs, _, _ = resolve_field(db, glm, ex.get("body_site", ""), "uberon",
                                 stats, prefix="glm_extract+")
        dis, cond, parts = resolve_field(db, glm, ex.get("disease", ""),
                                         "mondo", stats,
                                         prefix="glm_extract+")
        if "review" in bs.method:
            reviews.append(("body_site", bs.raw, bs.reason))
        for part_text, r in parts:
            if r.method == "review":
                reviews.append(("disease", part_text, r.reason))
        age = ex.get("age_years")
        sex = (ex.get("sex") or None)
    crow = (key, "incremental",
            None if bs.method in ("absent", "glm_pending") else bs.raw,
            bs.curie, bs.method, bs.confidence,
            None if dis.method in ("absent", "glm_pending") else dis.raw,
            dis.curie, dis.method, dis.confidence, cond,
            age, sex, None, None, None, utcnow(), batch_id)
    return crow, reviews


# -- batching ------------------------------------------------------------------

DONE_SUBQ = (
    "SELECT s.canonical_key FROM {src} s JOIN curation c "
    "ON c.canonical_key = s.canonical_key WHERE c.cohort = ? "
    "AND (c.body_site_method IS NULL OR c.body_site_method NOT LIKE '%pending%') "
    "AND (c.disease_method IS NULL OR c.disease_method NOT LIKE '%pending%')")


def fetch_batch(db, scope: str, resume: bool, batch_size: int, last_key: str):
    """Next batch after ``last_key`` (monotonic cursor: every key is attempted
    at most once per invocation; pending keys are retried by the next run)."""
    src, cols = SRC[scope]
    sql = f"SELECT {cols} FROM {src} WHERE canonical_key > ?"
    params: list = [last_key]
    if resume:
        sql += f" AND canonical_key NOT IN ({DONE_SUBQ.format(src=src)})"
        params.append(scope)
    sql += " ORDER BY canonical_key LIMIT ?"
    params.append(batch_size)
    return db.execute(sql, params).fetchall()


def write_snapshot(db):
    SNAP_DIR.mkdir(exist_ok=True)
    tmp = SNAP_DIR / "curation_snapshot.csv.gz.tmp"
    with gzip.open(tmp, "wt", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(CURATION_COLS)
        for row in db.execute(
                f"SELECT {','.join(CURATION_COLS)} FROM curation "
                "ORDER BY canonical_key"):
            w.writerow("" if v is None else v for v in row)
    os.replace(tmp, SNAP_DIR / "curation_snapshot.csv.gz")


def process_scope(db, glm: Glm, scope: str, args, run: dict) -> dict:
    """Process one scope in batches; returns stats for this scope."""
    cur_fn = curate_inherited if scope == "inherited" else curate_incremental
    src, _ = SRC[scope]
    sc = {"processed": 0, "glm_tokens": 0, "glm_calls": 0}
    batch_no = 0
    last_key = ""
    while True:
        left = (args.limit - run["processed"]) if args.limit else None
        if left is not None and left <= 0:
            break
        size = args.batch_size if left is None else min(args.batch_size, left)
        rows = fetch_batch(db, scope, args.resume, size, last_key)
        if not rows:
            break
        last_key = rows[-1]["canonical_key"]
        batch_id = f"{run['start']}_{scope}_{batch_no:04d}"
        db.execute(
            "INSERT OR REPLACE INTO batches VALUES (?,?,?,?,?,?,?,?,?)",
            (batch_id, scope, len(rows), None, None, None, None,
             utcnow(), None))
        stats = {"zooma_hits": 0, "ols4_hits": 0}
        glm_calls0, glm_tokens0 = glm.calls, glm.tokens
        cur_rows, review_rows, n_ok = [], [], 0
        for row in rows:
            try:
                crow, revs = cur_fn(db, glm, row, batch_id, stats)
            except Exception as e:                        # never kill a batch
                warn(f"{row['canonical_key']}: {type(e).__name__}: {e}")
                continue
            cur_rows.append(crow)
            review_rows.extend((crow[0],) + r for r in revs)
            if not any(m in (crow[4] or "", crow[8] or "")
                       for m in ("review", "pending")):
                n_ok += 1
        keys = [r[0] for r in cur_rows]
        db.executemany("DELETE FROM curation WHERE canonical_key=?",
                       [(k,) for k in keys])
        db.executemany("DELETE FROM review_queue WHERE canonical_key=?",
                       [(k,) for k in keys])
        db.executemany(
            f"INSERT INTO curation ({','.join(CURATION_COLS)}) "
            f"VALUES ({','.join('?' * len(CURATION_COLS))})", cur_rows)
        db.executemany("INSERT OR IGNORE INTO review_queue VALUES (?,?,?,?)",
                       review_rows)
        n_review = len({k for k, *_ in review_rows})
        n_pending = sum(1 for r in cur_rows
                        if "pending" in (r[4] or "") or "pending" in (r[8] or ""))
        db.execute(
            "UPDATE batches SET n_processed=?, n_ok=?, zooma_hits=?, "
            "glm_calls=?, glm_tokens=?, finished=? WHERE batch_id=?",
            (len(cur_rows), n_ok, stats["zooma_hits"], glm.calls - glm_calls0,
             glm.tokens - glm_tokens0, utcnow(), batch_id))
        db.commit()
        run["processed"] += len(cur_rows)
        run["batches"] += 1
        sc["processed"] += len(cur_rows)
        sc["glm_tokens"] = glm.tokens - glm_tokens0
        sc["glm_calls"] = glm.calls - glm_calls0
        log_line({"event": "batch", "batch_id": batch_id, "scope": scope,
                  "n_processed": len(cur_rows), "n_ok": n_ok,
                  "n_review": n_review, "n_pending": n_pending,
                  "zooma_hits": stats["zooma_hits"],
                  "ols4_hits": stats["ols4_hits"],
                  "glm_calls": glm.calls - glm_calls0,
                  "glm_tokens": glm.tokens - glm_tokens0,
                  "glm_tokens_cum": glm.tokens})
        print(f"[{batch_id}] n={len(cur_rows)} ok={n_ok} review={n_review} "
              f"pending={n_pending} zooma={stats['zooma_hits']} "
              f"ols4={stats['ols4_hits']} "
              f"glm_calls={glm.calls - glm_calls0} "
              f"tokens_cum={glm.tokens}", flush=True)
        if run["batches"] % 10 == 0:
            write_snapshot(db)
        batch_no += 1
        if glm.tokens >= args.budget_tokens:
            log_line({"event": "budget_stop", "scope": scope,
                      "glm_tokens": glm.tokens,
                      "budget_tokens": args.budget_tokens})
            warn(f"token budget {args.budget_tokens} hit after {batch_no} "
                 f"batches of {scope}; stopping resumably")
            sc["budget_stop"] = True
            break
    sc.setdefault("budget_stop", False)
    return sc


def print_summary(db, glm: Glm, args, budget_stop: bool, run: dict,
                  scope_stats: dict):
    done = db.execute("SELECT COUNT(*) FROM curation").fetchone()[0]
    out = [f"\n=== curation summary ({utcnow()}) ===",
           f"curation rows: {done}   (this run: {run['processed']} samples, "
           f"{run['batches']} batches)"]
    for field, col in (("body_site", "body_site_method"),
                       ("disease", "disease_method")):
        out.append(f"-- {field} method --")
        n_field = 0
        for coh, m, n in db.execute(
                f"SELECT cohort, {col}, COUNT(*) c FROM curation "
                f"GROUP BY cohort, {col} ORDER BY cohort, c DESC"):
            out.append(f"  {coh:12s} {str(m):32s} {n:7d}")
            n_field += n
        out.append(f"  {'TOTAL':21s}{n_field:18d}")
    for label, sql in (
            ("rows by cohort",
             "SELECT cohort, COUNT(*) FROM curation GROUP BY cohort"),
            ("condition_group",
             "SELECT condition_group, COUNT(*) FROM curation "
             "WHERE condition_group IS NOT NULL GROUP BY condition_group"),
            ("body_site_uberon mapped",
             "SELECT cohort, COUNT(*) FROM curation "
             "WHERE body_site_uberon IS NOT NULL GROUP BY cohort"),
            ("disease_mondo mapped",
             "SELECT cohort, COUNT(*) FROM curation "
             "WHERE disease_mondo IS NOT NULL GROUP BY cohort"),
            ("age/sex present",
             "SELECT cohort, SUM(age_years IS NOT NULL), SUM(sex IS NOT NULL)"
             " FROM curation GROUP BY cohort")):
        rows = db.execute(sql).fetchall()
        out.append(f"{label}: " +
                   "; ".join(", ".join(str(v) for v in r) for r in rows))
    n_review = db.execute("SELECT COUNT(*) FROM review_queue").fetchone()[0]
    n_review_keys = db.execute(
        "SELECT COUNT(DISTINCT canonical_key) FROM review_queue"
    ).fetchone()[0]
    out.append(f"review_queue: {n_review} items / {n_review_keys} samples")
    out.append(f"glm: calls={glm.calls} tokens={glm.tokens} "
               f"(budget {args.budget_tokens})")
    print("\n".join(out))
    return done


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scope", choices=["inherited", "incremental", "all"],
                    default="all",
                    help="which cohort to process (default: all)")
    ap.add_argument("--limit", type=int, default=None,
                    help="max samples this invocation, across scopes in "
                         "order inherited->incremental (default: all)")
    ap.add_argument("--batch-size", type=int, default=200)
    ap.add_argument("--no-resume", dest="resume", action="store_false",
                    default=True,
                    help="reprocess canonical_keys already in curation")
    ap.add_argument("--budget-tokens", type=int, default=100_000_000,
                    help="hard cap on cumulative GLM tokens this invocation; "
                         "on hit the current batch finishes, a budget_stop "
                         "event is logged, exit code 3")
    args = ap.parse_args(argv)

    db = sqlite3.connect(str(OUT_DB))
    db.row_factory = sqlite3.Row
    db.executescript(DDL)
    # read-only view of the seed registry inside the same connection
    db.execute(f"ATTACH DATABASE 'file:{SEED_DB}?mode=ro' AS seed")

    glm = Glm(load_glm_key())
    if not glm.enabled:
        warn("no GLM key (env GLM_API_KEY / ~/.glm_router_api_key); "
             "running ZOOMA-only, GLM-dependent items marked pending")
    run = {"start": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S"),
           "processed": 0, "batches": 0}
    scopes = (["inherited", "incremental"] if args.scope == "all"
              else [args.scope])
    budget_stop = False
    scope_stats: dict = {}
    for scope in scopes:
        scope_stats[scope] = process_scope(db, glm, scope, args, run)
        if scope_stats[scope]["budget_stop"]:
            budget_stop = True
            break
    write_snapshot(db)
    print_summary(db, glm, args, budget_stop, run, scope_stats)
    for scope, sc in scope_stats.items():       # projection per scope
        src, _ = SRC[scope]
        total = db.execute(f"SELECT COUNT(*) FROM {src}").fetchone()[0]
        have = db.execute("SELECT COUNT(*) FROM curation WHERE cohort=?",
                          (scope,)).fetchone()[0]
        per_sample = (sc["glm_tokens"] / sc["processed"]
                      if sc["processed"] else 0.0)
        print(f"projection {scope}: {have}/{total} curated; "
              f"{sc['glm_tokens']} tokens for {sc['processed']} samples "
              f"(~{per_sample:.1f}/sample) -> "
              f"~{int(per_sample * max(0, total - have))} tokens remaining")
    log_line({"event": "summary", "processed": run["processed"],
              "batches": run["batches"], "glm_calls": glm.calls,
              "glm_tokens": glm.tokens, "budget_stop": budget_stop,
              "resume": args.resume})
    db.close()
    return 3 if budget_stop else 0


if __name__ == "__main__":
    sys.exit(main())
