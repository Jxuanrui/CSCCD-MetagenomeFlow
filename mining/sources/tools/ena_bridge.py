#!/usr/bin/env python3
"""Phase-2 ENA bridge: ENA run tables -> accession columns on agp/imsms + registry flag.

Inputs : mining/sources/raw/bridges/*.tsv — ENA portal filereport TSVs, fields
         run_accession,sample_accession,sample_alias,sample_title.
           AGP  : ERP012803 + PRJEB11419 (identical run sets; ERP first, PRJ merged)
           iMSMS: ERP005534 / PRJEB24483 are NOT the HMP2 study (negative evidence,
                  kept for the record). The working accession is PRJNA398089, whose
                  sample_alias = <site_sub_coll>[_<data-type suffix>]; MGX runs carry
                  suffix '' or 'MGX'. Join chain: ENA alias base -> hmp2_metadata
                  (data_type=metagenomics) site_sub_coll -> External ID -> sample_id.
Writes : agp_samples / imsms_samples columns
           run_accession  TEXT  (JSON array, seed_runs.run_accessions convention)
           sample_accession TEXT
           join_method    TEXT
           in_registry    INTEGER 0/1
         /tmp/bridge/bridge_report.json; updates mining/sources_summary.json
         (adds "bridges" section, refreshes joinable/overlap numbers).
Never writes seed_runs / incremental_candidates.
"""
import csv
import json
import re
import sqlite3
import time

ROOT = "~/Course/CSCCD-MetagenomeFlow"
BRIDGES = f"{ROOT}/mining/sources/raw/bridges"
REG = f"{ROOT}/mining/seed_registry.sqlite"
META = f"{ROOT}/mining/sources/raw/imsms/hmp2_metadata.csv"
REPORT = "/tmp/bridge/bridge_report.json"
SUMMARY = f"{ROOT}/mining/sources_summary.json"
NOW = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

norm = lambda s: re.sub(r"\s+", " ", s.strip().lower())
loose = lambda s: re.sub(r"[-_\s]+", "", s.lower())


def read_tsv(name):
    path = f"{BRIDGES}/{name}"
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        return list(csv.DictReader(f, delimiter="\t"))


# ---------------------------------------------------------------- AGP bridge
def bridge_agp():
    """Merge ERP012803+PRJEB11419 run rows; build lookup tiers off sample_title."""
    runs_seen, entries = set(), {}          # entry: [sample_acc, {runs}]
    stats = {"files": {}}
    for fname in ("ERP012803.tsv", "PRJEB11419.tsv"):
        rows = read_tsv(fname)
        new = 0
        for r in rows:
            run = r["run_accession"]
            if run in runs_seen:
                continue
            runs_seen.add(run)
            new += 1
            key = r["sample_title"] or r["sample_alias"]
            ent = entries.setdefault(key, [r["sample_accession"], set()])
            ent[1].add(run)
        stats["files"][fname] = {"rows": len(rows), "new_runs_merged": new}
    # sample_title == qiita sample_name; sample_alias == "qiita_sid_10317:" + name,
    # so the alias tier collapses into the title tier here.
    tiers = {"exact": dict(entries), "norm": {}, "loose": {}}
    for key, ent in entries.items():
        tiers["norm"].setdefault(norm(key), ent)
        tiers["loose"].setdefault(loose(key), ent)
    stats.update({"ena_runs": len(runs_seen), "ena_samples": len(entries)})
    return tiers, stats


def join_agp(con, tiers):
    names = [r[0] for r in con.execute("SELECT sample_name FROM agp_samples")]
    hits, method_of = {}, {}
    for n in names:
        for m, table, key in (("exact", tiers["exact"], n),
                              ("norm", tiers["norm"], norm(n)),
                              ("loose", tiers["loose"], loose(n))):
            if key in table:
                hits[n] = table[key]
                method_of[n] = m
                break
    counts = {}
    for n, m in method_of.items():
        counts[m] = counts.get(m, 0) + 1
    upd = [(json.dumps(sorted(hits[n][1])), hits[n][0], method_of[n], n)
           for n in names if n in hits]
    con.executemany(
        "UPDATE agp_samples SET run_accession=?, sample_accession=?, join_method=? "
        "WHERE sample_name=?", upd)
    return {"rows": len(names), "matched": len(hits),
            "match_rate": round(len(hits) / len(names), 4),
            "methods": counts,
            "unmatched": len(names) - len(hits),
            "runs_attached": sum(len(hits[n][1]) for n in hits)}


