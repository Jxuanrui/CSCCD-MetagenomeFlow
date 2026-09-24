#!/usr/bin/env python3
"""M4 MVP prepare step: cohort feasibility scan + polite profile downloads.

Subcommands:
  scan      join curation x seed_runs x mgnify_analyses (+ iMSMS metadata)
            -> feasibility.json, cohorts.json (no downloads)
  download  read cohorts.json -> mining/m4/profiles/<source>/<key>.tsv.gz
            (+ annotations_cache.jsonl, download_report.json). Skip-if-exists
            makes reruns resume-safe; 1 stream, >=0.5 s gap between requests.

Honest notes baked into feasibility.json:
  - NO registry disease has >=10 case AND >=10 healthy *same-registry* samples
    with usable profiles; demonstration cohorts are chosen per instructions
    (top diseases by max(case, control)).
  - Legacy MGnify analyses (V1-V5) expose only rRNA-OTU/SSU tables (no mOTUs
    species profiles); V1 tables stop at family rank. FTP availability is
    per-analysis and partially pruned (e.g. NielsenHB_2014 / ERP002061 -> 404).
"""
import argparse
import collections
import csv
import gzip
import json
import os
import sqlite3
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
M4 = os.path.join(ROOT, "mining", "m4")
CURATION_DB = f"file:{ROOT}/mining/curation.sqlite?mode=ro"
REGISTRY_DB = f"file:{ROOT}/mining/seed_registry.sqlite?mode=ro"
IMSMS_META = f"{ROOT}/mining/sources/raw/imsms/hmp2_metadata.csv"
API = "https://www.ebi.ac.uk/metagenomics/api/v2/analyses/{mgya}/annotations"
API_V1_DL = "https://www.ebi.ac.uk/metagenomics/api/v1/analyses/{mgya}/downloads"
API_V1_FILE = "https://www.ebi.ac.uk/metagenomics/api/v1/analyses/{mgya}/file/{alias}"
UA = {"User-Agent": "CSCCD-MetagenomeFlow/m4 (+academic mining MVP)"}


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# ---------------------------------------------------------------- scan ----

def registry_metagenomic(cur):
    """run -> (mgya, pipeline_version); latest pipeline wins, mgya tie-break."""
    best = {}
    for run, mgya, pv in cur.execute(
        "SELECT run_accession, mgya, pipeline_version FROM mgnify_analyses "
        "WHERE in_seed_registry=1 AND experiment_type='Metagenomic'"
    ):
        if run not in best or (pv, mgya) > best[run]:
            best[run] = (pv, mgya)
    return best


