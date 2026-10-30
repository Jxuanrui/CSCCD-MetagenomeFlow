---
tool: "geNomad taxonomy mode"
dimension: "virome"
category: "taxonomy"
author: "team"
date: "2026-06-14"
tags: [genomad, votu, taxonomy, representative-sequences, aggregate]
scenario: [virome, votu-representatives, taxonomy-annotation]
---

# vOTU 代表序列 geNomad 分类注释建议

## Scenario

> 适用于 `56` 已生成 vOTU 代表序列 `result/virus/votu/contigs/virus.fasta` 后，用 `57_vir_votu_genomad.sh` 对代表序列做第二次 geNomad 分类注释；关键参数：aggregate run、只跑 vOTU reps、`genomad end-to-end --sensitivity 4.2 --splits 4 --cleanup`；输出 `virus_taxonomy.tsv`。

这一步不是病毒发现阶段的 geNomad 重复运行，而是专门面向 vOTU representative sequences 的 catalogue 级 taxonomy annotation。

脚本 52 的 geNomad 运行对象是每样本 assembly contigs，主要目的是发现病毒候选。脚本 57 的运行对象是去冗余后的 vOTU 代表序列，目的是给最终 catalogue 中的稳定单元补充分类信息。

因此，脚本 57 应在 vOTU 聚类完成后运行，并且只运行一次聚合分析，不需要按样本重复。

## Recommendation

推荐在 `56_vir_votu_gen.sh` 完成后运行：

```bash
# Run geNomad taxonomy annotation on vOTU representatives.
bash scripts/57_vir_votu_genomad.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

输入固定为 `result/virus/votu/contigs/virus.fasta`，输出为 `result/virus/votu/genomad/virus_taxonomy.tsv`。

下游生成 vOTU abundance table 时，应使用这里的 `virus_taxonomy.tsv` 作为 taxonomy source，而不是直接混用每样本 discovery 阶段的 geNomad taxonomy。前者与 vOTU ID 一一对应，更适合构建最终注释矩阵。

若后续重新聚类 vOTU，必须重新运行这一步。vOTU 代表序列改变后，旧 taxonomy 表即使文件仍存在，也不能再视为有效注释。

## Rationale

- **为什么是第二次 geNomad**：第一次服务于候选发现，第二次服务于最终 vOTU catalogue 注释，两者输入层级和用途不同。
- **为什么只跑代表序列**：vOTU 已经去冗余，对代表序列注释可以避免重复计算，也保证 taxonomy 与最终矩阵 ID 对齐。
- **为什么这是 aggregate step**：taxonomy 属于项目级 catalogue 属性，不依赖单个样本，按样本运行会产生重复且难以合并的注释。
- **为什么不能直接用 discovery 阶段结果**：发现阶段的 contig ID 与聚类后的 vOTU representative ID 可能不完全一致，直接合并容易错配。
- **为什么输出集中到 `virus_taxonomy.tsv`**：后续 `60_vir_votu_table.sh` 需要一个稳定的 taxonomy 表来给丰度矩阵追加注释列。
- **为什么重新聚类后要重跑**：代表序列选择变化会改变 annotation target，taxonomy 表必须跟随 catalogue 版本更新。
- **为什么保留 geNomad 原始输出目录**：摘要表之外的中间结果有助于追溯分类来源、score 和潜在边界问题。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: none, Exit: 0, Duration: 114s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/57_vir_votu_genomad.sh`
- `scripts/56_vir_votu_gen.sh`
- 输入：`result/virus/votu/contigs/virus.fasta`
- 输出：`result/virus/votu/genomad/virus_taxonomy.tsv`
