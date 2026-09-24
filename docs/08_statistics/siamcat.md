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

# 全维度交叉（细菌+病毒联合）
bash scripts/96_stat_ml_siamcat.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -g group -d all

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
| `-d` | 否 | `bacteria` | 维度：`bacteria` / `virus` / `fungi` / `all` |
| `--folds` | 否 | `10` | 交叉验证折数 |
| `--force` | 否 | — | 强制重新运行 |

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
| bacteria | `result/metaphlan4/merged/taxonomy.tsv` |
| virus | `result/virus/votu/table/vOTU_table_ann.txt` |
| fungi | `result/fungi/metaphlan4/{sample}/*_profile.txt` |
| all | 细菌+病毒特征合并（前缀 BAC| / VIR|） |

## 输出

默认 `-d bacteria` 输出到 `result/stat/bacteria/ml/`；`-d virus` / `-d fungi` 分别输出到对应维度的 `ml/` 子目录；`-d all` 输出到 `result/stat/ml/`。

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
特征表 → 过滤（丰度≥0.005% + 存在率≥5%）→ log.std 标准化
 → K 折 CV split → 训练 4 种模型 → AUC 评估 → 特征重要性排序
```

## 注意事项
- 需要每组 ≥5 个样本，总样本 ≥10 才能得到可靠 AUC
- 二分类标签取元数据分组列的前两个水平（字母序），第一个为阴性，第二个为阳性
- `-d all` 模式下细菌和病毒特征合并运行，每个特征加 `BAC|` / `VIR|` 前缀区分
- 真菌维度（`-d fungi`）为实验性功能，因真菌特征数通常较少
- SIAMCAT 的 `model.interpretation.plot` 输出 Top 20 特征重要性，供进一步筛选

## R 依赖包
`SIAMCAT`, `phyloseq`, `tidyverse`

## 官方链接
- Bioconductor: https://bioconductor.org/packages/SIAMCAT
- 论文: Wirbel et al. 2021, Nature Methods 18:627–638