def scan():
    reg = sqlite3.connect(REGISTRY_DB, uri=True)
    cur = reg.cursor()
    best = registry_metagenomic(cur)
    runs_by_key, study_by_key = {}, {}
    for key, rl, sn in cur.execute(
        "SELECT canonical_key, run_accessions, study_name FROM seed_runs "
        "WHERE run_accessions LIKE '[%'"
    ):
        try:
            runs_by_key[key] = json.loads(rl)
        except (ValueError, TypeError):
            runs_by_key[key] = []
        study_by_key[key] = sn or "(unset)"

    # iMSMS: sample_id -> tax_url
    imsms_url = dict(cur.execute(
        "SELECT sample_id, tax_url FROM imsms_samples WHERE tax_url IS NOT NULL AND tax_url != ''"))

    ccon = sqlite3.connect(CURATION_DB, uri=True)
    ccur = ccon.cursor()
    rows = ccur.execute(
        "SELECT canonical_key, disease_label, disease_mondo, condition_group "
        "FROM curation WHERE condition_group IN ('case','healthy')").fetchall()

    dis_case = collections.defaultdict(list)   # disease -> [(key, study)]
    dis_healthy = collections.defaultdict(list)
    for key, dis, mondo, cg in rows:
        d = dis or "(unlabeled)"
        runs = [r for r in runs_by_key.get(key, []) if r in best]
        if not runs:
            continue
        rec = (key, study_by_key.get(key, "?"), best[runs[0]][0])
        (dis_case if cg == "case" else dis_healthy)[d].append(rec)

    diseases = []
    all_names = set(dis_case) | set(dis_healthy)
    for d in sorted(all_names, key=lambda x: -max(len(dis_case.get(x, [])), len(dis_healthy.get(x, [])))):
        cases, healthy = dis_case.get(d, []), dis_healthy.get(d, [])
        case_studies = collections.Counter(s for _, s, _ in cases)
        healthy_studies = collections.Counter(s for _, s, _ in healthy)
        shared = sorted(set(case_studies) & set(healthy_studies) - {"(unset)"})
        diseases.append({
            "disease": d,
            "n_case_profile_ready": len(cases),
            "n_healthy_pool": len(healthy),
            "n_healthy_same_study": sum(healthy_studies[s] for s in shared),
            "case_studies": dict(case_studies.most_common(4)),
            "healthy_studies": dict(healthy_studies.most_common(4)),
            "meets_10_10": len(cases) >= 10 and len(healthy) >= 10,
        })

    # iMSMS arm: earliest metagenomics sample per participant
    dx_rows = []
    with open(IMSMS_META, newline="", encoding="utf-8", errors="replace") as f:
        rdr = csv.reader(f)
        hdr = next(rdr)
        ix = {c: hdr.index(c) for c in ("External ID", "data_type", "week_num", "Participant ID", "diagnosis")}
        for row in rdr:
            if len(row) <= max(ix.values()):
                continue
            if row[ix["External ID"]] in imsms_url and row[ix["data_type"]] == "metagenomics":
                try:
                    week = float(row[ix["week_num"]]) if row[ix["week_num"]] else 9e9
                except ValueError:
                    week = 9e9
                dx_rows.append((row[ix["Participant ID"]], week, row[ix["External ID"]], row[ix["diagnosis"]]))
    per_part = {}
    for part, week, sid, dx in dx_rows:
        if part not in per_part or (week, sid) < (per_part[part][0], per_part[part][1]):
            per_part[part] = (week, sid, dx)
    imsms_dx = collections.Counter(v[2] for v in per_part.values())

    # ---- demonstration cohort selection (documented, deterministic) ----
    def mgnify_cohort(name, label_filter, match_term, healthy_study, max_controls=250):
        cases = [k for k, s, _ in dis_case.get(name, []) if label_filter(k, s)]
        controls = sorted(k for k, s, _ in dis_healthy.get("Healthy", []) if s == healthy_study)
        if len(controls) > max_controls:          # deterministic stride subsample
            step = len(controls) / max_controls
            controls = sorted({controls[int(i * step)] for i in range(max_controls)})
        return {
            "source": "mgnify", "display": match_term,
            "bugsigdb_match_term": match_term,
            "cases": sorted(cases), "controls": controls,
            "control_study": healthy_study,
            "n_controls_available": sum(1 for k, s, _ in dis_healthy.get("Healthy", []) if s == healthy_study),
            "case_studies": sorted({s for k, s, _ in dis_case.get(name, []) if k in cases}),
        }

    cohorts = {
        "crohn_disease_imsms": {
            "source": "imsms", "display": "Crohn Disease (iMSMS)", "bugsigdb_match_term": "Crohn Disease",
            "case_dx": "CD", "control_dx": "nonIBD",
            "cases": sorted(v[1] for v in per_part.values() if v[2] == "CD"),
            "controls": sorted(v[1] for v in per_part.values() if v[2] == "nonIBD")},
        "ulcerative_colitis_imsms": {
            "source": "imsms", "display": "Ulcerative Colitis (iMSMS)", "bugsigdb_match_term": "Ulcerative Colitis",
            "case_dx": "UC", "control_dx": "nonIBD",
            "cases": sorted(v[1] for v in per_part.values() if v[2] == "UC"),
            "controls": sorted(v[1] for v in per_part.values() if v[2] == "nonIBD")},
        "hypertension_mgnify": mgnify_cohort(
            "Hypertension", lambda k, s: s == "LiJ_2017", "Hypertension", "MehtaRS_2018"),
        "hiv_infection_mgnify": mgnify_cohort(
            "immune", lambda k, s: s == "2019_Guillen_HIV", "HIV infection", "MehtaRS_2018"),
    }
    for c in cohorts.values():
        c["n_case"], c["n_control"] = len(c["cases"]), len(c["controls"])

    feasibility = {
        "generated_at": now(),
        "registry_join": {
            "curation_rows": ccur.execute("SELECT COUNT(*) FROM curation").fetchone()[0],
            "registry_metagenomic_runs": len(best),
            "distinct_runs_in_seed_lists": len({r for v in runs_by_key.values() for r in v}),
            "note": "profile-ready = curation key with >=1 in_seed_registry Metagenomic analysis "
                    "(legacy pipelines V1-V5 only; no V6/mOTUs re-annotations exist for these runs)",
        },
        "diseases": diseases,
        "meets_10case_10healthy": [d["disease"] for d in diseases if d["meets_10_10"]],
        "imsms": {
            "samples_with_tax_url": len(imsms_url),
            "participants_earliest_sample": dict(imsms_dx),
            "note": "diagnosis from hmp2_metadata.csv (External ID, data_type=metagenomics); "
                    "longestitudinal repeats deduplicated to earliest week per participant",
        },
        "blocked": {
            "Type 2 Diabetes Mellitus": "V1 analyses only -> family-rank OTU tables (no genus/species)",
            "Inflammatory Bowel Disease;Ulcerative Colitis (NielsenHB_2014)":
                "V3 analyses FTP-pruned (ERP002061 results 404); would also be the only same-study control pair",
            "BackhedF_2015 healthy pool": "excluded as controls: infant cohort (median age 0.3 y)",
        },
        "selected_cohorts": {k: {x: v[x] for x in ("source", "display", "n_case", "n_control", "control_study") if x in v}
                             for k, v in cohorts.items()},
        "caveats": [
            "No registry disease meets >=10 case AND >=10 healthy profile-ready threshold; "
            "demonstration cohorts picked by max(case, control) per task instructions.",
            "MGnify arm compares across studies (e.g. LiJ_2017 China vs MehtaRS_2018 USA) and across "
            "pipeline versions (V3 Greengenes OTUs vs V4.1 SILVA MAPseq): batch effects expected.",
            "Legacy profiles are rRNA-derived OTU/SSU tables (hundreds to ~100k assignments/sample), "
            "NOT WGS mOTUs species profiles; species rank only where the table resolves it.",
            "MGnify healthy controls subsampled deterministically (stride) to 250 of 928: "
            "ftp.ebi.ac.uk throttled to ~45 s/request, www.ebi.ac.uk API file proxy used instead.",
        ],
    }
    os.makedirs(M4, exist_ok=True)
    with open(f"{M4}/feasibility.json", "w") as f:
        json.dump(feasibility, f, indent=1)
    with open(f"{M4}/cohorts.json", "w") as f:
        json.dump({"generated_at": now(), "cohorts": cohorts}, f, indent=1)
    print(f"[scan] diseases={len(diseases)} meets_10_10={len(feasibility['meets_10case_10healthy'])}")
    for k, v in cohorts.items():
        print(f"[scan] cohort {k}: {v['n_case']} cases vs {v['n_control']} controls ({v['source']})")


