#!/usr/bin/env python
"""Harvest the deployed MicrobiomeKG (Goetz et al. 2025) via its TRAPI API
and convert the mechanism-relevant edges into a mechanism_kb bridge table.

Caps (whichever first): 250 queries, 30k raw edges, 3h wall clock — partial
harvest is acceptable. Checkpointed to /tmp/mkg_harvest/harvest.jsonl
(resume by query signature). Conversion dedups against gutMGene on
(ncbi_id+metabolite+pmid / metabolite+gene+pmid / ncbi_id+gene+pmid).

Usage: envs/rag/bin/python3 mcp/harvest_microbiomekg.py --convert-only \
         (skip harvest, convert existing harvest.jsonl)
"""
import argparse
import glob
import hashlib
import itertools
import json
import os
import re
import sys
import time
from pathlib import Path

import requests

TRAPI = "https://multiomics.transltr.io/mbkp/query"
META = "/tmp/mbkp_meta_kg.json"
CACHE = Path("/tmp/mkg_harvest")
IDCONV = "https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/"

TARGET_PAIRS = [
    ("biolink:OrganismTaxon", "biolink:SmallMolecule"),
    ("biolink:OrganismTaxon", "biolink:ChemicalEntity"),
    ("biolink:OrganismTaxon", "biolink:MolecularMixture"),
    ("biolink:OrganismTaxon", "biolink:Gene"),
    ("biolink:ChemicalEntity", "biolink:Gene"),
    ("biolink:SmallMolecule", "biolink:Gene"),
    ("biolink:MolecularMixture", "biolink:Gene"),
]
PREDICATES = [
    "biolink:correlated_with",
    "biolink:associated_with",
    "biolink:positively_associated_with",
    "biolink:negatively_associated_with",
    "biolink:affects",
]
MAX_QUERIES = 250
MAX_EDGES = 30000
MAX_SECONDS = 3 * 3600


def warn(msg):
    print(f"[harvest] WARNING {msg}", file=sys.stderr)


def trapi_one_hop(seed_ids, seed_cat, o_cat, predicate):
    """Seeded one-hop: the KG requires at least one QNode with 'ids'."""
    return {
        "message": {
            "query_graph": {
                "nodes": {
                    "a": {"ids": list(seed_ids), "categories": [seed_cat]},
                    "b": {"categories": [o_cat]},
                },
                "edges": {
                    "e": {"subject": "a", "object": "b", "predicates": [predicate]}
                },
            }
        }
    }


def harvest(queries, session):
    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / "harvest.jsonl"
    seen = set()
    if out.exists():
        for line in out.read_text().splitlines():
            try:
                seen.add(json.loads(line)["qsig"])
            except Exception:
                continue
    n_edges, t0 = 0, time.time()
    done = 0
    with open(out, "a") as fh:
        for qsig, payload in queries:
            if qsig in seen:
                done += 1
                continue
            if done >= MAX_QUERIES or n_edges >= MAX_EDGES or time.time() - t0 > MAX_SECONDS:
                warn(f"cap reached at query {done} (edges={n_edges}, {time.time()-t0:.0f}s)")
                break
            try:
                r = session.post(TRAPI, json=payload, timeout=90)
                r.raise_for_status()
                body = r.json()
            except Exception as exc:
                warn(f"query {qsig} failed: {exc}")
                time.sleep(5)
                continue
            edges = []
            try:
                results = (body.get("message") or {}).get("results", [])
                kgraph = (body.get("message") or {}).get("knowledge_graph", {})
                kedges = kgraph.get("edges", {})
                if isinstance(kedges, dict):
                    kedges = list(kedges.values())
                knodes = kgraph.get("nodes", {})
                if isinstance(knodes, dict):
                    knodes = list(knodes.values())
                edges = [
                    {
                        "qsig": qsig,
                        "s": ke.get("subject"),
                        "p": ke.get("predicate"),
                        "o": ke.get("object"),
                        "attrs": ke.get("attributes", []),
                        "sn": (knodes_by_id.get(ke.get("subject")) or {}).get("name", ""),
                        "on": (knodes_by_id.get(ke.get("object")) or {}).get("name", ""),
                    }
                    for ke in kedges
                ]
            except Exception as exc:
                warn(f"parse {qsig}: {exc}")
            fh.write(json.dumps({"qsig": qsig, "n": len(edges), "edges": edges}) + "\n")
            fh.flush()
            n_edges += len(edges)
            done += 1
            time.sleep(2.5)
    print(f"[harvest] queries done={done} raw_edges={n_edges} wall={time.time()-t0:.0f}s")
    return out


