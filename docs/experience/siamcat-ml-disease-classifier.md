---
tool: "siamcat-ml"
dimension: "stats"
category: "stats"
author: ""
date: "2026-06-11"
tags: [machine-learning, biomarker, disease-classifier]
scenario: [cross-cohort, gut-microbiome, high-depth]
---

# SIAMCAT 疾病分类模型的默认建模策略建议

## Scenario

> 适用于病例对照或分组明确的宏基因组项目，希望构建可解释的分类模型，而不是只做单变量差异检验。

本项目脚本面向的是聚合矩阵层的机器学习，输入来自 merged taxonomy、病毒表或联合特征。

真正影响结果可信度的不是”模型能不能跑通”，而是样本数、分组定义、特征过滤和交叉验证设计。

**关键参数速查**：`--folds 10`（10 折交叉验证，默认）；训练模型：lasso / ridge / enet / RF（random forest）；评估指标：ROC-AUC（主要）+ PR-AUC；至少 10 个重叠样本；主输出 `siamcat_auc_summary.tsv`（各模型 AUC 对比）+ `siamcat_top_features.tsv`（前 20 特征）。

## Recommendation

默认推荐先跑 `-d bacteria --folds 10`，把细菌 taxonomy 作为基线模型。

推荐命令骨架如下：

```bash
bash 96_stat_ml_siamcat.sh \
  -w PROJECT -r REPO -t 16 \
  -m metadata.csv -g disease \
  -d bacteria --folds 10
```

在样本数刚过下限时，不建议一开始就使用 `-d all`；先确认细菌模型是否稳定，再尝试细菌+病毒联合输入。

交叉验证折数建议保持 `10`；如果总样本量偏少，可下调到 `5`，但不建议为了追求高 AUC 把折数随意调大。

分组列 `-g` 应尽量代表明确的生物学标签，例如 disease/control；不要把批次、中心或测序平台直接当预测目标。

脚本默认训练 `lasso`、`ridge`、`enet`、`randomForest` 四种模型，正式报告优先比较 `siamcat_auc_summary.tsv`，不要只挑最好看的单图。

建模前建议先检查 confounder 图；若批次或年龄在标签上高度不平衡，先做批次评估，再解释模型特征。

## Rationale

- **为什么细菌矩阵是默认起点**：它在本项目中最稳定、样本覆盖通常最好，也最容易获得足够重叠样本数。
- **为什么不先上 `all`**：联合特征会增加维度和稀疏性，在样本数有限时更容易过拟合，且难以解释性能提升是否真实。
- **为什么 `10-fold` 合理**：这是泛用的稳定折中，既能提供较充分的训练样本，又能保留一定测试覆盖。
- **为什么少样本时改 `5-fold`**：每折测试样本太少会让 AUC 波动很大，适当降低折数比机械维持 `10` 更稳。
- **为什么要看多模型比较**：lasso 强调稀疏可解释，ridge 更稳，enet 介于两者之间，random forest 对非线性更敏感；单模型结论不够完整。
- **为什么脚本先做基础过滤**：`rowMeans(mat > 0) >= 0.05` 与最低相对丰度门槛可以减少纯噪声特征，降低模型训练负担。
- **为什么要检查 confounders**：高 AUC 不一定代表疾病信号，可能只是模型学会了批次、中心或年龄分布。
- **为什么正类水平要谨慎**：脚本默认取第二个 factor level 作为 positive class，元数据编码顺序会影响标签方向与解释。
- **为什么至少要 `10` 个重叠样本**：脚本本身就把这个作为下限，再低时机器学习输出几乎没有泛化意义。
- **为什么结果要保留 RDS 与解释图**：后续复核需要知道模型对象、AUC 与前 20 个解释特征，而不是只剩一个摘要文本。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/96_stat_ml_siamcat.sh`
- `agents/skills/96_stat_ml_siamcat.yaml`
- 输出主表：`result/stat/ml/siamcat_auc_summary.tsv`
- 输出状态：`result/stat/ml/siamcat_status.tsv`