# -------------------------------------------------------------- iMSMS bridge
def bridge_imsms(con):
    ena_base = {}                           # alias base -> [sample_acc, {mgx runs}]
    suffix_counts = {}
    for r in read_tsv("PRJNA398089.tsv"):
        parts = r["sample_alias"].split("_")
        base, suf = parts[0], (parts[1] if len(parts) > 1 else "")
        suffix_counts[suf] = suffix_counts.get(suf, 0) + 1
        if suf not in ("", "MGX"):          # MTX/MVX/BP/TR = other data types
            continue
        ent = ena_base.setdefault(base, [r["sample_accession"], set()])
        ent[1].add(r["run_accession"])

    ssc2ext, ext2ssc = {}, {}
    with open(META, newline="", encoding="utf-8", errors="replace") as f:
        rdr = csv.reader(f)
        hdr = next(rdr)
        i_ext, i_ssc, i_dt = hdr.index("External ID"), hdr.index("site_sub_coll"), hdr.index("data_type")
        for row in rdr:
            if row[i_dt] != "metagenomics":
                continue
            ext, ssc = row[i_ext].strip(), row[i_ssc].strip()
            if ext and ssc:
                ssc2ext.setdefault(ssc, set()).add(ext)
                ext2ssc.setdefault(ext, set()).add(ssc)

    sids = [r[0] for r in con.execute("SELECT sample_id FROM imsms_samples")]
    upd, methods = [], {}
    n_ssc_amb = n_ext_amb = 0
    for sid in sids:
        sscs = ext2ssc.get(sid, set())
        hits = {b: ena_base[b] for b in sscs if b in ena_base}
        if not hits:
            continue
        if len(sscs) > 1:
            n_ext_amb += 1
        base, ent = next(iter(sorted(hits.items())))
        method = "ena_alias(PRJNA398089)->site_sub_coll->external_id"
        if len(ssc2ext[base]) > 1:
            method += "+ssc_shared"
            n_ssc_amb += 1
        methods[method] = methods.get(method, 0) + 1
        upd.append((json.dumps(sorted(ent[1])), ent[0], method, sid))
    con.executemany(
        "UPDATE imsms_samples SET run_accession=?, sample_accession=?, join_method=? "
        "WHERE sample_id=?", upd)
    return {"rows": len(sids), "matched": len(upd),
            "match_rate": round(len(upd) / len(sids), 4),
            "methods": methods, "unmatched": len(sids) - len(upd),
            "runs_attached": sum(len(json.loads(u[0])) for u in upd),
            "alias_suffix_counts": suffix_counts,
            "quirk_counters": {"ext_with_multiple_ssc": n_ext_amb,
                               "ssc_shared_by_multiple_ext": n_ssc_amb}}


# ------------------------------------------------------------ registry join
def registry_join(con, table, id_col, cmd3_prefix=False):
    """in_registry=1 when membership is verifiable: attached runs in the registry
    run->key index, sample_accession being a canonical_key, or (imsms only) the
    cMD3 alias key embedding the sample_id itself. Path counts are non-exclusive."""
    reg = sqlite3.connect(f"file:{REG}?mode=ro", uri=True)
    run_ck, all_keys = {}, set()
    for t in ("seed_runs", "incremental_candidates"):
        for ck, rl in reg.execute(f"SELECT canonical_key, run_accessions FROM {t}"):
            all_keys.add(ck)
            for r in (json.loads(rl) if rl and rl != "[]" else []):
                run_ck.setdefault(r, ck)
    paths = {"run_index": 0, "sample_accession_key": 0, "cmd3_alias_key": 0}
    covered, n_in, n_bridged_in, n_alias_only = set(), 0, 0, 0
    for sid, runs_json, samp in con.execute(
            f"SELECT {id_col}, run_accession, sample_accession FROM {table}"):
        runs = json.loads(runs_json) if runs_json else []
        cks = {run_ck[r] for r in runs if r in run_ck}
        if any(r in run_ck for r in runs):
            paths["run_index"] += 1
        if samp and samp in all_keys:
            cks.add(samp)
            paths["sample_accession_key"] += 1
        if cmd3_prefix:
            k = f"cMD3:HMP_2019_ibdmdb:{sid}"
            if k in all_keys:
                cks.add(k)
                paths["cmd3_alias_key"] += 1
        if cks:
            covered |= cks
            con.execute(f"UPDATE {table} SET in_registry=1 WHERE {id_col}=?", (sid,))
            n_in += 1
            if runs:
                n_bridged_in += 1
            else:
                n_alias_only += 1
    return {"in_registry": n_in,
            "in_registry_bridged": n_bridged_in,
            "in_registry_alias_only_unbridged": n_alias_only,
            "registry_paths": paths, "registry_keys_covered": len(covered)}


