---
tool: ""                             # 必填 工具名（小写，如 humann3, kraken2）
dimension: ""                        # 必填 bacteria|virome|fungi|stats|shared
category: ""                         # 必填 taxonomy|functional|assembly|binning|annotation|qc|stats
author: ""                           # 可选 填写人姓名/ID
date: ""                             # 可选 YYYY-MM-DD
tags: []                             # 可选 标签列表，如 [parameter-tuning, troubleshooting]
scenario: []                         # 可选 适用场景标签
  # - gut-microbiome
  # - high-depth
  # - paired-end
  # - low-biomass
  # - cross-cohort
---

# 经验标题（一句话概括，如 "HUMAnN3 balanced vs fast 模式选择建议"）

## Scenario

> 一句话描述这个经验适用的分析场景：样本类型、数据量范围、分析目的。

示例：*肠道宏基因组，62M 双端 reads，物种级功能谱分析*

## Recommendation

明确写出推荐的做法、参数值、工具选择。尽量给出具体的命令行参数。

```bash
# 示例
--speed-mode balanced --threshold 1.0
```

## Rationale

解释为什么这样推荐——依据、原理、与其他选项的对比。

- **原理**：balanced 模式在 >20M reads 样本中平衡精度与召回率
- **对比**：fast 模式（3.0% 阈值）仅保留 ~5 个 SGBs，适合低深度样本
- **代价**：balanced 模式运行时间约 2-3 倍于 fast 模式

## Verified

验证记录：项目名 / 日期 / 结果状态

- Project_example, 2026-06-09, PASS
- CRC_project, 2026-05-15, PASS

## References（可选）

- 相关文献、文档链接
- 脚本 ID（如 13_bac_humann3.sh）
- 相关 issue 或讨论