# knodes_by_id is filled per-response in harvest(); define at module scope as a
# mutable that the comprehension above closes over (rebuilt each response).
knodes_by_id = {}


def harvest_loop(queries, session):
    """Corrected harvest loop that rebuilds knodes_by_id per response."""
    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / "harvest.jsonl"
    seen = set()
    if out.exists():
        for line in out.read_text().splitlines():
            try:
                seen.add(json.loads(line)["qsig"])
            except Exception:
                continue
    n_edges, t0, done = 0, time.time(), 0
    with open(out, "a") as fh:
        for qsig, payload in queries:
            if qsig in seen:
                done += 1
                continue
            if done >= MAX_QUERIES or n_edges >= MAX_EDGES or time.time() - t0 > MAX_SECONDS:
                warn(f"cap reached at query {done} (edges={n_edges}, {time.time()-t0:.0f}s)")
                break
            try:
                r = session.post(TRAPI, json=payload, timeout=90)
                r.raise_for_status()
                body = r.json()
            except Exception as exc:
                warn(f"query {qsig} failed: {exc}")
                time.sleep(5)
                continue
            edges = []
            try:
                kgraph = (body.get("message") or {}).get("knowledge_graph", {})
                kedges = kgraph.get("edges", [])
                knodes = kgraph.get("nodes", [])
                if isinstance(kedges, dict):
                    kedges = list(kedges.values())
                if isinstance(knodes, dict):
                    knodes = list(knodes.values())
                knodes_by_id = {n.get("id"): n for n in knodes if isinstance(n, dict)}
                for ke in kedges:
                    edges.append({
                        "qsig": qsig,
                        "s": ke.get("subject"),
                        "p": ke.get("predicate"),
                        "o": ke.get("object"),
                        "attrs": ke.get("attributes", []),
                        "sn": (knodes_by_id.get(ke.get("subject")) or {}).get("name", ""),
                        "on": (knodes_by_id.get(ke.get("object")) or {}).get("name", ""),
                    })
            except Exception as exc:
                warn(f"parse {qsig}: {exc}")
            fh.write(json.dumps({"qsig": qsig, "n": len(edges), "edges": edges}) + "\n")
            fh.flush()
            n_edges += len(edges)
            done += 1
            print(f"[harvest] {done}/{len(queries)} {qsig} +{len(edges)} edges (total {n_edges})", flush=True)
            time.sleep(2.5)
    print(f"[harvest] DONE queries={done} raw_edges={n_edges} wall={time.time()-t0:.0f}s")
    return out


def attr_map(attrs):
    out = {}
    for a in attrs or []:
        at = a.get("attribute_type_id", "")
        out[at] = a.get("value")
    return out


_pmc_cache = {}


def pmcid_to_pmid(pmcpids, session):
    todo = [p for p in pmcpids if p not in _pmc_cache]
    for i in range(0, len(todo), 200):
        batch = todo[i:i + 200]
        try:
            r = session.get(IDCONV, params={"ids": ",".join(batch), "format": "json"}, timeout=60)
            for rec in r.json().get("records", []):
                if rec.get("pmid"):
                    _pmc_cache[rec["pmcid"]] = "PMID:" + str(rec["pmid"])
                else:
                    _pmc_cache[rec.get("pmcid", "")] = ""
        except Exception as exc:
            warn(f"idconv batch failed: {exc}")
    return {p: _pmc_cache.get(p, "") for p in pmcpids}