# ------------------------------------------------------------ download ----

def http_get(url, timeout=120, retries=3):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as exc:  # noqa: BLE001 - record and retry
            last = exc
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"{last}")


def pick_biom_alias(downloads_json):
    """Deterministic taxonomy-biom choice from a v1 downloads payload (by alias).

    ftp.ebi.ac.uk throttled to ~45 s/request during this run; the
    www.ebi.ac.uk API file proxy serves the same bytes in ~1 s, so we use it.
    """
    cands = []
    for it in downloads_json.get("data") or []:
        alias = (it.get("attributes") or {}).get("alias") or ""
        a = alias.lower()
        if not a.endswith(".biom"):
            continue
        if a.endswith("ssu_otu_table_json.biom"):
            cands.append((0, alias))       # V4/V5 SSU MAPseq (genus+species)
        elif a.endswith("otu_table_json.biom"):
            cands.append((1, alias))       # V2/V3 OTU table (Greengenes)
        elif a.endswith("otu_table.biom"):
            cands.append((2, alias))       # V1 OTU table (family-rank only)
        elif a.endswith("lsu_otu_table_json.biom"):
            cands.append((3, alias))       # LSU fallback
    return min(cands)[1] if cands else None


def resolve_alias(mgya):
    """Taxonomy-biom alias for an analysis: v1 downloads list first, then the
    v2 annotations payload (some V3 analyses omit the biom from v1 downloads
    but the file proxy still serves it by filename)."""
    dls = json.loads(http_get(API_V1_DL.format(mgya=mgya)))
    alias = pick_biom_alias(dls)
    if alias:
        return alias
    ann = json.loads(http_get(API.format(mgya=mgya)))
    cands = []
    for dl in ann.get("downloads") or []:
        u = dl.get("url") or ""
        a = u.lower()
        if not a.endswith(".biom"):
            continue
        if "ssu" in a and "json" in a:
            cands.append((0, u))
        elif a.endswith("otu_table_json.biom"):
            cands.append((1, u))
        elif a.endswith("otu_table.biom"):
            cands.append((2, u))
        elif "lsu" in a and "json" in a:
            cands.append((3, u))
    return min(cands)[1].rsplit("/", 1)[-1] if cands else None


