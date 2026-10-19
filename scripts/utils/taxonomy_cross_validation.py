#!/usr/bin/env python3
"""taxonomy_cross_validation.py — E-TAX-01 (Phase 2 Batch 2)

Read-only taxonomy cross-validation with explicit Comparison Contracts.
No winner selection; detection agreement and quantitative agreement are
separate layers; unmapped/ambiguous taxa never enter correlations.

Usage: python3 taxonomy_cross_validation.py <workdir> <outdir>
"""
import csv
import glob
import os
import sys
from collections import defaultdict


def load_mpa_species(workdir):
    """MetaPhlAn4 bacteria profiles -> {(sample, species_name): relab_0_100}."""
    out = {}
    for prof in sorted(glob.glob(os.path.join(workdir, "result", "metaphlan4", "*", "*_profile.txt"))):
        sample = os.path.basename(os.path.dirname(prof))
        for line in open(prof):
            if line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or parts[0].count("|") != 6:
                continue  # species rows only (clade|taxid|relab|addl)
            name = parts[0].split("|")[-1][3:]
            try:
                v = float(parts[2])
            except ValueError:
                continue
            if v > 0:
                out[(sample, name)] = v
    return out


def load_bracken_species(workdir):
    """Bracken S-level -> {(sample, name): fraction_0_1} + taxid map."""
    out, taxids = {}, {}
    for tab in sorted(glob.glob(os.path.join(workdir, "result", "fungi", "kraken2", "*", "bracken", "*_S.bracken"))):
        sample = os.path.basename(os.path.dirname(os.path.dirname(tab)))
        with open(tab) as fh:
            for r in csv.DictReader(fh, delimiter="\t"):
                if r.get("taxonomy_lvl") != "S":
                    continue
                try:
                    frac = float(r.get("fraction_total_reads", 0) or 0)
                except ValueError:
                    continue
                if frac > 0:
                    out[(sample, r["name"])] = frac
                    taxids[r["name"]] = r.get("taxonomy_id", "")
    return out, taxids


def load_mag_gtdb(workdir):
    """98d MAG table -> {genome: gtdb_species_name} (R214)."""
    out = {}
    t = os.path.join(workdir, "result", "integration", "bacteria", "mag_integration_table.tsv")
    if not os.path.isfile(t):
        return out
    rows = list(csv.reader(open(t), delimiter="\t"))
    h = rows[0]
    gi, si = h.index("MAG_id"), h.index("GTDB_classification")
    for r in rows[1:]:
        lineage = r[si]
        sp = lineage.split(";")[-1].strip()
        out[r[gi]] = sp if sp.startswith("s__") else ""
    return out


