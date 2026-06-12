---
tool: "batch-correction"
dimension: "stats"
category: "stats"
author: ""
date: "2026-06-11"
tags: [batch-correction, cross-cohort, method-comparison]
scenario: [cross-cohort, gut-microbiome, high-depth]
---

# 宏基因组批次校正方法的分层使用建议

## Scenario

> 适用于跨中心、跨批次或跨平台的菌群丰度矩阵，需要比较多种批次校正方法而不是押注单一算法。

本项目脚本不会只输出一个“校正后真值矩阵”，而是并行生成 ConQuR、MMUPHin、ComBat、RUVIII、PercentileNorm、BMC 和 DEBIAS-M 的结果。

因此经验重点不是宣布谁永远最好，而是给出默认优先级与排除规则。

## Recommendation

默认推荐顺序：先看 `MMUPHin`、`ConQuR`、`ComBat` 三类主结果，再把其他方法作为敏感性分析。

推荐调用方式如下：

```bash
bash 95a_stat_batch_correct.sh \
  -w PROJECT -r REPO -t 16 \
  -m metadata.csv -b batch \
  -g disease
```

`-b` 必须是真正的批次变量，例如 center、run、platform；不要把 disease group 误填成 batch。

若存在明确生物学分组，建议始终传 `-g`；这样方法在校正时更不容易把真实组间差异一起抹掉。

正式报告优先从 `batch_correction_summary.tsv` 和 `batch_correction_status.tsv` 看哪些方法成功，再进入下游评估。

如果样本数很少、批次数很多或批次与分组几乎完全共线，优先保守解释，必要时只做批次评估而不输出“已校正矩阵”结论。

DEBIAS-M 建议视为可选增强项，不要把它作为是否完成批次校正的唯一判据，因为它额外依赖 Python 侧环境与模块可用性。

## Rationale

- **为什么并行多方法而不是单方法**：不同校正器对零膨胀、组成型数据和协变量控制的假设不同，宏基因组数据很少有绝对通吃方案。
- **为什么优先看 MMUPHin 和 ConQuR**：这两类方法更贴近微生物组数据结构，通常比把丰度矩阵直接当普通表达矩阵更合适。
- **为什么 ComBat 仍值得保留**：它是经典基线法，常用于和微生物组专用方法做对照，帮助判断校正是否过度或不足。
- **为什么一定要传生物学分组列**：没有 `-g` 时，校正器更容易把标签相关信号当批次噪声处理掉。
- **为什么完全共线时要谨慎**：若某个批次只包含病例或只包含对照，任何批次校正都无法可靠区分技术效应与生物效应。
- **为什么脚本允许方法局部失败**：不同 R 包版本、矩阵稀疏性和样本结构会导致某些方法报错；保存 `.FAILED` 和记状态比整步中断更实用。
- **为什么先看状态表再做下游**：并不是每个方法都一定成功，盲目读取所有输出会把失败占位文件或异常矩阵带入统计分析。
- **为什么 DEBIAS-M 是增强项**：它依赖额外 Python 入口，环境耦合更高，适合作为补充参考，而不是主流程唯一支柱。
- **为什么要把批次校正放在 merged taxonomy 层**：输入样本和特征对齐后，多方法比较更公平，也便于后续可视化和模型评估。
- **为什么结果需要后续评估**：校正成功不等于生物学合理，仍需结合 `95b` 的批次评估、PCA/PCoA 和已知标签检查是否过校正。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/95a_stat_batch_correct.sh`
- `agents/skills/95a_stat_batch_correct.yaml`
- 输出主表：`result/stat/batch/batch_correction_summary.tsv`
- 下游评估：`scripts/95b_stat_batch_evaluate.sh`