def biom_to_tsv(biom_bytes):
    """JSON BIOM -> 'lineage<TAB>count' rows (values summed per row)."""
    d = json.loads(biom_bytes.decode("utf-8", "replace"))
    rows = d.get("rows") or []
    counts = collections.Counter()
    for r, _c, v in d.get("data") or []:
        counts[r] += v
    out = []
    for i, row in enumerate(rows):
        if counts.get(i):
            tax = (row.get("metadata") or {}).get("taxonomy") or [row.get("id") or "?"]
            out.append(f"{';'.join(str(t) for t in tax)}\t{counts[i]:g}")
    return "\n".join(out) + "\n" if out else ""


def download():
    with open(f"{M4}/cohorts.json") as f:
        cohorts = json.load(f)["cohorts"]
    reg = sqlite3.connect(REGISTRY_DB, uri=True).cursor()
    best = registry_metagenomic(reg)
    runs_by_key = {}
    for key, rl in reg.execute(
        "SELECT canonical_key, run_accessions FROM seed_runs WHERE run_accessions LIKE '[%'"
    ):
        try:
            runs_by_key[key] = json.loads(rl)
        except (ValueError, TypeError):
            runs_by_key[key] = []
    imsms_url = dict(reg.execute(
        "SELECT sample_id, tax_url FROM imsms_samples WHERE tax_url IS NOT NULL AND tax_url != ''"))

    os.makedirs(f"{M4}/profiles/mgnify", exist_ok=True)
    os.makedirs(f"{M4}/profiles/imsms", exist_ok=True)
    cache = {}
    cache_path = f"{M4}/annotations_cache.jsonl"
    if os.path.exists(cache_path):
        with open(cache_path) as f:
            for line in f:
                try:
                    rec = json.loads(line)
                    if rec.get("alias"):
                        cache[rec["mgya"]] = rec["alias"]
                except (ValueError, KeyError):
                    continue
    cache_f = open(cache_path, "a")

    jobs = []  # (source, key, url|None, mgya|None)
    seen = set()
    for cname, c in cohorts.items():
        for role in ("cases", "controls"):
            for key in c[role]:
                if (c["source"], key) in seen:
                    continue
                seen.add((c["source"], key))
                if c["source"] == "imsms":
                    jobs.append(("imsms", key, imsms_url.get(key), None))
                else:
                    runs = [r for r in runs_by_key.get(key, []) if r in best]
                    pv, mgya = best[runs[0]] if runs else (None, None)
                    jobs.append(("mgnify", key, None, mgya))

    report = {"started_at": now(), "ok": 0, "skip": 0, "fail": [], "no_url": [], "finished_at": None}
    print(f"[download] {len(jobs)} sample jobs")
    for i, (source, key, url, mgya) in enumerate(jobs):
        dest = f"{M4}/profiles/{source}/{key}.tsv.gz"
        if os.path.exists(dest) and os.path.getsize(dest) > 0:
            report["skip"] += 1
            continue
        try:
            if source == "imsms":
                if not url:
                    report["no_url"].append(key)
                    continue
                data = http_get(url)
                with gzip.open(dest, "wb") as f:
                    f.write(data)
            else:
                if not mgya:
                    report["no_url"].append(f"{key}:no-analysis")
                    continue
                if mgya not in cache:
                    alias = resolve_alias(mgya)
                    cache[mgya] = alias
                    cache_f.write(json.dumps({"mgya": mgya, "alias": alias}) + "\n")
                    cache_f.flush()
                    time.sleep(0.5)
                alias = cache[mgya]
                if not alias:
                    report["no_url"].append(f"{key}:no-taxonomy-biom")
                    continue
                tsv = biom_to_tsv(http_get(API_V1_FILE.format(mgya=mgya, alias=alias)))
                if not tsv:
                    raise RuntimeError("empty biom table")
                with gzip.open(dest, "wb") as f:
                    f.write(tsv.encode())
            report["ok"] += 1
        except Exception as exc:  # noqa: BLE001 - honest gap recording
            report["fail"].append(f"{source}:{key}: {exc}")
        if (i + 1) % 50 == 0:
            print(f"[download] {i+1}/{len(jobs)} ok={report['ok']} skip={report['skip']} fail={len(report['fail'])}", flush=True)
        time.sleep(0.5)
    cache_f.close()
    report["finished_at"] = now()
    with open(f"{M4}/download_report.json", "w") as f:
        json.dump(report, f, indent=1)
    print(f"[download] done ok={report['ok']} skip={report['skip']} "
          f"fail={len(report['fail'])} no_url={len(report['no_url'])}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cmd", choices=("scan", "download"))
    args = ap.parse_args()
    if args.cmd == "scan":
        scan()
    else:
        download()


if __name__ == "__main__":
    main()
