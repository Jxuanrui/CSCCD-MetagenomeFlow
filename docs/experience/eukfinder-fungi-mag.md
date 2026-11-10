---
tool: "eukfinder"
dimension: "mycobiome"
category: "binning"
author: ""
date: "2026-06-12"
tags: [parameter-tuning, fungal-mag, eukaryotic-binning, quality-assessment]
scenario: [gut-microbiome, assembled-contigs, low-abundance-fungi]
---

# Eukfinder 真菌 eMAG 回收与质量评估建议

## Scenario

> 适用于从肠道宏基因组中回收真核或真菌 MAG，尤其是已经通过 Kraken2 PlusPF、FunOMIC 或其他 71/72 真菌分类结果确认样本存在真菌 reads 后。

典型流程不是把全量 metagenome contigs 直接交给通用 binning 工具，而是先识别或提取真菌 reads，单独重组装，再用 Eukfinder 识别真核 contigs 并进入 eMAG 回收。

由于真菌基因组更大、重复序列更多、覆盖度更低，实际 eMAG completeness 常见在 `30-70%`，不应套用细菌 MAG 的完整度预期。

## Recommendation

推荐先用 71/72 类真菌分类结果确认真菌信号，再提取 fungal reads 并单独组装；Eukfinder 输入应来自真菌重组装 contigs，而不是原始全量 assembly。

```bash
# First-pass fungal classification before eukaryotic MAG recovery.
bash scripts/71_fun_kraken2_fungi.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR} \
  --confidence 0.1 \
  --read-len 150

# Re-assemble fungal-enriched reads before Eukfinder.
megahit \
  -1 result/fungi/reads/sample/sample.fungi_1.fastq.gz \
  -2 result/fungi/reads/sample/sample.fungi_2.fastq.gz \
  -o result/fungi/assembly/sample \
  --min-contig-len 1500 \
  -t 16
```

Eukfinder 建议使用 `long_seqs` 模式识别长 contig 中的真核信号，`--mhlen 200` 可作为项目默认值。

```bash
# Identify eukaryotic contigs from fungal-enriched assembly.
eukfinder long_seqs \
  -l result/fungi/assembly/sample/sample.contigs.fa \
  -o result/fungi/eukfinder/sample/results \
  -n 16 \
  --mhlen 200
```

项目脚本封装了 Eukfinder long_seqs 调用；未安装时会生成占位说明文件，不应把占位文件解释为无真核 contig。

```bash
bash scripts/79_fun_eukfinder.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

Eukfinder 输出的真核 contigs 进入 binning 后，应使用 CheckM-Euk 或 BUSCO 做质量评估；不要用只面向原核 MAG 的 CheckM1/CheckM2 阈值直接定级。

```bash
# Assess fungal/eukaryotic MAG quality with BUSCO.
busco \
  -i result/fungi/bins/sample/bin_001.fa \
  -o sample_bin_001_busco \
  -m genome \
  -l fungi_odb10 \
  -c 16

# Alternative eukaryotic MAG quality assessment.
checkm-euk \
  --threads 16 \
  result/fungi/bins/sample \
  result/fungi/qc/checkm_euk/sample
```

正式解释中建议把 `30-50%` completeness 视为 draft eMAG，`50-70%` 视为较好的 fungal MAG 候选，`>70%` 在肠道低丰度真菌中已经值得重点复核。

## Rationale

- **为什么需要先做真菌分类**：71/72 输出能判断样本是否有足够真菌信号，避免对几乎无真菌 reads 的样本投入昂贵组装和 binning。
- **为什么要单独重组装 fungal reads**：全量 metagenome 中细菌 reads 占主导，直接组装会稀释真菌覆盖度并产生大量原核 contig 干扰。
- **为什么不能依赖 MetaBAT2/MaxBin2**：这些工具主要按原核基因组特征、覆盖度和 tetranucleotide composition 设计，对大而复杂的真核基因组不适配。
- **为什么 Eukfinder 更合适**：Eukfinder 使用真核特异信号、HMM profiles 和序列组成信息识别 eukaryotic contigs，能从原核背景中分离真核序列。
- **为什么 contig 长度建议 `>=1500 bp`**：过短序列缺少稳定的真核特征和 HMM 命中，容易造成分类噪声。
- **为什么 completeness 预期较低**：真菌基因组大、重复多、覆盖度低，肠道样本中常无法达到细菌 MAG 常见的高完整度。
- **为什么用 BUSCO 或 CheckM-Euk**：真核 MAG 质量需要真核单拷贝基因集或 eukaryote-aware 模型评估，原核质量模型会误判。
- **为什么占位文件不能当作阴性结果**：脚本在未安装 Eukfinder 时会输出说明文件以不中断流程，这表示工具缺失，不表示样本没有真核 contig。
- **为什么需要后续人工复核**：eMAG 候选常混有低覆盖 contig、重复区和跨物种片段，正式结果应结合 taxonomy、GC、coverage 和 BUSCO 一起检查。

## Verified

- **validated — 已通过实际运行验证**
- Project_example / S01 / 2026-06-17 / exit=0 / 耗时 148s
  - 输入：`result/fungi/assembly/S01/S01.contigs.fa`
  - 输出：`Eukfinder_results/` — Bact=62 contigs, Unk=4, EUnk=4, Euk=0
  - 0 个真核 contig 为预期行为（Project_example 测序深度不足）
  - 前置条件：ETE3 taxa.sqlite（~700MB）已初始化；EukDB（628/667 基因组，12.8GB）已就绪
  - Provenance: `agents/provenance/20260617_79_fun_eukfinder_S01.json`

## References（可选）

- `scripts/79_fun_eukfinder.sh`
- `docs/tools_ref/eukfinder.md`
- 上游来源：`scripts/71_fun_kraken2_fungi.sh`
- 上游来源：`scripts/75_fun_funomics.sh`
