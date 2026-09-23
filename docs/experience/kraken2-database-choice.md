---
tool: "kraken2"
dimension: "bacteria"
category: "taxonomy"
author: "team"
date: "2026-06-11"
tags: [database-choice, confidence-threshold, bracken]
scenario: [gut-microbiome, paired-end, low-biomass]
---

# Kraken2 数据库与置信度阈值选择建议

## Scenario

> 适用于需要快速获得广覆盖分类结果的宏基因组样本，尤其是希望同时覆盖细菌、古菌、病毒和真菌时。

Kraken2 在本项目中的角色不是替代 MetaPhlAn4，而是提供更快、更广的 k-mer 分类视角，并通过 Bracken 做丰度回估。

数据库选择和 `--confidence` 是这里最关键的两个旋钮。

## Recommendation

默认推荐使用脚本中的 PlusPF 数据库，不建议在正式项目里直接降到极小库，除非内存或时长已经成为硬约束。

推荐的默认调用保持如下：

```bash
kraken2 \
  --db db/kraken2/pluspf \
  --paired R1.fastq.gz R2.fastq.gz \
  --confidence 0.1 \
  --report-zero-counts \
  --use-names
```

Bracken 读长参数必须与原始测序一致；PE150 用 `-r 150`，PE100 用 `-r 100`，不要偷懒沿用默认值。

常规肠道样本优先用 `--confidence 0.1`；这是本项目的主推荐平衡点。

低生物量、疑似污染较多、或临床保守判读场景，建议把 `--confidence` 提到 `0.3`。

探索性样本或希望尽量保留弱信号时，可暂时降到 `0.05`，但要在结果解释里明确它更偏召回而非精确度。

Bracken 保留脚本默认 `-t 10`，不要轻易降到 `0`；否则很多仅由少数 reads 支撑的物种会进入回估矩阵。

如果队列中存在不同读长样本，优先按读长分批建 Bracken 索引，而不是混跑后统一按 `150` 解释。

## Rationale

- **为什么 PlusPF 是默认库**：它同时覆盖细菌、古菌、病毒、真菌和原生生物，更符合宏基因组项目“广覆盖”的实际需求。
- **为什么不默认用更小库**：缩库会明显降低分类覆盖，尤其会牺牲非细菌成分与边缘类群。
- **为什么 `0.1` 是常规平衡点**：脚本把它定义为肠道宏基因组的推荐值，既能压掉一部分弱 k-mer 噪声，又不会像 `0.3+` 那样过度保守。
- **为什么低生物量场景要更高阈值**：污染和偶然命中在低 biomass 数据里影响更大，提高置信度能减少假阳性传播到 Bracken。
- **为什么 Bracken 读长必须匹配**：Bracken 是基于数据库预估 read-length 分布回推丰度的，读长错配会直接扭曲重估结果。
- **为什么 `-t 10` 值得保留**：极低 read 支撑的分类单元往往最不稳，先用门槛去掉噪声比事后再清洗更干净。
- **为什么开启 `--report-zero-counts`**：多样本合并矩阵时列对齐更稳定，后续可视化和比较不需要额外补零。
- **为什么 Kraken2 不能单独代表真值**：它的优势是快和广，但 k-mer 方法对近缘基因组共享片段、污染片段和数据库偏倚更敏感。
- **为什么适合与 MetaPhlAn4 互补**：前者看广谱 read 归属，后者看 marker 稳健分类；两者一致时可信度更高，不一致时可提示数据库或低丰度问题。

## Verified

- validated — 已通过实际运行验证
- 2026-06-14 — User: local, Sample: S01-S06 ×6, Params: none, Durations: S01=57s S02=65s S03=57s S04=61s S05=60s S06=61s, Exit: 0, Duration: 57s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/14_bac_kraken2.sh`
- `agents/skills/14_bac_kraken2.yaml`
- Bracken 输出：`*_S.bracken`、`*_G.bracken`、`*_P.bracken`
- `result/kraken2/{sample}/{sample}.report`
