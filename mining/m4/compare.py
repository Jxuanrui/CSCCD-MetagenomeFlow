#!/usr/bin/env python3
"""M4 MVP comparison engine: disease signatures from precomputed profiles + BugSigDB agreement.

Per selected cohort (cohorts.json, profiles from mining/m4/profiles/):
  1. parse profiles (iMSMS MetaPhlAn3 tsv / MGnify legacy OTU-SSU biom->tsv),
     harmonize taxa to canonical binomial / genus names,
  2. case vs healthy per-taxon Mann-Whitney U on log1p(relative %) + median sign,
     BH-FDR q<0.05 -> our signature,
  3. deterministic BugSigDB condition match (token-set subset, diff<=2) on gut
     signatures, sign-consistency / Jaccard / pure-python hypergeometric p,
  4. write results/<disease>/{signature.tsv,bugsigdb_agreement.json},
     results/summary.json and print a 10-line human summary.

Usage: compare.py [--fdr 0.05] [--prevalence 0.2]
"""
import argparse
import collections
import gzip
import json
import math
import os
import re
import statistics
import time

from scipy.stats import false_discovery_control, mannwhitneyu

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
M4 = os.path.join(ROOT, "mining", "m4")
PROFILE_DIR = f"{M4}/profiles"
RESULTS = f"{M4}/results"
BSDB = f"{ROOT}/mcp/data/bugsigdb_bridge/bridge_table.json"

# ------------------------------------------------------------ taxonomy ----

STRAIN_MARKERS = {"str", "str.", "subsp", "subsp.", "bv", "bv.", "serovar", "serotype",
                  "type", "tp", "isolate", "clone", "cf.", "sp", "sp.", "genomovar", "genomospec"}


def canon(name):
    """Canonical taxon string: lowercase alpha tokens, ranks/strains stripped.

    Returns '' for unnameable taxa ('g__', 's__bacterium', single-token species).
    """
    s = str(name).strip().strip("\"'").split("|")[-1]
    if s[:3] in ("s__", "g__", "f__"):
        s = s[3:]
    s = s.replace("_", " ")
    toks = [t for t in re.split(r"[^A-Za-z0-9-]+", s.lower()) if t and t != "-"]
    if toks and toks[0] in ("candidatus", "candidat"):
        toks = toks[1:]
    for i, t in enumerate(toks):
        if t in STRAIN_MARKERS:
            toks = toks[:i]
            break
    while len(toks) >= 3 and re.fullmatch(r"\d+([-/][a-z0-9]+)*", toks[-1]):
        toks = toks[:-1]
    if len(toks) >= 2 and toks[1] == "sp":
        toks = toks[:1]
    if not toks or toks[0] in ("bacterium", "bacteria", "archaeon", "uncultured"):
        return ""
    return " ".join(toks)


def taxon_from_lineage(lineage):
    """';'-joined Greengenes/SILVA lineage -> (genus_canon, species_canon)."""
    parts = [p for p in str(lineage).split(";")]
    genus = species = ""
    for p in parts:
        if p.startswith("g__") and len(p) > 3:
            genus = canon(p)
        if p.startswith("s__") and len(p) > 3:
            sp = canon(p)
            if sp and genus and sp.split()[0] == genus:
                species = sp
            elif sp and len(sp.split()) >= 2:
                species = sp
            elif sp and genus:          # bare epithet (V3 style)
                species = f"{genus} {sp}"
    return genus, species


# ------------------------------------------------------------ profiles ----

def load_profile(source, key):
    """-> (genus abundances, species abundances) in percent, canonical names."""
    path = f"{PROFILE_DIR}/{source}/{key}.tsv.gz"
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    gen, spe = collections.Counter(), collections.Counter()
    total = 0.0
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if source == "imsms":
                if len(parts) < 3 or "|" not in parts[0]:
                    continue
                try:
                    rel = float(parts[2])
                except ValueError:
                    continue
                clade = parts[0]
                if "|t__" in clade or "|s__" not in clade:
                    if clade.count("|") >= 5 and re.search(r"\|g__[^|]+$", clade):
                        g = canon(clade.rsplit("|", 1)[-1])
                        if g:
                            gen[g] += rel
                    continue
                sp = canon(clade.rsplit("|", 1)[-1])
                if sp and len(sp.split()) >= 2:
                    spe[sp] += rel          # genus rows exist separately in MetaPhlAn output
            else:
                if len(parts) < 2:
                    continue
                try:
                    cnt = float(parts[-1])
                except ValueError:
                    continue
                total += cnt
                g, s = taxon_from_lineage(parts[0])
                if g:
                    gen[g] += cnt
                if s:
                    spe[s] += cnt
    if source != "imsms" and total > 0:
        for d in (gen, spe):
            for k in d:
                d[k] = 100.0 * d[k] / total
    return gen, spe


