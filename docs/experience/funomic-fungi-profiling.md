---
tool: "funomic"
dimension: "mycobiome"
category: "taxonomy"
author: ""
date: "2026-06-12"
tags: [parameter-tuning, fungi-profiling, functional-profiling, marker-database]
scenario: [gut-microbiome, whole-genome-metagenomics, low-abundance-fungi]
---

# FunOMIC 真菌 WGS 分类与功能谱分析建议

## Scenario

> 适用于肠道 WGS metagenomics 中的真菌群落分析，尤其是低丰度 fungi 需要比通用 k-mer 分类器更稳健的物种识别和功能解释时。

典型输入是已经完成质控和宿主去除的双端 reads，样本可以来自粪便、肠内容物或其他低真菌负荷的微生物组项目。

如果研究问题明确聚焦 mycobiome，FunOMIC 应作为真菌主分析工具；Kraken2 PlusPF 更适合做快速筛查，而不是最终物种谱依据。

**关键参数速查**：FunOMIC 数据库约 1.6M 物种特异 marker（T 数据库）+ 约 3.4M 功能蛋白（P 数据库），专为肠道真菌 WGS 低丰度检测设计；`--threads 16`；输出包含 classification.tsv、abundance.tsv 和 function.tsv；FunOMIC 不可用时回退到 DIAMOND blastx 比对 P 数据库。

## Recommendation

推荐在 host removal 之后直接运行 FunOMIC 分类流程，输出物种丰度表和功能 profile；当前项目脚本会优先调用 `funomic classify`，未安装时回退到 DIAMOND marker 分类。

```bash
# Run FunOMIC on host-filtered paired-end reads.
funomic classify \
  --forward result/kneaddata/sample/sample_1.kneaddata.fastq.gz \
  --reverse result/kneaddata/sample/sample_2.kneaddata.fastq.gz \
  --threads 16 \
  --output result/fungi/funomic/sample

# Expected core outputs.
ls result/fungi/funomic/sample/*classification.tsv
ls result/fungi/funomic/sample/*abundance*.tsv
ls result/fungi/funomic/sample/*function*.tsv
```

在本项目中可通过脚本统一调用，保持输入、输出和回退逻辑一致。

```bash
bash scripts/75_fun_funomics.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

若 FunOMIC 命令暂不可用，允许使用 FunOMIC-P DIAMOND 数据库作为过渡结果，但正式报告应标注这是 fallback 模式。

```bash
# Fallback mode used by the wrapper when FunOMIC CLI is unavailable.
diamond blastx \
  --db db/funomic/P/FunOMIC.P.v1.dmnd \
  --query result/fungi/funomic/sample/sample_merged.fastq.gz \
  --out result/fungi/funomic/sample/sample_classification.tsv \
  --outfmt 6 qseqid sseqid pident length evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 1 \
  --threads 16 \
  --sensitive
```

推荐把 FunOMIC 结果作为 mycobiome 主表，至少保留 species abundance table 和 functional profile 两类输出；不要只保留分类表而丢弃功能层结果。

## Rationale

- **为什么优先 FunOMIC**：FunOMIC 使用约 1.6M species-specific markers 和约 3.4M functional proteins，数据库设计直接面向真菌 WGS 分类与功能分析。
- **为什么比 Kraken2 更适合主分析**：通用 k-mer 数据库的真菌参考覆盖有限，低丰度 fungi 容易被漏检或受近缘物种混淆影响。
- **为什么必须先去宿主**：肠道样本中宿主 reads 可能占比较高，直接进入真菌分类会浪费计算量，并增加非目标序列造成的噪声。
- **为什么要保留功能 profile**：mycobiome 研究通常不仅关心真菌物种，还关心碳水化合物降解、毒力、代谢和环境适应相关功能。
- **为什么 fallback 结果要标注**：DIAMOND marker 分类可用作过渡，但不等价于完整 FunOMIC pipeline，输出结构和可解释性都更有限。
- **为什么 Kraken2 可作为前置筛查**：PlusPF 能快速判断样本是否有可检测真菌信号，帮助决定是否值得投入完整 FunOMIC 计算。
- **为什么低丰度样本要谨慎设阈值**：真菌 reads 少时，过高 abundance cutoff 会删掉真实信号；更稳妥的做法是结合 reads 数、marker 数和跨样本重复性解释。
- **为什么 species 表和功能表要成对保存**：后续差异分析、关联宿主表型和功能解释都需要能从物种层追溯到功能层。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/75_fun_funomics.sh`
- `docs/tools_ref/funomics.md`
- `db/funomic/P/FunOMIC.P.v1.dmnd`
- `db/funomic/T/FunOMIC.T.v1.fasta`
