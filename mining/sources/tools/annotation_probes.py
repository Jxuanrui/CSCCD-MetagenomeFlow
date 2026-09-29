#!/usr/bin/env python3
"""Verify /analyses/{MGYA}/annotations on a small diverse probe set.

The annotations payload exposes `results_dir` (FTP base) + `downloads` (file URLs).
We verify a deterministic template: mgnify_results/{ena[:6]}/{ena}/{run[:8]}/{run}/{pipe}/{exp}
against each candidate ENA study accession, to enable deferred downloads without
per-analysis API calls. Verbatim payloads stored in mgnify_annotation_probes.
"""
import json
import re
import sqlite3
import time
import urllib.request

REG = "~/Course/CSCCD-MetagenomeFlow/mining/seed_registry.sqlite"
REPORT = "/tmp/sources_work/annotation_probes.json"
BASE = "https://www.ebi.ac.uk/metagenomics/api/v2"
STUDIES = "~/Course/CSCCD-MetagenomeFlow/mining/sources/raw/mgnify/studies.jsonl"
UA = {"User-Agent": "CSCCD-MetagenomeFlow/phase1-index"}


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read().decode())


def main():
    ena_of = {}
    for line in open(STUDIES):
        s = json.loads(line)
        ena_of[s["accession"]] = s.get("ena_accessions") or []

    con = sqlite3.connect(REG, timeout=60)
    con.execute("PRAGMA busy_timeout=60000")
    con.execute("""CREATE TABLE IF NOT EXISTS mgnify_annotation_probes (
        mgya TEXT PRIMARY KEY, run_accession TEXT, mgy_study TEXT,
        experiment_type TEXT, pipeline_version TEXT,
        annotations_json TEXT, template_ok INTEGER, indexed_at TEXT)""")
    con.execute("DELETE FROM mgnify_annotation_probes")

    rows = list(con.execute("""SELECT mgya, run_accession, mgy_study, experiment_type, pipeline_version
                               FROM mgnify_analyses WHERE run_accession IS NOT NULL"""))
    buckets = {}
    for r in rows:
        k = (r[4], r[3], re.sub(r"\d.*", "", r[1] or ""))
        buckets.setdefault(k, []).append(r)
    probes = [v[len(v) // 2] for v in sorted(buckets.values())]

    out, now = [], time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    for mgya, run_acc, mgy_study, exp_type, pipeline in probes:
        rec = {"mgya": mgya, "run_accession": run_acc, "mgy_study": mgy_study,
               "experiment_type": exp_type, "pipeline_version": pipeline}
        try:
            data = get_json(f"{BASE}/analyses/{mgya}/annotations")
            dls = data.get("downloads") or []
            rdir = (data.get("results_dir") or "").rstrip("/")
            rec["n_downloads"] = len(dls)
            rec["download_groups"] = sorted({d.get("download_group") for d in dls})
            rec["results_dir"] = rdir
            modern = pipeline == "V6"  # V5 uses the legacy sharded layout
            tpl_ok, matched_ena = 0, None
            for ena in ena_of.get(mgy_study, []):
                if modern:
                    cand = (f"https://ftp.ebi.ac.uk/pub/databases/metagenomics/mgnify_results/"
                            f"{ena[:6]}/{ena}/{run_acc[:-3]}/{run_acc}/{pipeline}/{exp_type.lower()}")
                    if rdir == cand:
                        tpl_ok, matched_ena = 1, ena
                        break
                else:  # legacy V<=5: sharded layout; only study-level prefix is deterministic
                    num = pipeline[1:]
                    ver = num if "." in num else num + ".0"
                    cand = (f"https://ftp.ebi.ac.uk/pub/databases/metagenomics/mgnify_results/"
                            f"{ena[:6]}/{ena}/version_{ver}")
                    if rdir.startswith(cand):
                        tpl_ok, matched_ena = 1, ena
                        break
            rec["layout"] = "modern" if modern else "legacy"
            ftp_urls = [d.get("url") or "" for d in dls
                        if (d.get("url") or "").startswith(
                            "https://ftp.ebi.ac.uk/pub/databases/metagenomics/mgnify_results/")]
            urls_ok = bool(ftp_urls) and all(u.startswith(rdir + "/") for u in ftp_urls)
            rec["ftp_urls_under_results_dir"] = urls_ok
            rec["non_ftp_urls"] = len(dls) - len(ftp_urls)
            rec["template_ok"] = 1 if (tpl_ok and urls_ok) else 0
            rec["matched_ena"] = matched_ena
            con.execute("INSERT OR REPLACE INTO mgnify_annotation_probes VALUES (?,?,?,?,?,?,?,?)",
                        (mgya, run_acc, mgy_study, exp_type, pipeline, json.dumps(data), rec["template_ok"], now))
        except Exception as e:
            rec["error"] = str(e)
            con.execute("INSERT OR REPLACE INTO mgnify_annotation_probes VALUES (?,?,?,?,?,?,?,?)",
                        (mgya, run_acc, mgy_study, exp_type, pipeline, json.dumps({"error": str(e)}), 0, now))
        out.append(rec)
        time.sleep(0.6)
    con.commit()
    with open(REPORT, "w") as f:
        json.dump(out, f, indent=2)
    for r in out:
        print(r.get("pipeline_version"), r.get("experiment_type"), r.get("run_accession"),
              "OK ena=" + str(r.get("matched_ena")) if r.get("template_ok") else ("ERR " + str(r.get("error", "template-mismatch"))),
              "n=" + str(r.get("n_downloads", "-")))


if __name__ == "__main__":
    main()
