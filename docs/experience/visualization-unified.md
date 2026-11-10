---
tool: "r-visualization"
dimension: "stats"
category: "stats"
author: ""
date: "2026-06-14"
tags: [visualization, multi-omics, publication-figures]
scenario: [multi-omics, aggregate, publication-ready]
---

# 统一统计可视化的一次性出图策略建议

## Scenario

> 适用于已完成 91 diversity 与 92 differential 的项目，用 `94_stat_visualization.sh` 聚合 bacteria/virus/fungi 的 merged taxonomy/abundance 表，一次生成 `result/stat/visualization/` 多组学概览图；可加 `-m metadata.csv` 叠加分组信息，必要时用 `--force` 重画。

## Recommendation

默认建议把 `94_stat_visualization.sh` 放在差异分析和多样性分析之后运行，用它生成论文初稿阶段的全局概览图，而不是为每一种图单独维护脚本。

推荐命令骨架如下：

```bash
bash scripts/94_stat_visualization.sh \
  -w PROJECT -r REPO \
  -m metadata.csv --force
```

如果只是检查已有结果，不加 `--force` 可避免重复生成；当输入表、差异结果或元数据更新后，再使用 `--force` 保证所有图来自同一批结果。

## Required Inputs

核心输入是各维度已合并的 taxonomy/abundance 表，以及 91 和 92 步骤产生的统计结果。脚本作为 aggregate step，不面向单个样本运行。

元数据 `-m metadata.csv` 是可选项，但正式出图建议提供；这样热图、PCoA 或分组相关图可以带上疾病/对照、批次或其他协变量信息。

## Outputs

主要输出目录为 `result/stat/visualization/`，一次运行覆盖多种图形类型。

- `phylum_barplot.pdf`：phylum 层级堆叠柱状图，用于展示主要类群组成。
- `merged_multiomics_heatmap.pdf`：ComplexHeatmap 多组学联合热图。
- `taxonomy_alluvial.pdf`：ggalluvial alluvial/sankey 图，展示 bacteria/virus/fungi 的分类流向或维度关系。
- `dimension_presence_upset.pdf`：UpSetR 多组学 overlap 图，检查特征在不同维度中的交集。
- 其他组合图：脚本依赖 ggplot2、ggpubr、patchwork 和 phyloseq 组织补充可视化。

## Rationale

- **为什么放在 91/92 之后**：多样性坐标、差异结果和合并丰度表都已稳定，统一出图更容易保证所有图使用同一版输入。
- **为什么一次运行生成所有图**：统计结果汇报通常需要组成图、热图、跨维度关系图和 overlap 图；集中生成能减少手动漏图和版本不一致。
- **为什么推荐 metadata overlay**：分组、批次和临床变量可以直接暴露在图上，便于判断图形结构是否由目标生物学差异驱动。
- **为什么保留 `--force`**：可视化是下游产物，输入更新后应显式重建，避免旧图混入新结果。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证
