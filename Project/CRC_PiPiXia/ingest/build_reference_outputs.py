#!/usr/bin/env python3
"""Build the Reference_result delivery tree for one dataset (project-local).

Reproduces Project/Reference_result/ schema from this run's platform outputs:
  humann3/   ko.tsv, ko_unstratified.tsv, ko_stratified.tsv,
             pathabundance.tsv, pathabundance_relab.tsv,
             pathabundance_relab_unstratified.tsv,
             pathabundance_relab_stratified.tsv,
             KEGG.Pathway.raw.txt, KEGG.PathwayL1.raw.txt, KEGG.PathwayL2.raw.txt
  kraken2/   bracken.S/G/P/D.txt, .0.2 prevalence-filtered, .0.2-H host-removed
  metaphlan4/ taxonomy.tsv, taxonomy_species.tsv

Inputs (must already exist, 25-sample gate enforced):
  result/humann3/merged/pathabundance_relab.tsv (+ per-sample raw/relab/coverage)
  result/metaphlan4/merged/taxonomy.tsv + per-sample profiles
  result/kraken2/merged/bracken_S/G/P.tsv + per-sample bracken + reports

KEGG aggregates are rebuilt from ko_unstratified + db/kegg/misc mappings
(ko-pathway.txt, ko-levels.txt, pathway-definition.txt); row names follow the
CURRENT KEGG release, so row sets may differ from Reference_result (recorded
in manifest, per review decision).

Usage:
  python3 build_reference_outputs.py --workdir Project/CRC_PiPiXia/PRJEB22893 \
      --expected-manifest manifests/download_manifest_all25.json
"""

