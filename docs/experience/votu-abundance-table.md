---
tool: "biostack/vtab-kit"
dimension: "virome"
category: "quantification"
author: ""
date: "2026-06-14"
tags: [votu, abundance-table, salmon, taxonomy, quantification]
scenario: [virome, salmon-quantification, cross-sample-matrix]
---

# vOTU 跨样本丰度矩阵生成建议

## Scenario

> 适用于 `59` 已完成 Salmon 定量且 `57` 已生成 geNomad taxonomy 后，用 `60_vir_votu_table.sh` 汇总 `samples.tsv` 中所有样本；关键输入：`result/virus/salmon/*/report.tsv`、`virus_taxonomy.tsv`、`samples.tsv`；输出 `vOTU_table.txt` 与 `vOTU_table_ann.txt`。

vOTU abundance table 是病毒组分析里最接近 16S OTU table 的最终矩阵产物。

这一步把每个样本的 Salmon quantification 合并成跨样本矩阵，并可把 geNomad taxonomy 追加到矩阵中，形成可直接用于 diversity、差异丰度和可视化的基础表。

它是 aggregate step，不应按单样本解释。单样本 Salmon report 只是中间量，真正用于统计分析的是统一 ID 空间下的 cross-sample vOTU matrix。

## Recommendation

推荐在 vOTU representative index 构建和 Salmon 定量全部完成后运行：

```bash
# Build cross-sample vOTU abundance table.
bash scripts/60_vir_votu_table.sh \
  -m samples.tsv \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

主要输出位于 `result/virus/votu/table/`。`vOTU_table.txt` 是基础丰度矩阵，`vOTU_table_ann.txt` 是追加 taxonomy 的注释矩阵。

正式下游分析建议优先使用注释矩阵，但在差异分析前应明确使用的是 TPM、count 还是经过额外标准化的值。若工具需要原始 count，不应直接把 TPM 当作 count 输入。

运行前应检查 `samples.tsv` 是否只包含本次分析需要的样本，并确认每个样本对应的 Salmon report 已生成。缺失样本如果被静默跳过，会造成矩阵列数和 metadata 不一致。

## Rationale

- **为什么需要统一矩阵**：多样性、差异丰度和分组可视化都要求所有样本共享同一组 vOTU 行，单样本 report 无法直接比较。
- **为什么依赖 Salmon 定量**：Salmon 提供每个样本对 vOTU representative sequences 的 TPM 和 count，是矩阵合并的直接来源。
- **为什么加入 taxonomy**：分类注释让丰度变化可以从 vOTU ID 上升到病毒类群层面解释，便于汇总和图形展示。
- **为什么使用 `samples.tsv`**：样本清单定义了矩阵列空间，能避免把旧样本、测试样本或未纳入研究的样本混入最终表。
- **为什么这是 aggregate step**：矩阵的意义来自跨样本比较，按样本单独生成没有统计分析价值。
- **为什么要区分 TPM 和 count**：TPM 适合相对丰度和可视化，count 更适合部分差异分析模型，两者不能混用。
- **为什么像 16S OTU table**：vOTU table 同样是 feature-by-sample abundance matrix，只是 feature 从细菌 OTU/ASV 换成病毒操作分类单元。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/60_vir_votu_table.sh`
- `scripts/59_vir_salmon_quant.sh`
- `scripts/57_vir_votu_genomad.sh`
- 输入：`result/virus/salmon/{sample}/report.tsv`
- 输出：`result/virus/votu/table/vOTU_table.txt`
- 输出：`result/virus/votu/table/vOTU_table_ann.txt`
