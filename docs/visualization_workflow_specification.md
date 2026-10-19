# 统计与可视化流程规范（91-99 系列）

本文档描述 `scripts/91_*` 到 `scripts/99_*` 这批统计分析/可视化脚本的输入输出、依赖关系与执行顺序，供后续新增脚本、排查故障或调参时查阅。对应 Snakemake 规则集中在 `pipeline/rules/statistics.smk`（跨队列验证在独立的 `pipeline/rules/crosscohort.smk`）。

## 总览：四层依赖结构

```
第0层 数据整合层（91-95，98b/98c/98d）
  ├─ 91_stat_diversity.sh   ──> diversity_alpha_summary.tsv         [多样性，链头]
  ├─ 92_stat_differential.sh──> differential_summary.tsv            [差异分析]
  ├─ 93_stat_cooccurrence.sh──> network/network_summary.txt         [共现网络]
  ├─ 94_stat_visualization.sh──> composition_done.txt               [物种组成可视化]
  ├─ 95a_stat_batch_correct.sh ──> corrected_matrices.done          [批次校正]
  │    └─ 95b_stat_batch_evaluate.sh ──> evaluation_report.tsv      [批次校正评估]
  └─ 98b/98c/98d_*_integration_tables.sh ──> result/integration/{dim}/{func_type}_*.tsv  [功能表整合，第2层的输入来源]

第2层 功能分析层（96 系列，依赖第0层整合表 + humann3 输出）
  96_stat_functional.sh（20 个 dimension×func_type 组合，Snakemake 用 xargs -P6 并行调用独立进程）
       ──> {dim}/functional/{type}/{dim}_functional_{type}_done.txt
              ├─ 96_functional_permanova.sh      ──> {dim}_permanova_done.txt
              ├─ 96_functional_integrated.sh      ──> 00_summary/{dim}_summary_done.txt
              └─ 96_functional_cross_dimension.sh ──> cross_dimension_functional_done.txt

  96b_pathway_activity.sh（独立，只依赖 humann3，不依赖 96_stat_functional）
  96c_functional_redundancy.sh（依赖第0层功能表 + 原始 taxonomy 表，三维度分别跑）
  96_stat_ml_siamcat.sh + 96_ml_visualization.R（SIAMCAT 机器学习，依赖 taxonomy/votu/fungi 丰度表）

第3层 下游微生物组学层（依赖第0层整合表 + 原始 taxonomy，彼此独立可并行）
  99a_core_microbiome.sh（核心微生物组）
  99b_lefse.sh（LEfSe，三维度×多个 func_type 循环）
  ──> downstream_summary 规则汇总 99a+96c+96b 三个模块状态 ──> downstream_summary.tsv

第4层 报告与跨队列层
  97_stat_crosscohort.sh ──> result/viz_crosscohort/*（跨队列 AUC、meta-analysis）
  98_stat_report.sh 汇总 91/92/96_siamcat/97 等产出 ──> result/stat/report/report_{timestamp}.md
```

**关键点**：
- 91（多样性）是整条 stat 流程 Snakemake 规则的"链头"，92/93 都以它的 sentinel 为 input 触发顺序执行，但实质数据依赖仍是原始丰度表——这是为了控制执行顺序，不是真正的数据依赖。
- 96 系列的 permanova/integrated/cross_dimension 硬依赖 96_stat_functional 先跑完全部 20 个组合，不能提前跑。
- 96b/96c/99a/99b 相互独立，都直接消费第0层整合表，可以并行执行。
- `97_stat_crosscohort.sh` 的产出目录是 `result/viz_crosscohort/`，`98_stat_report.sh` 读取的也是这个路径（此前存在路径不一致的 bug，读到了不存在的 `result/stat/crosscohort/`，已修复）。

## 通用约定

