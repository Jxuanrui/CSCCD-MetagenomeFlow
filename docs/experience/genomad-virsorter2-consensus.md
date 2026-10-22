---
tool: "genomad-virsorter2"
dimension: "virome"
category: "annotation"
author: ""
date: "2026-06-11"
tags: [virus-identification, consensus, sensitivity-specificity]
scenario: [paired-end, high-depth, low-biomass]
---

# geNomad 与 VirSorter2 交叉确认的病毒候选策略

## Scenario

> 适用于病毒组装 contig 的候选筛选，希望在召回率和特异性之间取得较稳平衡，而不是单靠一种识别器输出。

本项目流程把 geNomad 和 VirSorter2 都放在 CheckV 之前，意味着它们的主要作用是提供“候选病毒集合”。

经验上，这一步最值得强调的是“双工具互证”，不是盲目放宽单工具阈值。

## Recommendation

推荐保持 geNomad 与 VirSorter2 双跑，并在进入 CheckV 前做交集或至少高置信并集复核。

脚本中的主参数建议如下：

```bash
genomad end-to-end --sensitivity 7.5 --splits 4 --cleanup
virsorter run --min-length 1000 \
  --include-groups "dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae"
```

geNomad 建议保留 `--sensitivity 7.5` 作为默认高灵敏度设置，适合先做广覆盖召回。

VirSorter2 建议保留 `--min-length 1000`，不建议为了多捞一些短片段而继续下调。

正式病毒 catalogue 构建时，优先保留 geNomad 与 VirSorter2 同时支持的 contig；单工具阳性更适合作为候补集单独标记。

如果样本疑似低生物量或宿主污染重，优先提高共识门槛，而不是只看 geNomad 的高灵敏度输出。

若 geNomad 与 VirSorter2 结果规模差异极大，先排查 assembly 质量、contig 长度分布和数据库配置，再解释生物学原因。

## Rationale

- **为什么要双工具互证**：两者建模思路不同，重叠结果通常比任一单独列表更可信。
- **为什么 geNomad 可以开高灵敏度**：它适合做前置召回，把潜在病毒、质粒和生活方式信息尽量收齐，后面还有 VirSorter2 与 CheckV 再筛。
- **为什么 VirSorter2 维持 `1000 bp`**：过短 contig 缺乏足够病毒特征，边界预测与分类都更容易不稳。
- **为什么交集优先于简单并集**：并集会最大化召回，但也更容易把低质量、边缘或污染片段带入下游质量评估。
- **为什么单工具阳性不要立刻丢弃**：某些真实病毒可能只被一种模型抓到，但在主结果中应明确降级标记，而不是与共识集合混在一起。
- **为什么结果差异过大值得排查**：这常提示 contig 过碎、数据库损坏、版本差异或样本本身含有大量非典型移动元件。
- **为什么 geNomad 先 cleanup 也合理**：大部分后续步骤只依赖摘要和候选序列，中间缓存不是长期必需资产。
- **为什么这一步不直接做最终质量分级**：病毒真假和病毒质量是两个问题；共识识别后仍需交给 CheckV 做完整度和污染评估。
- **为什么适合在病毒发现阶段偏保守**：后续 host prediction、vOTU 聚类和统计分析都怕假阳性扩散，前面略保守通常比后面返工更省成本。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/52_vir_genomad.sh`
- `scripts/53_vir_virsorter2.sh`
- `agents/skills/52_vir_genomad.yaml`
- `agents/skills/53_vir_virsorter2.yaml`
