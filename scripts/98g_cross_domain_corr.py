#!/usr/bin/env python3
"""Build a cross-domain abundance correlation network.

The script reads bacteria, virus and optional fungi abundance inputs, applies
TSS followed by CLR normalization, calculates cross-domain Spearman
correlations in source-feature blocks, and writes Cytoscape-compatible tables.
"""

import argparse
import glob
import os
import tempfile
from pathlib import Path

import networkx as nx
import numpy as np
import pandas as pd
from scipy import stats


DOMAIN_PAIRS = (("bacteria", "virus"), ("bacteria", "fungi"), ("virus", "fungi"))


def log(message):
    print(f"[cross_domain_corr] {message}")


def read_table(path):
    """Read a tabular abundance matrix while ignoring MetaPhlAn comments."""
    with open(path, encoding="utf-8") as handle:
        rows = [line for line in handle if line.strip() and not line.startswith("#")]
    if not rows:
        return pd.DataFrame()
    return pd.read_csv(pd.io.common.StringIO("".join(rows)), sep="\t", dtype={0: str})


def species_only(frame):
    feature_column = frame.columns[0]
    features = frame[feature_column].fillna("").astype(str)
    keep = features.str.contains(r"(?:^|\|)s__", regex=True) & ~features.str.contains(
        r"(?:^|\|)t__", regex=True
    )
    return frame.loc[keep].copy()


def parse_matrix(path, domain, is_metaphlan=False):
    frame = read_table(path)
    if frame.empty or frame.shape[1] < 2:
        return pd.DataFrame()
    if is_metaphlan:
        frame = species_only(frame)
    if frame.empty:
        return pd.DataFrame()
    feature_column = frame.columns[0]
    frame[feature_column] = frame[feature_column].fillna("").astype(str).str.strip()
    frame = frame[(frame[feature_column] != "") & (frame[feature_column] != "UNCLASSIFIED")]
    numeric = frame.iloc[:, 1:].apply(pd.to_numeric, errors="coerce").fillna(0.0)
    numeric.index = [f"{domain}:{feature}" for feature in frame[feature_column]]
    numeric = numeric.groupby(level=0).sum()
    numeric.columns = numeric.columns.astype(str)
    return numeric


def parse_virus_matrix(path, value_column):
    frame = read_table(path)
    if frame.empty or frame.shape[1] < 2:
        return pd.DataFrame()
    feature_column = find_column(frame.columns, ("gene", "votu", "votu_id", "virus"))
    if feature_column is None:
        raise ValueError("病毒丰度表缺少 gene/vOTU 特征列")
    suffix = f"_{value_column.lower()}"
    abundance_columns = [
        column for column in frame.columns
        if str(column).strip().lower().endswith(suffix)
    ]
    if not abundance_columns:
        raise ValueError(f"病毒丰度表未找到 *{suffix} 丰度列")
    features = frame[feature_column].fillna("").astype(str).str.strip()
    keep = (features != "") & (features.str.lower() != "nan")
    numeric = frame.loc[keep, abundance_columns].apply(pd.to_numeric, errors="coerce").fillna(0.0)
    numeric.index = [f"virus:{feature}" for feature in features.loc[keep]]
    numeric.columns = [str(column).strip()[:-len(suffix)] for column in abundance_columns]
    numeric = numeric.groupby(level=0).sum()
    numeric = numeric.T.groupby(level=0).sum().T
    log(f"virus 使用 {value_column} 丰度列: {len(numeric.columns)} 个样本")
    return numeric


def parse_profiles(directory, domain):
    profile_paths = sorted(glob.glob(os.path.join(directory, "*", "*_profile.txt")))
    matrices = []
    for path in profile_paths:
        sample_id = Path(path).parent.name
        frame = read_table(path)
        if frame.empty or "clade_name" not in frame.columns or "relative_abundance" not in frame.columns:
            continue
        frame = species_only(frame)
        if frame.empty:
            continue
        values = pd.to_numeric(frame["relative_abundance"], errors="coerce").fillna(0.0)
        matrix = pd.DataFrame({sample_id: values.to_numpy()}, index=[f"{domain}:{item}" for item in frame["clade_name"]])
        matrices.append(matrix.groupby(level=0).sum())
    if not matrices:
        return pd.DataFrame()
    return pd.concat(matrices, axis=1).fillna(0.0).groupby(level=0, axis=1).sum()


