# 统一可视化

**环境**: `envs/r_stat` | **脚本**: `scripts/94_stat_visualization.sh`

## 功能
对细菌/病毒/真菌分析结果进行统一可视化，生成堆叠柱状图、多组学热图（CLR 变换）、分类学桑基图、UpSet 跨维度交叉图和 PCoA 组合图。

## 用法

```bash
bash scripts/94_stat_visualization.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -m metadata.csv
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |
| `-m` | 否 | — | 元数据 CSV |

## 输出

所有组成可视化按维度写入 `result/stat/{bacteria,virus,fungi}/composition/`，完成哨兵为 `result/stat/composition_done.txt`。

| 文件 | 内容 |
|------|------|
| `barplot_composition_by_group.pdf` | Phylum/Genus 组成柱状图 |
| `barplot_genus_groupmean.pdf` | Genus 分组均值柱状图 |
| `heatmap_genus.pdf` | Genus 丰度热图 |
| `{dimension}_viz_status.tsv` | 该维度可视化状态日志 |

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
- 读取 `result/stat/{dimension}/{dimension}_microtable.rds`，并写入对应维度的 `composition/` 子目录
- 各维度图表独立，某一维度缺失不影响其他维度输出

## R 依赖包
`ComplexHeatmap`, `ggplot2`, `ggalluvial`, `UpSetR`, `patchwork`, `phyloseq`, `tidyverse`
