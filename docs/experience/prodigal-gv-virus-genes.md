---
tool: "Prodigal-gv / Prodigal 2.6.3"
dimension: "virome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [gene-prediction, prodigal-gv, viral-genes, proteins, annotation]
scenario: [virome, checkv-filtered-viruses, per-sample-gene-prediction]
---

# Prodigal-gv 病毒基因预测建议

## Scenario

> 适用于 `54` 产出的 CheckV-filtered `viruses.fna`，按样本运行 `55_vir_prodigal_gv.sh` 预测病毒 ORF；关键参数：优先 `prodigal-gv` 处理病毒替代遗传密码，缺失时用标准 `prodigal -p meta`；输出 `result/virus/prodigal/{sample}/*.faa`、`*.fna`、`*.gff`。

病毒基因预测是 vOTU 聚类后功能注释的前置步骤，也是后续 HMM、结构注释或蛋白数据库比对的基础输入。

与细菌 MAG 的基因预测不同，病毒和巨型病毒可能使用替代遗传密码或存在更不规则的基因结构。若环境中可用 Prodigal-gv，应优先使用它；当前脚本在项目环境中以标准 Prodigal `-p meta` 作为可运行 fallback。

这一步按样本执行，因为输入仍来自每个样本 CheckV 过滤后的病毒 contigs。若后续只分析 vOTU 代表序列，则应避免把每样本蛋白与代表序列蛋白混用。

## Recommendation

推荐在 CheckV 过滤完成后、功能注释或 vOTU 下游分析之前运行：

```bash
# Run viral gene prediction for one sample.
bash scripts/55_vir_prodigal_gv.sh \
  -s SAMPLE \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

输出目录为 `result/virus/prodigal/{sample}/`，其中 `{sample}.faa` 用于蛋白层面功能注释，`{sample}.fna` 用于基因核酸序列分析，`{sample}.gff` 用于坐标追溯和 genome browser 检查。

如果同时有 per-sample contigs 和 vOTU representative sequences，建议在报告中明确区分“样本级 ORF”和“catalogue 级 ORF”。前者适合检查单样本基因组成，后者更适合跨样本功能丰度和非冗余功能注释。

若研究包含巨型病毒、噬菌体或高比例未知病毒，Prodigal-gv 的收益会更明显，因为替代遗传密码处理错误会直接影响蛋白长度、终止密码子位置和后续数据库命中。

## Rationale

- **为什么要在 CheckV 后运行**：过滤低质量和污染 contig 后再预测基因，可以减少宿主基因或碎片化 ORF 混入病毒蛋白集合。
- **为什么优先 Prodigal-gv**：它针对病毒遗传密码做过适配，对巨型病毒和部分噬菌体的替代密码子更稳。
- **为什么 fallback 到 `prodigal -p meta`**：标准 Prodigal 在宏基因组模式下仍能处理短 contig 和混合来源序列，是环境不可用时的可复现选择。
- **为什么保留三类输出**：`.faa` 支持蛋白功能注释，`.fna` 支持核酸层面分析，`.gff` 支持坐标和基因结构追溯。
- **为什么按样本运行**：输入文件来自 `result/virus/checkv/{sample}/viruses.fna`，按样本保留来源可避免后续丰度和异常样本排查时丢失上下文。
- **为什么不要直接把 ORF 数当功能丰富度**：contig 长度、完整度和遗传密码处理都会影响 ORF 数，功能解释应结合 vOTU 质量与注释结果。
- **为什么这一步早于功能数据库搜索**：所有下游蛋白数据库、HMM 和结构注释都依赖高质量蛋白序列，基因预测错误会被后续步骤放大。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/55_vir_prodigal_gv.sh`
- 输入：`result/virus/checkv/{sample}/viruses.fna`
- 输出：`result/virus/prodigal/{sample}/{sample}.faa`
- 输出：`result/virus/prodigal/{sample}/{sample}.fna`
- 输出：`result/virus/prodigal/{sample}/{sample}.gff`