def load_domain(input_path, domain, metaphlan=False):
    if not input_path:
        return pd.DataFrame()
    if os.path.isdir(input_path):
        return parse_profiles(input_path, domain)
    return parse_matrix(input_path, domain, is_metaphlan=metaphlan)


def clr_normalize(matrix):
    totals = matrix.sum(axis=0)
    tss = matrix.divide(totals.replace(0, np.nan), axis=1).fillna(0.0)
    pseudocount = 1e-6
    logged = np.log(tss + pseudocount)
    return logged.subtract(logged.mean(axis=0), axis=1)


def prevalence(matrix):
    return (matrix > 0).mean(axis=1)


def standardize_ranks(values):
    ranked = stats.rankdata(values, axis=1, method="average")
    ranked = ranked - ranked.mean(axis=1, keepdims=True)
    scale = ranked.std(axis=1, ddof=1, keepdims=True)
    valid = scale[:, 0] > 0
    ranked[valid] /= scale[valid]
    ranked[~valid] = 0.0
    return ranked, valid


def benjamini_hochberg(pvalues):
    return stats.false_discovery_control(pvalues, method="bh")


def correlate_pair(source, target, block_size, tempdir):
    source_values = source.to_numpy(dtype=float)
    target_values = target.to_numpy(dtype=float)
    source_ranks, source_valid = standardize_ranks(source_values)
    target_ranks, target_valid = standardize_ranks(target_values)
    sample_count = source_values.shape[1]
    test_count = source_values.shape[0] * target_values.shape[0]
    rho_path = os.path.join(tempdir, "rho.dat")
    pvalue_path = os.path.join(tempdir, "pvalue.dat")
    rho_values = np.memmap(rho_path, mode="w+", dtype="float32", shape=(test_count,))
    pvalue_values = np.memmap(pvalue_path, mode="w+", dtype="float64", shape=(test_count,))
    degrees_freedom = sample_count - 2

    for start in range(0, source_values.shape[0], block_size):
        stop = min(start + block_size, source_values.shape[0])
        correlations = source_ranks[start:stop] @ target_ranks.T / (sample_count - 1)
        correlations = np.clip(correlations, -1.0, 1.0)
        valid = source_valid[start:stop, None] & target_valid[None, :]
        correlations[~valid] = 0.0
        if degrees_freedom > 0:
            perfect = np.abs(correlations) >= 1.0 - np.finfo(float).eps
            denominator = np.maximum(1.0 - correlations**2, np.finfo(float).tiny)
            with np.errstate(over="ignore", divide="ignore", invalid="ignore"):
                statistic = np.abs(correlations) * np.sqrt(degrees_freedom / denominator)
                pvalues = 2.0 * stats.t.sf(statistic, degrees_freedom)
            pvalues[perfect] = 0.0
        else:
            pvalues = np.ones_like(correlations)
        pvalues[~valid] = 1.0
        offset = start * target_values.shape[0]
        rho_values[offset:offset + correlations.size] = correlations.ravel()
        pvalue_values[offset:offset + pvalues.size] = pvalues.ravel()

    rho_values.flush()
    pvalue_values.flush()
    fdr_values = benjamini_hochberg(pvalue_values)
    return rho_values, pvalue_values, fdr_values


def correlation_edges(source, target, block_size, rho_cutoff, fdr_cutoff):
    if source.empty or target.empty or source.shape[1] < 3:
        return []
    edges = []
    with tempfile.TemporaryDirectory(prefix="cross_domain_corr_") as tempdir:
        rho_values, pvalue_values, fdr_values = correlate_pair(source, target, block_size, tempdir)
        target_count = target.shape[0]
        for start in range(0, source.shape[0], block_size):
            stop = min(start + block_size, source.shape[0])
            offset = start * target_count
            size = (stop - start) * target_count
            rho_block = np.asarray(rho_values[offset:offset + size]).reshape(stop - start, target_count)
            pvalue_block = np.asarray(pvalue_values[offset:offset + size]).reshape(stop - start, target_count)
            fdr_block = fdr_values[offset:offset + size].reshape(stop - start, target_count)
            positions = np.argwhere((np.abs(rho_block) >= rho_cutoff) & (fdr_block <= fdr_cutoff))
            for source_index, target_index in positions:
                edges.append({
                    "source": source.index[start + source_index],
                    "target": target.index[target_index],
                    "weight": rho_block[source_index, target_index],
                    "pvalue": pvalue_block[source_index, target_index],
                    "fdr": fdr_block[source_index, target_index],
                    "type": "correlation",
                })
    return edges


