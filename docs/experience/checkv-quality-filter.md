---
tool: "checkv-quality"
dimension: "virome"
category: "qc"
author: ""
date: "2026-06-11"
tags: [virus-qc, completeness, deduplication]
scenario: [paired-end, high-depth, low-biomass]
---

# CheckV 病毒 contig 质量过滤建议

## Scenario

> 适用于 geNomad 与 VirSorter2 已完成候选识别的样本，需要把病毒序列合并、去重，并生成可用于后续 vOTU 与注释的质量摘要。

在本项目里，CheckV 不是孤立评估器，而是“候选病毒集合进入正式分析前的质量闸门”。

脚本默认先合并两路候选，再用 `seqkit rmdup -s` 去重，然后执行 `checkv end_to_end`。

## Recommendation

建议保留当前两步法，不要直接把 geNomad 或 VirSorter2 任一路输出单独送进下游。

主流程建议如下：

```bash
cat genomad_virus.fna virsorter2_viral.fa > merged.fasta
seqkit rmdup -s -o virus_contigs.fasta merged.fasta
checkv end_to_end virus_contigs.fasta result/virus/checkv/sample -d db/checkv -t 16
```

去重建议继续使用 `-s` 按序列内容去重，而不是按 header 去重。

下游构建 vOTU 或做宿主预测时，优先使用 `quality_summary.tsv` 中质量达标的 contig；不要把全部 `viruses.fna` 原样放行。

如果样本中没有任何有效病毒候选，保留脚本生成的空摘要 sentinel，这比直接报错中断整条 virome 流程更合理。

对正式结果，建议至少区分“完整/高质量/中等质量/低质量”几个层级，而不是把 CheckV 输出压成单一保留列表。

原前病毒 `provirus.fna` 建议与自由病毒 contig 分开解释，不要在同一丰度表里混作同类单位。

## Rationale

- **为什么先做双工具合并再去重**：这样既能保留两路召回，又避免同一序列被重复统计。
- **为什么按序列去重而不是按名称**：不同工具给同一 contig 的命名往往不同，只有基于序列内容去重才稳。
- **为什么 CheckV 是必要闸门**：病毒识别器告诉你“像不像病毒”，CheckV 进一步告诉你“质量怎样、是否完整、是否可能是原前病毒片段”。
- **为什么质量分层比简单通过/不通过更好**：不同下游任务对质量要求不同，宿主预测、功能注释、vOTU 聚类未必需要相同门槛。
- **为什么空摘要要保留**：队列分析里，零病毒样本本身也是结果；用 sentinel 表达“确实没有”比流程崩掉更利于统计汇总。
- **为什么 `provirus` 要单列**：原前病毒处在宿主基因组背景中，其长度、边界和解释逻辑都不同于游离病毒 contig。
- **为什么不能把所有候选都送去 vOTU**：低质量或强污染片段会放大聚类噪声，导致 vOTU catalogue 失真。
- **为什么 CheckV 放在识别器之后**：先收集高置信候选，再做质量细分，比先对全量组装 contig 跑 CheckV 更节约资源。
- **为什么 `quality_summary.tsv` 应成为过滤主表**：它集中给出完整度、污染和质量等级，是后续规则化过滤的最佳接口。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/54_vir_checkv_contig.sh`
- `agents/skills/54_vir_checkv_contig.yaml`
- 上游来源：`scripts/52_vir_genomad.sh`
- 上游来源：`scripts/53_vir_virsorter2.sh`