- **Sentinel 模式**：每个脚本完成后写一个 `*_done.txt` 文件标记完成；Snakemake 据此判断是否需要重跑。若 sentinel 存在且非空，脚本默认跳过重跑，除非传 `--force`。
- **空表/小样本量的 graceful skip**：功能表为空（有表头无数据行）或样本量不足统计方法要求时，脚本写入 `SKIPPED: <原因>` 到 sentinel 并以 exit 0 退出，不视为失败。例如 `96_stat_functional.sh` 对空功能表、`96_stat_ml_siamcat.sh` 对样本量<10 的情况都是这样处理的。这是"流程稳定性优先于统计严谨性"的设计取舍——本项目的统计分析目的是验证流程本身能否跑通，不是追求发表级别的统计显著性。
- **绘图容错**：多数 R 脚本在关键绘图包缺失时会降级为 WARN 并跳过绘图部分，但核心统计分析仍会继续执行并产出数据表。
- **conda 环境**：所有脚本统一用 `conda run --prefix {REPO}/envs/r_stat --no-capture-output Rscript ...` 调用 R；脚本内部会做 `.libPaths()` 修正以确保读到 conda 环境自带的包而不是系统库。

---

## 第0层：数据整合层

### 91_diversity.R / 91_stat_diversity.sh — 多样性分析

- **用途**：计算细菌/病毒/真菌三个维度的 alpha/beta 多样性并出图。
- **参数**：必需 `-w WORKDIR -r REPO -t THREADS -m METADATA_CSV`；可选 `-g GROUP_COL`（默认 `group`）、`--force`。
- **输入**：`result/metaphlan4/merged/taxonomy.tsv`（细菌）、`result/virus/votu/table/vOTU_table_ann.txt`（病毒）、`result/fungi/metaphlan4`（真菌）、`result/metaphlan4/merged/mpa_tree.nwk`（树，供 UniFrac 用）。
- **输出**：`result/stat/diversity_alpha_summary.tsv`（sentinel）、`diversity_status.tsv`、各维度目录下的 alpha 箱图、beta PCoA 散点图、phyloseq rds（依赖 `file2meco`，缺失则 SKIPPED）。
- **依赖**：`microeco, magrittr, dplyr, tidyr, vegan, MicrobiotaProcess`；绘图 `ggplot2, ggpubr, rstatix, svglite, ragg`。
- **坑**：绘图设备重定向到 `grDevices::pdf(file=NULL)` 防止意外弹窗；若无 `diversity_alpha_summary.tsv` 产出会直接 `stop()`。

### 92_differential.R / 92_stat_differential.sh — 差异分析

- **用途**：跨维度差异丰度分析，使用 maaslin2/ancombc2 等方法。
- **参数**：必需 `-w -r -t -m -g`；可选 `-d DIMENSION`（bacteria|virus|fungi|all，默认 all）、`--force`。
- **输入**：同 91 的三张丰度表。
- **输出**：`differential_status.tsv`、`differential_summary.tsv`（sentinel），每方法一个结果 tsv。
- **依赖**：`microeco, magrittr, dplyr, tidyr`；绘图脚本 `scripts/R/plot_differential.R` 需 `ggplot2, ggrepel, ggtext`；`ancombc2` 依赖 `file2meco`，缺失时该方法跳过但不影响其他方法。
- **坑**：即使所有维度都失败，也会写出 header-only 的 `differential_summary.tsv` 并给出 `[WARN]`，保证 sentinel 存在——sh 脚本据此判断"是否成功"，实际可能是空表，排查问题时不要只看 sentinel 是否存在。

### 93_stat_cooccurrence.sh — 共现网络分析（无独立 .R 文件，内嵌 heredoc R 代码）

- **用途**：细菌/病毒/真菌内部及跨域（bac-vir、bac-fun）共现网络分析。
- **参数**：必需 `-w -r -t -m`；可选 `-g GROUP_COL`、`-n NET_TYPE`（bac|vir|fun|cross_bac_vir|cross_bac_fun|all，默认 all）、`--force`。
- **输入**：`taxonomy.tsv`（细菌）、`votu_table.tsv`（病毒，注意与 91/92 用的 `vOTU_table_ann.txt` 不是同一个文件）、真菌优先用 `result/integration/fungi/funomic_species_count.tsv`（PHF 方法），若不存在则回退到 metaphlan4 逐样本 profile。
- **输出**：`result/stat/network/network_summary.txt`（sentinel）。
- **依赖**：`SpiecEasi, NetCoMi, MetaNet, igraph, ggplot2, phyloseq, tidyverse, svglite, ragg`。

