#!/usr/bin/env python3
"""Phase-1 final: build mining/sources_summary.json from per-source reports + DB.

Includes deferred-download size estimation (few HEADs on ftp.ebi.ac.uk).
"""
import glob
import gzip
import json
import os
import sqlite3
import time
import urllib.request

MROOT = "~/Course/CSCCD-MetagenomeFlow/mining"
REG = f"{MROOT}/seed_registry.sqlite"
OUT = f"{MROOT}/sources_summary.json"
UA = {"User-Agent": "CSCCD-MetagenomeFlow/phase1-index"}


def head_bytes(url):
    try:
        req = urllib.request.Request(url, headers=UA, method="HEAD")
        with urllib.request.urlopen(req, timeout=60) as r:
            cl = r.headers.get("Content-Length")
            return int(cl) if cl else None
    except Exception:
        return None


def load(path):
    try:
        return json.load(open(path))
    except Exception:
        return None


def main():
    con = sqlite3.connect(f"file:{REG}?mode=ro", uri=True)
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    # --- MGnify DB facts ---
    n_studies = con.execute("SELECT COUNT(*) FROM mgnify_studies").fetchone()[0]
    n_analyses = con.execute("SELECT COUNT(*) FROM mgnify_analyses").fetchone()[0]
    exp_split = dict(con.execute(
        "SELECT experiment_type, COUNT(*) FROM mgnify_analyses GROUP BY experiment_type"))
    pipe_shot = dict(con.execute(
        "SELECT pipeline_version, COUNT(*) FROM mgnify_analyses WHERE experiment_type='Metagenomic' GROUP BY pipeline_version"))
    shot_total = con.execute(
        "SELECT COUNT(*) FROM mgnify_analyses WHERE experiment_type='Metagenomic'").fetchone()[0]
    shot_hit = con.execute(
        "SELECT COUNT(*) FROM mgnify_analyses WHERE experiment_type='Metagenomic' AND in_seed_registry=1").fetchone()[0]
    join = load("/tmp/sources_work/mgnify_join.json") or {}
    probes = load("/tmp/sources_work/annotation_probes.json") or []

    # --- size estimation from probe payloads ---
    groups_seen, sizes = {}, {}
    for p in probes:
        if not p.get("template_ok"):
            continue
        payload = json.loads(next(con.execute(  # verbatim payload from probes table
            "SELECT annotations_json FROM mgnify_annotation_probes WHERE mgya=?",
            (p["mgya"],)))[0]) if not p.get("error") else {}
        for d in (payload.get("downloads") or []):
            g = d.get("download_group")
            if g and g not in groups_seen and d.get("file_type") in ("tsv", "json"):
                groups_seen[g] = d.get("url")
    for g, url in list(groups_seen.items())[:12]:
        sizes[g] = head_bytes(url)
        time.sleep(0.6)
    per_analysis_v6 = sum(v for v in sizes.values() if v) or 0

    # --- AGP / iMSMS reports ---
    agp = load("/tmp/sources_work/agp_join.json") or {}
    imsms = load("/tmp/sources_work/imsms_report.json") or {}

    n_agp = con.execute("SELECT COUNT(*) FROM agp_samples").fetchone()[0]
    agp_gz = os.path.getsize(f"{MROOT}/sources/raw/agp/sample_info.tsv.gz") if os.path.exists(
        f"{MROOT}/sources/raw/agp/sample_info.tsv.gz") else None
    n_imsms = con.execute("SELECT COUNT(*) FROM imsms_samples").fetchone()[0]
    imsms_meta = os.path.getsize(f"{MROOT}/sources/raw/imsms/hmp2_metadata.csv")
    per_sample_imsms = 19539 + 1284792  # HEAD-verified

    reg_keys = con.execute(
        "SELECT (SELECT COUNT(*) FROM seed_runs)+(SELECT COUNT(*) FROM incremental_candidates)").fetchone()[0]

    def gb(n):
        return round(n / 1e9, 2)

    summary = {
        "generated_at": now,
        "policy": "index now, download later (URLs + join keys only; 1-2 verification files per source)",
        "registry": {"seed_runs": 63803, "incremental_candidates": 2804, "total_keys": reg_keys},
        "sources": {
            "mgnify": {
                "api": "https://www.ebi.ac.uk/metagenomics/api/v2",
                "biome_lineage": "root:Host-associated:Human:Digestive system:Large intestine:Fecal",
                "studies_indexed": n_studies,
                "analyses_indexed": n_analyses,
                "experiment_type_split": exp_split,
                "pipeline_split_shotgun": pipe_shot,
                "shotgun_analyses": shot_total,
                "shotgun_analyses_in_registry": shot_hit,
                "registry_keys_with_mgnify_analysis": join.get("registry_keys_matched", {}),
                "registry_coverage_rate": join.get("registry_coverage_rate"),
                "raw_pages": "mining/sources/raw/mgnify/pages/*.jsonl (per-study, resume-safe)",
                "annotations": "annotations_json NULL by policy; deterministic FTP template verified on probes (mgnify_annotation_probes table)",
            },
            "agp": {
                "origin": "qiita public_download sample_information study_id=10317",
                "samples_indexed": n_agp,
                "phenotype_columns": agp.get("n_cols"),
                "n_nonnull_phenotypes_avg": 852.9,
                "gz_size_bytes": agp_gz,
                "accession_columns_found": agp.get("accession_like_column_hits") or "none",
                "joinable_to_registry": agp.get("join_direct_sample_name_to_registry", 0),
                "quirk": "no ENA/BioSample accession columns in qiita sample_info; join requires ENA alias bridge (AGP studies PRJEB11419/ERP012803 sample aliases == qiita sample_name), deferred",
                "registry_heuristic_presence": {"seed_runs_matching_american_gut": 549},
            },
            "imsms": {
                "origin": "ibdmdb.org products_MGX_2017-08-12 (HMP2 iMSMS)",
                "samples_indexed": n_imsms,
                "with_tax_and_func_urls": imsms.get("n_with_both"),
                "metadata_rows": imsms.get("metadata_rows"),
                "metadata_row_found": imsms.get("metadata_row_found"),
                "head_probes_bytes": imsms.get("head_probes_bytes"),
                "joinable_to_registry": imsms.get("join_direct_to_registry", 0),
                "quirk": "hmp2_metadata.csv (490 cols) has no ENA accessions; CSM-style External IDs need ERS alias mapping via ENA (ERP005534/PRJEB24483), deferred",
                "registry_heuristic_presence": {"seed_runs_matching_ibd_hmp2": 1949},
            },
        },
        "overlap_matrix_vs_registry": {
            "registry_total_keys": reg_keys,
            "mgnify_shotgun_analyses_matching": shot_hit,
            "mgnify_registry_keys_covered": join.get("registry_keys_matched", {}).get("any"),
            "mgnify_coverage_fraction": join.get("registry_coverage_rate"),
            "agp_keys_covered": 0,
            "imsms_keys_covered": 0,
            "note": "AGP/iMSMS carry no ENA accessions at source; alias bridges identified for phase 2",
        },
        "verification_downloads": {
            "imsms_tax_tsv_bytes": 19539,
            "imsms_func_tarbz2_bytes": 1284792,
            "mgnify_annotation_probes": len(probes),
            "mgnify_probe_download_groups_head_bytes": sizes,
        },
        "deferred_download_estimate": {
            "method": "HEAD-verified per-file sizes x counts",
            "imsms_all_samples": gb(n_imsms * per_sample_imsms),
            "mgnify_shotgun_all_v6_like": gb(shot_total * per_analysis_v6) if per_analysis_v6 else None,
            "mgnify_shotgun_in_registry_only": gb(shot_hit * per_analysis_v6) if per_analysis_v6 else None,
            "agp": 0,
        },
        "timestamps": {
            "mgnify_indexed_at": join.get("mgnify", {}).get("indexed_at"),
            "agp_indexed_at": agp.get("indexed_at"),
            "imsms_indexed_at": imsms.get("indexed_at"),
            "summary_generated_at": now,
        },
    }
    with open(OUT, "w") as f:
        json.dump(summary, f, indent=2)
    print(json.dumps(summary, indent=2)[:3000])


if __name__ == "__main__":
    main()
