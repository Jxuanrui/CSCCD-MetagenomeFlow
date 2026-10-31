# SIAMCAT — 机器学习生物标志物发现

**环境**: `envs/r_stat` | **脚本**: `scripts/96_stat_ml_siamcat.sh`

## 功能
使用 SIAMCAT 框架对微生物组特征（物种分类丰度）进行机器学习建模，支持 Lasso / Ridge / Elastic Net / Random Forest 四种算法，输出 10 折交叉验证 AUC、模型评估图和 Top 特征重要性排序，用于识别最具判别力的生物标志物。

## 用法

```bash
# 默认（细菌维度，10折交叉验证）
bash scripts/96_stat_ml_siamcat.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group

# 全维度交叉（细菌+病毒+真菌联合（BVF））
bash scripts/96_stat_ml_siamcat.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group --combination BVF --repeats 10

# 指定5折
bash scripts/96_stat_ml_siamcat.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group --folds 5
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 项目工作目录 |
| `-r` | 是 | — | CSCCD-MetagenomeFlow 根目录 |
| `-t` | 是 | — | 线程数 |
| `-m` | 是 | — | 元数据 CSV |
| `-g` | 是 | — | 分组列名 |
| `-d` | 否 | `bacteria` | 维度：`bacteria` / `virus` / `fungi` / `all`(=BVF) |
| `--combination` | 否 | 从 `-d` 派生 | 特征块选择：`B`/`V`/`F`/`BV`/`BF`/`VF`/`BVF`/`all`；显式传参时默认 `--sample-set BVF`（协议：七组共用三表交集） |
| `--sample-set` | 否 | `auto` | `auto`=各组合各自交集（非协议便利）；`BVF`=三表交集（A-2 配对前提） |
| `--repeats` | 否 | `1` | 外层重复次数；>1 输出每重复明细与 mean±sd（含 `n_degenerate` 披露） |
| `-M` | 否 | `auto` | 真菌输入源（仅显式传参生效并 WARN non-protocol；协议用途固定 98d funomic） |
| `--folds` | 否 | `10` | 交叉验证折数 |
| `--force` | 否 | — | 强制重新运行（跳过 regime 守卫） |
| `--skip-shap` | 否 | — | 跳过 SHAP 特征归因 |

## 四种 ML 算法

| 算法 | 特点 | AUC 期望 |
|------|------|---------|
| **Lasso** | L1 正则化，特征选择强 | 中等，特征稀疏 |
| **Ridge** | L2 正则化，保留所有特征 | 可能最高 |
| **Elastic Net** | L1+L2 混合，折中 | 接近最优 |
| **Random Forest** | 非线性，特征交互 | 稳健，但解释性差 |

## 输入数据

| 维度 | 来源 |
|------|------|
| bacteria | `result/metaphlan4/merged/taxonomy.tsv`（WC1R 输入治理：仅保留 k__Bacteria 物种 s__ 终端行；层级/真核/古菌行剔除并计数） |
| virus | `result/integration/virus/votu_annotation_matrix_relab.tsv` 的 `vOTU_TPM_` 列（98c 产物；块内自行换算相对丰度——RELAB 列 %.4f 会抹掉低丰度信号，不采用） |
| fungi | `result/integration/fungi/normalized/funomic_species_relab.tsv`（98d 产物；协议用途固定此源，`-M` 仅显式传参时生效并 WARN non-protocol） |
| all | 细菌+病毒+真菌三块合并（BAC|/VIR|/FUN|，= `--combination BVF`） |

## 输出

默认 `-d bacteria` 输出到 `result/stat/bacteria/ml/`；`-d virus` / `-d fungi` 分别输出到对应维度的 `ml/` 子目录；`-d all`（=BVF）输出到 `result/stat/ml/`；`--combination BV/BF/VF` 输出到 `result/stat/ml_<组合>/`。三块特征各转 0-1 相对丰度后过滤（per-block，WC1R2）。`--sample-set auto|BVF`：显式 `--combination` 默认 BVF（七组共用三表交集，配对前提）；auto=各组合各自交集（非协议便利）。resume 会核对 manifest 的 **combination / sample_set / fungi_method** 三字段与本次参数，任一不一致时报错要求 `--force`（防旧口径哨兵被静默复用，WC1R2-C2）；**没有 manifest 的旧哨兵（如 WC1R 之前的结果）重跑同样报错，需 `--force` 重建**。显式 `-M` 的非协议结果被协议 resume 拦下时也请用 `--force`。`--repeats N` 外层循环输出 mean±sd 与 n_degenerate。

| 文件 | 内容 |
|------|------|
| `siamcat_auc_summary.tsv` | 四种模型 AUC 汇总 |
| `siamcat_done.txt` | 完成标志（含 AUC 列表） |
| `siamcat_{model}.rds` | SIAMCAT 模型对象（可 reload 查看） |
| `siamcat_{model}_evaluation.pdf` | ROC / PR 曲线 |
| `siamcat_{model}_interpretation.pdf` | 特征重要性排序图（Top 20） |
| `siamcat_confounders.pdf` | 混杂因素检查图 |
| `siamcat_status.tsv` | 各步骤状态日志 |

## 分析流程

```
特征表 → 过滤（平均相对丰度≥1e-4（0.01%） + 存在率≥5%）→ log.std 标准化
 → K 折 CV split → 训练 4 种模型 → AUC 评估 → 特征重要性排序
```

## 注意事项
- 需要每组 ≥5 个样本，总样本 ≥10 才能得到可靠 AUC
- 二分类标签取元数据分组列的前两个水平（字母序），第一个为阴性，第二个为阳性
- `-d all`（=BVF）/ `--combination` 模式下三块特征合并（`BAC|`/`VIR|`/`FUN|` 前缀）；七组 B/V/F/BV/BF/VF/BVF 可选
- 真菌维度（`-d fungi`）为实验性功能，因真菌特征数通常较少
- SIAMCAT 的 `model.interpretation.plot` 输出 Top 20 特征重要性，供进一步筛选

## R 依赖包
`SIAMCAT`, `phyloseq`, `tidyverse`

## 官方链接
- Bioconductor: https://bioconductor.org/packages/SIAMCAT
- 论文: Wirbel et al. 2021, Nature Methods 18:627–638