# ------------------------------------------------------------- bugsigdb ----

STOP = {"the", "of", "and", "in", "with", "disease", "disorder", "a", "an"}
NUMERAL = {"2": "ii", "1": "i", "3": "iii"}
GUT_KEYWORDS = ("feces", "stool", "gut", "colon", "rectum", "intestin", "colorect",
                "caecum", "cecum", "ileum", "digestive", "faeca")


def toks(name):
    t = [NUMERAL.get(w, w) for w in re.split(r"[^a-z0-9]+", str(name).lower()) if w]
    return {w for w in t if w not in STOP}


def cond_match(a, b):
    A, B = toks(a), toks(b)
    if not A or not B:
        return False
    return A == B or (A < B and len(B - A) <= 2) or (B < A and len(A - B) <= 2)


CONTROL_WORDS = {"control", "controls", "healthy", "nonibd", "normal", "non"}


def load_bugsigdb():
    with open(BSDB) as f:
        return json.load(f)["signature"]


def match_signatures(sigs, term):
    matched, site_dropped = [], 0
    for s in sigs:
        if not cond_match(term, s.get("condition") or ""):
            continue
        site = str(s.get("body_site") or "").lower()
        if not any(k in site for k in GUT_KEYWORDS):
            site_dropped += 1
            continue
        g1 = toks(s.get("group1_name") or "")
        d = s.get("direction")
        if d not in ("increased", "decreased"):
            continue
        if g1 & CONTROL_WORDS:                       # direction is vs group1
            d = "decreased" if d == "increased" else "increased"
        taxa = set()
        for lin in s.get("taxon_lineage") or []:
            g, sp = taxon_from_lineage(lin.replace("|", ";"))
            if sp:
                taxa.add(sp)
            elif g:
                taxa.add(g)
        if taxa:
            matched.append({"bsdb_id": s.get("bsdb_id"), "pmid": s.get("pmid"),
                            "condition": s.get("condition"), "direction": d, "taxa": taxa})
    return matched, site_dropped


def consensus_direction(matched):
    votes = collections.defaultdict(collections.Counter)
    for s in matched:
        for t in s["taxa"]:
            votes[t][s["direction"]] += 1
    cons = {}
    for t, c in votes.items():
        inc, dec = c["increased"], c["decreased"]
        cons[t] = "increased" if inc > dec else "decreased" if dec > inc else "mixed"
    return cons


def hyperg_sf(k, N, K, n):
    """P(X >= k) for X ~ Hypergeometric(N population, K successes, n draws). Pure python."""
    lo, hi = max(k, 0), min(n, K)
    if lo > hi:
        return 0.0
    denom = math.comb(N, n)
    return sum(math.comb(K, x) * math.comb(N - K, n - x) for x in range(lo, hi + 1)) / denom


# ----------------------------------------------------------------- stats ----

