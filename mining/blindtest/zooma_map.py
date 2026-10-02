"""Deterministic free-text -> ontology mapping for the curation agent.

Pipeline per field (tissue -> UBERON, disease -> MONDO):
  1. candidate raw-text extraction from BioSample attribute dicts
  2. ZOOMA v2 annotate, confidence ladder HIGH then GOOD, ontology-filtered
     query first, unfiltered query as fallback (target-ontology IRIs only)
  3. label resolution / gold normalization via EBI OLS4

Stdlib only. All HTTP responses are disk-cached under ``cache_dir`` so reruns
are free and the remote services are treated politely (fixed sleeps).

Result contract for :func:`map_text`::

    {
      "status": "hit" | "ambiguous" | "no_hit",   # no_hit => ZOOMA found nothing
      "term_iri": str | None,                     # chosen term (top-ranked)
      "term_label": str | None,                   # OLS4 label, best effort
      "confidence": "HIGH" | "GOOD" | None,       # ZOOMA tier that produced it
      "query": "filtered" | "unfiltered",         # which ZOOMA pass won
      "n_terms": int,                             # distinct terms at winning tier
      "text": str,                                # input text
    }
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ZOOMA_BASE = "https://www.ebi.ac.uk/spot/zooma/v2/api/services/annotate"
OLS4_BASE = "https://www.ebi.ac.uk/ols4/api"

USER_AGENT = "cscmd-curation-agent/0.1 (gut-metagenome mining; contact: lab-use)"

#: values that mean "field absent", never sent to ZOOMA
PLACEHOLDER_VALUES = {
    "", "missing", "not applicable", "not available", "not collected",
    "n/a", "na", "none", "null", "unknown", "unspecified", "no data",
    "not determined", "not provided", "-", "--",
}

#: disease values that mean healthy; MONDO has no "healthy" term so these are
#: resolved by rule, not by ontology lookup
HEALTHY_VALUES = {
    "healthy", "health", "normal", "healthy control", "healthy volunteer",
    "control", "non-disease", "no disease", "healthy donor", "none",
    "not applicable", "n/a", "na", "neg", "negative",
}

_CONF_ORDER = {"HIGH": 4, "GOOD": 3, "MEDIUM": 2, "LOW": 1}

# -- candidate extraction tables -------------------------------------------
# ordered: first matching attribute key wins; substring fallback lower priority
TISSUE_KEYS_EXACT = [
    "body_site", "body site", "host_body_site", "body_location",
    "environment_material", "environmental_medium",
    "tissue", "tissue_type", "tissue_type_ontology", "host_tissue_sampled",
    "anatomical_location", "host_anatomical_location", "anatomy",
    "isolation_source", "sample_type", "source", "specimen", "organ",
]
TISSUE_KEYS_SUBSTR = ["site", "tissue", "material", "medium", "source",
                      "isolation", "anatom", "specimen"]
TISSUE_KEYS_LAST = ["description", "title", "sample_title"]

DISEASE_KEYS_EXACT = [
    "disease", "host_disease", "disease_status", "disease_state",
    "disease_phenotype", "host_disease_status", "condition",
    "host_condition", "condition_group", "phenotype", "host_phenotype",
    "health_state", "host_health", "clinical_condition", "diagnosis",
]
DISEASE_KEYS_SUBSTR = ["disease", "condition", "phenotype", "diagnosis",
                       "health"]

_BRACKET_ID_RE = re.compile(r"\[[A-Za-z_]+:\d+\]")
_WS_RE = re.compile(r"\s+")


class HttpError(Exception):
    """Non-retryable HTTP failure after all retries."""


# -- HTTP + disk cache -------------------------------------------------------

class ApiCache:
    """JSON-blob disk cache keyed by url hash; one file per request."""

    def __init__(self, cache_dir: str):
        self.dir = cache_dir
        os.makedirs(cache_dir, exist_ok=True)

    def _path(self, key: str) -> str:
        h = hashlib.sha1(key.encode("utf-8")).hexdigest()
        return os.path.join(self.dir, h[:2], h + ".json")

    def get(self, key: str):
        p = self._path(key)
        if os.path.exists(p):
            try:
                with open(p) as fh:
                    return json.load(fh)
            except (OSError, ValueError):
                return None
        return None

    def put(self, key: str, blob) -> None:
        p = self._path(key)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = p + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(blob, fh)
        os.replace(tmp, p)


def _warn(msg: str) -> None:
    print(f"[zooma_map] {msg}", file=sys.stderr)


def http_get_json(url: str, cache: ApiCache, sleep_s: float,
                  retries: int = 3, timeout: int = 30):
    """GET url as JSON with disk cache, politeness sleep, 429/5xx backoff."""
    blob = cache.get(url)
    if blob is not None:
        return blob
    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(
            url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                blob = json.loads(resp.read().decode("utf-8"))
            time.sleep(sleep_s)
            cache.put(url, blob)
            return blob
        except urllib.error.HTTPError as e:
            if e.code == 404:
                time.sleep(sleep_s)
                blob = {"_status": 404}
                cache.put(url, blob)
                return blob
            if e.code == 429 or 500 <= e.code < 600:
                wait = 10 * (attempt + 1)
                _warn(f"HTTP {e.code} for {url[:120]}; backoff {wait}s")
                time.sleep(wait)
                last_err = e
                continue
            raise HttpError(f"HTTP {e.code} for {url[:200]}") from e
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            wait = 5 * (attempt + 1)
            _warn(f"network error {e!r}; retry in {wait}s")
            time.sleep(wait)
            last_err = e
    raise HttpError(f"giving up on {url[:200]}: {last_err!r}")


# -- text normalization ------------------------------------------------------

def clean_value(raw: str) -> str:
    """Strip bracketed ontology IDs, collapse whitespace, drop empties."""
    v = _BRACKET_ID_RE.sub("", str(raw))
    v = _WS_RE.sub(" ", v).strip().strip(",;|")
    return v


def norm_label(text: str) -> str:
    """Comparison form of a label: lowercase, underscores->spaces."""
    return _WS_RE.sub(" ", str(text).strip().lower()).replace("_", " ")


def is_healthy_text(text: str) -> bool:
    return norm_label(text) in HEALTHY_VALUES


def _usable(text: str) -> bool:
    return norm_label(text) not in PLACEHOLDER_VALUES and len(text) >= 2


# -- candidate extraction ----------------------------------------------------

def _pick(attrs: dict, exact: list, substr: list, last: list = ()) -> list:
    """Ordered unique values from attr keys: exact matches, then substring,
    then last-resort keys. Returns [(key, value), ...]."""
    out, seen = [], set()
    lower = {str(k).lower(): (k, v) for k, v in attrs.items()}
    for table in (exact, None, last):
        keys = []
        if table is None:  # substring pass
            for lk in sorted(lower):
                if lk in seen_exact(lower, exact):
                    continue
                if any(s in lk for s in substr):
                    keys.append(lk)
        else:
            keys = [k for k in table if k in lower]
        for k in keys:
            v = clean_value(lower[k][1])
            nv = norm_label(v)
            if _usable(v) and nv not in seen:
                seen.add(nv)
                out.append((lower[k][0], v))
    return out


def seen_exact(lower: dict, exact: list) -> set:
    return {k for k in exact if k in lower}


def extract_tissue_candidates(attrs: dict) -> list:
    """Candidate (key, value) raw texts for body site / tissue."""
    return _pick(attrs, TISSUE_KEYS_EXACT, TISSUE_KEYS_SUBSTR,
                 TISSUE_KEYS_LAST)[:3]


def extract_disease_candidates(attrs: dict) -> list:
    """Candidate (key, value) raw texts for host disease."""
    return _pick(attrs, DISEASE_KEYS_EXACT, DISEASE_KEYS_SUBSTR)[:3]


# -- ZOOMA -------------------------------------------------------------------

def _parse_zooma(results: list, ontology: str) -> dict:
    """Distinct target-ontology terms per confidence tier of a ZOOMA response.

    Returns {confidence: [(iri, rank), ...]} with rank = position in response.
    """
    tiers: dict = {}
    prefix = f"http://purl.obolibrary.org/obo/{ontology.upper()}_"
    for rank, res in enumerate(results):
        conf = (res.get("confidence") or "").upper()
        if conf not in _CONF_ORDER:
            continue
        for iri in res.get("semanticTags") or []:
            if not iri.startswith(prefix):
                continue
            tiers.setdefault(conf, {})
            tiers[conf].setdefault(iri, rank)  # keep best (lowest) rank
    return {c: sorted(irs.items(), key=lambda kv: kv[1])
            for c, irs in tiers.items()}


def zooma_query(text: str, ontology: str, cache: ApiCache,
                filtered: bool = True, sleep_s: float = 0.35) -> list:
    """One ZOOMA annotate call; returns parsed tiers (see _parse_zooma)."""
    params = {"propertyValue": text}
    if filtered:
        params["filter"] = f"ontologies:[{ontology.lower()}]"
    url = ZOOMA_BASE + "?" + urllib.parse.urlencode(params)
    blob = http_get_json(url, cache, sleep_s)
    if not isinstance(blob, list):
        return {}
    return _parse_zooma(blob, ontology)


def map_text(text: str, ontology: str, cache_dir: str,
             sleep_s: float = 0.35) -> dict:
    """Map one raw-text value to a target-ontology term (see module docstring).

    ``ontology`` is an OBO namespace usable as both ZOOMA filter and IRI
    prefix, e.g. 'uberon' or 'mondo'.
    """
    cache = ApiCache(os.path.join(cache_dir, "zooma"))
    text = clean_value(text)
    if not _usable(text):
        return {"status": "no_hit", "term_iri": None, "term_label": None,
                "confidence": None, "query": None, "n_terms": 0, "text": text}

    for query_kind, filtered in (("filtered", True), ("unfiltered", False)):
        try:
            tiers = zooma_query(text, ontology, cache, filtered, sleep_s)
        except HttpError as e:
            _warn(f"zooma unreachable for {text!r}: {e}")
            tiers = {}
        for conf in ("HIGH", "GOOD"):
            terms = tiers.get(conf)
            if not terms:
                continue
            best_iri, _ = terms[0]
            return {
                "status": "hit" if len(terms) == 1 else "ambiguous",
                "term_iri": best_iri,
                "term_label": ols4_label(best_iri, cache_dir),
                "confidence": conf,
                "query": query_kind,
                "n_terms": len(terms),
                "text": text,
                "all_terms": [iri for iri, _ in terms],
            }
    return {"status": "no_hit", "term_iri": None, "term_label": None,
            "confidence": None, "query": None, "n_terms": 0, "text": text}


# -- OLS4 --------------------------------------------------------------------

def ols4_label(iri: str, cache_dir: str, sleep_s: float = 0.3) -> str | None:
    """Preferred label for an ontology term IRI (None if unresolvable)."""
    cache = ApiCache(os.path.join(cache_dir, "ols4"))
    url = (OLS4_BASE + "/terms?" +
           urllib.parse.urlencode({"iri": iri}))
    blob = http_get_json(url, cache, sleep_s)
    terms = ((blob or {}).get("_embedded") or {}).get("terms") or []
    return terms[0].get("label") if terms else None


def ols4_search_exact(label: str, ontology: str, cache_dir: str,
                      sleep_s: float = 0.3) -> str | None:
    """IRI whose label equals ``label`` exactly (case-insensitive) in one
    ontology; None when no exact-label match exists. Gold normalization."""
    cache = ApiCache(os.path.join(cache_dir, "ols4"))
    url = (OLS4_BASE + "/search?" + urllib.parse.urlencode(
        {"q": label, "ontology": ontology, "exact": "true"}))
    blob = http_get_json(url, cache, sleep_s)
    docs = ((blob or {}).get("response") or {}).get("docs") or []
    want = norm_label(label)
    for doc in docs:
        if norm_label(doc.get("label") or "") == want:
            return doc.get("iri")
    return None


def normalize_gold(text: str, ontology: str, cache_dir: str) -> dict:
    """Normalize a curated gold label to an ontology IRI.

    Splits ';'-separated composites, resolves each part via OLS4 exact search.
    Healthy parts get ``{"healthy": true}`` (no MONDO term exists).
    Returns {"parts": [{"text", "iri", "label", "healthy"}], "iris": [...]}.
    """
    parts = []
    for chunk in str(text).split(";"):
        t = clean_value(chunk)
        if not t:
            continue
        if ontology.lower() == "mondo" and is_healthy_text(t):
            parts.append({"text": t, "iri": None, "label": "healthy",
                          "healthy": True})
            continue
        try:
            iri = ols4_search_exact(t, ontology, cache_dir)
        except HttpError as e:
            _warn(f"ols4 unreachable for {t!r}: {e}")
            iri = None
        parts.append({"text": t, "iri": iri,
                      "label": (ols4_label(iri, cache_dir)
                                if iri else t.lower()),
                      "healthy": False})
    return {"parts": parts, "iris": [p["iri"] for p in parts if p["iri"]]}
