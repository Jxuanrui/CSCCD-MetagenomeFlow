---
id: "97_stat_crosscohort"
name: "Cross-Cohort Validation"
dimension: "statistics"
category: "crosscohort_validation"
description: "Enhanced cross-cohort validation with local multi-cohort support + 8 core visualizations"
version: "2.0"
author: "MaxMetagenome Team"
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
| SIAMCAT model | `${WORKDIR}/result/stat/ml/siamcat_lasso.rds` | ✅ | Trained ML model from script 96 |
| Metadata | `${WORKDIR}/metadata.csv` | ✅ | Must contain: sample_id, GROUP_COL, cohort |
| Abundance table | `${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv` | ✅ | Per-cohort MetaPhlAn4 output |

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
| Sentinel | `${WORKDIR}/result/viz_crosscohort/crosscohort_done.txt` | Completion marker |

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
  -r ~/Course/Maxmetagenome \
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
  -r ~/Course/Maxmetagenome \
  -m Project/Project_example/metadata.csv \
  -g Group \
  --source local
```

### Example 3: curatedMetagenomicData (Requires Network)

```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Project_example \
  -r ~/Course/Maxmetagenome \
  -m Project/Project_example/metadata.csv \
  -g Group \
  --source curated \
  --condition CRC
```

## Known Issues

| Issue | Workaround |
|-------|------------|
| curatedMGD requires network | Use `--source local` for offline environments |
| Requires ≥3 cohorts for meta-analysis | Remove `--meta-analysis` flag for 1-2 cohorts |
| Metadata must have `cohort` column | Add cohort labels manually or use single-cohort mode |
| Large cohorts (>200 samples) slow | Consider downsampling or increase timeout |

## Integration Status

- **Status**: `integrated`
- **Snakemake rule**: `pipeline/rules/crosscohort.smk::crosscohort_validation`
- **Skill card**: `agents/skills/97_stat_crosscohort.yaml`
- **Documentation**: `docs/97_crosscohort_usage.md`
- **Test script**: `scripts/test_97_crosscohort.sh`

## Related Skills

- `96_stat_ml_siamcat`: ML biomarker discovery (prerequisite)
- `95a_stat_batch_correct`: Batch correction methods
- `92_stat_differential`: Differential abundance (future integration for feature stability)

## Validation

Tested with:
- Mock 3-cohort setup (Project_example × 3)
- Local multi-cohort mode with meta-analysis
- All 8 visualizations generated successfully
- Meta-analysis I² and pooled AUC calculated correctly

## Future Enhancements

1. **Differential abundance integration**: Read per-cohort LEfSe/MaAsLin2 results → effect direction consistency check
2. **Feature stability scoring**: Quantitative score = (# cohorts significant) / (total cohorts)
3. **Interactive HTML report**: `rmarkdown` report with all plots + interpretation text
4. **Virus/Fungi support**: Extend to vOTU and fungal abundance tables
5. **Holdout validation**: Train on cohort A → test on B/C/D separately (already partially implemented)
