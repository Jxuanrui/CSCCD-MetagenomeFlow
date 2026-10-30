---
tool: "vcontact3"
dimension: "virome"
category: "virus-taxonomy"
author: "team"
date: "2026-06-13"
tags: [parameter-tuning, phage-taxonomy, gene-sharing-network, ictv-classification]
scenario: [gut-microbiome, assembled-contigs, virus-catalogue]
---

# vConTACT3 病毒基因共享网络分类建议

## Scenario

> 适用于已完成 vOTU 生成（脚本 56）和 PHAROKKA 注释（脚本 64）的病毒组研究，需要通过基因共享网络将 vOTU 归类到 ICTV 病毒科/属。核心参数：`--nucleotide votu.fa`（vOTU 核酸）；`--db-path vcontact3/`（参考病毒数据库，可离线预下载）；`-e graphml cytoscape completeness`（输出格式）；主输出 `exports/final_assignments.csv`（ICTV 分类汇总）和 `.cyjs` 网络文件（Cytoscape 可视化）。蛋白输入优先使用 PHAROKKA 的 `phanotate.faa`。

vConTACT3 把 query vOTU 和参考病毒基因组构建蛋白共享网络（Leiden 社区检测），按社区归类确定分类学位置，是唯一能同步产出 ICTV 分类标注和可视化网络图的病毒组分类工具。

## Recommendation

正式分析建议通过项目脚本运行，自动处理 gene2genome 映射准备：

```bash
# Run vConTACT3 through the project wrapper.
bash scripts/69_vir_vcontact3.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接调用时，需先准备数据库（首次离线部署）：

```bash
# First time: prepare offline database.
vcontact3 prepare_databases --db-path db/vcontact3/

# Run vConTACT3 classification.
vcontact3 run \
  --nucleotide result/virus/votu/contigs/virus.fasta \
  --output result/virus/vcontact3 \
  --db-path db/vcontact3 \
  -t 16 \
  -e graphml cytoscape completeness
```

`final_assignments.csv` 含每个 vOTU 的分类层级（Realm/Phylum/Class/Order/Family/Genus）和置信度；未分类的 vOTU 标注为 `Unclassified` 或 `New`：

```bash
# Quick summary of family-level classification.
awk -F',' 'NR>1 {print $6}' exports/final_assignments.csv | sort | uniq -c | sort -rn | head -20
```

vConTACT3 数据库在 2025 年大幅更新（新增 ICTV MSL39 参考），若使用旧版 vConTACT2 结果发表，建议使用 vConTACT3 重分类后更新附表。

## Rationale

- **为什么用基因共享而非序列比对**：病毒进化速率快，全基因组核酸比对灵敏度低；蛋白功能基因共享是病毒进化的保守特征，适合跨科甚至跨目的分类。
- **为什么需要 PHAROKKA 蛋白**：蛋白序列质量直接影响网络密度和社区检测精度；PHAROKKA 使用 prodigal-gv 预测的病毒蛋白比通用工具更准确，减少蛋白预测噪声。
- **为什么离线预下载数据库**：vConTACT3 默认在线下载，高性能集群或限制网络环境建议提前运行 `prepare_databases`。
- **为什么要同时输出 graphml 和 cytoscape**：`.graphml` 供编程分析，`.cyjs` 供 Cytoscape 可视化；后者对评审人展示基因共享网络非常有效。
- **已知限制**：vOTU 序列质量差（CheckV 低分）会降低蛋白预测准确率，导致网络连接稀疏；建议过滤 CheckV completeness < 50% 的 vOTU 后再运行。
- **文献依据**：vConTACT 方法发表于 Bin Jang et al. 2019 Nat Biotechnol；vConTACT3 于 2025 年更新，显著扩大了参考数据库并改进了社区检测算法。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: none, Exit: 0, Duration: 1800s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/69_vir_vcontact3.sh`
- `scripts/56_vir_votu_gen.sh`（依赖 vOTU 序列）
- `scripts/64_vir_pharokka.sh`（依赖蛋白 phanotate.faa）
- `scripts/62_vir_checkv_mag.sh`（建议 CheckV 过滤后再运行）
- Bin Jang et al. 2019 Nat Biotechnol (vConTACT2)
