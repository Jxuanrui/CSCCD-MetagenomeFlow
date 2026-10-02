---
tool: "CoverM"
dimension: "bacteria"
category: "binning"
author: ""
date: "2026-06-13"
tags: [binning, coverm, depth, bam, abundance]
scenario: [gut-microbiome, assembled-contigs, mag-recovery]
---

# CoverM contig 深度计算建议

## Scenario

> 适用于每个样本已经完成组装和质控，需要把 clean reads 回贴到同一样本的 contigs 上，生成分箱所需的 contig depth 与排序 BAM。这个步骤是 MetaBAT2、MaxBin2 和 SemiBin2 之前的共同前置条件。

典型输入包括 `{sample}.contigs.fa` 与 kneaddata 清洗后的双端 reads，典型输出包括 `depth.txt` 和排序后的 `{sample}.bam`。前者为 abundance-aware binner 提供每条 contig 的覆盖度信息，后者则被 SemiBin2 直接消费，因此这一环节的输出质量会直接影响后面所有 MAG recovery 结果。

深度计算必须用 reads 回贴到它们来源的同一份 assembly，而不是随意映射到别的样本 contigs。多样本联合深度通常能提升分箱可分性，但计算成本更高；对单样本独立分析流程，single-sample mapping 仍是最常见、最稳妥的标准做法。

**关键参数速查**：Tool = `CoverM`；Depends on = `{sample}.contigs.fa` + kneaddata clean reads；Key params = `coverm contig --methods metabat`, `--min-read-percent-identity 0.97`, `--min-read-aligned-percent 0.75`；Outputs = `depth.txt`（核心字段为 contig / mean depth / variance）+ sorted `{sample}.bam`；Downstream = `depth.txt` for MetaBAT2 / MaxBin2, BAM reused by SemiBin2；Rule = map reads back to the SAME assembly

## Recommendation

项目包装脚本会先生成 BAM，再从 BAM 计算 MetaBAT-compatible depth 表，建议按样本直接运行：

```bash
# Generate sorted BAM and contig depth for one sample.
bash scripts/32_bac_coverm_depth.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果要手动复现实验逻辑，推荐把“比对生成 BAM”和“从 BAM 提取深度”分成两步写清楚：

```bash
# Map cleaned paired-end reads back to the same sample assembly.
coverm make \
  -p minimap2-sr \
  -t 16 \
  -r result/assembly/megahit/S01/S01.contigs.fa \
  -1 result/kneaddata/S01/S01_1.kneaddata.fastq.gz \
  -2 result/kneaddata/S01/S01_2.kneaddata.fastq.gz \
  -o result/binning/coverm/S01

# Calculate MetaBAT-style depth summary from the sorted BAM.
coverm contig \
  -t 16 \
  --methods metabat \
  --min-read-percent-identity 0.97 \
  --min-read-aligned-percent 0.75 \
  --bam-files result/binning/coverm/S01/S01.bam \
  -o result/binning/coverm/S01/depth.txt
```

仓库当前脚本使用的是两步式 CoverM 工作流，并把 BAM 命名规范化到 `result/binning/coverm/{sample}/{sample}.bam`。如果后面还要跑 SemiBin2，就不要只保留 `depth.txt`，必须同时确认 BAM 已排序且可索引，否则会在分箱阶段才暴露问题。

## Rationale

- **为什么必须回贴到同一份 assembly**：覆盖度是相对具体 contig 集定义的，把 reads 映射到别的组装结果会破坏 abundance 信号，直接降低分箱可靠性。
- **为什么 `depth.txt` 是三类分箱器的共同前置**：MetaBAT2 和 MaxBin2 都显式依赖 contig abundance，缺少深度信息时很难把组成相近的 contigs 分开。
- **为什么还要保留 BAM**：SemiBin2 不只要深度摘要，还需要原始比对证据，因此 BAM 不是中间垃圾文件，而是后续机器学习分箱的正式输入。
- **为什么推荐单样本 mapping 作为默认方案**：single-sample depth 计算简单、解释直接、资源可控，适合大多数逐样本 MAG recovery 流程。
- **为什么多样本 depth 可能更强**：当同一基因组在不同样本中的丰度变化明显时，跨样本协方差能帮助分开组成相似但生态位不同的群体。
- **为什么加入 identity 和 alignment percent 过滤**：过低相似度或过短局部比对会把噪音映射写进深度矩阵，尤其在近缘菌丰富的肠道数据中更容易误导分箱。
- **为什么 BAM 必须排序并最好带索引**：后续工具通常假设 BAM 已排序，部分版本还会直接检查索引文件；提前标准化能减少后面隐性报错。
- **为什么该步骤经常被低估**：很多分箱问题表面上出在 MetaBAT2 或 SemiBin2，实际上根因是深度矩阵质量差、输入 reads 不匹配或 BAM 生成流程不规范。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/32_bac_coverm_depth.sh`
- `agents/skills/32_bac_coverm_depth.yaml`
