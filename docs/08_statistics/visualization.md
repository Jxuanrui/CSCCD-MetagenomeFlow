# 统一可视化

**环境**: `envs/r_stat` | **脚本**: `scripts/94_stat_visualization.sh`

## 功能
对细菌/病毒/真菌分析结果进行统一可视化，生成堆叠柱状图、多组学热图（CLR 变换）、分类学桑基图、UpSet 跨维度交叉图和 PCoA 组合图。

## 用法

```bash
bash scripts/94_stat_visualization.sh \
    -w /path/to/workdir -r ~/Course/Maxmetagenome -m metadata.csv
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |
| `-m` | 否 | — | 元数据 CSV |

## 输出

| 文件 | 内容 |
|------|------|
| `bacteria_top20_stacked_barplot.pdf` | Top 20 物种样本间堆叠图 |
| `merged_multiomics_heatmap.pdf` | 细菌+病毒+真菌联合热图（CLR） |
| `taxonomy_alluvial.pdf` | Kingdom→Phylum→Class 桑基图 |
| `dimension_presence_upset.pdf` | 三维度特征 UpSet 图 |
| `pcoa_composite.pdf` | 三维度 PCoA 联合图 |

## 图表说明

| 图表 | 数据类型 | 说明 |
|------|---------|------|
| 堆叠柱状图 | 细菌相对丰度 | Top 20 物种 per-sample |
| 联合热图 | 三维度 CLR 变换 | 行聚类，列聚类 |
| 桑基图 | 分类层级流 | K→P→C 流向 |
| UpSet 图 | 特征有无矩阵 | 跨维度特征重叠 |
| PCoA 组合图 | 多样性分析的 Beta 坐标 | 三维度并排比较 |

## 注意事项
- 热图使用 CLR 变换（成分数据标准预处理）
- 若 `DIVERSITY_DIR`（`result/stat/diversity`）中有 PCoA 结果，会自动复用
- 各维度图表独立，某一维度缺失不影响其他维度输出

## R 依赖包
`ComplexHeatmap`, `ggplot2`, `ggalluvial`, `UpSetR`, `patchwork`, `phyloseq`, `tidyverse`