### 94_visualization.R / 94_stat_visualization.sh — 物种组成可视化

- **用途**：统一的物种组成可视化（柱图、热图等），跨三维度。
- **参数**：必需 `-w -r`；可选 `-m METADATA_CSV`、`--force`。
- **输入**：三张丰度表 + `result/stat/metadata.tsv`（来自 `01_metadata_qc.sh` 标准化后的元数据）。
- **输出**：`result/stat/composition_done.txt`（sentinel）；细菌 `barplot_composition_by_group.pdf`、`heatmap_genus.pdf` 作为二次校验文件。
- **坑**：sh 脚本的 skip 判断除了 sentinel 还额外检查这两个 pdf 均存在才跳过，比其他脚本更严格。

### 95a_stat_batch_correct.sh / 95b_stat_batch_evaluate.sh — 批次校正与评估

- **95a**：参数必需 `-w -r -t -m -b BATCH_COL`；可选 `-g GROUP_COL`、`--force`。输入 `taxonomy.tsv`。输出 `result/stat/bacteria/batch/corrected_matrices.done`（sentinel）+ 多种校正矩阵（含 ComBat 等；其中调用了 Python 的 `debiasm` 模块做 DEBIAS-M 校正，若 Python 环境不可用该方法会失败但不影响其他方法）。
- **95b**：依赖 95a 产出。参数必需 `-w -r -m -b`；可选 `-g`、`--force`。输出 `evaluation_report.tsv`（sentinel，按 batch_R2 升序 + group_R2 降序排名推荐方法）、`batch_pcoa_top3.pdf`（仅取排名前3方法画图）。依赖 `vegan`（adonis/R2 计算）、`patchwork`。

### 98b/98c/98d 系列 — 功能整合表生成

这批脚本把各功能注释工具（dbCAN/VFDB/AMR/MEROPS/KEGG等）的原始输出整合成统一格式的 `result/integration/{dimension}/{func_type}_*.tsv`（细菌：`_abundance.tsv`；真菌：`_gene_count.tsv`），是第2层功能分析（96 系列）的直接输入来源。包括：
- `98b_bac_integration_tables.sh`（细菌功能表）
- `98c_bac_mge_summary.sh` / `98c_vir_integration_tables.sh`（细菌 MGE 汇总 / 病毒功能表）
- `98d_bac_mag_integration.sh` / `98d_fun_integration_tables.sh`（细菌 MAG 整合 / 真菌功能表）

---

## 第2层：功能分析层

### 96_stat_functional.R / 96_stat_functional.sh — 功能差异分析（核心模块）

- **用途**：用 Maaslin3 对功能表做差异分析 + 超几何富集检验，支持 16 种功能类型、3 个维度、共 20 个合法组合。
- **参数**：必需 `-w -r`；可选 `-m`、`-d DIMENSION`（bacteria|fungi|virus，默认 bacteria）、`-t FUNC_TYPE`（pathway|kegg_ko|cog|cazyme|arg|vfdb|defense|ncyc|pcyc|funomic|amr|merops|phrog|vog|lifestyle|host_genus|viral_family，默认 pathway）、`--force`。
- **合法组合**（`dimension:func_type`）：
  - bacteria: pathway, kegg_ko, cog, cazyme, arg, vfdb, defense, ncyc, pcyc（9个）
  - fungi: kegg_ko, cog, cazyme, vfdb, amr, merops（6个）
  - virus: phrog, vog, lifestyle, host_genus, viral_family（5个）
