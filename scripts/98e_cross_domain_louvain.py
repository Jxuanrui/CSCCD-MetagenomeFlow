#!/usr/bin/env python3
"""跨域基因组 ANI 相似度图的 Louvain 社区检测。

配合 98e_cross_domain_ani_cluster.sh 使用：读取 FastANI 输出的 pairwise ANI 矩阵
（无表头，5列：query, ref, ANI, orthologous_matches, total_fragments），以基因组
文件路径为节点、ANI值为边权重构建无向图（不做阈值预过滤，全图输入 Louvain），
输出每个基因组所属的簇编号。

参考 VEBA (https://github.com/jolespin/veba) cluster 模块的图聚类思路重新实现，
不拷贝 VEBA 源码（VEBA 为 AGPLv3，networkx/python-louvain 均为 BSD/MIT 许可）。
"""

import argparse
import csv

import networkx as nx
from networkx.algorithms.community import louvain_communities


def load_manifest(path):
    """返回 {fasta_path: (genome_id, domain)}"""
    path_to_genome = {}
    with open(path) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            path_to_genome[row["fasta_path"]] = (row["genome_id"], row["domain"])
    return path_to_genome


def build_graph(ani_matrix_path, path_to_genome):
    graph = nx.Graph()
    for genome_id, domain in path_to_genome.values():
        graph.add_node(genome_id, domain=domain)

    with open(ani_matrix_path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) < 3:
                continue
            query_path, ref_path, ani = fields[0], fields[1], float(fields[2])
            if query_path == ref_path:
                continue
            if query_path not in path_to_genome or ref_path not in path_to_genome:
                continue
            q_id = path_to_genome[query_path][0]
            r_id = path_to_genome[ref_path][0]
            if graph.has_edge(q_id, r_id):
                # FastANI 的 --ql/--rl 是有向比对（query->ref, ref->query 各一行），
                # 取二者较大 ANI 值作为该无向边权重
                graph[q_id][r_id]["weight"] = max(graph[q_id][r_id]["weight"], ani)
            else:
                graph.add_edge(q_id, r_id, weight=ani)
    return graph


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--ani-matrix", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    path_to_genome = load_manifest(args.manifest)
    graph = build_graph(args.ani_matrix, path_to_genome)

    # 无边的孤立节点（FastANI 未产出任何比对结果，如唯一真菌基因组）
    # 各自独立成簇，而非被丢弃
    if graph.number_of_edges() > 0:
        communities = louvain_communities(graph, weight="weight", seed=42)
    else:
        communities = [{n} for n in graph.nodes()]

    node_to_cluster = {}
    for cluster_id, members in enumerate(communities):
        for node in members:
            node_to_cluster[node] = cluster_id

    with open(args.out, "w") as fh:
        fh.write("genome_id\tdomain\tcluster_id\n")
        for genome_id, domain in path_to_genome.values():
            cluster_id = node_to_cluster.get(genome_id, "NA")
            fh.write(f"{genome_id}\t{domain}\tcluster_{cluster_id}\n")

    print(f"[cross_domain_louvain] 节点数: {graph.number_of_nodes()} | "
          f"边数: {graph.number_of_edges()} | 簇数: {len(communities)}")


if __name__ == "__main__":
    main()
