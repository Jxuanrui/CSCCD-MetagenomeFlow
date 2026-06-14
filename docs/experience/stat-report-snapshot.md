---
tool: "stat-report"
dimension: "stats"
category: "stats"
author: ""
date: "2026-06-14"
tags: [report, snapshot, collaboration]
scenario: [aggregate, markdown-report, pi-review]
---

# 统计结果快照报告的使用策略建议

## Scenario

> 适用于 91-97 统计分析基本完成后，用 `98_stat_report.sh` 扫描 `result/stat/`，汇总 AUC、diversity stats、top features 和图件，生成 `result/stat/report/report_YYYYMMDD.md`；可用 `-o OUTPUT_DIR` 改输出目录，`--force` 覆盖旧报告。

## Recommendation

默认建议在每次准备向合作者或 PI 汇报前运行 98，生成一个带时间戳的 Markdown 快照。它适合作为“当前统计结果索引”，不适合作为新的统计分析步骤。

推荐命令骨架如下：

```bash
bash scripts/98_stat_report.sh \
  -w PROJECT -r REPO \
  --force
```

如果需要把报告放到共享目录或项目汇报目录，使用 `-o OUTPUT_DIR`。不建议手工复制单个表格和图片给合作者，因为容易遗漏分析状态、失败标记或版本信息。

## Required Inputs

脚本读取 `result/stat/` 下已有结果，包括 diversity、differential、batch、network、ML、cross-cohort 和 visualization 等模块输出。它是 aggregate step，不要求单独输入某个统计表。

建议在 91-97 步骤完成后运行；若部分模块尚未完成，报告仍可生成，但对应位置只能显示缺失或空结果，不能代表完整分析。

## Outputs

默认输出目录为 `result/stat/report/`，主要产物是时间戳 Markdown 文件。

- `report_YYYYMMDD.md`：快照报告，汇总当前扫描到的关键统计输出。
- AUC tables：收集 SIAMCAT 和 cross-cohort 的 AUC 结果。
- diversity stats：汇总 alpha/beta diversity 相关统计结果。
- top features：整理差异分析或机器学习中的关键特征。
- figure index：列出 `result/stat/` 下可用于汇报的 PDF/PNG 图件。

## Rationale

- **为什么在 91-97 后运行**：报告脚本只汇总已有结果，越靠后运行越能覆盖完整统计链路。
- **为什么输出 Markdown**：Markdown 适合快速审阅、版本管理和进一步改写成汇报材料。
- **为什么需要 timestamp**：多轮分析会产生多版结果，时间戳可以保留审阅历史并减少覆盖风险。
- **为什么强调它不是统计分析**：98 不重新计算显著性、AUC 或多样性指标；它只是把已发现的结果组织成可共享快照。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证
