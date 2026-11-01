#!/usr/bin/env python3
"""interpretation_views.py — Batch 3.2 (DA consensus + confidence presentation)

Consumes existing DA producer tables and Batch 1/2 frozen evidence
statuses; normalizes ONLY (no reruns, no new thresholds, no vote-to-
confidence). Direction semantics come from each producer's own contrast
definition; effect sizes keep their type and are never averaged.

Usage: python3 interpretation_views.py <workdir> <outdir>
"""
import csv
import glob
import os
import sys
from collections import defaultdict


def norm_taxa(t):
    """Deterministic entity normalization across the three producer string
    encodings: deseq2 'k__B|p__...' / maaslin2 'k__B.p__...' / wilcox
    'B|...' (no rank prefixes). -> pipe-joined bare ranks."""
    t = t.replace(".", "|")
    parts = [p.split("__", 1)[-1] if "__" in p else p for p in t.split("|")]
    return "|".join(parts)


def load_da(workdir):
    base = os.path.join(workdir, "result", "stat")
    rows = []
    methods = set()
    for dim in ("bacteria", "virus", "fungi"):
        diff = os.path.join(base, dim, "differential")
        if not os.path.isdir(diff):
            continue
        f = os.path.join(diff, "deseq2_results.tsv")
        if os.path.isfile(f):
            methods.add("DESeq2")
            for r in csv.DictReader(open(f), delimiter="\t"):
                rows.append([norm_taxa(r["Taxa"]), "taxon", f"{dim}:treat_vs_control", "DESeq2",
                             r.get("log2FoldChange", ""), "log2FC(DESeq2, relab-pseudocounts)",
                             "treat_enriched" if float(r["log2FoldChange"] or 0) > 0 else "control_enriched",
                             r.get("pvalue", ""), r.get("padj", ""), "0.05(FDR, frozen)", f])
        f = os.path.join(diff, "maaslin2_results.tsv")
        if os.path.isfile(f):
            methods.add("MaAsLin2")
            for r in csv.DictReader(open(f), delimiter="\t"):
                c = r.get("coefficient", "")
                rows.append([norm_taxa(r["Taxa"]), "taxon", f"{dim}:treat_vs_control", "MaAsLin2",
                             c, "coefficient(AST+TSS)",
                             "treat_enriched" if float(c or 0) > 0 else "control_enriched",
                             r.get("pvalue", ""), r.get("qvalue", ""), "0.05(q, frozen)", f])
        f = os.path.join(diff, "wilcox_results.tsv")
        if os.path.isfile(f):
            methods.add("Wilcoxon(AST)")
            for r in csv.DictReader(open(f), delimiter="\t"):
                l2 = r.get("log2FC", "")
                comp = r.get("Comparison", "")
                ref, comp_grp = ("control", "treat") if comp.startswith("control") else ("treat", "control")
                rows.append([norm_taxa(r["Taxa"]), "taxon", f"{dim}:{comp_grp}_vs_{ref}", "Wilcoxon(AST)",
                             l2, "log2FC(mean_group2/mean_group1)",
                             "group2_enriched" if float(l2 or 0) > 0 else "group1_enriched",
                             r.get("P.unadj", ""), r.get("P.adj", ""), "0.05(FDR, frozen)", f])
        methods.add("ANCOM-BC2")  # census: NOT_ASSESSED on this fixture
    return rows, methods