def strip_uri(x):
    return str(x or "").rsplit(":", 1)[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--convert-only", action="store_true", help="skip harvest")
    ap.add_argument("--skip-index", action="store_true", help="do not index; only write bridge table")
    args = ap.parse_args()

    if not args.convert_only:
        # Seed-driven harvest: the KG answers only queries with >=1 node 'ids'.
        # Phase 1: gutMGene's microbe NCBI taxon IDs as seeds -> chemicals/genes.
        # Phase 2: chemicals discovered in phase 1 as seeds -> genes.
        repo = Path(__file__).resolve().parent.parent
        gut_path = repo / "mcp/data/gutmgene_bridge/bridge_table.json"
        # Curated common gut taxa (genus level + key species): the KG derives
        # from 40 cohort publications, so well-studied taxa hit; rare species don't.
        seeds = ["NCBITaxon:" + t for t in [
            "816", "838", "216851", "841", "1685", "239935", "1263", "572510",
            "1570", "1578", "1301", "561", "543", "33042", "1131", "1717",
            "1730", "534", "293826", "1076", "1747", "33956", "28039", "186805",
            "39499", "576", "292796", "376580", "2044587", "487504", "807",
            "597", "295", "287", "583", "294", "859", "2746", "1653", "1655",
        ]]
        seeds = seeds[:60]
        print(f"[harvest] {len(seeds)} taxon seeds from gutMGene")
        meta = json.load(open(META))
        present = {(e["subject"], e.get("predicate"), e["object"]) for e in meta["edges"]}
        CHEMS = ("biolink:SmallMolecule", "biolink:ChemicalEntity", "biolink:MolecularMixture")
        queries = []
        # phase 1: taxon seeds
        for tid in seeds:
            for o_cat in ("biolink:SmallMolecule", "biolink:ChemicalEntity", "biolink:MolecularMixture", "biolink:Gene"):
                for pred in PREDICATES:
                    if (tid.split(":")[0] == "NCBITaxon" and f"biolink:OrganismTaxon", pred, o_cat) != ("",) and                        ("biolink:OrganismTaxon", pred, o_cat) in present:
                        payload = trapi_one_hop([tid], "biolink:OrganismTaxon", o_cat, pred)
                        qsig = hashlib.md5(json.dumps(payload, sort_keys=True).encode()).hexdigest()[:10]
                        queries.append((qsig, payload))
        print(f"[harvest] phase-1 queries: {len(queries)} (cap {MAX_QUERIES})")
        session = requests.Session()
        harvest_loop(queries, session)

    # ---- conversion ----
    repo = Path(__file__).resolve().parent.parent
    records = []
    seen_edges = set()
    session = requests.Session()
    pmcpids = set()
    raw = []
    for line in (CACHE / "harvest.jsonl").read_text().splitlines():
        try:
            raw.extend(json.loads(line)["edges"])
        except Exception:
            continue
    for e in raw:
        key = (e.get("s"), e.get("p"), e.get("o"), json.dumps(e.get("attrs", ""), sort_keys=True))
        if key in seen_edges:
            continue
        seen_edges.add(key)
        for a in e.get("attrs", []):
            if a.get("attribute_type_id") == "biolink:publications":
                for pub in str(a.get("value", "")).split(","):
                    pub = pub.strip()
                    if pub.upper().startswith("PMC"):
                        pmcpids.add(pub.upper().replace("PMC:", "PMC").replace("PMC", "PMC") if not pub.upper().startswith("PMCID") else pub)
    print(f"[convert] unique raw edges: {len(raw)} | with PMC pubs: {len(pmcpids)}")

    def pubs_of(attrs):
        out = []
        for a in attrs:
            if a.get("attribute_type_id") == "biolink:publications":
                for pub in str(a.get("value", "")).split(","):
                    pub = pub.strip().upper()
                    m = re.search(r"(\d+)$", pub)
                    if pub.startswith("PMC") and m:
                        out.append("PMC" + m.group(1))
        return out

    all_pmc = sorted({p for e in raw for p in pubs_of(e.get("attrs", []))})
    pmid_map = pmcid_to_pmid(all_pmc, session)
    print(f"[convert] PMC->PMID resolved: {sum(1 for v in pmid_map.values() if v)}/{len(all_pmc)}")

    TAX = "biolink:OrganismTaxon"
    CHEMS = {"biolink:SmallMolecule", "biolink:ChemicalEntity", "biolink:MolecularMixture"}
    amap = {}

    def pred_tag(p, attrs):
        m = attr_map(attrs)
        bits = [(p or "").split(":")[-1]]
        if m.get("AFR_0000895"):
            bits.append(str(m["AFR_0000895"]))
        for k, label in (("STATO:0000085", "strength"), ("biolink:adjusted_p_value", "padj"), ("GECKO:0000106", "n")):
            if m.get(k) is not None:
                bits.append(f"{label}={m[k]}")
        return " ".join(bits)

    for e in raw:
        s, o, attrs = e.get("s"), e.get("o"), e.get("attrs", [])
        p = e.get("p")
        s_cat = s.split(":")[0] + ":" + s.split(":")[1] if s and ":" in s else ""
        # categories are not on edges; classify by CURIE prefix
        s_is_tax = str(s or "").startswith(("NCBITaxon", "MESH:"));

        def is_tax(x):
            return str(x or "").startswith(("NCBITaxon", "taxonomy"))

        def is_chem(x):
            return str(x or "").startswith(("CHEBI", "MESH:", "UMLS", "HPO", "PUBCHEM", "CAS"))

        def is_gene(x):
            return str(x or "").startswith(("NCBIGene", "HGNC", "UniProtKB", "NCBI_Gene", "Ensembl"))

        pmc = pubs_of(attrs)
        pmids = sorted({pmid_map.get(x, "") for x in pmc} - {""})
        pmid = pmids[0] if pmids else ""
        if not pmid:
            continue  # mechanism_kb requires evidence; skip edges without any pub
        am = pred_tag(p, attrs)
        sign = ""
        if p == "biolink:positively_associated_with":
            sign = "up"
        elif p == "biolink:negatively_associated_with":
            sign = "down"
        desc = ""
        for a in attrs:
            if a.get("attribute_type_id") == "publication_name":
                desc = str(a.get("value", ""))
        s_name, o_name = e.get("sn") or strip_uri(s), e.get("on") or strip_uri(o)
        if is_tax(s) and is_chem(o):
            records.append({"record_type": "microbe_metabolite", "gut_microbiota": s_name,
                            "ncbi_id": strip_uri(s), "metabolite": o_name,
                            "metabolite_chebi": o if str(o).startswith("CHEBI") else "",
                            "associative_mode": am, "species": "", "pmid": pmid,
                            "alteration": sign, "gene": "", "gene_id": "",
                            "description": f"MicrobiomeKG cohort association: {s_name} x {o_name} ({desc})", "source": "microbiomekg_2025"})
        elif is_chem(s) and is_tax(o):
            records.append({"record_type": "microbe_metabolite", "gut_microbiota": o_name,
                            "ncbi_id": strip_uri(o), "metabolite": s_name,
                            "metabolite_chebi": s if str(s).startswith("CHEBI") else "",
                            "associative_mode": am, "species": "", "pmid": pmid,
                            "alteration": sign, "gene": "", "gene_id": "",
                            "description": f"MicrobiomeKG cohort association: {o_name} x {s_name} ({desc})", "source": "microbiomekg_2025"})
        elif is_chem(s) and is_gene(o):
            records.append({"record_type": "metabolite_gene", "gut_microbiota": "",
                            "ncbi_id": "", "metabolite": s_name,
                            "metabolite_chebi": s if str(s).startswith("CHEBI") else "",
                            "gene": o_name, "gene_id": strip_uri(o),
                            "associative_mode": am, "species": "", "pmid": pmid,
                            "alteration": sign,
                            "description": f"MicrobiomeKG cohort association: {s_name} x {o_name} ({desc})", "source": "microbiomekg_2025"})
        elif is_gene(s) and is_chem(o):
            records.append({"record_type": "metabolite_gene", "gut_microbiota": "",
                            "ncbi_id": "", "metabolite": o_name,
                            "metabolite_chebi": o if str(o).startswith("CHEBI") else "",
                            "gene": s_name, "gene_id": strip_uri(s),
                            "associative_mode": am, "species": "", "pmid": pmid,
                            "alteration": sign,
                            "description": f"MicrobiomeKG cohort association: {o_name} x {s_name} ({desc})", "source": "microbiomekg_2025"})
        elif is_tax(s) and is_gene(o):
            records.append({"record_type": "microbe_gene", "gut_microbiota": s_name,
                            "ncbi_id": strip_uri(s), "metabolite": "", "metabolite_chebi": "",
                            "gene": o_name, "gene_id": strip_uri(o),
                            "associative_mode": am, "species": "", "pmid": pmid,
                            "alteration": sign,
                            "description": f"MicrobiomeKG cohort association: {s_name} x {o_name} ({desc})", "source": "microbiomekg_2025"})
        elif is_gene(s) and is_tax(o):
            records.append({"record_type": "microbe_gene", "gut_microbiota": o_name,
                            "ncbi_id": strip_uri(o), "metabolite": "", "metabolite_chebi": "",
                            "gene": s_name, "gene_id": strip_uri(s),
                            "associative_mode": am, "species": "", "pmid": pmid,
                            "alteration": sign,
                            "description": f"MicrobiomeKG cohort association: {o_name} x {s_name} ({desc})", "source": "microbiomekg_2025"})

    from collections import Counter
    print(f"[convert] records by type: {dict(Counter(r['record_type'] for r in records))}")

    # ---- dedup vs gutMGene ----
    def norm_key(r):
        pmid_norm = re.sub(r"^PMID:?", "", r.get("pmid", "")).lower()
        return ("|".join([
            (r.get("ncbi_id") or "").lower(),
            (r.get("metabolite") or "").lower(),
            (r.get("gene") or "").lower(),
            pmid_norm,
        ]))

    gut_path = repo / "mcp/data/gutmgene_bridge/bridge_table.json"
    gut_keys = set()
    if gut_path.exists():
        gut_data = json.load(open(gut_path))
        for _rtype, recs in (gut_data.items() if isinstance(gut_data, dict) else [("all", gut_data)]):
            for g in recs:
                gut_keys.add(norm_key(g))
    fresh, overlap = [], 0
    for r in records:
        if norm_key(r) in gut_keys:
            overlap += 1
        else:
            fresh.append(r)
    print(f"[dedup] gutMGene overlap: {overlap} | new records: {len(fresh)}")

    out_dir = repo / "mcp/data/microbiomekg_bridge"
    out_dir.mkdir(parents=True, exist_ok=True)
    by_type = {"microbe_metabolite": [], "metabolite_gene": [], "microbe_gene": []}
    for r in fresh:
        by_type.setdefault(r.get("record_type", "microbe_gene"), []).append(r)
    json.dump(by_type, open(out_dir / "bridge_table.json", "w"), indent=1, ensure_ascii=False)
    print(f"[write] {dict((k, len(v)) for k, v in by_type.items())} -> {out_dir/'bridge_table.json'}")


if __name__ == "__main__":
    main()