def compare_disease(name, cohort, samples, sigs, args):
    """samples: {role: {'genus': {key: {taxon: rel}}, 'species': ...}}"""
    out = {"cohort": name, "source": cohort["source"], "display": cohort["display"]}
    tables = {}
    for rank in ("species", "genus"):
        case_keys = [k for k in cohort["cases"] if k in samples[rank]]
        ctrl_keys = [k for k in cohort["controls"] if k in samples[rank]]
        tab = samples[rank]
        taxa = {t for k in case_keys + ctrl_keys for t in tab.get(k, {})}
        prev_c = {t: sum(1 for k in case_keys if tab[k].get(t, 0) > 0) / max(len(case_keys), 1) for t in taxa}
        prev_h = {t: sum(1 for k in ctrl_keys if tab[k].get(t, 0) > 0) / max(len(ctrl_keys), 1) for t in taxa}
        tested = sorted(t for t in taxa if max(prev_c[t], prev_h[t]) >= args.prevalence)
        rows = []
        for t in tested:
            x = [math.log1p(tab[k].get(t, 0)) for k in case_keys]
            y = [math.log1p(tab[k].get(t, 0)) for k in ctrl_keys]
            u, p = mannwhitneyu(x, y, alternative="two-sided")
            u = float(u)
            med_c = statistics.median(tab[k].get(t, 0) for k in case_keys)
            med_h = statistics.median(tab[k].get(t, 0) for k in ctrl_keys)
            direction = "increased" if (med_c, statistics.fmean(x)) > (med_h, statistics.fmean(y)) else "decreased"
            rbc = 2 * u / (len(x) * len(y)) - 1  # rank-biserial (case>control)
            rows.append({"taxon": t, "rank": rank, "p": p, "direction": direction,
                         "median_case": med_c, "median_control": med_h,
                         "prevalence_case": prev_c[t], "prevalence_control": prev_h[t],
                         "mean_log1p_case": statistics.fmean(x), "mean_log1p_control": statistics.fmean(y),
                         "rank_biserial": rbc})
        if rows:
            qs = false_discovery_control([r["p"] for r in rows], method="bh")
            for r, q in zip(rows, qs):
                r["q"] = float(q)
        tables[rank] = {"n_case": len(case_keys), "n_control": len(ctrl_keys),
                        "n_tested": len(tested), "rows": rows}
        out[f"n_case_{rank}"] = len(case_keys)
        out[f"n_control_{rank}"] = len(ctrl_keys)
        out[f"n_tested_{rank}"] = len(tested)

    sig_rows = [r for rank in ("species", "genus") for r in tables[rank]["rows"] if r["q"] < args.fdr]
    sig_rows.sort(key=lambda r: r["q"])
    out["n_sig"] = len(sig_rows)

    # BugSigDB agreement
    matched, site_dropped = match_signatures(sigs, cohort["bugsigdb_match_term"])
    cons = consensus_direction(matched)
    our_taxa = {r["taxon"] for r in sig_rows}
    overlap = our_taxa & set(cons)
    consistent = {t for t in overlap if cons[t] == next(r["direction"] for r in sig_rows if r["taxon"] == t)}
    discordant = overlap - consistent
    novel = our_taxa - set(cons)
    universe = {r["taxon"] for rank in ("species", "genus") for r in tables[rank]["rows"]}
    K = len(universe & set(cons))
    n_overlap = len(overlap)
    p_enrich = hyperg_sf(n_overlap, len(universe), K, len(our_taxa)) if our_taxa and universe else None
    jaccard = len(overlap) / len(our_taxa | set(cons)) if (our_taxa | set(cons)) else 0.0
    verdict = ("replicates known"
               if matched and len(consistent) >= 3 and n_overlap >= 5 and p_enrich is not None and p_enrich < 0.05
               else "novel candidates")

    for r in sig_rows:
        r["in_bugsigdb"] = r["taxon"] in cons
        r["bugsigdb_direction"] = cons.get(r["taxon"], "")

    agreement = {
        "disease_term": cohort["bugsigdb_match_term"],
        "matched_conditions": sorted({m["condition"] for m in matched}),
        "n_matched_signatures": len(matched),
        "n_signatures_dropped_non_gut_site": site_dropped,
        "bugsigdb_taxa_union": len(cons),
        "our_sig_taxa": len(our_taxa),
        "overlap": n_overlap,
        "sign_consistent": len(consistent),
        "sign_discordant": len(discordant),
        "novel_taxa": len(novel),
        "jaccard": round(jaccard, 4),
        "p_hypergeometric_overlap": (round(p_enrich, 6) if p_enrich is not None else None),
        "enrichment_universe": {"tested_taxa": len(universe), "tested_in_bugsigdb": K},
        "taxa_match_rate": round(K / len(universe), 4) if universe else None,
        "sig_taxa_match_rate": round(n_overlap / len(our_taxa), 4) if our_taxa else None,
        "verdict": verdict,
        "verdict_rule": "replicates known iff matched signatures exist AND sign_consistent>=3 "
                        "AND overlap>=5 AND hypergeometric p<0.05; else novel candidates",
        "top_novel_taxa": [r["taxon"] for r in sig_rows if r["taxon"] in novel][:10],
        "example_pmids": sorted({str(m["pmid"]) for m in matched})[:8],
    }
    return tables, sig_rows, agreement, out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fdr", type=float, default=0.05)
    ap.add_argument("--prevalence", type=float, default=0.2)
    args = ap.parse_args()

    with open(f"{M4}/cohorts.json") as f:
        cohorts = json.load(f)["cohorts"]
    sigs = load_bugsigdb()
    os.makedirs(RESULTS, exist_ok=True)

    loaded = {}          # (source,key) -> parsed
    for cname, c in cohorts.items():
        for key in set(c["cases"]) | set(c["controls"]):
            if (c["source"], key) not in loaded:
                loaded[(c["source"], key)] = load_profile(c["source"], key)

    summary = {"generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "fdr_cutoff": args.fdr, "prevalence_cutoff": args.prevalence, "diseases": {}}
    for cname, c in cohorts.items():
        samples = {"species": {}, "genus": {}}
        for (src, key), prof in loaded.items():
            if src != c["source"] or prof is None:
                continue
            gen, spe = prof
            samples["genus"][key] = gen
            samples["species"][key] = spe
        tables, sig_rows, agreement, out = compare_disease(cname, c, samples, sigs, args)
        ddir = f"{RESULTS}/{cname}"
        os.makedirs(ddir, exist_ok=True)
        cols = ["taxon", "rank", "direction", "p", "q", "median_case", "median_control",
                "mean_log1p_case", "mean_log1p_control", "prevalence_case", "prevalence_control",
                "rank_biserial", "in_bugsigdb", "bugsigdb_direction"]
        with open(f"{ddir}/signature.tsv", "w") as f:
            f.write("\t".join(cols) + "\n")
            for r in sig_rows:
                f.write("\t".join(str(round(r[k], 6) if isinstance(r[k], float) else r[k]) for k in cols) + "\n")
        with open(f"{ddir}/bugsigdb_agreement.json", "w") as f:
            json.dump(agreement, f, indent=1)
        out.update({"n_sig": len(sig_rows), "agreement": agreement,
                    "top_novel": agreement["top_novel_taxa"][:5],
                    "top_sig": [{"taxon": r["taxon"], "dir": r["direction"], "q": round(r["q"], 6)} for r in sig_rows[:5]]})
        summary["diseases"][cname] = out
        print(f"[compare] {cname}: sig={len(sig_rows)} overlap={agreement['overlap']} "
              f"consistent={agreement['sign_consistent']} verdict={agreement['verdict']}")

    dl = {}
    if os.path.exists(f"{M4}/download_report.json"):
        with open(f"{M4}/download_report.json") as f:
            dl = json.load(f)
    required = {(c["source"], k) for c in cohorts.values()
                for k in set(c["cases"]) | set(c["controls"])}
    present = sum(1 for s, k in required
                  if os.path.exists(f"{PROFILE_DIR}/{s}/{k}.tsv.gz")
                  and os.path.getsize(f"{PROFILE_DIR}/{s}/{k}.tsv.gz") > 0)
    missing = [f"{s}:{k}" for s, k in sorted(required)
               if not os.path.exists(f"{PROFILE_DIR}/{s}/{k}.tsv.gz")
               or os.path.getsize(f"{PROFILE_DIR}/{s}/{k}.tsv.gz") == 0]
    summary["download"] = {"profiles_required": len(required), "profiles_cached": present,
                           "missing": missing, "last_pass": {k: dl[k] for k in ("ok", "skip", "fail") if k in dl}}
    summary["caveats"] = [
        "MGnify arm: cross-study cases vs controls (LiJ_2017/Guillen vs MehtaRS_2018) and cross-pipeline "
        "(V3 Greengenes vs V4.1/V5 SILVA) genus-level rRNA-OTU profiles; batch effects expected.",
        "Legacy MGnify profiles are SSU/OTU tables, not WGS mOTUs; species rank only where tables resolve it.",
        "iMSMS arm: single study, MetaPhlAn3 species level; one earliest sample per participant.",
        "BugSigDB matching is name-based (token-subset, diff<=2); MONDO/EFO crosswalks not used.",
        "Cohorts below the >=10/10 same-study feasibility bar were run as a demonstration per task instructions.",
    ]
    with open(f"{RESULTS}/summary.json", "w") as f:
        json.dump(summary, f, indent=1)

    print("\n===== M4 MVP SUMMARY (10 lines) =====")
    for i, line in enumerate([
        f"1. Cohort scan: 0/14 registry diseases met >=10 case AND >=10 healthy profile-ready bar; demonstration cohorts used.",
        f"2. Profiles cached: {present}/{len(required)} required sample profiles on disk"
        + (f"; missing (server 404): {', '.join(missing[:3])}" if missing else "") + ".",
    ]):
        print(line)
    for j, (cname, d) in enumerate(summary["diseases"].items(), start=3):
        a = d["agreement"]
        print(f"{j}. {d['display']}: {d.get('n_case_species', d.get('n_case_genus'))} cases vs "
              f"{d.get('n_control_species', d.get('n_control_genus'))} controls; "
              f"{d['n_sig']} sig taxa (q<{args.fdr}); BugSigDB {a['n_matched_signatures']} signatures "
              f"-> overlap {a['overlap']}, consistent {a['sign_consistent']}, "
              f"p={a['p_hypergeometric_overlap']}, verdict: {a['verdict']}.")
    print(f"{len(summary['diseases']) + 3}. Top novel candidates: " +
          "; ".join(f"{k}: {', '.join(v['top_novel'][:3]) or '-'}" for k, v in summary["diseases"].items()))


if __name__ == "__main__":
    main()
