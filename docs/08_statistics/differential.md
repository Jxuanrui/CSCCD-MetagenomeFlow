# 差异丰度分析（Differential Abundance）

**环境**: `envs/r_stat` | **脚本**: `scripts/92_stat_differential.sh`

## 功能
使用四种互补的差异丰度分析方法（ALDEx2, MaAsLin2, LinDA, ANCOMBC2），对细菌/病毒/真菌分类表进行跨组差异分析。输出各方法结果、共识差异特征列表和可视化，支持单维度或全维度运行。

## 用法

```bash
# 全维度分析（细菌+病毒+真菌）
bash scripts/92_stat_differential.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group

# 仅细菌维度
bash scripts/92_stat_differential.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group -d bacteria
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 项目工作目录 |
| `-r` | 是 | — | CSCCD-MetagenomeFlow 根目录 |
| `-t` | 是 | — | 线程数 |
| `-m` | 是 | — | 元数据 CSV |
| `-g` | 是 | — | 分组列名 |
| `-d` | 否 | `all` | 维度：`bacteria` / `virus` / `fungi` / `all` |
| `--force` | 否 | — | 强制重新运行 |

## 四种差异分析方法

| 方法 | 算法基础 | 适用场景 | 优势 |
|------|---------|---------|------|
| **ALDEx2** | 蒙特卡洛 + Dirichlet 分布 | 小样本、稀疏数据 | 鲁棒性高，适合低深度数据 |
| **MaAsLin2** | 线性/广义线性混合模型 | 协变量校正、批次效应 | 支持随机效应，灵活度最高 |
| **LinDA** | 线性回归 + 偏差校正 | 大规模特征 | 快速，适合高通量数据 |
| **ANCOMBC2** | 偏差校正 + 成分分析 | 多组比较、结构零值 | 严格控制 FDR，处理零值最优 |

## 输出

| 文件 | 内容 |
|------|------|
| `result/stat/differential_summary.tsv` | 差异分析汇总（各方法显著特征数） |
| `result/stat/differential_status.tsv` | 各步骤运行状态 |
| `result/stat/{dimension}/differential/lefse_results.tsv` | LEfSe 结果（当前仅细菌维度启用） |
| `result/stat/{dimension}/differential/wilcox_results.tsv` | Wilcoxon 差异检验结果 |
| `result/stat/{dimension}/differential/ancombc2_results.tsv` | ANCOMBC2 结果（依赖 `file2meco`） |

## 共识策略

1. 每种方法独立运行，输出显著特征（padj < 0.05）
2. 取 **≥2 种方法** 同时显著的特征作为共识差异特征
3. ANCOMBC2 标记为 `supplementary = TRUE`，不纳入共识计数（其零值处理更严格）
4. 共识特征是后续分析（SIAMCAT ML、可视化）的首选输入

## 注意事项
- 需要每组至少 2 个样本，总样本数 ≥4 才能进行差异分析
- 低丰度（平均相对丰度 <0.05%）的特征在分析前被自动过滤
- 共识列表的严格程度：ANCOMBC2 > ALDEx2 > LinDA > MaAsLin2（一般到宽松）
- 真菌维度使用 MetaPhlAn4 单样本 profile（`result/fungi/metaphlan4/`），若目录为空则跳过
- 若存在 `batch` 列，MaAsLin2 会自动将其作为随机效应纳入模型

## R 依赖包
`ALDEx2`, `Maaslin2`, `MicrobiomeStat`, `ANCOMBC`, `phyloseq`, `tidyverse`, `UpSetR`