def add_cols(con, table, id_col):
    have = {r[1] for r in con.execute(f"PRAGMA table_info({table})")}
    for col, decl in (("run_accession", "TEXT"), ("sample_accession", "TEXT"),
                      ("join_method", "TEXT"), ("in_registry", "INTEGER DEFAULT 0")):
        if col not in have:
            con.execute(f"ALTER TABLE {table} ADD COLUMN {col} {decl}")
    con.execute(f"UPDATE {table} SET run_accession=NULL, sample_accession=NULL, "
                f"join_method=NULL, in_registry=0")


def update_summary(report):
    with open(SUMMARY, encoding="utf-8") as f:
        data = json.load(f)
    for src in ("agp", "imsms"):
        sec = report[src]
        data["sources"][src]["bridged_with_accessions"] = sec["matched"]
        data["sources"][src]["bridge_match_rate"] = sec["match_rate"]
        data["sources"][src]["joinable_to_registry"] = sec["registry"]["in_registry"]
        data["sources"][src]["bridged_at"] = NOW
    om = data["overlap_matrix_vs_registry"]
    om["agp_keys_covered"] = report["agp"]["registry"]["registry_keys_covered"]
    om["agp_samples_in_registry"] = report["agp"]["registry"]["in_registry"]
    om["imsms_keys_covered"] = report["imsms"]["registry"]["registry_keys_covered"]
    om["imsms_samples_in_registry"] = report["imsms"]["registry"]["in_registry"]
    om["note"] = ("AGP/iMSMS bridged via ENA alias tables (see bridges section); "
                  "counts refreshed at bridge time")
    report["generated_at"] = NOW
    report["raw_dir"] = "mining/sources/raw/bridges/"
    report["mechanism_notes"] = {
        "agp": ("registry rows reached are the 549 Meta2DB 2022_American_Gut_Project keys "
                "(PRJEB11419), joined through their ERR run lists; 648 qiita sample_names "
                "collapse onto those 549 keys (re-sequencing duplicates share runs)"),
        "imsms": ("run_index hits resolve to GMrepo SRS-keyed seed_runs rows carrying HMP2 "
                  "SRR runs (1317 distinct keys); cMD3 alias keys "
                  "cMD3:HMP_2019_ibdmdb:<sample_id> exist for 1627/1638 samples"),
    }
    data["bridges"] = report
    data.setdefault("timestamps", {})["bridges_built_at"] = NOW
    with open(SUMMARY, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def main():
    con = sqlite3.connect(REG, timeout=60)
    con.execute("PRAGMA busy_timeout=60000")
    for table in ("agp_samples", "imsms_samples"):
        add_cols(con, table, {"agp_samples": "sample_name",
                              "imsms_samples": "sample_id"}[table])
    tiers, agp_ena = bridge_agp()
    agp = join_agp(con, tiers)
    con.commit()                       # release writer lock before ro-conn reads
    agp["ena"] = agp_ena
    agp["registry"] = registry_join(con, "agp_samples", "sample_name")
    con.commit()
    imsms = bridge_imsms(con)
    con.commit()
    imsms["registry"] = registry_join(con, "imsms_samples", "sample_id", cmd3_prefix=True)
    con.commit()
    imsms["negative_evidence"] = {
        "ERP005534": "HMP1 study (CCIS aliases, 424 samples) — not HMP2/iMSMS",
        "PRJEB24483": "empty filereport — accession not present in ENA portal",
        "PRJNA398089": "actual ENA-mirrored HMP2 project (BioProject); alias=site_sub_coll(+suffix)",
    }
    con.commit()
    report = {"agp": agp, "imsms": imsms}
    with open(REPORT, "w") as f:
        json.dump(report, f, indent=2)
    update_summary(report)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
