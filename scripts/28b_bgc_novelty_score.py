#!/usr/bin/env python3
"""28b_bac_bgc_novelty.sh 的配套脚本：解析 antiSMASH region .gbk，DIAMOND 比对 MIBiG，聚合 novelty_score。"""
import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

from Bio import SeqIO


def extract_region_proteins(gbk_path):
    """从单个 region .gbk 提取所有 CDS 的 (protein_id, translation) 列表。"""
    proteins = []
    for record in SeqIO.parse(str(gbk_path), "genbank"):
        for feature in record.features:
            if feature.type != "CDS":
                continue
            translation = feature.qualifiers.get("translation", [None])[0]
            if not translation:
                continue
            locus_tag = feature.qualifiers.get("locus_tag", [None])[0]
            protein_id = locus_tag or f"{gbk_path.stem}_{feature.location.start}_{feature.location.end}"
            proteins.append((protein_id, translation))
    return proteins


def region_product(gbk_path):
    for record in SeqIO.parse(str(gbk_path), "genbank"):
        for feature in record.features:
            if feature.type == "region":
                products = feature.qualifiers.get("product", [])
                if products:
                    return ";".join(products)
    return "NA"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", required=True)
    ap.add_argument("--antismash-dir", required=True, help="该样本 antiSMASH 输出目录（含 *.region*.gbk）")
    ap.add_argument("--mibig-dmnd", required=True)
    ap.add_argument("--mibig-data-json", required=True)
    ap.add_argument("--diamond-bin", required=True)
    ap.add_argument("--tmp-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--threads", type=int, default=4)
    args = ap.parse_args()

    antismash_dir = Path(args.antismash_dir)
    tmp_dir = Path(args.tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    region_gbks = sorted(antismash_dir.glob("*.region*.gbk"))

    header = ["sample", "contig_id", "region_id", "product", "n_cds",
              "best_mibig_cluster", "best_mibig_organism", "best_mibig_product",
              "best_mibig_hit_fraction", "novelty_score"]

    with open(args.mibig_data_json) as fh:
        mibig_data = json.load(fh)

    def mibig_meta(cluster_id):
        entry = mibig_data.get(cluster_id)
        if not entry or not entry.get("regions"):
            return "NA", "NA"
        region = entry["regions"][0]
        return region.get("organism", "NA"), ";".join(region.get("products", []) or ["NA"])

    if not region_gbks:
        with open(out_path, "w", newline="") as fh:
            writer = csv.writer(fh, delimiter="\t")
            writer.writerow(header)
        print(f"[28b_bgc_novelty] 样本 {args.sample} 无 BGC region，写空结果")
        return

    query_fasta = tmp_dir / f"{args.sample}_query_proteins.faa"
    region_cds_count = {}
    with open(query_fasta, "w") as qf:
        for gbk in region_gbks:
            region_id = gbk.stem
            proteins = extract_region_proteins(gbk)
            region_cds_count[region_id] = len(proteins)
            for protein_id, seq in proteins:
                qf.write(f">{region_id}###{protein_id}\n{seq}\n")

    rows = []
    if query_fasta.stat().st_size == 0:
        for gbk in region_gbks:
            region_id = gbk.stem
            contig_id = region_id.split(".region")[0]
            rows.append([args.sample, contig_id, region_id, region_product(gbk), 0,
                         "NA", "NA", "NA", 0.0, 1.0])
    else:
        diamond_out = tmp_dir / f"{args.sample}_diamond.tsv"
        subprocess.run(
            [
                args.diamond_bin, "blastp",
                "--query", str(query_fasta),
                "--db", args.mibig_dmnd,
                "--out", str(diamond_out),
                "--outfmt", "6", "qseqid", "sseqid", "pident", "qcovhsp", "scovhsp",
                "--sensitive",
                "-e", "1e-5",
                "--query-cover", "50",
                "--subject-cover", "50",
                "--threads", str(args.threads),
                "--max-target-seqs", "5",
                "--quiet",
            ],
            check=True,
        )

        region_cluster_hits = {}
        with open(diamond_out) as fh:
            for line in fh:
                qseqid, sseqid, *_ = line.rstrip("\n").split("\t")
                region_id, protein_id = qseqid.split("###", 1)
                # MIBiG proteins.fasta 的 header 格式为 "{cluster_id}|{index}"，
                # cluster_id 即 BGC0000001 等编号，无需借助 data.json 二次映射
                cluster_id = sseqid.split("|", 1)[0]
                region_cluster_hits.setdefault(region_id, {}).setdefault(cluster_id, set()).add(protein_id)

        for gbk in region_gbks:
            region_id = gbk.stem
            contig_id = region_id.split(".region")[0]
            n_cds = region_cds_count.get(region_id, 0)
            product = region_product(gbk)
            cluster_hits = region_cluster_hits.get(region_id, {})
            if not cluster_hits or n_cds == 0:
                rows.append([args.sample, contig_id, region_id, product, n_cds,
                             "NA", "NA", "NA", 0.0, 1.0])
                continue
            best_cluster, best_hit_ids = max(cluster_hits.items(), key=lambda kv: len(kv[1]))
            best_fraction = len(best_hit_ids) / n_cds
            novelty = 1.0 - best_fraction
            best_organism, best_product = mibig_meta(best_cluster)
            rows.append([args.sample, contig_id, region_id, product, n_cds,
                         best_cluster, best_organism, best_product,
                         round(best_fraction, 4), round(novelty, 4)])

    with open(out_path, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(header)
        writer.writerows(rows)

    n_novel = sum(1 for r in rows if r[-1] >= 0.9)
    print(f"[28b_bgc_novelty] 样本 {args.sample} | region数: {len(rows)} | novelty>=0.9: {n_novel}")


if __name__ == "__main__":
    main()
