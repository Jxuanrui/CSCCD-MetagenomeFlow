---
tool: "Salmon v1.x"
dimension: "bacteria"
category: "gene-abundance"
author: ""
date: "2026-06-13"
tags: [salmon, gene-abundance, tpm, numreads, quantification]
scenario: [gut-microbiome, paired-end, shotgun-metagenomics]
---

# Salmon 基因丰度定量参数建议

## Scenario

> 适用于已经构建非冗余基因集并完成 Salmon index 的项目，需要把每个样本的 kneaddata clean reads 定量到同一套 gene FASTA。

**关键参数速查**：Tool = `Salmon v1.x`；Depends on = Salmon index from `salmon_build` step + kneaddata reads；Key params = `--libType A`/`-l A`, `--validateMappings`, `--gcBias`, `--threads 16`; Outputs = `quant.sf` (TPM + NumReads), aggregated gene abundance table。

解释结果时要区分 TPM 和 NumReads：TPM 更适合描述样本内或跨样本相对丰度趋势，差异分析和统计模型通常应优先使用 `NumReads` 或由它汇总的 count 矩阵。`salmon_build` 必须使用与注释和丰度矩阵同一套 gene FASTA，否则基因 ID 无法可靠对应。

## Recommendation

项目脚本按样本运行，输入是 kneaddata 双端 reads 和已经构建好的 Salmon index：

```bash
# Quantify one sample against the project gene catalog index.
bash scripts/20_bac_salmon_quant.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果直接运行 Salmon，建议保留自动文库类型、选择性比对和 GC bias 校正：

```bash
# Direct Salmon quant command for paired-end metagenomic reads.
salmon quant \
  -i result/assembly/salmon/index \
  --libType A \
  --threads 16 \
  --meta \
  --validateMappings \
  --gcBias \
  -1 result/kneaddata/S01/S01_1.kneaddata.fastq.gz \
  -2 result/kneaddata/S01/S01_2.kneaddata.fastq.gz \
  -o result/assembly/salmon/S01
```

所有样本完成后，再用 `salmon quantmerge` 分别合并 TPM 和 NumReads：

```bash
# Merge per-sample quant.sf files into project-level matrices.
salmon quantmerge \
  --quants result/assembly/salmon/* \
  -o result/assembly/salmon/gene.TPM.tsv

salmon quantmerge \
  --quants result/assembly/salmon/* \
  --column NumReads \
  -o result/assembly/salmon/gene.NumReads.tsv
```

## Rationale

- **为什么必须先运行 salmon_build**：`salmon quant` 只接受索引目录，索引里的 transcript/gene ID 决定后续 `quant.sf` 的行名。
- **为什么 index 必须来自同一套 gene FASTA**：如果注释、CD-HIT、Salmon index 使用不同 FASTA，丰度表和功能表会出现 ID 错配。
- **为什么用 `--libType A`**：宏基因组文库方向性可能不稳定，自动检测比硬编码 `IU` 或 `ISR` 更稳妥。
- **为什么保留 `--validateMappings`**：Salmon v1.x 中选择性比对能减少相似基因之间的错误分配，尤其适合同源基因丰富的基因目录。
- **为什么建议 `--gcBias`**：不同基因 GC 含量差异会影响 reads 覆盖，GC 校正有助于降低系统性定量偏差。
- **为什么输出同时看 TPM 和 NumReads**：TPM 适合相对丰度展示，NumReads 更接近原始计数，适合差异分析工具的输入习惯。
- **为什么用 `--meta`**：宏基因组样本不是转录组表达建模，meta 模式使用更适合 metagenomic quantification 的优化设定。
- **为什么最后统一合并矩阵**：单样本 `quant.sf` 便于排错，项目级 TPM/count table 才适合关联分析、功能汇总和可视化。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/20_bac_salmon_quant.sh`
- `agents/skills/20_bac_salmon_quant.yaml`
- `scripts/19_bac_salmon_build.sh`
