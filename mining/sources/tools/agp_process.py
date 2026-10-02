#!/usr/bin/env python3
"""Phase-1 AGP index: stream qiita sample_info TSV -> gzip + staging table.

Staging: /tmp/sources_work/staging.sqlite (table agp_samples), copied into
seed_registry.sqlite by the loader. Join info reported to /tmp/sources_work/agp_join.json.
"""
import csv
import gzip
import io
import json
import re
import sqlite3
import time
import zipfile

ZIP = "/tmp/sources_research/qiita_agp_sample_info.zip"
RAW_DIR = "~/Course/CSCCD-MetagenomeFlow/mining/sources/raw/agp"
GZ_OUT = f"{RAW_DIR}/sample_info.tsv.gz"
STAGING = "/tmp/sources_work/staging.sqlite"
REPORT = "/tmp/sources_work/agp_join.json"

ACCRE = re.compile(r"^(E[RS]R|SRR|SRS|SAME?[AD]|SAMD|SRS)\d{5,}$")

def main():
    t0 = time.time()
    z = zipfile.ZipFile(ZIP)
    name = z.namelist()[0]
    con = sqlite3.connect(STAGING)
    con.execute("""CREATE TABLE IF NOT EXISTS agp_samples (
        sample_name TEXT PRIMARY KEY,
        accession_cols_json TEXT,
        n_nonnull_phenotypes INTEGER,
        indexed_at TEXT)""")
    con.execute("DELETE FROM agp_samples")
    n_rows = n_cols = 0
    dup = empty = 0
    acc_col_hits = {}   # column name -> count of accession-like values
    with z.open(name) as fin, gzip.open(GZ_OUT, "wt", encoding="utf-8", newline="") as fout:
        txt = io.TextIOWrapper(fin, encoding="utf-8", errors="replace")
        reader = csv.reader(txt, delimiter="\t")
        writer = csv.writer(fout, delimiter="\t", lineterminator="\n")
        header = next(reader)
        n_cols = len(header)
        writer.writerow(header)
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        rows = []
        for row in reader:
            if len(row) < n_cols:          # pad short rows
                row = row + [""] * (n_cols - len(row))
            n_rows += 1
            writer.writerow(row)
            sname = row[0]
            n_nonnull = sum(1 for v in row[1:] if v != "")
            for j, v in enumerate(row):
                if v and ACCRE.match(v):
                    acc_col_hits[header[j]] = acc_col_hits.get(header[j], 0) + 1
            if sname:
                rows.append((sname, None, n_nonnull, now))
            else:
                empty += 1
            if len(rows) >= 5000:
                con.executemany("INSERT OR REPLACE INTO agp_samples VALUES (?,?,?,?)", rows)
                rows = []
        if rows:
            con.executemany("INSERT OR REPLACE INTO agp_samples VALUES (?,?,?,?)", rows)
    con.commit()

    # join attempt against registry keys
    reg = sqlite3.connect("file:~/Course/CSCCD-MetagenomeFlow/mining/seed_registry.sqlite?mode=ro", uri=True)
    reg_keys = set(k for (k,) in reg.execute(
        "SELECT canonical_key FROM seed_runs UNION SELECT canonical_key FROM incremental_candidates"))
    agp_names = set(k for (k,) in con.execute("SELECT sample_name FROM agp_samples"))
    direct = len(agp_names & reg_keys)

    report = {
        "zip_member": name,
        "n_rows": n_rows, "n_cols": n_cols,
        "distinct_sample_names": len(agp_names),
        "accession_like_column_hits": acc_col_hits,
        "join_direct_sample_name_to_registry": direct,
        "elapsed_s": round(time.time() - t0, 1),
        "indexed_at": now,
    }
    with open(REPORT, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
