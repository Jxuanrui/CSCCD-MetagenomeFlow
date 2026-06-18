# 多样性分析（Alpha / Beta Diversity）

**环境**: `envs/r_stat` | **脚本**: `scripts/91_stat_diversity.sh`

## 功能
对 MetaPhlAn4 细菌/真菌分类表和病毒 vOTU 丰度表，计算 Alpha 多样性（Shannon / Chao1 / Simpson / Observed / FaithPD）和 Beta 多样性（Bray-Curtis / Aitchison CLR），生成 PCoA 可视化和 PERMANOVA 统计。支持细菌、病毒、真菌三个维度并行分析。

## 用法

```bash
bash scripts/91_stat_diversity.sh \
    -w /path/to/workdir -r ~/Course/Maxmetagenome -t 16 \
    -m metadata.csv -g group
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 项目工作目录 |
| `-r` | 是 | — | MaxMetagenome 根目录 |
| `-t` | 是 | — | 线程数 |
| `-m` | 是 | — | 元数据 CSV（必须包含 sample_id 和分组列） |
| `-g` | 否 | `group` | 元数据中的分组列名 |
| `--force` | 否 | — | 忽略哨兵文件，强制重新运行 |

## 输入数据

| 维度 | 输入路径 | 格式 |
|------|---------|------|
| 细菌 | `result/metaphlan4/merged/taxonomy.tsv` | 样本×物种丰度矩阵 |
| 病毒 | `result/virus/votu/table/vOTU_table_ann.txt` | 样本×vOTU 丰度矩阵 |
| 真菌 | `result/fungi/metaphlan4/{sample}/*_profile.txt` | MetaPhlAn4 单样本 profile |
| 系统发育树 | `result/metaphlan4/merged/mpa_tree.nwk` | FaithPD 计算所需（可选） |

## 输出

| 文件 | 内容 |
|------|------|
| `alpha_diversity.tsv` | 所有样本的 Alpha 多样性值（5 指标×3 维度） |
| `beta_pcoa.tsv` | PCoA 坐标（Bray-Curtis + Aitchison CLR） |
| `permanova.tsv` | PERMANOVA 检验结果 |
| `diversity_status.tsv` | 各步骤运行状态日志 |
| `alpha_diversity_boxplot.pdf` | 分组箱线图（含 Wilcoxon 检验） |
| `beta_pcoa.pdf` | PCoA 散点图 |

## Alpha 多样性指标

| 指标 | 含义 | 生物意义 |
|------|------|---------|
| Shannon | 物种丰富度+均匀度综合 | 群落多样性综合指标 |
| Chao1 | 估计物种总数 | 反映稀有物种补充 |
| Simpson | 优势度集中度 | 优势物种比例 |
| Observed | 观测物种数 | 直接计数 |
| FaithPD | 系统发育多样性 | 物种进化距离总和（需系统发育树） |

## Beta 多样性指标

| 指标 | 距离类型 | 推荐场景 |
|------|---------|---------|
| Bray-Curtis | 丰度差异 | 物种组成差异（标准指标） |
| Aitchison CLR | 成分对数比 | 成分数据（宏基因组丰度本质上是成分数据，推荐首选） |

## 注意事项
- 元数据 CSV 必须包含样本 ID 列（列名可以是 `sample` / `sample_id` / `SampleID` 等）和分组列
- 至少有 3 个样本（分组后每组 ≥2）才能进行有意义的统计比较
- CLR 变换后使用欧氏距离，符合成分数据分析标准（优于 Bray-Curtis 但解释性稍差）
- FaithPD 需要系统发育树文件，若不存在则跳过该指标
- 真菌输入来自 MetaPhlAn4（脚本 72），若真菌 profile 目录为空则跳过真菌维度

## R 依赖包
`phyloseq`, `vegan`, `microbiome`, `picante`, `ape`, `ggplot2`, `ggpubr`, `tidyverse`