- **输入**：按 `dimension+func_type` 组合选择对应的整合表（来自 98b/98c/98d 脚本产出）。
- **输出**：`result/stat/{dimension}/functional/{func_type}/{dimension}_functional_{func_type}_done.txt`（sentinel）。
- **依赖**：`maaslin3, ggplot2, dplyr, tidyr, tibble, stringr, RColorBrewer`。
- **重要坑（并行相关）**：`maaslin_cores` 强制恒为 `1`。maaslin3 内建的 mirai/nanonext 并行调度机制（`cores > 1`）在这批数据规模下会偶发死锁任务调度器，且是 mirai/nanonext 本身的调度器问题（复现过：即使单进程隔离运行、无任何其他并发 R 进程，也会挂死），不是多个 maaslin3 进程互相冲突导致的 race condition——这是上游 [biobakery/maaslin3#25](https://github.com/biobakery/maaslin3/issues/25) 已知的问题类型，官方 README 也建议默认单核。因此本项目所有 20 个组合都在 R 层单核跑，靠 Snakemake 层用 `xargs -P 6` 并行调用多个独立脚本进程来提速（详见下方 `pipeline/rules/statistics.smk` 的 `stat_functional` 规则）。
- **其他坑**：`legacy_bacteria_skip_prevalence_types <- c("cog", "ncyc", "pcyc")`，这几类细菌功能表跳过 prevalence 过滤；功能特征数少时也自动跳过 prevalence 过滤；功能表为空（有表头无数据行）时写 `SKIPPED` sentinel 并 exit 0。

### 96_functional_integrated.R / .sh — 功能整合可视化

- **用途**：单维度内跨数据库（KEGG/COG/CAZyme/ARG 等）整合可视化，生成汇总面板。
- **参数**：必需 `-d DIMENSION`；可选 `-w -r -m -g -c CPUS`、`--force`。
- **输出**：`result/stat/{dimension}/functional/00_summary/{dimension}_summary_done.txt`（sentinel）。
- **依赖**：`ggplot2, dplyr, tidyr, tibble, stringr, ggtext, ggsci, ComplexHeatmap, circlize, svglite, ragg, purrr, rlang`。硬依赖 96_stat_functional 该维度下所有组合先跑完。

### 96_functional_permanova.R / .sh — PERMANOVA 整体差异检验

- **用途**：对每个维度的功能表做 PERMANOVA 整体差异检验。
- **输出**：`result/stat/{dimension}/functional/{dimension}_permanova_done.txt`（sentinel）。依赖 96_stat_functional 输出。

### 96_functional_cross_dimension.R / .sh — 跨维度比较

- **用途**：比较细菌/真菌/病毒之间显著功能信号的重叠与差异。
- **参数**：可选 `-w -r`、`--force`（无维度参数，脚本内部处理全部三维度）。
- **输出**：`result/stat/cross_dimension/functional/cross_dimension_functional_done.txt`（sentinel）。
- **依赖**：`ggplot2, dplyr, tidyr, tibble, stringr, ggsci, ComplexHeatmap, circlize, svglite, ragg, igraph`。硬依赖三个维度的 96_stat_functional 都跑完。

### 96b_pathway_activity.R / .sh — 通路活性分析

- **用途**：基于 humann3 通路表做通路活性打分与可视化。
- **依赖关系**：独立模块，只依赖 humann3 输出，不依赖 96_stat_functional。
- **输出**：`pathway_activity_summary.txt`（sentinel）。

### 96c_functional_redundancy.R / .sh — 功能冗余 / 功能-物种关联分析

- **用途**：分析功能与物种丰度的关联（Spearman 相关），评估功能冗余度。三维度分别跑，真菌可选跳过。
- **输入**：第0层功能整合表 + 原始 taxonomy 表。
- **输出**：`functional_redundancy_summary.txt`（sentinel）。
- **性能坑**：早期版本用双重 for 循环逐对调用 `stats::cor.test()`（对 bacteria:kegg_ko 规模是约 2170 万次调用），已改为向量化实现（rank 变换后用 `stats::cor()` 一次性算全部 Pearson-of-ranks，等价于逐对 Spearman；p 值用 t 分布公式复刻 `cor.test(exact=FALSE)` 的内部计算），数值上验证与原实现完全一致（最大绝对误差 correlation 为 0，p 值约 2.22e-16 机器精度误差）。

### 96_stat_ml_siamcat.sh / 96_ml_visualization.R — SIAMCAT 机器学习

- **用途**：用 SIAMCAT 做机器学习分类，评估微生物特征对分组的判别力。
- **参数**：必需 `-w -r -t -m -g`；可选 `-d DIMENSION`（bacteria|virus|fungi|all，默认 bacteria）、`-M FUNGI_METHOD`（auto|phf|funomic|metaphlan4，默认 auto）、`--folds N`（默认10）、`--force`。
- **输入**：`taxonomy.tsv`（细菌）、`votu_table.tsv`（病毒）、fungi 丰度表（按 `-M` 选择或 auto 探测）。
- **输出**：`siamcat_done.txt`（sentinel）+ 各模型（lasso/ridge/enet/randomForest）的评估图和 rds。
- **坑**：样本量 < 10 时无法满足 SIAMCAT 交叉验证要求，写 `SKIPPED` sentinel 并 exit 0，随后 `96_ml_visualization.R` 检测到 SKIPPED 会生成占位 PDF（写明"SIAMCAT requires >=10 samples"）而不是报错。

---

## 第3层：下游微生物组学层

### 99a_core_microbiome.R / .sh — 核心微生物组分析

- **用途**：识别核心（高流行度）物种/功能特征，三维度分别跑。
- **输出**：`core_microbiome_summary.txt`（sentinel）。
- **依赖关系**：直接消费第0层整合表 + 原始 taxonomy，与 96b/96c/99b 相互独立，可并行执行。

### 99b_lefse.R / .sh — LEfSe 分析

- **用途**：LEfSe（线性判别分析效应量）差异特征检测，三维度 × 多个 func_type 循环跑。
- **坑**：单个组合失败仅记 WARN，不阻断其他组合继续跑。
- **依赖关系**：与 99a/96b/96c 相互独立，可并行执行。

### downstream_summary 规则

汇总 99a（核心微生物组）+ 96c（功能冗余）+ 96b（通路活性）三个模块的完成状态到 `downstream_summary.tsv`。

---

## 第4层：跨队列与报告层

### 97_crosscohort.R / 97_stat_crosscohort.sh — 跨队列验证

详见 `docs/08_statistics/crosscohort_local.md`。核心产出目录 `result/viz_crosscohort/`，包含森林图/瀑布图/ROC叠加/UpSet/特征稳定性/PCoA/校准曲线/效应相关等 8 个可视化，以及可选的 meta-analysis（随机效应模型合并 AUC，I² 异质性评估）。

### 98_stat_report.sh — 最终报告生成

汇总 91（多样性）/92（差异分析）/96_stat_ml_siamcat（机器学习）/97（跨队列）等模块的产出，扫描 `result/stat` 下所有 pdf/png 及 `*.FAILED` 哨兵文件，生成 `result/stat/report/report_{timestamp}.md`。读取跨队列结果时使用 `result/viz_crosscohort/auc_summary.tsv`（与 97 的实际产出路径保持一致）。

---

## 已知限制与设计取舍

1. **稳定性优先于统计严谨性**：本项目的统计分析定位是验证宏基因组分析流程的工程稳定性，不是产出可发表的统计结论。因此空表/小样本量场景统一走 graceful skip，而不是想办法凑够样本量或改变统计方法去追求"能算出结果"。
2. **maaslin3 并行度**：见上文 96_stat_functional 小节，`cores` 恒为 1，靠 Snakemake 层的进程级并行（`xargs -P N`）弥补速度损失。
3. **真菌丰度表来源优先级**：多个脚本（93/96_stat_ml_siamcat 等）在选择真菌丰度表时都遵循同一优先级：PHF 方法整合表 > FunOMIC 整合表 > MetaPhlAn4 逐样本 profile，取决于哪个上游产出实际存在。