def find_column(columns, candidates):
    normalized = {str(column).strip().lower(): column for column in columns}
    for candidate in candidates:
        if candidate in normalized:
            return normalized[candidate]
    return None


def host_prediction_edges(path, known_nodes):
    if not path or not os.path.isfile(path):
        log("iPHoP 宿主预测文件不存在，跳过宿主预测边")
        return [], {}
    frame = pd.read_csv(path)
    virus_column = find_column(frame.columns, ("virus", "virus_name", "virus_id", "query"))
    host_column = find_column(
        frame.columns,
        ("host", "host genome", "host_name", "host_genome", "host_taxon"),
    )
    confidence_column = find_column(
        frame.columns,
        ("confidence", "confidence score", "confidence_score", "score"),
    )
    if not virus_column or not host_column:
        log("iPHoP 文件缺少 Virus/Host 列，跳过宿主预测边")
        return [], {}
    extra_nodes = {}
    edge_by_pair = {}
    valid_records = 0
    unmatched_viruses = set()
    for row in frame[[virus_column, host_column] + ([confidence_column] if confidence_column else [])].itertuples(index=False):
        virus_name, host_name = str(row[0]).strip(), str(row[1]).strip()
        if not virus_name or not host_name or virus_name.lower() == "nan" or host_name.lower() == "nan":
            continue
        valid_records += 1
        source = f"virus:{virus_name}"
        target = f"bacteria:{host_name}"
        confidence = pd.to_numeric(row[2], errors="coerce") if confidence_column else np.nan
        confidence = float(confidence) if pd.notna(confidence) else 1.0
        if source not in known_nodes:
            unmatched_viruses.add(virus_name)
            continue
        if target not in known_nodes:
            extra_nodes[target] = {"node_id": target, "domain": "bacteria", "prevalence": 0.0, "abundance_mean": 0.0}
        edge = {"source": source, "target": target, "weight": confidence,
                "pvalue": np.nan, "fdr": np.nan, "type": "host_prediction"}
        pair = (source, target)
        if pair not in edge_by_pair or confidence > edge_by_pair[pair]["weight"]:
            edge_by_pair[pair] = edge
    edges = list(edge_by_pair.values())
    log(f"iPHoP 有效记录: {valid_records} | 匹配宿主预测边: {len(edges)} | "
        f"未匹配 virus ID: {len(unmatched_viruses)}")
    if unmatched_viruses:
        examples = ", ".join(sorted(unmatched_viruses)[:5])
        log(f"iPHoP 未匹配 virus ID 示例（不在 prevalence 过滤后 vOTU 节点中）: {examples}")
    return edges, extra_nodes


