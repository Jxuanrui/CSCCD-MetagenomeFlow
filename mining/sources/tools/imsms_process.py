#!/usr/bin/env python3
"""Phase-1 iMSMS/HMP2 index: parse products_MGX HTML -> per-sample URLs + staging table."""
import csv
import json
import os
import re
import sqlite3
import time
import urllib.request

RAW = "~/Course/CSCCD-MetagenomeFlow/mining/sources/raw/imsms"
CACHED_HTML = "/tmp/sources_research/ibdmdb_mgx.html"
PAGE_URL = "https://ibdmdb.org/downloads/html/products_MGX_2017-08-12.html"
META_CANDIDATES = [
    "https://g-227ca.190ebd.75bc.data.globus.org/ibdmdb/metadata/hmp2_metadata_2018-08-20.csv",
    "https://ibdmdb.org/screen/HMP2/MGX/hmp2_metadata.csv",
    "https://ibdmdb.org/downloads/hmp2_metadata.csv",
]
STAGING = "/tmp/sources_work/staging.sqlite"
REPORT = "/tmp/sources_work/imsms_report.json"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) CSCCD-MetagenomeFlow/phase1-index"}


def fetch(url, binary=False, timeout=120):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def head_size(url):
    try:
        req = urllib.request.Request(url, headers=UA, method="HEAD")
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.headers.get("Content-Length")
    except Exception as e:
        return f"error: {e}"


def main():
    os.makedirs(RAW, exist_ok=True)
    t0 = time.time()
    # 1. products page (reuse saved copy; else fetch; fallback to cached research copy)
    if os.path.exists(f"{RAW}/products_MGX_2017-08-12.html"):
        html = open(f"{RAW}/products_MGX_2017-08-12.html", encoding="utf-8", errors="replace").read()
        page_src = "saved"
    else:
        try:
            html = fetch(PAGE_URL)
            with open(f"{RAW}/products_MGX_2017-08-12.html", "w") as f:
                f.write(html)
            page_src = "fetched"
        except Exception as e:
            html = open(CACHED_HTML, encoding="utf-8", errors="replace").read()
            page_src = f"cached-fallback ({e})"
            with open(f"{RAW}/products_MGX_2017-08-12.html", "w") as f:
                f.write(html)
    hrefs = re.findall(r"href='([^']+)'", html) + re.findall(r'href="([^"]+)"', html)
    tax = [u for u in hrefs if "taxonomic_profile3_WGS/" in u and u.endswith(".tsv")]
    func = [u for u in hrefs if "func_profile3_WGS/" in u and u.endswith(".tar.bz2")]

    def stem_tax(u):
        return os.path.basename(u).replace("_taxonomic_profile_3.tsv", "")
    def stem_func(u):
        return os.path.basename(u).replace("_humann3.tar.bz2", "")

    tax_by_s, func_by_s = {}, {}
    for u in tax:
        tax_by_s.setdefault(stem_tax(u), u)
    for u in func:
        func_by_s.setdefault(stem_func(u), u)
    samples = sorted(set(tax_by_s) | set(func_by_s))

    # 2. raw URL list asset
    with open(f"{RAW}/per_sample_urls.jsonl", "w") as f:
        for s in samples:
            f.write(json.dumps({"sample_id": s, "tax_url": tax_by_s.get(s),
                                "func_url": func_by_s.get(s)}) + "\n")

    # 3. hmp2_metadata.csv (join keys; small, allowed)
    meta_path, meta_src = f"{RAW}/hmp2_metadata.csv", None
    if not os.path.exists(meta_path):
        for c in META_CANDIDATES:
            try:
                data = fetch(c, binary=True)
                with open(meta_path, "wb") as f:
                    f.write(data)
                meta_src = c
                break
            except Exception:
                time.sleep(2.5)
    else:
        meta_src = "existing"

    # 4. staging table
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    con = sqlite3.connect(STAGING)
    con.execute("""CREATE TABLE IF NOT EXISTS imsms_samples (
        sample_id TEXT PRIMARY KEY,
        tax_url TEXT,
        func_url TEXT,
        metadata_row_found INTEGER,
        indexed_at TEXT)""")
    con.execute("DELETE FROM imsms_samples")
    meta_ids, meta_acc_hits = set(), {}
    if os.path.exists(meta_path):
        with open(meta_path, newline="", encoding="utf-8", errors="replace") as f:
            rdr = csv.reader(f)
            mhdr = next(rdr)
            idcols = [i for i, h in enumerate(mhdr) if h.strip().lower() in
                      ("external id", "external_id", "sample_id", "sample name", "sample_name", "data_id")]
            acccols = [i for i, h in enumerate(mhdr) if "accession" in h.lower()]
            accre = re.compile(r"^(E[RS]R|SRR|SRS|SAME[AD]|SAMN|SAMD)\d{5,}$")
            for row in rdr:
                for i in idcols:
                    if i < len(row) and row[i]:
                        meta_ids.add(row[i].strip())
                for i in acccols:
                    if i < len(row) and accre.match(row[i].strip()):
                        meta_acc_hits[mhdr[i]] = meta_acc_hits.get(mhdr[i], 0) + 1
    con.executemany(
        "INSERT OR REPLACE INTO imsms_samples VALUES (?,?,?,?,?)",
        [(s, tax_by_s.get(s), func_by_s.get(s), 1 if s in meta_ids else 0, now) for s in samples])
    con.commit()

    # 5. registry join: metadata accessions or CSM-style ids vs canonical keys
    reg = sqlite3.connect("file:~/Course/CSCCD-MetagenomeFlow/mining/seed_registry.sqlite?mode=ro", uri=True)
    reg_keys = set(k for (k,) in reg.execute(
        "SELECT canonical_key FROM seed_runs UNION SELECT canonical_key FROM incremental_candidates"))
    direct = sum(1 for s in samples if s in reg_keys)
    meta_direct = len(meta_ids & reg_keys)

    # 6. HEAD probes for deferred-download size estimate (2 files, politeness 2.5s)
    probes = {}
    if samples:
        s0 = samples[0]
        if tax_by_s.get(s0):
            probes[tax_by_s[s0]] = head_size(tax_by_s[s0]); time.sleep(2.5)
        if func_by_s.get(s0):
            probes[func_by_s[s0]] = head_size(func_by_s[s0])
    n_both = sum(1 for s in samples if s in tax_by_s and s in func_by_s)

    report = {
        "page_source": page_src, "meta_source": meta_src,
        "n_tax_urls": len(tax), "n_func_urls": len(func),
        "n_samples": len(samples), "n_with_both": n_both,
        "metadata_rows": len(meta_ids), "metadata_row_found": sum(1 for s in samples if s in meta_ids),
        "metadata_accession_col_hits": meta_acc_hits,
        "join_direct_to_registry": direct, "join_metadata_ids_to_registry": meta_direct,
        "head_probes_bytes": probes,
        "elapsed_s": round(time.time() - t0, 1), "indexed_at": now,
    }
    with open(REPORT, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
