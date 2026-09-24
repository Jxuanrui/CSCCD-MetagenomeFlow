---
tool: "kraken2-report-filter"
dimension: "mycobiome"
category: "taxonomy"
author: ""
date: "2026-06-14"
tags: [kraken2, fungi-screening, lightweight-profile]
scenario: [gut-microbiome, whole-genome-metagenomics, first-pass-screen]
---

# MicroFisher 风格真菌概览建议

## Scenario

> 适用于想从 Kraken2 结果里快速拿到 fungi-only 视图：若 `result/fungi/kraken2/{sample}/{sample}.report` 已存在则直接过滤，否则补跑一次 PlusPF Kraken2，并输出 `result/fungi/microfisher/{sample}/{sample}_fungal_profile.tsv`。

这里的 “MicroFisher” 指的是用途相近的轻量真菌概览，不是商业 MicroFisher 产品本身。当前实现本质上是 Kraken2 report filter。

## Recommendation

推荐把它作为全队列真菌筛查里最快的一层视图。若步骤 71 已经跑过，直接复用 report；没有 report 时再补跑一次不保存 reads 级输出、只生成分类报告的 Kraken2。

```bash
# Reuse an existing Kraken2 report or generate a quick fallback report.
bash scripts/77_fun_microfisher.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

这个结果适合回答“样本里有哪些真菌门/属/种被 Kraken2 命中”，不适合作为正式物种丰度主表；正式分析仍建议和 FunOMIC 或 DIAMOND 结果互相参照。

## Outputs

最终输出固定为每样本 fungi-only 视图：

```text
result/fungi/microfisher/{sample}/{sample}_fungal_profile.tsv
```

优先复用的上游文件是：

```text
result/fungi/kraken2/{sample}/{sample}.report
```

若上游 report 缺失，脚本会调用 PlusPF 数据库快速补跑 Kraken2，再用 `awk` 只提取属于 kingdom `Fungi` 或典型真菌门谱系下的 `P/G/S` 级条目，输出列为 `taxon / taxid / reads / abundance_level`。

## Rationale

- **为什么它最快**：本质是 report 过滤；即使需要补跑 Kraken2，也远快于 FunOMIC 或 DIAMOND blastx。
- **为什么适合做 fungi-only 视图**：Kraken2 原始 report 很宽，直接过滤后能立刻聚焦真菌门、属、种层级。
- **为什么要优先复用步骤 71**：避免重复做同一份 reads 的 k-mer 分类，把计算资源留给更慢的真菌专用分析。
- **为什么不能当作商业 MicroFisher**：它只是命名上借用了“快速真菌概览”的用途，底层完全是 Kraken2 PlusPF 的近似实现。
- **为什么要和其他方法互补**：Kraken2 快，但数据库覆盖和近缘误分配问题仍在；FunOMIC 和 BLAST 更适合做确认。
- **为什么适合作为前置决策工具**：若这里完全没有真菌信号，往往可以先降低该样本在后续 fungi-specific 分析中的优先级。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/77_fun_microfisher.sh`
- `scripts/71_fun_kraken2_fungi.sh`
- `docs/experience/kraken2-fungi-database.md`
