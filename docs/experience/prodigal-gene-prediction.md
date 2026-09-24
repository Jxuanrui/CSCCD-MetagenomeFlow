---
tool: "Prodigal v2.6.3"
dimension: "bacteria"
category: "assembly"
author: ""
date: "2026-06-13"
tags: [assembly, prodigal, gene-prediction, orf, metagenome]
scenario: [gut-microbiome, assembled-contigs, per-sample-analysis]
---

# Prodigal 宏基因组基因预测建议

## Scenario

> 适用于每个样本已经完成 contig 组装，需要从原核生物 contigs 中批量预测蛋白编码基因，并立即衔接功能注释与基因目录构建。对 shotgun metagenome 而言，优先使用 `-p meta`，不要把匿名混样 contigs 当作完整基因组去跑 `-p single`。

典型输入是 MEGAHIT 产出的 `{sample}.contigs.fa`，典型输出是 `{sample}.faa`、`{sample}.fna` 和 `{sample}.gff`。其中 `.faa` 是后续 eggNOG、KEGG、AMRFinder、CARD 和 dbCAN 等功能注释的核心入口，`.fna` 则用于跨样本 CD-HIT 去冗余，`.gff` 保留坐标与基因完整性标记，便于追踪基因来源。

在宏基因组场景下，Prodigal v2.6.3 的 `-p meta` 使用通用 metagenome 模型，不需要针对每个样本单独训练参数；这也是它适合按样本稳定批处理的原因。若组装 contig 过短，基因边界不完整的比例会上升，因此上游通常建议 contig 长度至少在 `500 bp` 量级再解释基因预测结果。

**关键参数速查**：Tool = `Prodigal v2.6.3`；Depends on = MEGAHIT `{sample}.contigs.fa`；Key params = `-p meta`（metagenomics mode, no training）, `-f gff`（GFF coordinate output）, `-a {sample}.faa`（protein output）, `-d {sample}.fna`（nucleotide output）；Recommended input quality = contig length `>=500 bp`；Outputs = `.faa` + `.fna` + `.gff`；Downstream = eggNOG(21) / KEGG(22) / AMRFinder(23) / CARD(24) / dbCAN(25)

## Recommendation

项目流程已经封装好每样本 Prodigal 调用，推荐直接使用包装脚本，保持输出路径与下游步骤一致：

```bash
# Per-sample Prodigal gene prediction in metagenome mode.
bash scripts/17_bac_prodigal.sh \
  -s S01 \
  -t 1 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果需要单独审计参数或在流程外复现，直接命令应显式写出 `-p meta`、蛋白输出、核酸输出和 GFF 坐标输出：

```bash
# Direct Prodigal v2.6.3 command for assembled metagenomic contigs.
prodigal \
  -i result/assembly/megahit/S01/S01.contigs.fa \
  -a result/assembly/prodigal/S01/S01.faa \
  -d result/assembly/prodigal/S01/S01.fna \
  -f gff \
  -o result/assembly/prodigal/S01/S01.gff \
  -p meta
```

这个步骤是典型的逐样本基因预测，不需要等待全队列完成。实际项目中最重要的不是 `.gff`，而是 `.faa` 是否完整产出，因为后续绝大多数功能注释工具都直接消费蛋白序列；`.fna` 的价值则体现在后面的跨样本非冗余基因目录构建。

## Rationale

- **为什么必须用 `-p meta`**：宏基因组 contigs 来自混合群落，长度和完整性差异很大，`-p single` 面向高质量单基因组，直接套用会增加边界误判和模型偏置。
- **为什么不需要每样本训练**：Prodigal v2.6.3 在 `-p meta` 下使用通用 metagenome 模型，这正是它适合批量处理匿名 contigs 的原因，省去了按样本重复训练的开销。
- **为什么 `.faa` 是最关键输出**：eggNOG、KEGG、AMRFinder、CARD、dbCAN 等下游注释几乎都以蛋白序列为主要输入，`.faa` 决定后续功能注释能否顺利推进。
- **为什么 `.fna` 也必须保留**：跨样本基因目录通常在核苷酸层面做 `95% identity / 90% coverage` 去冗余，CD-HIT-EST 直接使用 Prodigal 的 `.fna` 作为输入。
- **为什么还要输出 `.gff`**：GFF 文件保留坐标、链方向和 `partial` 标记，后续若要筛完整基因、回溯 contig 位置或做局部可视化，`.gff` 是唯一结构化来源。
- **为什么推荐 contig 至少 `500 bp` 再解释结果**：过短 contigs 更容易产生截断 ORF 和片段化基因，即使 `-p meta` 能运行，生物学解释价值也会明显下降。
- **为什么按样本运行而不是先合并再预测**：每样本单独预测更利于和后续样本级定量、溯源和目录合并对接，也能避免 header、路径和统计摘要混在一起。
- **为什么该步骤通常不是性能瓶颈**：Prodigal 是单线程工具，但内存需求低、运行稳定，瓶颈通常出现在后续 CD-HIT 聚类或大规模功能注释，而不是这一步本身。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/17_bac_prodigal.sh`
- `agents/skills/17_bac_prodigal.yaml`