def main():
    workdir, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    mpa = load_mpa_species(workdir)
    brk, taxids = load_bracken_species(workdir)
    rows = []

    # ---- C1: MetaPhlAn4 vs Bracken (species, NCBI-style read-level) ------
    # Contract: TierA | all samples | species | mpa_vOct22-NCBI-style vs
    # PlusPF-NCBI(bracken) | relab | 0-100 vs 0-1 -> mpa/100 (conversion on
    # the fly; source tables untouched) | mapping: exact same string, same
    # rank, both NCBI-context => MAPPED (deterministic string equality, NOT
    # first-match; different underlying DBs so not EXACT) | missing semantics:
    # absent row = not detected (both producers report only detections).
    # deterministic name normalization within NCBI-context: mpa writes
    # underscores, bracken spaces (documented mapping method, not first-match)
    norm = lambda n: n.replace("_", " ")
    mpa_n = {(smp, norm(n)): v for (smp, n), v in mpa.items()}
    brk_n = {(smp, norm(n)): v for (smp, n), v in brk.items()}
    keys = sorted(set(mpa_n) | set(brk_n))
    mapped_pairs = 0
    for (sample, name) in keys:
        a = mpa_n.get((sample, name))
        b = brk_n.get((sample, name))
        det_a = a is not None
        det_b = b is not None
        if det_a and det_b:
            agree = "SHARED"
            mapped_pairs += 1
        elif det_a:
            agree = "SOURCE_A_ONLY"
        else:
            agree = "SOURCE_B_ONLY"
        rows.append(["TierA", sample, "species", "metaphlan4_vOct22", "71_kraken2_PlusPF(full-profile)",
                     name, name, "NCBI-style", "NCBI(PlusPF)", "-", "-",
                     "MAPPED(name-normalized underscores)", "TRUE" if det_a else "FALSE", "TRUE" if det_b else "FALSE",
                     agree, "relative_abundance",
                     f"{a/100:.6f}" if a is not None else "",
                     f"{b:.6f}" if b is not None else "",
                     "fraction_0_1", "TRUE(mpa/100)" if a is not None else "TRUE",
                     "bracken:" + taxids.get(name, "") if name in taxids else "mpa_profile"])
    # detection Jaccard over comparable universe (same-name pairs only)
    names_a = {norm(n) for (_, n) in mpa}
    names_b = {norm(n) for (_, n) in brk}
    comparable = names_a & names_b
    j = len(comparable) / len(names_a | names_b) if (names_a | names_b) else 0.0

    # quantitative agreement (only SHARED, same quantity, scale-converted)
    xs, ys = [], []
    for r in rows:
        if r[14] == "SHARED":
            xs.append(float(r[16]))
            ys.append(float(r[17]))
    corr = ""
    if len(xs) > 2:
        import statistics
        mx, my = statistics.mean(xs), statistics.mean(ys)
        num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        den = (sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)) ** 0.5
        corr = f"{num/den:.4f}" if den else ""

    # ---- C2: GTDB-R214 MAG vs MetaPhlAn reads (cross-system, no crosswalk)
    mags = load_mag_gtdb(workdir)
    c2_mapped = 0
    c2_unmapped = 0
    mpa_names = {n for (_, n) in mpa}
    for genome, sp in mags.items():
        bare = sp[3:] if sp else ""
        if bare and bare in mpa_names:
            c2_mapped += 1
            status = "NAME_MATCH_ACROSS_SYSTEMS(UNTRUSTED)"
        else:
            c2_unmapped += 1
            status = "UNMAPPED_NO_CROSSWALK"
        rows.append(["TierA/P01", "MAG-level", "species", "gtdbtk_R214(MAG)", "metaphlan4_vOct22(read)",
                     sp, bare if bare in mpa_names else "", "GTDB", "NCBI-style", "R214", "-",
                     status, "TRUE" if bare else "FALSE", "TRUE" if bare in mpa_names else "FALSE",
                     "DESCRIPTIVE_ONLY", "none", "", "", "", "",
                     "98d_mag_integration"])

    out = os.path.join(outdir, "taxonomy_cross_validation.tsv")
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["project","sample_id","rank","source_A","source_B","source_A_taxon","source_B_taxon",
                    "taxonomy_system_A","taxonomy_system_B","taxonomy_release_A","taxonomy_release_B",
                    "mapping_status","detection_A","detection_B","detection_agreement","quantity_type",
                    "value_A","value_B","common_unit","scale_conversion","provenance"])
        w.writerows(rows)
    print(f"[C1 mpa-vs-bracken] taxa A={len(names_a)} B={len(names_b)} comparable(name-equal)={len(comparable)} "
          f"shared_rows={mapped_pairs} detection_jaccard={j:.3f} (universe=union of detected names)")
    print(f"[C1 quantitative] n_paired={len(xs)} pearson={corr or 'NA(n<=2)'} scale=mpa/100 vs fraction0-1")
    print(f"[C2 MAG-vs-read] MAGs={len(mags)} name-matched(UNTRUSTED)={c2_mapped} UNMAPPED_NO_CROSSWALK={c2_unmapped} "
          f"| cross-system join NOT performed (descriptive only)")
    print(f"[out] {out} rows={len(rows)}")


if __name__ == "__main__":
    main()