import argparse
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
ACTIVATE = REPO / "scripts" / "activate.sh"
KEGG_MISC = REPO / "db" / "kegg" / "misc"
HUMANN_BIN = REPO / "envs" / "humann4" / "bin"


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_matrix(path):
    """Read a humann-style tsv -> {row_id: {sample: float}} + sample order."""
    samples, rows = [], {}
    with open(path, errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        samples = [s for s in header[1:] if s]
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if not parts[0]:
                continue
            rows[parts[0]] = dict(zip(samples, (float(x) for x in parts[1: len(samples) + 1])))
    return samples, rows


def write_matrix(path, row_ids, sample_order, rows):
    with open(path, "w") as fh:
        fh.write("\t".join(["# ID"] + sample_order) + "\n")
        for rid in row_ids:
            fh.write("\t".join([rid] + ["%.10f" % rows[rid].get(s, 0.0)
                                        for s in sample_order]) + "\n")


def humann_col_index(header, run):
    """Humann names value columns '<run>_Abundance' / '<run>-Abundance-RPKs'."""
    for i, col in enumerate(header):
        if col == run or col.startswith(run + "_") or col.startswith(run + "-"):
            return i
    return None


def join_per_sample(workdir, runs, kind):
    """Join per-sample humann tables -> {sample: {row: value}}."""
    joined = {}
    for run in runs:
        p = workdir / "result" / "humann3" / run / f"{run}_{kind}.tsv"
        with open(p, errors="replace") as fh:
            header = fh.readline().rstrip("\n").split("\t")
            vi = humann_col_index(header[1:], run)
            if vi is None:
                raise SystemExit(f"{p}: no value column for run {run}")
            vi += 1  # file column index (header includes the row-name column)
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if not parts[0]:
                    continue
                try:
                    v = float(parts[vi])
                except (IndexError, ValueError):
                    v = 0.0
                joined.setdefault(parts[0], {})[run] = v
    return joined


def regroup_to_ko(workdir, runs, log):
    """Join per-sample raw genefamilies -> humann_regroup uniref90_ko -> ko."""
    tmp = workdir / "temp" / "refbuild"
    tmp.mkdir(parents=True, exist_ok=True)
    joined = {}
    for run in runs:
        p = workdir / "result" / "humann3" / run / f"{run}_genefamilies.tsv"
        with open(p, errors="replace") as fh:
            header = fh.readline().rstrip("\n").split("\t")
            vi = humann_col_index(header[1:], run)
            if vi is None:
                raise SystemExit(f"{p}: no value column for run {run}")
            vi += 1
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if not parts[0]:
                    continue
                try:
                    v = float(parts[vi])
                except (IndexError, ValueError):
                    v = 0.0
                joined.setdefault(parts[0], {})[run] = v
    # humann_regroup needs a joined table on disk; use the env's python util
    joined_path = tmp / "genefamilies_joined.tsv"
    sample_order = sorted(runs)
    with open(joined_path, "w") as fh:
        fh.write("\t".join(["# Gene Family"] + sample_order) + "\n")
        for rid, per in sorted(joined.items()):
            fh.write("\t".join([rid] + ["%.10f" % per.get(s, 0.0)
                                        for s in sample_order]) + "\n")
    ko_path = tmp / "ko_joined.tsv"
    cmd = [str(HUMANN_BIN / "humann_regroup_table"), "--input", str(joined_path),
           "--group", "uniref90_ko", "--function", "sum", "--output", str(ko_path)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=7200)
    if proc.returncode != 0 or not ko_path.exists():
        raise SystemExit(f"humann_regroup_table failed: {proc.stderr[-500:]}")
    ko_samples, ko_rows = read_matrix(ko_path)
    # regroup drops the UNMAPPED control row; the reference schema keeps it
    unmapped = joined.get("UNMAPPED", {})
    if unmapped:
        ko_rows["UNMAPPED"] = {s: unmapped.get(s, 0.0) for s in ko_samples}
        ko_rows = {"UNMAPPED": ko_rows.pop("UNMAPPED"), **ko_rows}
    return ko_samples, ko_rows


def split_stratified(rows, sample_order):
    """Split KO rows into unstratified (plain) and stratified (KO|taxa)."""
    unstrat, strat = {}, {}
    for rid, per in rows.items():
        if "|" in rid:
            strat[rid] = per
        else:
            unstrat[rid] = per
    return unstrat, strat


def build_kegg_tables(ko_rows, sample_order, out_dir):
    """Aggregate ko_unstratified by KEGG pathway/level1/level2 mappings."""
    ko2path = {}
    with open(KEGG_MISC / "ko-pathway.txt", errors="replace") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 2:
                ko2path.setdefault(p[0], []).append(p[1])
    path_name = {}
    with open(KEGG_MISC / "pathway-definition.txt", errors="replace") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 2:
                path_name[p[0]] = p[1]
    ko_levels = {}
    with open(KEGG_MISC / "ko-levels.txt", errors="replace") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 5:
                ko_levels[p[0]] = (p[2], p[3], p[4])  # L3, L2, L1

    def agg(mapping):
        out = {}
        for ko, per in ko_rows.items():
            for key in mapping.get(ko, ()):
                acc = out.setdefault(key, [0.0] * len(sample_order))
                for i, v in enumerate(per.values()):
                    acc[i] += v
        return out

    def write_kegg(path, header, mapping_names, agg_rows):
        with open(path, "w") as fh:
            fh.write("\t".join([header, "KO"] + sample_order) + "\n")
            for key, per in sorted(agg_rows.items()):
                kos = "".join(sorted(ko2path_keys.get(key, ())))
                fh.write("\t".join([key, kos] + ["%.10f" % v for v in per]) + "\n")

    # pathway-level (L3 named like reference: 'name [PATH:mapXXXX]')
    pw_rows = {}
    for ko, per in ko_rows.items():
        for mp in ko2path.get(ko, ()):
            nm = f" {path_name.get(mp, mp)} [PATH:{mp}]"
            acc = pw_rows.setdefault(nm, [0.0] * len(sample_order))
            for i, v in enumerate(per.values()):
                acc[i] += v
    with open(out_dir / "KEGG.Pathway.raw.txt", "w") as fh:
        fh.write("\t".join(["Pathway", "KO"] + sample_order) + "\n")
        for nm, per in sorted(pw_rows.items()):
            fh.write("\t".join([nm, ""] + ["%.10f" % v for v in per]) + "\n")

    l1_rows, l2_rows = {}, {}
    for ko, per in ko_rows.items():
        lv = ko_levels.get(ko)
        if not lv:
            continue
        for idx, table in ((2, l1_rows), (1, l2_rows)):
            acc = table.setdefault(lv[idx], [0.0] * len(sample_order))
            for i, v in enumerate(per.values()):
                acc[i] += v
    for name, rows in (("KEGG.PathwayL1.raw.txt", l1_rows),
                       ("KEGG.PathwayL2.raw.txt", l2_rows)):
        with open(out_dir / name, "w") as fh:
            fh.write("\t".join(["PathwayL1" if "L1" in name else "PathwayL2",
                                "KO"] + sample_order) + "\n")
            for nm, per in sorted(rows.items()):
                fh.write("\t".join([nm, ""] + ["%.10f" % v for v in per]) + "\n")
    return len(pw_rows), len(l1_rows), len(l2_rows)


def bracken_levels(workdir, runs, kraken_dir):
    """Merge per-sample bracken S/G/P + derive D from per-sample reports."""
    levels = {"S": {}, "G": {}, "P": {}, "D": {}}
    for run in runs:
        report = kraken_dir / run / f"{run}.report"
        domain_reads = {}
        if report.exists():
            with open(report, errors="replace") as fh:
                for line in fh:
                    p = line.rstrip("\n").split("\t")
                    if len(p) >= 6 and p[3] == "D":
                        # kraken2 report: %, reads_total, reads_direct, rank, taxid, name
                        domain_reads[p[5].strip()] = int(p[1])
        for lvl in ("S", "G", "P"):
            p = kraken_dir / run / "bracken" / f"{run}_{lvl}.bracken"
            if not p.exists():
                continue
            with open(p, errors="replace") as fh:
                fh.readline()
                for line in fh:
                    f = line.rstrip("\n").split("\t")
                    if len(f) < 6:
                        continue
                    name, new_est = f[0], int(float(f[5]))
                    levels[lvl].setdefault(name, {})[run] = new_est
        # D: domain totals from the kraken2 report (top-level D rows)
        for name, reads in domain_reads.items():
            levels["D"].setdefault(name, {})[run] = reads
    return levels


def prevalence_and_host(levels, runs):
    """Apply .0.2 (prevalence >= 20%) and .0.2-H (remove host clades)."""
    host = {"S": {"Homo sapiens"}, "G": {"Homo"}, "P": {"Chordata"},
            "D": set()}
    out = {}
    for lvl, table in levels.items():
        n = len(runs)
        base, prev, hostv = {}, {}, {}
        for name, per in table.items():
            if name in host.get(lvl, set()):
                continue
            hits = sum(1 for r in runs if per.get(r, 0) > 0)
            base[name] = per
            if hits / n >= 0.2:
                prev[name] = per
                if lvl == "S" and name != "Homo sapiens":
                    hostv[name] = per
        out[lvl] = {"base": base, "prev": prev, "host": hostv}
    return out


def write_bracken(out_dir, runs, levels):
    for lvl in ("S", "G", "P", "D"):
        names = sorted(levels[lvl]["base"])
        with open(out_dir / f"bracken.{lvl}.txt", "w") as fh:
            fh.write("\t".join(["Taxonomy"] + runs) + "\n")
            for nm in names:
                fh.write("\t".join([nm] + [str(levels[lvl]["base"][nm].get(r, 0))
                                           for r in runs]) + "\n")
        names = sorted(levels[lvl]["prev"])
        with open(out_dir / f"bracken.{lvl}.0.2", "w") as fh:
            fh.write("\t".join(["Taxonomy"] + runs) + "\n")
            for nm in names:
                fh.write("\t".join([nm] + [str(levels[lvl]["prev"][nm].get(r, 0))
                                           for r in runs]) + "\n")
        names = sorted(levels[lvl]["host"])
        with open(out_dir / f"bracken.{lvl}.0.2-H", "w") as fh:
            fh.write("\t".join(["Taxonomy"] + runs) + "\n")
            for nm in names:
                fh.write("\t".join([nm] + [str(levels[lvl]["host"][nm].get(r, 0))
                                           for r in runs]) + "\n")


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--expected-manifest", required=True)
    args = ap.parse_args()

    workdir = Path(args.workdir).resolve()
    man = json.load(open(workdir / "manifests" / "download_manifest_all25.json"))
    all_runs = sorted(man["selected_runs"])
    done = json.load(open(workdir / "manifests" / "analysis_result.json"))
    # The result file reflects the LAST batch (multi-batch runs overwrite it).
    # Full-set completion is proven by: (a) the last batch completed with no
    # failures, and (b) every run of the full set has verified per-sample
    # artefacts (checked below). The 25-run sample set governs deliverables.
    if not done.get("complete") or done.get("failed"):
        raise SystemExit("last analysis batch is not COMPLETE; "
                         "refusing to build deliverables")
    runs = all_runs
    out = workdir / "Reference_result"
    for sub in ("humann3", "kraken2", "metaphlan4"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    log = workdir / "logs" / "reference_build.jsonl"

    def jlog(**rec):
        with open(log, "a") as fh:
            fh.write(json.dumps({"ts": now(), **rec}, ensure_ascii=False) + "\n")
        print(json.dumps(rec, ensure_ascii=False), flush=True)

    # --- gate: per-sample artefacts exist for all runs ---
    missing = []
    for run in runs:
        for p in (workdir / "result" / "humann3" / run / f"{run}_pathabundance_relab.tsv",
                  workdir / "result" / "metaphlan4" / run / f"{run}_profile.txt",
                  workdir / "result" / "kraken2" / run / "bracken" / f"{run}_S.bracken"):
            if not p.exists() or p.stat().st_size == 0:
                missing.append(str(p))
    if missing:
        raise SystemExit("missing per-sample artefacts: %s" % missing[:5])
    jlog(step="gate", status="ok", runs=len(runs))

    # --- humann3: ko tables ---
    ko_samples, ko_rows = regroup_to_ko(workdir, runs, log)
    ko_unstrat, ko_strat = split_stratified(ko_rows, ko_samples)
    h3 = out / "humann3"
    write_matrix(h3 / "ko.tsv", sorted(ko_rows), ko_samples, ko_rows)
    write_matrix(h3 / "ko_unstratified.tsv", sorted(ko_unstrat), ko_samples, ko_unstrat)
    write_matrix(h3 / "ko_stratified.tsv", sorted(ko_strat), ko_samples, ko_strat)
    jlog(step="ko", rows=len(ko_rows), unstrat=len(ko_unstrat), strat=len(ko_strat))

    # --- humann3: pathway tables (copy merged + splits already on disk) ---
    merged_h3 = workdir / "result" / "humann3" / "merged"
    for name in ("pathabundance.tsv", "pathabundance_relab.tsv"):
        src = merged_h3 / name
        if src.exists():
            (h3 / name).write_bytes(src.read_bytes())
    # full per-sample relab tables carry UNMAPPED/UNINTEGRATED + stratified rows;
    # the merged table (13b) is unstratified-only
    full = join_per_sample(workdir, runs, "pathabundance_relab")
    pw_samples = runs
    pw_full = {rid: {s: full[rid].get(s, 0.0) for s in pw_samples}
               for rid in full}
    pw_un = {rid: per for rid, per in pw_full.items() if "|" not in rid}
    pw_st = {rid: per for rid, per in pw_full.items() if "|" in rid}
    write_matrix(h3 / "pathabundance_relab.tsv",
                 sorted(pw_full), pw_samples, pw_full)
    write_matrix(h3 / "pathabundance_relab_unstratified.tsv",
                 sorted(pw_un), pw_samples, pw_un)
    write_matrix(h3 / "pathabundance_relab_stratified.tsv",
                 sorted(pw_st), pw_samples, pw_st)
    jlog(step="pathabundance", rows=len(pw_full),
         unstrat=len(pw_un), strat=len(pw_st))

    # --- KEGG aggregates from ko_unstratified ---
    npw, nl1, nl2 = build_kegg_tables(ko_unstrat, ko_samples, h3)
    jlog(step="kegg", pathways=npw, l1=nl1, l2=nl2)

    # --- kraken2/bracken ---
    levels = bracken_levels(workdir, runs, workdir / "result" / "kraken2")
    filtered = prevalence_and_host(levels, runs)
    write_bracken(out / "kraken2", runs, filtered)
    jlog(step="bracken", s=len(filtered["S"]["base"]), g=len(filtered["G"]["base"]),
         p=len(filtered["P"]["base"]), d=len(filtered["D"]["base"]))

    # --- metaphlan4 ---
    m4 = out / "metaphlan4"
    src_tax = workdir / "result" / "metaphlan4" / "merged" / "taxonomy.tsv"
    if src_tax.exists():
        (m4 / "taxonomy.tsv").write_bytes(src_tax.read_bytes())
    src_sp = workdir / "result" / "metaphlan4" / "merged" / "taxonomy_species.tsv"
    if src_sp.exists():
        (m4 / "taxonomy_species.tsv").write_bytes(src_sp.read_bytes())

    # --- manifest ---
    files = sorted(p for p in out.rglob("*") if p.is_file())
    manifest = {
        "dataset": workdir.name,
        "generated_at": now(),
        "runs": runs,
        "code_hashes": {"build_reference_outputs.py": sha256_of(Path(__file__))},
        "kegg_release_note": "row names follow current db/kegg release",
        "files": [{"path": str(p.relative_to(out)), "sha256": sha256_of(p),
                   "bytes": p.stat().st_size} for p in files],
    }
    (workdir / "manifests" / "reference_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    jlog(step="reference_build", status="COMPLETE", files=len(files),
         manifest=str(workdir / "manifests" / "reference_manifest.json"))
    print("REFERENCE BUILD COMPLETE:", len(files), "files in", out)


if __name__ == "__main__":
    sys.exit(main())
