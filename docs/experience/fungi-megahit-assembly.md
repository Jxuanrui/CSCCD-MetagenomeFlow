---
tool: "megahit"
dimension: "mycobiome"
category: "assembly"
author: ""
date: "2026-06-14"
tags: [fungal-assembly, low-abundance, contig-recovery]
scenario: [gut-microbiome, whole-genome-metagenomics, per-sample-analysis]
---

# MEGAHIT 真菌组装参数建议

## Scenario

> 适用于每个样本已完成 KneadData，希望从 WGS 中尽量保留低覆盖真菌 contig；推荐思路是 `--presets meta-sensitive`，输出 `result/fungi/assembly/{sample}/{sample}.contigs.fa`，并为后续 `79_fun_eukfinder.sh` 与 `80_fun_prodigal.sh` 提供输入。

真菌在肠道样本里往往覆盖更低、组装更碎，因此这里的参数选择应偏向召回，而不是沿用典型细菌 MAG 工作流里更激进的过滤阈值。

## Recommendation

推荐真菌组装使用 `meta-sensitive` 预设，而不是细菌流程常见的 `meta-large`。这一步是 per-sample assembly，应该直接吃 `result/kneaddata/{sample}/` 下的 clean reads。

```bash
# Fungal assembly tuned for lower coverage signal.
bash scripts/78_fun_megahit.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

如果目标是尽量捕获低覆盖真菌 contig，经验上 `--min-contig-len 500` 更有利于保留弱信号；但需要注意，当前 `78_fun_megahit.sh` 的实际实现写死为 `--min-contig-len 1000`。因此这份经验更接近“推荐策略”，而不是对当前脚本参数的逐字复述。

## Outputs

每样本核心输出为：

```text
result/fungi/assembly/{sample}/{sample}.contigs.fa
```

脚本同时会保留：

```text
result/fungi/assembly/{sample}/{sample}.megahit.log
```

这一步的直接下游依赖是 `79_fun_eukfinder.sh` 和 `80_fun_prodigal.sh`；再往后，`81-86` 会通过 Prodigal 汇总的 FAA 文件自动做全样本功能注释。

## Rationale

- **为什么用 `meta-sensitive`**：低丰度真菌在肠道 WGS 中常缺乏稳定深度，敏感预设更有机会保住稀疏 contig。
- **为什么不直接沿用细菌默认**：细菌流程更偏向大群落、高覆盖和 binning 质量；真菌步骤更看重先把 contig 留下来。
- **为什么 `500 bp` 常被视为合理建议**：更短阈值能减少低覆盖真菌 contig 被提前过滤掉的风险，适合后续基因预测和真核识别探索。
- **为什么仍要提示当前脚本是 `1000 bp`**：文档如果不说明这一点，用户会以为 wrapper 已实现 `500 bp`，实际运行结果会和预期不一致。
- **为什么它是 Eukfinder 和 Prodigal 的共同上游**：无论是回收真核 contig 还是做标准基因预测，都必须先有 fungi-focused assembly。
- **为什么建议逐样本运行**：真菌信号本来就弱，按样本单独组装更利于保留样本来源、下游定量和问题排查。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/78_fun_megahit.sh`
- `scripts/79_fun_eukfinder.sh`
- `scripts/80_fun_prodigal.sh`
- `docs/experience/megahit-assembly-strategy.md`