def write_summary(path, nodes, edges):
    graph = nx.Graph()
    graph.add_nodes_from(nodes["node_id"])
    for edge in edges:
        graph.add_edge(edge["source"], edge["target"], weight=edge["weight"], type=edge["type"])
    degrees = [degree for _, degree in graph.degree()]
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("cross_domain_correlation_network\n")
        handle.write(f"nodes\t{graph.number_of_nodes()}\n")
        handle.write(f"edges\t{len(edges)}\n")
        handle.write(f"correlation_edges\t{sum(edge['type'] == 'correlation' for edge in edges)}\n")
        handle.write(f"host_prediction_edges\t{sum(edge['type'] == 'host_prediction' for edge in edges)}\n")
        handle.write(f"connected_components\t{nx.number_connected_components(graph) if graph.number_of_nodes() else 0}\n")
        handle.write(f"degree_min\t{min(degrees) if degrees else 0}\n")
        handle.write(f"degree_max\t{max(degrees) if degrees else 0}\n")
        handle.write(f"degree_mean\t{np.mean(degrees) if degrees else 0:.6f}\n")
        handle.write("degree_distribution\n")
        for degree, count in sorted(pd.Series(degrees, dtype=int).value_counts().items()):
            handle.write(f"{degree}\t{count}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bacteria", required=True, help="MetaPhlAn matrix file or profile directory")
    parser.add_argument("--virus", required=True, help="vOTU abundance matrix")
    parser.add_argument("--virus-value-column", choices=("tpm", "count"), default="tpm",
                        help="Value suffix selected from the vOTU table (default: tpm)")
    parser.add_argument("--fungi", help="Optional fungi matrix file or MetaPhlAn profile directory")
    parser.add_argument("--iphop", help="Optional iPHoP Host_prediction_to_genome_m90.csv")
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--block-size", type=int, default=1000)
    parser.add_argument("--min-prevalence", type=float, default=0.10)
    parser.add_argument("--rho-cutoff", type=float, default=0.30)
    parser.add_argument("--fdr-cutoff", type=float, default=0.05)
    args = parser.parse_args()

    if args.block_size < 1:
        parser.error("--block-size 必须大于 0")
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    matrices = {
        "bacteria": load_domain(args.bacteria, "bacteria", metaphlan=True),
        "virus": parse_virus_matrix(args.virus, args.virus_value_column),
        "fungi": load_domain(args.fungi, "fungi", metaphlan=os.path.isdir(args.fungi) if args.fungi else False),
    }
    if matrices["bacteria"].empty or matrices["virus"].empty:
        raise ValueError("细菌和病毒丰度矩阵均必须包含至少一个特征和一个样本")
    filtered_matrices = {}
    node_frames = []
    for domain, matrix in matrices.items():
        if matrix.empty:
            filtered_matrices[domain] = matrix
            continue
        feature_prevalence = prevalence(matrix)
        filtered = matrix.loc[feature_prevalence >= args.min_prevalence]
        filtered_matrices[domain] = clr_normalize(filtered)
        node_frames.append(pd.DataFrame({
            "node_id": filtered.index,
            "domain": domain,
            "prevalence": feature_prevalence.reindex(filtered.index).to_numpy(),
            "abundance_mean": filtered.mean(axis=1).to_numpy(),
        }))
        log(f"{domain} 通过 prevalence 过滤的特征: {len(filtered)}")
    all_samples = sorted(set().union(*(matrix.columns for matrix in filtered_matrices.values() if not matrix.empty)))
    clr_matrix = pd.concat(
        [matrix.reindex(columns=all_samples) for matrix in filtered_matrices.values() if not matrix.empty]
    )
    clr_matrix.to_csv(outdir / "abundance_matrix.tsv", sep="\t", index_label="node_id", float_format="%.8g", na_rep="NA")

    nodes = pd.concat(node_frames, ignore_index=True)
    edges = []
    for source_domain, target_domain in DOMAIN_PAIRS:
        source = filtered_matrices[source_domain]
        target = filtered_matrices[target_domain]
        shared_samples = source.columns.intersection(target.columns)
        log(f"{source_domain}-{target_domain} 共同样本: {len(shared_samples)}")
        pair_edges = correlation_edges(source.loc[:, shared_samples], target.loc[:, shared_samples],
                                       args.block_size, args.rho_cutoff, args.fdr_cutoff)
        log(f"{source_domain}-{target_domain} 保留相关边: {len(pair_edges)}")
        edges.extend(pair_edges)
    host_edges, extra_nodes = host_prediction_edges(args.iphop, set(nodes["node_id"]))
    if extra_nodes:
        nodes = pd.concat([nodes, pd.DataFrame(extra_nodes.values())], ignore_index=True)
    edges.extend(host_edges)
    edge_columns = ["source", "target", "weight", "pvalue", "fdr", "type"]
    edge_frame = pd.DataFrame(edges, columns=edge_columns).drop_duplicates(subset=["source", "target", "type"])
    edge_frame.to_csv(outdir / "network_edges.tsv", sep="\t", index=False, float_format="%.8g", na_rep="NA")
    nodes.sort_values(["domain", "node_id"]).to_csv(outdir / "network_nodes.tsv", sep="\t", index=False, float_format="%.8g")
    write_summary(outdir / "network_summary.txt", nodes, edge_frame.to_dict("records"))
    log(f"完成 | 节点: {len(nodes)} | 边: {len(edge_frame)} | 样本: {len(all_samples)}")


if __name__ == "__main__":
    main()
