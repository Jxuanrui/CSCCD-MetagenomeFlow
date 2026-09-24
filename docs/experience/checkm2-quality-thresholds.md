---
tool: "checkm2"
dimension: "bacteria"
category: "quality-control"
author: "team"
date: "2026-06-12"
tags: [parameter-tuning, mag-quality, mimag, checkm2]
scenario: [gut-microbiome, mag-recovery, high-throughput-qc]
---

# CheckM2 MAG 质量分级阈值建议

## Scenario

> 适用于 DAS_Tool 或单一 binner 输出的 MAGs，需要快速评估 completeness、contamination 和 strain heterogeneity，并筛选进入 GTDB-Tk、dRep 或下游功能注释的 bins。

CheckM2 是 CheckM 的后继方案，使用机器学习模型预测 MAG 质量，适合高通量项目中对大量 bins 做统一 QC。

## Recommendation

项目脚本会收集 `result/binning/dastool/*/bins/*.fa`，运行 CheckM2，并筛选 completeness `>=50%` 且 contamination `<=10%` 的 MAGs：

```bash
# Run CheckM2 on DAS_Tool bins collected across samples.
bash scripts/37_bac_checkm2.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接运行时，先确认数据库已经下载并放在固定路径，然后显式指定 `--database_path`：

```bash
# Direct CheckM2 prediction.
checkm2 predict \
  --input result/binning/checkm2/input \
  -x fa \
  --output-directory result/binning/checkm2 \
  --database_path db/checkm2 \
  --threads 16 \
  --force
```

核心输出表包含 completeness、contamination 和 strain heterogeneity；当前脚本使用 `quality_report.tsv`，如果下游统一约定为 `report.tsv`，建议保留一个显式副本或软链接：

```bash
ln -sf quality_report.tsv result/binning/checkm2/report.tsv
```

质量分级建议按 MIMAG 标准统一写入报告：

```bash
# Add MIMAG-style quality tiers from CheckM2 report.
awk -F'\t' 'BEGIN{OFS="\t"}
  NR==1 {print $0, "quality_tier"; next}
  $2>=90 && $3<=5 {print $0, "high_quality"; next}
  $2>=50 && $3<=10 {print $0, "medium_quality"; next}
  {print $0, "low_quality"}' \
  result/binning/checkm2/quality_report.tsv \
  > result/binning/checkm2/quality_report.mimag.tsv
```

推荐阈值如下：high-quality 为 completeness `>=90%` 且 contamination `<=5%`；medium-quality 为 completeness `>=50%` 且 contamination `<=10%`；low-quality 为 completeness `<50%` 或污染超出 medium 标准。

## Rationale

- **为什么用 MIMAG 阈值**：completeness `>=90%` 且 contamination `<=5%`、以及 completeness `>=50%` 且 contamination `<=10%` 是 MAG 发表和跨项目比较最常用的质量分层。
- **为什么 CheckM2 适合高通量 QC**：CheckM2 使用神经网络和机器学习特征，不完全依赖 marker gene lineage placement，通常比 CheckM1 快约 10-25 倍。
- **为什么仍要保留 medium-quality MAGs**：肠道低丰度或新颖菌株可能无法达到 high-quality，但 medium-quality bins 对物种发现、泛基因组和功能筛查仍有价值。
- **为什么关注 contamination**：污染偏高会误导 GTDB-Tk 分类、功能注释、ANI 聚类和基因组流行病学解释，应优先过滤。
- **为什么看 strain heterogeneity**：strain heterogeneity 高可能表示多菌株混合或近缘物种误并，适合回到 binning/refinement 阶段复查。
- **当前脚本注意点**：`scripts/37_bac_checkm2.sh` 输出 `quality_report.tsv`，数据库路径为 `${REPO}/db/checkm2`，并把 medium 及以上 bins 复制到 `drep_input`。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_mags=0, Exit: 0, Duration: 600s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/37_bac_checkm2.sh`
- `scripts/36_bac_dastool.sh`
