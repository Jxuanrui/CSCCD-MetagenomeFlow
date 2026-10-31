---
tool: "bacphlip"
dimension: "virome"
category: "virus-lifestyle"
author: "team"
date: "2026-06-13"
tags: [parameter-tuning, lifestyle-prediction, lytic-lysogenic, phage-ecology]
scenario: [gut-microbiome, assembled-contigs, virus-catalogue]
---

# BACPHLIP 噬菌体裂解/溶原生活方式预测建议

## Scenario

> 适用于完成 vOTU 聚类（脚本 56）后需要评估病毒群落裂解/溶原比例的肠道病毒组研究。核心参数：`--multi_fasta`（批量多序列 FASTA 输入模式）；`-f`（覆盖已有输出）；输出 `*.bacphlip`（逐序列预测，含 `virulent_score` 和 `temperate_score` 概率）合并为 `bacphlip_results.tsv`。高置信裂解性噬菌体（`virulent_score > 0.9`）可用于宿主操控分析；高置信溶原性（`temperate_score > 0.9`）提示可能存在前噬菌体整合能力。

BACPHLIP 基于随机森林，利用 HMMER 扫描噬菌体功能蛋白（整合酶、转座酶等溶原性标记）区分生活方式，不依赖完整基因组序列，适合 metagenome 来源的 vOTU 分析。

## Recommendation

正式分析建议通过项目脚本运行，输入 vOTU 代表序列：

```bash
# Run BACPHLIP through the project wrapper.
bash scripts/67_vir_bacphlip.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接调用时，使用 `--multi_fasta` 对全部 vOTU 序列批量预测：

```bash
# Direct BACPHLIP command (multi-fasta mode).
bacphlip \
  -i result/virus/votu/contigs/virus.fasta \
  --multi_fasta \
  -f
```

输出合并后可计算样本或队列层的裂解性噬菌体比例，用于差异分析：

```bash
# Summarize lifestyle predictions.
awk 'NR==1 || $2>0.9 || $3>0.9' bacphlip_results.tsv | \
  cut -f1,2,3 > high_confidence_lifestyle.tsv
```

若 vOTU 数量超过 1 万条，预测耗时较长；可先用 PHAROKKA 注释结果中的整合酶/转座酶注释做快速筛查，再对候选溶原性 vOTU 运行 BACPHLIP 精细预测。

## Rationale

- **为什么做生活方式预测**：裂解性和溶原性噬菌体对宿主的影响完全不同；裂解性噬菌体直接杀伤细菌，溶原性噬菌体整合到宿主基因组影响宿主基因表达，区分生活方式是解释病毒-宿主互作的前提。
- **为什么用随机森林而非规则**：纯溶原性标记（整合酶）扫描会漏掉缺乏整合酶但表现溶原行为的噬菌体，RF 综合利用多类功能标记提升召回。
- **为什么设 0.9 高置信阈值**：BACPHLIP 输出是概率而非二元标签；中间段（0.3-0.7）预测置信度低，建议报告时只做统计层分析，不逐序列定论。
- **为什么先聚成 vOTU 再预测**：对每个 vOTU 代表序列预测一次即可，冗余序列不参与预测，节省时间并避免重复计数。
- **文献依据**：Hockenberry & Bhatt 2021 BMC Genomics 展示了 BACPHLIP 在已知噬菌体数据集上的高准确率（>90%），适合宏基因组来源的 vOTU 生活方式注释。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_predictions=77, Exit: 0, Duration: 120s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/67_vir_bacphlip.sh`
- `scripts/56_vir_votu_gen.sh`（依赖 vOTU 序列）
- Hockenberry & Bhatt 2021 BMC Genomics (BACPHLIP)
