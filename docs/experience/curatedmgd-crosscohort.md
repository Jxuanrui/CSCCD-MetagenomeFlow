---
tool: "curatedmgd-crosscohort"
dimension: "stats"
category: "stats"
author: ""
date: "2026-06-14"
tags: [cross-cohort, curatedmetagenomicdata, siamcat]
scenario: [external-validation, public-cohort, biomarker]
---

# curatedMetagenomicData 跨队列验证的默认策略建议

## Scenario

> 适用于 96 SIAMCAT 模型已完成后，用 `97_stat_curatedMGD.sh` 读取 curatedMetagenomicData 公共队列，经 MMUPHin 批次校正后做外部 holdout 验证；必需 `-m metadata.csv -g GROUP_COL`，可用 `-c CONDITION` 指定疾病标签、`--augment-n N` 加入外部训练样本。

## Recommendation

默认把 97 作为 SIAMCAT 模型的外部泛化验证步骤，而不是替代 96 的内部交叉验证。正式写作中应优先报告 cross-cohort AUC 和 ROC 图，因为它们更接近独立队列验证。

推荐命令骨架如下：

```bash
bash scripts/97_stat_curatedMGD.sh \
  -w PROJECT -r REPO \
  -m metadata.csv -g disease \
  -c CRC --augment-n 50
```

`-g` 应指向本队列的 disease/control 分组列；`-c` 应与研究疾病一致。只有在明确希望把公共队列样本并入训练时，才使用 `--augment-n N`，否则先做纯外部验证更容易解释。

## Required Inputs

本步骤依赖 96 脚本已经完成，并且 `result/stat/ml/` 下存在 SIAMCAT 模型或完成标记。没有 96 的模型对象时，97 无法进行 holdout validation。

必需参数包括 `-m metadata.csv` 和 `-g GROUP_COL`。`-m` 是本研究队列元数据，`-g` 是疾病/对照或其他二分类标签列；`-c CONDITION` 用于指定外部公共队列中的疾病标签。

## Outputs

输出重点是外部队列验证性能，而不是重新发现一组全新的差异特征。

- `crosscohort_auc.tsv`：SIAMCAT 模型在 curatedMetagenomicData 外部队列上的 AUC 汇总。
- ROC plots：外部 holdout validation 的 ROC 曲线，用于论文图或补充材料。
- `crosscohort_done.txt`：跨队列验证完成标记。

如使用 `--augment-n N`，报告中需要注明外部样本被加入训练集的数量，避免把增强训练和纯外部验证混为一谈。

## Rationale

- **为什么必须先完成 96**：97 的核心任务是验证已训练的 SIAMCAT 模型，而不是从零开始训练分类器。
- **为什么使用 curatedMetagenomicData**：公共宏基因组队列提供独立中心、不同批次和不同研究设计的数据，是检验 biomarker 泛化性的最低门槛。
- **为什么需要 MMUPHin**：跨研究数据常受批次和队列差异影响，批次校正能降低技术差异对模型验证的干扰。
- **为什么谨慎使用 `--augment-n`**：加入外部样本可能提升模型稳定性，但也改变了验证设定；正式结果中应与纯 holdout AUC 分开解释。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证
