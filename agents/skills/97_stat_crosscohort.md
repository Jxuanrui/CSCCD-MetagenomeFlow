---
id: "97_stat_crosscohort"
name: "Cross-Cohort Validation"
dimension: "statistics"
category: "crosscohort_validation"
description: "Enhanced cross-cohort validation with local multi-cohort support + 8 core visualizations"
version: "2.0"
author: "CSCCD-MetagenomeFlow Team"
date: "2026-06-17"
---

## Overview

Cross-cohort validation framework that supports:
- **Local multi-cohort mode**: Load from multiple local project directories
- **curatedMetagenomicData mode**: Load from online datasets (requires network)
- **8 core visualizations**: Forest plot, Waterfall, ROC overlay, UpSet, Feature stability, PCoA batch, Calibration curves, Effect correlation
- **Meta-analysis**: Random-effects model for pooled AUC estimation with I² heterogeneity

## Rule Type

`aggregate` (requires all cohorts' data loaded before execution)

## Inputs

| Name | Path Pattern | Required | Description |
|------|--------------|----------|-------------|
| SIAMCAT model | `${WORKDIR}/result/stat/bacteria/ml/siamcat_lasso.rds` | ✅ | Trained ML model from script 96 (E-1 aligned path) |
| Metadata | `${WORKDIR}/metadata.csv` | ✅ | Must contain: sample_id, GROUP_COL, cohort |
| Abundance table | `${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv` | ✅ | Per-cohort MetaPhlAn4 output；M-97-DIM 起：k__Bacteria s__ 终端行域过滤+0-1 相对丰度化（与 96 号 WC1R 口径一致，每队列 INFO 审计行） |

## Outputs

| Name | Path Pattern | Description |
|------|--------------|-------------|
| AUC summary | `${WORKDIR}/result/viz_crosscohort/auc_summary.tsv` | Cohort × AUC × CI × n_samples |
| Meta-analysis | `${WORKDIR}/result/viz_crosscohort/meta_analysis_results.tsv` | Pooled AUC + I² + Q statistic |
| Forest plot | `${WORKDIR}/result/viz_crosscohort/forest_plot_auc.pdf` | AUC per cohort with 95% CI |
| Waterfall plot | `${WORKDIR}/result/viz_crosscohort/waterfall_auc.pdf` | Cohorts ranked by AUC |
| ROC overlay | `${WORKDIR}/result/viz_crosscohort/roc_overlay_all_cohorts.pdf` | All cohort ROC curves on one plot |
| UpSet | `${WORKDIR}/result/viz_crosscohort/upset_shared_features.pdf` | Shared top 50 features |
| Stability heatmap | `${WORKDIR}/result/viz_crosscohort/heatmap_feature_stability.pdf` | Feature × Cohort presence matrix |
| PCoA batch | `${WORKDIR}/result/viz_crosscohort/pcoa_batch_effect.pdf` | PCoA colored by cohort |
| Calibration | `${WORKDIR}/result/viz_crosscohort/calibration_per_cohort.pdf` | Calibration curves grid |
| Effect correlation | `${WORKDIR}/result/viz_crosscohort/effect_correlation_matrix.pdf` | Cohort-to-cohort effect scatter |
| Sentinel | `crosscohort_done.txt` | 见上（declared） |

注：单 cohort 时 UpSet/效应相关图按结构性跳过显式 INFO；森林图为 0–1 全量程 + 0.5 参考线（AUC<0.5 可见）。

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--source` | `local` | Data source: `local` or `curated` |
| `--cohorts` | auto-detect | Comma-separated cohort names (for local mode) |
| `--train-cohort` | first cohort | Cohort to train on |
| `--test-cohorts` | all except train | Test cohorts (comma-separated) |
| `--condition` | `CRC` | Disease for curatedMGD: CRC/T2D/IBD |
| `--meta-analysis` | disabled | Enable random-effects meta-analysis |
| `--force` | disabled | Overwrite existing results |

## Dependencies

| Script/Tool | Purpose |
|-------------|---------|
| `96_stat_ml_siamcat.sh` | Provides trained SIAMCAT model |
| `11_bac_metaphlan4.sh` | Provides abundance tables per cohort |

## Benchmarks

| Metric | Value |
|--------|-------|
| Typical runtime | 5-15 min (3 cohorts × 50 samples) |
| Peak memory | ~8 GB |
| CPU usage | Single-threaded R |
| I/O | Read abundance tables + metadata, write 10-15 PDFs |

## Usage Examples

### Example 1: Local Multi-Cohort (Recommended)

```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Hospital_A \
  -r ~/Course/CSCCD-MetagenomeFlow \
  -m Project/Hospital_A/metadata.csv \
  -g Group \
  --source local \
  --cohorts "Hospital_A,Hospital_B,Hospital_C" \
  --train-cohort Hospital_A \
  --meta-analysis
```

### Example 2: Single Cohort (Framework Testing)

```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Project_example \
  -r ~/Course/CSCCD-MetagenomeFlow \
  -m Project/Project_example/metadata.csv \
  -g Group \
  --source local
```

### Example 3: curatedMetagenomicData (Requires Network)

```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Project_example \
  -r ~/Course/CSCCD-MetagenomeFlow \
  -m Project/Project_example/metadata.csv \
  -g Group \
  --source curated \
  --condition CRC
```

## Known Issues

| Issue | Workaround |
|-------|------------|
| curatedMGD requires network | Use `--source local` for offline environments |
| Requires ≥3 个 logit 有界的外部队列（AUC∈(0,1) 且 CI 不触 0/1；无界行以 INFO 剔除并写入 meta_analysis_results.tsv 的 n_dropped_unbounded/dropped_cohorts 列） for meta-analysis | Remove `--meta-analysis` flag for 1-2 cohorts |
| Metadata must have `cohort` column | Add cohort labels manually or use single-cohort mode |
| Large cohorts (>200 samples) slow | Consider downsampling or increase timeout |

## Integration Status

- **Status**: `integrated`
- **Snakemake rule**: `pipeline/rules/crosscohort.smk::crosscohort_validation`
- （原 Skill card yaml / Documentation / Test script 引用指向不存在的文件，已删除——监工复核指出；本 .md 即唯一技能文档）

## Related Skills

- `96_stat_ml_siamcat`: ML biomarker discovery (prerequisite)
- `95a_stat_batch_correct`: Batch correction methods
- `92_stat_differential`: Differential abundance (future integration for feature stability)

## Validation

Tested with（2026-09-30 A-3 验收，证据归档 .claude/reviews/a3_crosscohort_evidence_20260930.md）:
- 构造数据方向断言（真值 AUC 0.20 正确报 0.20；旧 auto 调用报 0.80）
- 双队列 e2e（训练 0.965 / 反相外部 0.035=1−0.965 未被翻转，森林图全量程可见）
- P01 隔离副本 96 SKIPPED → 97 SKIPPED exit 0
- 失败注入（标签集不匹配/缺 test cohort）→ FAILED + exit 1 + 无哨兵
- 单 cohort 条件产出与 8 图声明一致

## Future Enhancements

1. **Differential abundance integration**: Read per-cohort LEfSe/MaAsLin2 results → effect direction consistency check
2. **Feature stability scoring**: Quantitative score = (# cohorts significant) / (total cohorts)
3. **Interactive HTML report**: `rmarkdown` report with all plots + interpretation text
4. **Virus/Fungi support**: Extend to vOTU and fungal abundance tables
5. **Holdout validation**: Train on cohort A → test on B/C/D separately (already partially implemented)


## 限制（M-97-DIM 审后标注，2026-10-01）

- **curated 模式禁用**（M-97-CUR）：curatedMetagenomicData 路径用短物种名（`rownames="short"`）且无域过滤/relab——与 96 训练特征名不匹配，结果大概率无效但不报错；修复属技术路线级另行拍板
- **多维度模型不可验证**（M-96-Q2）：ML_DIR 硬编码 `bacteria/ml`，仅 B 组（纯细菌）模型可跨队列验证；B-3 七组中其余六组只报队列内 CV
- **描述性图口径变更**（M-97-DIM 起）：热图/PCoA/效应相关图基于"s__ 细菌行+0-1 relab"数据，不可与旧产物直接比较
