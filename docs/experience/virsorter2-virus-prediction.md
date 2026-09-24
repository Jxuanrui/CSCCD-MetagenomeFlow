---
tool: "VirSorter2 2.2+"
dimension: "virome"
category: "virus-identification"
author: "team"
date: "2026-06-14"
tags: [virus-identification, virsorter2, genomad, consensus, contigs]
scenario: [virome, per-sample-assembly, consensus-virus-discovery]
---

# VirSorter2 病毒候选识别与 geNomad 共识建议

## Scenario

> 适用于 `51_vir_megahit` 产生的每样本 assembly contigs，需要用 `53_vir_virsorter2.sh` 补充病毒候选；关键参数：`--min-score 0.9` 严格或 `0.5` 敏感，`--include-groups dsDNAphage,ssDNA,NCLDV,RNA,lavidaviridae`；输出 `final-viral-score.tsv` 与 `final-viral-boundary.tsv`。

VirSorter2 适合作为 geNomad 之外的独立病毒识别证据，而不是单独决定最终病毒 catalogue。

本项目把脚本 52 和 53 放在 CheckV 之前，说明它们共同服务于候选病毒集合构建。更稳妥的做法是把 geNomad 和 VirSorter2 的交集作为高置信病毒集合，再把单工具阳性作为候补或敏感性分析集合。

对污染较重、宿主 DNA 背景高或 contig 较碎的样本，VirSorter2 的边界预测与分数表尤其有价值，因为它能帮助识别 contig 中更像病毒区域的片段。

这一步的核心目标不是最大化候选数量，而是给后续 CheckV、vOTU 聚类和丰度定量提供更可信的病毒输入。

## Recommendation

推荐通过项目脚本按样本运行 VirSorter2，并与 geNomad 结果做交叉确认：

```bash
# Run VirSorter2 for one sample through the project wrapper.
bash scripts/53_vir_virsorter2.sh \
  -s SAMPLE \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

标准输出目录为 `result/virus/virsorter2/{sample}/`，关键文件是 `final-viral-score.tsv` 和 `final-viral-boundary.tsv`。

正式 catalogue 建议优先保留 geNomad 与 VirSorter2 同时支持的 contig。若研究目标偏发现新型病毒，可以额外保留 VirSorter2 单阳性结果，但应在下游表格中单独标记证据来源，不要与双工具共识结果混在一起解释。

阈值选择上，`--min-score 0.9` 更适合主结果或低生物量样本，`0.5` 更适合探索性召回。无论使用哪个阈值，都应记录在方法和结果 metadata 中，因为它会直接改变进入 CheckV 的候选集合规模。

## Rationale

- **为什么要与 geNomad 做共识**：两类工具的特征和模型来源不同，交集结果通常比单工具输出更稳，能降低假阳性进入 vOTU 聚类的风险。
- **为什么保留 `final-viral-score.tsv`**：分数表是候选排序和阈值追溯的基础，后续若需要提高或放宽筛选强度，可以不重复完整运行。
- **为什么保留 `final-viral-boundary.tsv`**：病毒信号可能只覆盖 contig 的一段，边界信息能帮助识别宿主污染或嵌合片段。
- **为什么区分 `0.9` 和 `0.5`**：高阈值提高特异性，低阈值提高召回；病毒发现阶段可以敏感，主 catalogue 构建阶段应偏保守。
- **为什么指定 include groups**：显式覆盖 dsDNA phage、ssDNA、RNA、NCLDV 和 lavidaviridae，避免默认设置遗漏研究中关心的病毒类群。
- **为什么这一步在 CheckV 之前**：VirSorter2 判定“像不像病毒”，CheckV 再评估质量和污染，两者解决的问题不同，顺序不能互换。
- **为什么按样本运行**：输入来自每个样本的 assembly contigs，先保持样本来源清晰，后续再统一进入质量过滤和跨样本 vOTU 构建。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: S01-S06 ×6, Params: none, Durations: S01=225s S02=277s S03=323s S04=249s S05=229s S06=283s, Exit: 0, Duration: 225s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/52_vir_genomad.sh`
- `scripts/53_vir_virsorter2.sh`
- 输入：`result/virus/assembly/{sample}/{sample}.contigs.fa`
- 输出：`result/virus/virsorter2/{sample}/final-viral-score.tsv`
- 输出：`result/virus/virsorter2/{sample}/final-viral-boundary.tsv`
