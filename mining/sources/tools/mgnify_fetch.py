#!/usr/bin/env python3
"""Phase-1 MGnify index: enumerate 331 fecal studies -> all analyses (resumable).

Writes per-study JSONL pages under mining/sources/raw/mgnify/pages/.
A study is complete when its file ends with a {"complete": true} line.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://www.ebi.ac.uk/metagenomics/api/v2"
BIOME = urllib.parse.quote("root:Host-associated:Human:Digestive system:Large intestine:Fecal")
RAW = "~/Course/CSCCD-MetagenomeFlow/mining/sources/raw/mgnify"
PAGES_DIR = os.path.join(RAW, "pages")
STUDIES_JSONL = os.path.join(RAW, "studies.jsonl")
ERRORS = os.path.join(RAW, "errors.jsonl")
SLEEP = 0.6  # >=0.5s politeness between paged calls
UA = {"User-Agent": "CSCCD-MetagenomeFlow/phase1-index (academic; contact: lab)"}


def get_json(url, tries=4):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.loads(r.read().decode("utf-8"))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
            last = e
            code = getattr(e, "code", None)
            if code == 404:
                raise
            time.sleep(2.0 * (i + 1))
    raise RuntimeError(f"failed after {tries} tries: {url}: {last}")


def paginate(first_url):
    """MGnify v2 returns {"count": N, "items": [...]} with no links; paginate via page=N."""
    base = first_url.split("&page=")[0].split("?page=")[0]
    sep = "&" if "?" in base else "?"
    page, seen = 1, 0
    while True:
        url = f"{base}{sep}page={page}"
        data = get_json(url)
        items = data.get("items", [])
        yield url, page, items
        seen += len(items)
        total = data.get("count")
        if not items or (total is not None and seen >= total):
            return
        page += 1
        time.sleep(SLEEP)


def study_complete(mgy):
    path = os.path.join(PAGES_DIR, mgy + ".jsonl")
    if not os.path.exists(path):
        return False
    with open(path, "rb") as f:
        try:
            f.seek(-400, os.SEEK_END)
        except OSError:
            pass
        tail = f.read().decode("utf-8", "replace").strip().splitlines()
    return bool(tail) and '"complete": true' in tail[-1]


def fetch_studies():
    if os.path.exists(STUDIES_JSONL):
        with open(STUDIES_JSONL) as f:
            return [json.loads(l) for l in f if l.strip()]
    studies = []
    for url, page, items in paginate(f"{BASE}/studies/?biome_lineage={BIOME}&page_size=100"):
        studies.extend(items)
    with open(STUDIES_JSONL, "w") as f:
        for s in studies:
            f.write(json.dumps(s) + "\n")
    return studies


def fetch_study_analyses(mgy):
    out = os.path.join(PAGES_DIR, mgy + ".jsonl")
    n, tmp = 0, 0
    with open(out, "a") as f:
        for url, page, items in paginate(f"{BASE}/studies/{mgy}/analyses/?page_size=100&page=1"):
            rec = {"study": mgy, "page": page, "url": url,
                   "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   "n_items": len(items), "items": items}
            f.write(json.dumps(rec) + "\n")
            f.flush()
            n += len(items)
            tmp = max(tmp, page)
    with open(out, "a") as f:  # completion marker (resume gate)
        f.write(json.dumps({"study": mgy, "complete": True, "n_analyses": n}) + "\n")
    return n


def main():
    os.makedirs(PAGES_DIR, exist_ok=True)
    studies = fetch_studies()
    print(f"studies listed: {len(studies)}", flush=True)
    done, total_n, skipped = 0, 0, 0
    t0 = time.time()
    for s in studies:
        mgy = s["accession"]
        if study_complete(mgy):
            skipped += 1
            continue
        try:
            n = fetch_study_analyses(mgy)
            total_n += n
        except Exception as e:  # graceful degradation: log and move on
            with open(ERRORS, "a") as f:
                f.write(json.dumps({"study": mgy, "error": str(e),
                                    "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}) + "\n")
            continue
        done += 1
        if done % 10 == 0:
            print(f"[{time.time()-t0:7.0f}s] {done+skipped}/{len(studies)} studies, "
                  f"{total_n} new analyses, {skipped} resumed-skip", flush=True)
    print(f"DONE studies={len(studies)} fetched={done} skipped={skipped} "
          f"new_analyses={total_n} elapsed={time.time()-t0:.0f}s errors_logged={os.path.exists(ERRORS)}",
          flush=True)


if __name__ == "__main__":
    sys.exit(main())
