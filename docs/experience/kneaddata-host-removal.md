---
tool: "kneaddata"
dimension: "bacteria"
category: "quality-control"
author: "team"
date: "2026-06-12"
tags: [parameter-tuning, host-removal, quality-control, bowtie2]
scenario: [gut-microbiome, human-host-removal, paired-end]
---

# kneaddata 肠道样本人源宿主去除建议

## Scenario

> 适用于 fastp 质控后的肠道宏基因组 paired-end reads，需要去除人源宿主污染后再进入 taxonomy、functional profiling、assembly 和 MAG binning。

肠道样本通常宿主比例较低，常见去除率约 `0.5-5%`；皮肤、口腔、低生物量或取样宿主细胞较多的样本可能达到 `50-90%`。因此不要用固定去除率判断失败，应结合样本类型、采样方式和 kneaddata 日志判断。

## Recommendation

项目脚本默认读取 fastp 输出，使用 `${REPO}/db/kneaddata/human` 作为人源数据库，并跳过重复 trimming：

```bash
# Run host removal after fastp.
bash scripts/02_qc_kneaddata.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接运行时，肠道样本建议使用 hg37dec_v0.1 或项目中等价的人源 Bowtie2 数据库，Bowtie2 使用 local sensitive 模式，并跳过 TRF：

```bash
# Direct kneaddata command with explicit Bowtie2 settings.
kneaddata \
  --input1 result/fastp/S01/S01_1.fastq.gz \
  --input2 result/fastp/S01/S01_2.fastq.gz \
  --output result/kneaddata/S01 \
  --reference-db db/kneaddata/hg37dec_v0.1 \
  --threads 16 \
  --bypass-trim \
  --bypass-trf \
  --bowtie2-options "--very-sensitive-local" \
  --output-prefix S01 \
  --log result/kneaddata/S01/kneaddata.log
```

后续 assembly 和 binning 建议保留 paired clean reads，也保留去宿主后产生的 orphan reads：

```bash
# Keep paired reads and orphan reads for downstream assembly if present.
gzip -c result/kneaddata/S01/S01_paired_1.fastq > result/kneaddata/S01/S01_1.kneaddata.fastq.gz
gzip -c result/kneaddata/S01/S01_paired_2.fastq > result/kneaddata/S01/S01_2.kneaddata.fastq.gz

gzip -c result/kneaddata/S01/S01_unmatched_1.fastq > result/kneaddata/S01/S01_orphan_1.kneaddata.fastq.gz
gzip -c result/kneaddata/S01/S01_unmatched_2.fastq > result/kneaddata/S01/S01_orphan_2.kneaddata.fastq.gz
```

当前项目 wrapper 只压缩并保留 paired reads；如果目标是最大化 assembly 输入量，建议单独保留 orphan reads 后再评估是否纳入组装。

## Rationale

- **为什么用人源 hg37dec_v0.1**：对大多数肠道宏基因组去宿主已经足够，数据库体积和比对成本可控；项目脚本中的 `db/kneaddata/human` 应保持为固定版本数据库。
- **为什么使用 `--very-sensitive-local`**：local 模式能识别 reads 中局部人源片段，灵敏度高于严格 end-to-end；对肠道样本通常能在速度和召回之间取得平衡。
- **为什么跳过 trimming**：fastp 已完成接头和低质量过滤，kneaddata 阶段再跑 Trimmomatic 会增加运行时间，并可能重复剪切导致 reads 变短。
- **为什么跳过 TRF**：tandem repeat filtering 对 WGS metagenomics 的主要问题帮助有限，反而会增加耗时并可能误删可用微生物 reads。
- **为什么保留 orphan reads**：一端被判定为宿主污染时，另一端仍可能是高质量微生物 read；这些 orphan reads 对组装和低丰度基因恢复仍有价值。
- **为什么关注去除率范围**：肠道样本宿主污染低时 `0.5-5%` 很常见；皮肤和口腔样本宿主比例高，`50-90%` 也可能合理，不应直接按肠道阈值判错。
- **当前脚本注意点**：`scripts/02_qc_kneaddata.sh` 使用 `--bypass-trim` 和固定 human 数据库，但未显式设置 `--bypass-trf`、`--bowtie2-options` 或 orphan 输出保留策略。

## Verified

- validated — 已通过实际运行验证
- 2026-06-12 — User: local, Sample: S01, Params: threads=16, reference_db=db/kneaddata/human/hg37dec_v0.1, bowtie2_options=--very-sensitive-local --phred33, mode=strict, Exit: 0, Duration: 21s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/02_qc_kneaddata.sh`
