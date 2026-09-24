---
tool: "fastp"
dimension: "bacteria"
category: "quality-control"
author: "team"
date: "2026-06-12"
tags: [parameter-tuning, quality-control, adapter-trimming, paired-end]
scenario: [gut-microbiome, paired-end, shotgun-metagenomics]
---

# fastp 双端 WGS 原始数据质控参数建议

## Scenario

> 适用于肠道宏基因组 paired-end WGS 原始 reads 的第一步质控，包括接头去除、低质量碱基过滤、过短 reads 过滤和 QC 报告留档。

典型流程是先运行 fastp，再把 clean reads 交给 kneaddata 去宿主、分类分析、组装和分箱。对于肠道 shotgun metagenomics，推荐以数据保留为优先，不要使用过严的质量或长度阈值。

## Recommendation

项目脚本已经固定使用 Q20、最小长度 50 bp、双端接头自动检测，并保留 HTML 与 JSON 报告：

```bash
# Run the project wrapper.
bash scripts/01_qc_fastp.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果直接运行 fastp，建议把关键参数显式写入命令，便于审计和复现：

```bash
# Direct fastp command for paired-end gut metagenome reads.
fastp \
  -i S01_1.fastq.gz \
  -I S01_2.fastq.gz \
  -o S01_clean_1.fastq.gz \
  -O S01_clean_2.fastq.gz \
  --qualified_quality_phred 20 \
  --unqualified_percent_limit 40 \
  --length_required 50 \
  --detect_adapter_for_pe \
  --correction \
  --json S01.fastp.json \
  --html S01.fastp.html \
  --thread 16
```

建议长期保留 `*.html` 和 `*.json`。HTML 适合人工检查，JSON 适合批量提取 total reads、passed reads、Q20、Q30、GC 和 duplication rate 等指标。

## Rationale

- **为什么用 Q20**：Q20 对应约 1% 碱基错误率，在 shotgun metagenomics 中能平衡测序错误控制与低丰度物种 reads 保留；过高阈值会显著增加数据损失。
- **为什么允许 40% 低质量碱基**：`--unqualified_percent_limit 40` 避免因为局部质量下降而整条 read 被过度丢弃，适合复杂肠道样本的后续分类和组装。
- **为什么最小长度用 50 bp**：`--length_required 50` 能去除过短 reads，同时保留仍可用于 k-mer 分类、比对和 assembly graph 构建的信息。
- **为什么开启双端接头自动检测**：`--detect_adapter_for_pe` 不依赖预先指定 adapter 序列，对不同测序批次或建库试剂更稳健。
- **为什么保留 JSON 和 HTML**：fastp 内置报告已经覆盖过滤前后质量分布、接头、长度、GC 和 duplication，适合作为项目级 QC 追踪输入。
- **为什么优先 fastp 而不是 Trimmomatic**：fastp 通常比传统 Trimmomatic 流程快约 3-5 倍，同时内置接头检测、质量过滤和报告生成，减少额外工具串联。
- **当前脚本注意点**：`scripts/01_qc_fastp.sh` 已使用 Q20、50 bp、自动接头检测和 `--correction`；`--unqualified_percent_limit 40` 是 fastp 常用默认策略，直接命令中建议显式写出。

## Verified

- validated — 已通过实际运行验证
- 2026-06-12 — User: local, Sample: S01, Params: threads=16, qualified_quality_phred=20, unqualified_percent_limit=40, length_required=50, detect_adapter_for_pe=true, Exit: 0, Duration: 18s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/01_qc_fastp.sh`
