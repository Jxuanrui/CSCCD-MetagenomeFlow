#!/usr/bin/env python3
"""Phase-1 loader: JSONL + staging -> seed_registry.sqlite new tables + registry join.

New tables: mgnify_studies, mgnify_analyses (+in_seed_registry), agp_samples, imsms_samples.
Never touches seed_runs / incremental_candidates rows.
"""
import glob
import json
import os
import sqlite3
import time

RAW = "~/Course/CSCCD-MetagenomeFlow/mining/sources/raw"
REG = "~/Course/CSCCD-MetagenomeFlow/mining/seed_registry.sqlite"
STAGING = "/tmp/sources_work/staging.sqlite"
OUT = "/tmp/sources_work/mgnify_join.json"
NOW = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_mgnify(con):
    con.execute("DELETE FROM mgnify_analyses")
    con.execute("DELETE FROM mgnify_studies")
    studies = [json.loads(l) for l in open(f"{RAW}/mgnify/studies.jsonl") if l.strip()]
    counts = {}
    for path in glob.glob(f"{RAW}/mgnify/pages/*.jsonl"):
        for line in open(path):
            if '"complete": true' not in line:
                continue
            rec = json.loads(line)
            if rec.get("complete"):
                counts[rec["study"]] = rec["n_analyses"]
    con.executemany(
        "INSERT OR REPLACE INTO mgnify_studies VALUES (?,?,?,?,?,?)",
        [(s["accession"], s.get("title"), (s.get("biome") or {}).get("lineage"),
          s.get("updated_at"), counts.get(s["accession"]), NOW) for s in studies])

    rows, seen = [], set()
    for path in glob.glob(f"{RAW}/mgnify/pages/*.jsonl"):
        for line in open(path):
            if '"complete": true' in line:
                continue
            page = json.loads(line)
            for it in page.get("items", []):
                mgya = it.get("accession")
                if not mgya or mgya in seen:
                    continue
                seen.add(mgya)
                run = it.get("run") or {}
                rows.append((
                    mgya, run.get("accession"), run.get("sample_accession"),
                    it.get("study_accession"), it.get("experiment_type"),
                    it.get("pipeline_version"), None, NOW))
    con.executemany("""INSERT OR REPLACE INTO mgnify_analyses
        (mgya, run_accession, sample_accession, mgy_study, experiment_type,
         pipeline_version, annotations_json, indexed_at) VALUES (?,?,?,?,?,?,?,?)""", rows)
    return len(studies), len(rows)


def join_registry(con):
    """Set in_seed_registry for shotgun analyses; compute overlap matrix."""
    reg = sqlite3.connect(f"file:{REG}?mode=ro", uri=True)
    keys_seed, runs_seed = set(), {}
    for ck, rl in reg.execute("SELECT canonical_key, run_accessions FROM seed_runs"):
        keys_seed.add(ck)
        for r in (json.loads(rl) if rl and rl != "[]" else []):
            runs_seed.setdefault(r, ck)
    keys_inc, runs_inc = set(), {}
    for ck, rl in reg.execute("SELECT canonical_key, run_accessions FROM incremental_candidates"):
        keys_inc.add(ck)
        for r in (json.loads(rl) if rl and rl != "[]" else []):
            runs_inc.setdefault(r, ck)
    all_keys = keys_seed | keys_inc

    exp_types = dict(con.execute(
        "SELECT experiment_type, COUNT(*) FROM mgnify_analyses GROUP BY experiment_type"))
    shot = "Metagenomic" if "Metagenomic" in exp_types else max(exp_types, key=exp_types.get)

    stats = {"experiment_type_counts": exp_types, "shotgun_label": shot,
             "registry_keys": {"seed_runs": len(keys_seed), "incremental": len(keys_inc),
                               "union": len(all_keys)},
             "registry_runs_parsed": {"seed_runs": len(runs_seed), "incremental": len(runs_inc)}}

    matched = {}   # canonical_key -> set(mgya)
    n_shot = 0
    upd = []
    for mgya, run_acc, samp_acc in con.execute(
            "SELECT mgya, run_accession, sample_accession FROM mgnify_analyses WHERE experiment_type=?",
            (shot,)):
        n_shot += 1
        ck = None
        if run_acc:
            ck = runs_seed.get(run_acc) or runs_inc.get(run_acc) \
                 or (run_acc if run_acc in all_keys else None)
        if not ck and samp_acc and samp_acc in all_keys:
            ck = samp_acc
        upd.append((1 if ck else 0, mgya))
        if ck:
            matched.setdefault(ck, set()).add(mgya)
    con.executemany("UPDATE mgnify_analyses SET in_seed_registry=? WHERE mgya=?", upd)

    in_seed = sum(1 for f, _ in upd if f)
    cov_seed = sum(1 for k in matched if k in keys_seed)
    cov_inc = sum(1 for k in matched if k in keys_inc and k not in keys_seed)
    stats.update({
        "shotgun_analyses": n_shot,
        "shotgun_analyses_in_registry": in_seed,
        "registry_keys_matched": {"any": len(matched), "via_seed_runs": cov_seed,
                                  "via_incremental_only": cov_inc},
        "registry_coverage_rate": round(len(matched) / len(all_keys), 4),
    })
    return stats


def main():
    src = sqlite3.connect(STAGING)
    con = sqlite3.connect(REG, timeout=60)
    con.execute("PRAGMA busy_timeout=60000")
    con.executescript("""
    CREATE TABLE IF NOT EXISTS mgnify_studies (
        mgy_study TEXT PRIMARY KEY, title TEXT, biome_lineage TEXT,
        updated_at TEXT, analyses_count INTEGER, indexed_at TEXT);
    CREATE TABLE IF NOT EXISTS mgnify_analyses (
        mgya TEXT PRIMARY KEY, run_accession TEXT, sample_accession TEXT,
        mgy_study TEXT, experiment_type TEXT, pipeline_version TEXT,
        annotations_json TEXT, indexed_at TEXT, in_seed_registry INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS agp_samples (
        sample_name TEXT PRIMARY KEY, accession_cols_json TEXT,
        n_nonnull_phenotypes INTEGER, indexed_at TEXT);
    CREATE TABLE IF NOT EXISTS imsms_samples (
        sample_id TEXT PRIMARY KEY, tax_url TEXT, func_url TEXT,
        metadata_row_found INTEGER, indexed_at TEXT);
    CREATE INDEX IF NOT EXISTS idx_mgnify_analyses_study ON mgnify_analyses(mgy_study);
    CREATE INDEX IF NOT EXISTS idx_mgnify_analyses_run ON mgnify_analyses(run_accession);
    """)
    n_st, n_an = load_mgnify(con)
    for tbl in ("agp_samples", "imsms_samples"):
        cols = [r[1] for r in src.execute(f"PRAGMA table_info({tbl})")]
        con.execute(f"DELETE FROM {tbl}")
        con.executemany(f"INSERT INTO {tbl} VALUES ({','.join('?'*len(cols))})",
                        list(src.execute(f"SELECT * FROM {tbl}")))
    con.commit()
    stats = join_registry(con)
    con.commit()
    stats["mgnify"] = {"studies_indexed": n_st, "analyses_indexed": n_an, "indexed_at": NOW}
    with open(OUT, "w") as f:
        json.dump(stats, f, indent=2)
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
