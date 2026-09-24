---
tool: "metabat2"
dimension: "bacteria"
category: "binning"
author: "team"
date: "2026-06-12"
tags: [parameter-tuning, mag-binning, abundance-depth, metabat2]
scenario: [gut-microbiome, assembled-contigs, mag-recovery]
---

# MetaBAT2 MAG 分箱参数建议

## Scenario

> 适用于 MEGAHIT 等组装器产出的 metagenome contigs，需要基于 tetranucleotide composition 和覆盖度信息恢复 MAGs。

典型输入是 `result/assembly/megahit/{sample}/{sample}.contigs.fa` 和由 clean reads 回贴得到的 contig depth 文件。肠道单样本常见产出约 `5-50` 个 MAGs，具体取决于测序深度、物种丰富度、组装连续性和样本混杂程度。

## Recommendation

项目脚本已经把 MetaBAT2 最小 contig 长度设为 `1500 bp`，并使用上游覆盖度文件：

```bash
# Run MetaBAT2 through the project wrapper.
bash scripts/33_bac_metabat2.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接运行时，推荐显式设置 `-m 1500`，并在低丰度菌株恢复场景中关闭 CV sum 过滤：

```bash
# Generate depth from paired-end BAM alignments.
jgi_summarize_bam_contig_depths \
  --outputDepth result/binning/metabat2/S01/depth.txt \
  result/binning/align/S01/*.bam

# Run MetaBAT2 with a less strict contig length threshold.
metabat2 \
  -i result/assembly/megahit/S01/S01.contigs.fa \
  -a result/binning/metabat2/S01/depth.txt \
  -o result/binning/metabat2/S01/bin \
  -m 1500 \
  --minCVSum 0 \
  --numThreads 16
```

多样本项目建议尽量提供跨样本覆盖度，而不是只用单样本 depth。可以采用 co-assembly 后多样本回贴，也可以对 single-sample assembly 做 cross-mapping，再把多个 BAM 汇总为同一个 depth matrix：

```bash
# Summarize cross-sample depth for one contig set.
jgi_summarize_bam_contig_depths \
  --outputDepth result/binning/metabat2/cohort/depth.txt \
  result/binning/align/S01/*.bam \
  result/binning/align/S02/*.bam \
  result/binning/align/S03/*.bam

metabat2 \
  -i result/assembly/coassembly/cohort.contigs.fa \
  -a result/binning/metabat2/cohort/depth.txt \
  -o result/binning/metabat2/cohort/bin \
  -m 1500 \
  --minCVSum 0 \
  --numThreads 32
```

## Rationale

- **为什么最小 contig 长度用 1500 bp**：MetaBAT2 默认常用 2500 bp 对复杂肠道样本可能偏严；1500 bp 能纳入更多中短 contigs，提高 MAG completeness。
- **为什么设置 `--minCVSum 0`**：低丰度或覆盖度波动较小的 bins 可能被 CV 过滤排除，关闭该过滤有助于恢复低丰度菌株。
- **为什么必须使用 depth**：只靠序列组成难以区分 GC 和 tetranucleotide composition 接近的物种；paired-end BAM depth 能提供独立的丰度维度。
- **为什么推荐多样本覆盖度**：跨样本丰度变化能显著增强相近基因组的可分性，通常比单样本 depth 更利于准确 binning。
- **为什么 yield 波动很大**：肠道样本 richness、strain complexity、测序深度、宿主去除、组装 N50 和污染水平都会影响 MAG 数量，`5-50` 个 MAGs 每样本属于常见范围。
- **当前脚本注意点**：`scripts/33_bac_metabat2.sh` 使用 `-m 1500` 和 `result/binning/coverm/{sample}/depth.txt`；如果需要 `--minCVSum 0` 或 jgi depth，需要在直接命令或后续脚本版本中显式加入。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: notes=0 bins across all 6 samples; short-read assemblies insufficient depth for binning, n_bins_total=0, Exit: 0, Duration: 720s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/33_bac_metabat2.sh`
- `scripts/32_bac_coverm_depth.sh`
