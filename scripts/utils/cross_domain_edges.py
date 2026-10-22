#!/usr/bin/env python3
"""cross_domain_edges.py — I-EDGE-01 (Batch 3.1)

Normalizes existing cross-domain edge producers into the Edge Contract:
edge_type (scientific claim) is separate from evidence_type (why we believe
it). Consumes frozen evidence; never re-derives host ratings, thresholds or
universes. Historical tables are untouched - this writes a new sidecar.

Producers consumed:
  98g network_edges.tsv  (correlation | host_prediction)
  Batch 2 viral_host_evidence.tsv (linked via evidence_pointer, not copied)

Usage: python3 cross_domain_edges.py <workdir> <outdir>
"""
import csv
import os
import sys
from collections import Counter


def main():
    workdir, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    src = os.path.join(workdir, "result", "cross_domain", "correlation", "network_edges.tsv")
    host_ev = os.path.join(workdir, "result", "integration", "virus", "viral_host_evidence.tsv")

    # evidence pointer index: votu -> sidecar rows (for linkage, not copying)
    host_evidence_by_votu = {}
    if os.path.isfile(host_ev):
        with open(host_ev) as fh:
            for r in csv.DictReader(fh, delimiter="\t"):
                host_evidence_by_votu.setdefault(r["votu_id"], []).append(r)

    out_rows = []
    census = Counter()
    with open(src) as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            s, t = r["source"], r["target"]
            if r["type"] == "correlation":
                # Spearman on TSS+CLR abundances (98g producer semantics)
                edge_type, ev_type = "ECOLOGICAL_ASSOCIATION", "ABUNDANCE_CORRELATION"
                method, score_type = "spearman(TSS+CLR)", "spearman_rho"
                score, p, fdr = r.get("weight", ""), r.get("pvalue", ""), r.get("fdr", "")
                direction = "positive" if score not in ("", "NA") and float(score) >= 0 else "negative"
                unit = "clr_value"
                interp = "ACCEPTED_INTERPRETATION"
            elif r["type"] == "host_prediction":
                # iPHoP genome-level m90 edges from 98g; never rated by the
                # Batch 2 hierarchy -> RAW_EVIDENCE_ONLY, threshold NOT_APPLICABLE
                edge_type, ev_type = "HOST_MODEL_PREDICTION", "IPHOP_GENOME_M90_MODEL"
                method, score_type = "iPHoP(genome m90)", "NOT_APPLICABLE"
                score, p, fdr = "NOT_APPLICABLE", "NOT_APPLICABLE", "NOT_APPLICABLE"
                direction, unit = "NOT_APPLICABLE", "NOT_APPLICABLE"
                interp = "RAW_EVIDENCE_ONLY"
            else:
                census["unknown_producer_type"] += 1
                continue
            sd, _, sid = s.partition(":")
            td, _, tid = t.partition(":")
            census[f"edge:{edge_type}"] += 1
            census[f"pair:{sd}-{td}"] += 1
            out_rows.append([
                s, sd, sid, t, td, tid, edge_type, ev_type,
                "98g_cross_domain_correlation", method, score, score_type,
                p, fdr, direction, "relative_abundance_transformed" if unit == "clr_value" else unit,
                unit, interp, "PRODUCER_EDGE", src, "98g"])

    # linkage rows: point virus nodes at frozen Batch 2 host evidence
    # (single source of truth: pointer only, no evidence copied, no recount)
    n_link = 0
    for votu, evs in host_evidence_by_votu.items():
        for ev in evs:
            if not votu:
                continue
            n_link += 1
            out_rows.append([
                votu, "virus", votu, ev["raw_target_id"], "host_target", ev["raw_target_id"],
                "VOTU_SUPPORTED_BY_HOST_EVIDENCE", ev["evidence_type"],
                "viral_host_evidence.tsv", ev["evidence_source"], ev["raw_score"],
                "RAW_SCORE(tool-specific;不可跨类比较)", "NOT_APPLICABLE", "NOT_APPLICABLE",
                "NOT_APPLICABLE", "NOT_APPLICABLE", "NOT_APPLICABLE",
                "RAW_EVIDENCE_ONLY" if ev["evidence_status"] == "RAW_EVIDENCE" else "ACCEPTED_INTERPRETATION",
                "EVIDENCE_POINTER", host_ev, "batch2_host_evidence"])

    out = os.path.join(outdir, "cross_domain_edges.tsv")
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["source_entity_id","source_entity_type","source_id","target_entity_id","target_entity_type",
                    "target_id","edge_type","evidence_type","evidence_source","method","score","score_type",
                    "p_value","fdr","direction","quantity_type","unit","interpretation_status",
                    "record_role","provenance_file","provenance_step"])
        w.writerows(out_rows)
    for k, v in sorted(census.items()):
        print(f"  {k}: {v}")
    print(f"  evidence_pointer_rows(host sidecar linkage, non-counting): {n_link}")
    print(f"  -> {out} total={len(out_rows)}")


if __name__ == "__main__":
    main()
