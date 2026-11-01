# 多样性分析（Alpha / Beta Diversity）

**环境**: `envs/r_stat` | **脚本**: `scripts/91_stat_diversity.sh` → `scripts/91_diversity.R`

## 功能
对细菌（MetaPhlAn4）、病毒（vOTU）、真菌（MetaPhlAn4）三个维度分别构建 `microeco::microtable` 对象，计算 Alpha 多样性（vegan 默认全套指标）与 Beta 多样性（Bray-Curtis），输出 PCoA 坐标与 PERMANOVA 检验结果。同时导出标准 `phyloseq` RDS（见下）供后续所有 R 包直接使用。

## 用法

```bash
bash scripts/91_stat_diversity.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 项目工作目录 |
| `-r` | 是 | — | CSCCD-MetagenomeFlow 根目录 |
| `-t` | 是 | — | 线程数 |
| `-m` | 是 | — | 元数据 CSV（必须包含 sample_id 和分组列） |
| `-g` | 否 | `group` | 元数据中的分组列名 |
| `--force` | 否 | — | 忽略哨兵文件，强制重新运行 |

## 输入数据

| 维度 | 输入路径 | 格式 |
|------|---------|------|
| 细菌 | `result/metaphlan4/merged/taxonomy.tsv` | 样本×物种丰度矩阵 |
| 病毒 | `result/virus/votu/table/vOTU_table_ann.txt` + `result/virus/votu/vclust/clusters.tsv` | 样本×vOTU 丰度矩阵 + 聚类映射 |
| 真菌 | `result/fungi/metaphlan4/{sample}/*_profile.txt` | MetaPhlAn4 单样本 profile |

不涉及系统发育树输入（未启用 UniFrac/FaithPD，见下方限制）。

## 输出（每维度独立，路径 `result/stat/{bacteria,virus,fungi}/`）

| 文件 | 内容 |
|------|------|
| `abundance/{kingdom,phylum,class,order,family,genus,species}_relabund.tsv` | 各分类级别相对丰度矩阵 |
| `diversity/alpha_diversity.tsv` | Alpha 多样性表（microeco `cal_alphadiv()` 默认指标：Observed/Chao1/ACE/Shannon/Simpson/InvSimpson/Fisher/Pielou/Coverage） |
| `diversity/beta_bray_curtis.tsv` | 样本间 Bray-Curtis 距离矩阵 |
| `diversity/pcoa_coordinates.tsv` | PCoA 前 3 个主坐标（基于 Bray-Curtis） |
| `diversity/permanova_results.tsv` | `vegan::adonis2` 按分组列检验结果 |
| `diversity/alpha_diversity_boxplot.pdf` | Shannon 指数组间箱线图 |
| `diversity/pcoa_beta_scatter.pdf` | Bray-Curtis PCoA 组间散点图 |
| `{dimension}_microtable.rds` | microeco microtable 对象（供 92/94 等下游脚本读取） |
| `phyloseq/{dimension}_phyloseq.rds` | 标准 phyloseq 对象（`file2meco::meco2phyloseq()` 转换，供 92-98 及新增脚本直接读取） |
| `metadata.tsv`（`result/stat/` 根目录） | 标准化后的元数据表 |
| `diversity_alpha_summary.tsv`（`result/stat/` 根目录） | 合并三个维度的 Alpha 多样性汇总表，包含 `dimension` 列 |
| `diversity_status.tsv`（`result/stat/` 根目录） | 多样性分析状态日志 |

真菌维度若物种表全部为 UNCLASSIFIED 或有效物种数 <2，会跳过并写入 `diversity/diversity_status.tsv`（`fungi_mt SKIPPED`）、`abundance/.ok`、`differential/.skipped` 作为哨兵，属预期行为。

组成柱状图/热图由 `94_stat_visualization.sh` 单独生成（见 `docs/08_statistics/visualization.md`）。

## Alpha 多样性指标（microeco 默认全套，非可选）

| 指标 | 含义 |
|------|------|
| Observed | 观测物种数 |
| Chao1 / se.chao1 | 估计物种总数及标准误 |
| ACE / se.ACE | 丰度覆盖估计量及标准误 |
| Shannon | 丰富度+均匀度综合 |
| Simpson / InvSimpson | 优势度集中度 |
| Fisher | Fisher's alpha 多样性 |
| Pielou | 均匀度 |
| Coverage | Good's coverage |

## Beta 多样性指标

| 指标 | 说明 |
|------|------|
| Bray-Curtis | 唯一实现的距离度量，用于 PCoA 和 PERMANOVA |

## 注意事项
- 元数据 CSV 必须包含样本 ID 列和分组列
- 至少有 2 个样本才能计算 Bray-Curtis/PCoA/PERMANOVA
- 真菌输入来自 MetaPhlAn4（脚本 72），若真菌 profile 目录为空或全 UNCLASSIFIED 则跳过该维度
- 当前实现**不包含** FaithPD/UniFrac（无系统发育树输入）和 Aitchison CLR 距离——如需这些指标需扩展脚本

## R 依赖包
`microeco`, `vegan`, `file2meco`, `magrittr`
