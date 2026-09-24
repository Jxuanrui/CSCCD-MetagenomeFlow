# 统计报告生成

**环境**: bash + Rscript | **脚本**: `scripts/98_stat_report.sh`

## 功能
按需生成带时间戳的 Markdown 格式分析结果快照报告，汇总 diversity / differential / network / batch / ML / cross-cohort 各模块的状态和关键输出。

## 用法

```bash
# 默认输出到 result/stat/report/
bash scripts/98_stat_report.sh -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 指定输出目录
bash scripts/98_stat_report.sh -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -o /custom/path
```

## 报告内容

- **QA Summary**: 检测到的 `.FAILED` 哨兵文件数量
- **Diversity**: `diversity_alpha_summary.tsv` 前 6 行预览
- **Differential Abundance**: `differential_summary.tsv` 前 6 行预览
- **Networks**: `network_summary.tsv` 或 `network_summary.txt` 内容
- **Batch**: `bacteria/batch/evaluation_report.tsv` 前 8 行预览
- **ML**: `bacteria/ml/siamcat_auc_summary.tsv` 或 `bacteria/ml/siamcat_done.txt` 内容
- **Cross-cohort**: `crosscohort_auc.tsv` 或 `crosscohort_done.txt` 内容
- **Figures**: 自动发现 `result/stat/` 下的所有 PDF/PNG 图

## 输出

| 文件 | 内容 |
|------|------|
| `report_{YYYYMMDD}_{HHMMSS}.md` | 带时间戳的 Markdown 报告 |

## 使用场景

- 分析完成后快速生成报告分享给合作者
- 多时间点比较分析结果变迁
- 生成论文补充材料草稿

## 注意事项
- 报告是快照性质的，不修改任何分析结果
- 若某模块尚未运行，报告中对应部分显示 `Missing:` 标记
- 每次运行生成新报告，历史报告保留（文件名含时间戳）