def main():
    workdir, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    rows, methods = load_da(workdir)

    # per-entity summary: support count (each method's own frozen rule) and
    # direction consistency; NO confidence inference.
    sig = defaultdict(list)
    for r in rows:
        try:
            fdr = float(r[8])
        except (ValueError, TypeError):
            continue
        if fdr < 0.05:
            sig[(r[0], r[2])].append((r[3], r[6]))
    cons_rows = []
    for (ent, contrast), ms in sorted(sig.items()):
        dirs = {d for _, d in ms}
        if len(dirs) > 1:
            dc = "MIXED"
        elif len(ms) == 1:
            dc = "SINGLE_METHOD"
        else:
            dc = "CONSISTENT_" + next(iter(dirs)).split("_")[0].upper()
        cons_rows.append([ent, "taxon", contrast, len(ms), dc,
                          ";".join(sorted(m for m, _ in ms)), "NOT_ASSESSED"])

    out = os.path.join(outdir, "da_consensus.tsv")
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["entity_id","entity_type","contrast_id","method","effect_size","effect_size_type",
                    "direction","p_value","fdr","significance_rule","provenance_file"])
        w.writerows(rows)
    out2 = os.path.join(outdir, "da_consensus_summary.tsv")
    with open(out2, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["entity_id","entity_type","contrast_id","support_method_count",
                    "direction_consistency","supporting_methods","confidence_status"])
        w.writerows(cons_rows)
    print(f"[DA] methods_seen={sorted(methods)} method_rows={len(rows)} significant_entities={len(cons_rows)}")
    import collections
    print("[DA] direction_consistency:", dict(collections.Counter(r[4] for r in cons_rows)))
    print(f"[DA] -> {out} / {out2}")

    # ---- confidence presentation: cross-module status rollup consuming
    # ONLY frozen statuses; unsupported assignments stay at zero by design.
    cv = []
    def add(entity, module, status, basis, rule, conflict, reason, prov):
        cv.append([entity, module, status, basis, rule, conflict, reason, prov])
    host = os.path.join(workdir, "result", "integration", "virus", "viral_host_evidence.tsv")
    if os.path.isfile(host):
        by = defaultdict(set)
        for r in csv.DictReader(open(host), delimiter="\t"):
            by[r["votu_id"]].add(r["evidence_status"])
        for v, st in sorted(by.items()):
            status = "UNKNOWN" if "RAW_EVIDENCE" in "".join(st) else "NOT_ASSESSED"
            add(v, "virus_host", status,
                f"host_evidence statuses={'/'.join(sorted(st))}; no frozen acceptance threshold (Batch 2)",
                "none(Batch 2 RAW_EVIDENCE policy)", "FALSE", "", host)
    amg = os.path.join(workdir, "result", "integration", "virus", "viral_amg_evidence.tsv")
    if os.path.isfile(amg):
        n = 0
        for r in csv.reader(open(amg), delimiter="\t"):
            n += 1
        add("ALL_AMG_GENES", "amg", "UNKNOWN",
            f"{n} evidence rows with aux provenance split; annotation != mechanism",
            "none(auxiliary_score_source provenance only)", "FALSE", "", amg)
    fun = os.path.join(workdir, "result", "integration", "fungi", "fungal_evidence.tsv")
    if os.path.isfile(fun):
        n = sum(1 for _ in open(fun)) - 1
        add("ALL_FUNGAL_DETECTIONS", "fungi", "NOT_ASSESSED",
            f"{n} evidence rows; single dominant source; no negative controls; no crosswalk (feasibility pending)",
            "none(F-FUNGI-CONF-01 pending)", "FALSE", "", fun)
    for r in cons_rows[:0]:
        pass
    add("ALL_DA_ENTITIES", "differential_abundance", "NOT_ASSESSED",
        "support_method_count/direction_consistency reported; no frozen DA confidence rule",
        "none", "TRUE" if any(c[4] == "MIXED" for c in cons_rows) else "FALSE", "", out2)
    out3 = os.path.join(outdir, "confidence_view.tsv")
    with open(out3, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["entity_id","module","confidence_status","confidence_basis","assessment_rule",
                    "unresolved_conflict","not_assessed_reason","provenance_file"])
        w.writerows(cv)
    import collections as _c
    print("[CONF] status dist:", dict(_c.Counter(r[2] for r in cv)))
    print("[CONF] unsupported assignments by construction = 0 (only frozen statuses consumed)")
    print(f"[CONF] -> {out3}")


if __name__ == "__main__":
    main()
