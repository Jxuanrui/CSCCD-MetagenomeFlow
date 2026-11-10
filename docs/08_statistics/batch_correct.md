# 批次校正与评估

**环境**: `envs/r_stat` | **脚本**: `scripts/95a_stat_batch_correct.sh` / `95b_stat_batch_evaluate.sh`

## 功能
对多中心/多批次宏基因组数据进行批次校正。95a 运行多种校正方法，95b 评估各方法效果并推荐最佳方法。

## 用法

```bash
# 第一步：运行多种批次校正方法
bash scripts/95a_stat_batch_correct.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -b batch \
    -g group

# 第二步：评估并推荐最佳方法
bash scripts/95b_stat_batch_evaluate.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow \
    -m metadata.csv -b batch \
    -g group
```

| 参数 | 必需 | 默认 | 95a | 95b | 含义 |
|------|------|------|-----|-----|------|
| `-w` | 是 | — | ✓ | ✓ | 工作目录 |
| `-r` | 是 | — | ✓ | ✓ | 项目根目录 |
| `-t` | 是 | — | ✓ | — | 线程数 |
| `-m` | 是 | — | ✓ | ✓ | 元数据 CSV |
| `-b` | 是 | — | ✓ | ✓ | 批次列名 |
| `-g` | 否 | — | ✓ | ✓ | 生物分组列 |

## 输入

| 项目 | 路径 |
|------|------|
| 丰度矩阵 | `result/metaphlan4/merged/taxonomy.tsv` |
| 元数据 | 通过 `-m` 传入 |

## Step 1（95a）— 批量校正方法

脚本 95a 运行多种批次校正方法，包括：
- **ConQuR**: 分位数回归
- **MMUPHin**: Meta 分析批次校正
- **ComBat-seq**: 基于负二项回归
- **Harmony**: 软聚类校正
- **limma::removeBatchEffect**: 线性模型

## Step 2（95b）— 评估指标

脚本 95b 使用以下指标评估校正效果：

| 指标 | 含义 | 目标 |
|------|------|------|
| Silhouette（批次） | 批次混合度 | 越低越好 |
| Silhouette（分组） | 生物信号保留 | 越高越好 |
| RDA R²（批次） | 批次解释方差 | 越低越好 |
| RDA R²（分组） | 分组解释方差 | 越高越好 |

## 输出

| 文件 | 内容 |
|------|------|
| `corrected_matrices.done` | 校正完成哨兵 |
| `evaluation_report.tsv` | 各方法评估指标汇总（最佳方法标记） |

## 注意事项
- 建议在差异分析（92）之前运行批次校正
- 若批次效应不显著（RDA R² < 5%），可能不需要校正
- `-g group` 帮助评估校正是否保留了生物差异；不指定则仅评估批次混合度
- 校正矩阵存于 `result/stat/bacteria/batch/`，供下游分析手动选择

## R 依赖包
`MBECS`, `ConQuR`, `MMUPHin`, `sva`, `limma`, `harmony`, `vegan`, `tidyverse`
