---
tool: "genomad"
dimension: "virome"
category: "virus-identification"
author: "team"
date: "2026-06-12"
tags: [parameter-tuning, virus-discovery, plasmid-detection, virsorter2-consensus]
scenario: [gut-microbiome, assembled-contigs, paired-end]
---

# geNomad 病毒与质粒识别及 VirSorter2 共识筛选建议

## Scenario

> 适用于已经完成宏基因组组装的肠道样本，需要从 contigs 中识别病毒、噬菌体和质粒候选，并为后续 CheckV、vOTU 构建和生活方式分析提供高可信输入。

典型输入是去宿主后的 WGS metagenome 组装结果，推荐先对 contig 做长度预过滤，再同时运行 geNomad 和 VirSorter2。

如果目标是病毒发现，geNomad 适合作为主召回工具；如果目标是构建发表级病毒 catalogue，应把 geNomad 高分结果与 VirSorter2 结果做交集或高置信并集。

**关键参数速查**：最小长度 `1500 bp`（seqkit 预过滤）；score 阈值 `>=0.70`（主结果）/ `0.50-0.70`（候补集）；`--sensitivity 7.5`；`--splits 4`；`--cleanup` 删除中间文件。与 VirSorter2 取交集获得高可信病毒候选集。

## Recommendation

正式分析建议先过滤 `1500 bp` 以下 contig，再运行 geNomad end-to-end，并保留病毒、质粒和生活方式预测结果。

```bash
# Filter short contigs before viral discovery.
seqkit seq -m 1500 assembly/sample.contigs.fa > assembly/sample.contigs.min1500.fa

# Run geNomad with the project database and high sensitivity.
genomad end-to-end \
  --threads 16 \
  --sensitivity 7.5 \
  --splits 4 \
  --cleanup \
  assembly/sample.contigs.min1500.fa \
  result/virus/genomad/sample \
  db/genomad/genomad/genomad_db

# Keep high-confidence geNomad calls for the primary candidate set.
csvtk filter2 -t -f '$score >= 0.70' \
  result/virus/genomad/sample/sample.contigs.min1500_summary/sample.contigs.min1500_virus_summary.tsv \
  > result/virus/genomad/sample/sample.genomad.score70.tsv
```

VirSorter2 建议使用同一批 `1500 bp` 以上 contig 作为输入，避免两个工具因为输入长度集合不同而造成交集偏差。

```bash
# Run VirSorter2 on the same filtered contig set.
virsorter run \
  -i assembly/sample.contigs.min1500.fa \
  -w result/virus/virsorter2/sample \
  --db-dir db/virsorter2 \
  --min-length 1500 \
  --include-groups "dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae" \
  -j 16 \
  --verbose

# Use shared contig IDs as the conservative primary set.
comm -12 \
  <(cut -f1 result/virus/genomad/sample/sample.genomad.score70.tsv | tail -n +2 | sort) \
  <(cut -f1 result/virus/virsorter2/sample/final-viral-score.tsv | tail -n +2 | sort) \
  > result/virus/consensus/sample.genomad_vs2.ids
```

geNomad score 建议主结果使用 `>=0.70`；`0.50-0.70` 的候选可以保留为补充列表，但不要直接进入主 vOTU catalogue。

生活方式预测建议跟随 geNomad 输出单独整理，区分 lytic 与 lysogenic 候选；溶原性解释必须结合 CheckV 的 provirus 边界和宿主信息，不要只凭单一标签下结论。

当前项目脚本 `52_vir_genomad.sh` 默认使用 `--sensitivity 7.5` 和 `--splits 4`，可继续作为召回阶段默认值；正式结果筛选应在输出表层面再加 score 和长度门槛。

## Rationale

- **为什么用 geNomad 做主召回**：geNomad 使用神经网络和序列特征整合策略，不完全依赖传统 marker 命中，对新颖病毒和质粒候选的召回通常优于单纯 marker-based 方法。
- **为什么 score 使用 `>=0.70`**：较高分数能减少边缘移动元件、低复杂度片段和细菌 contig 被误判为病毒的风险，适合作为主结果门槛。
- **为什么先过滤 `1500 bp`**：过短 contig 缺乏足够基因结构和序列上下文，病毒识别、生活方式预测和后续质量估计都会更不稳定。
- **为什么要与 VirSorter2 做共识**：两个工具的模型和证据来源不同，取交集能显著降低单工具假阳性扩散到 CheckV、vOTU 和宿主预测步骤的概率。
- **为什么不直接丢弃单工具阳性**：真实新颖病毒可能只被 geNomad 或 VirSorter2 其中之一识别，适合保留为候补集，但应在结果等级中明确降级。
- **为什么要保留质粒结果**：质粒与病毒都属于移动遗传元件，肠道样本中二者可能共享部分序列特征，单独保留有助于解释抗性基因和移动元件传播。
- **为什么生活方式预测要谨慎解释**：lytic 与 lysogenic 标签受 contig 完整度和宿主边界影响，最好与 CheckV provirus trimming、宿主预测和功能注释共同判断。
- **为什么脚本灵敏度可以偏高**：召回阶段可以稍宽，真正控制主结果质量的是后续 score、长度、VirSorter2 共识和 CheckV 过滤。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: S01-S06 ×6, Params: none, Durations: S01=708s S02=716s S03=713s S04=701s S05=708s S06=710s, Exit: 0, Duration: 708s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/52_vir_genomad.sh`
- `scripts/53_vir_virsorter2.sh`
- `docs/experience/genomad-virsorter2-consensus.md`
