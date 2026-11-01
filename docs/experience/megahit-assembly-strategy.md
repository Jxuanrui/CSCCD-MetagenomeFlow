---
tool: "megahit-assembly"
dimension: "bacteria"
category: "assembly"
author: "team"
date: "2026-06-11"
tags: [assembly-strategy, min-contig, mag-recovery]
scenario: [gut-microbiome, high-depth, paired-end]
---

# MEGAHIT 组装策略与最小 contig 长度建议

## Scenario

> 适用于去宿主后的双端宏基因组样本，需要在 contig 数量、下游注释灵敏度和 MAG 回收质量之间做取舍。

同一个样本做”功能注释”和”分箱回收”时，最优组装参数不一定相同。

本项目脚本已经把选择压缩到两个核心维度：`--presets` 与 `--min-contig-len`。

**关键参数速查**：`--min-contig-len 500`（通用注释）/ `1000-1500`（MAG binning）；`--presets meta-large`（默认）/ `meta-sensitive`（低丰度）；k-mer 列表 `21,29,39,59,79,99,119,141`；`-m 0.9` 内存上限；`-t 16` 线程。组装后关键输出：`final.contigs.fa`，N50 和 total assembly size 通过 `seqkit stats` 获取。

## Recommendation

如果目标是通用下游分析，保持脚本默认：

```bash
megahit \
  -1 R1.fastq.gz \
  -2 R2.fastq.gz \
  --presets meta-large \
  --min-contig-len 500 \
  -m 0.9 \
  -t 16
```

如果目标是 MAG 挖掘、CoverM 深度估计和后续 binning，建议把 `--min-contig-len` 提到 `1000`；对更保守的 MAG 流程可进一步到 `1500`。

`meta-large` 作为默认预设是合理的；只有在明确想保留更多低丰度序列且能接受更慢组装时，再考虑 `meta-sensitive`。

常规单样本线程建议 `16-32`；内存紧张时优先减少并发样本数，而不是把 `-m 0.9` 降得很低。

正式分析建议将组装结果按用途分开解释：`500 bp` 适合广泛注释输入，`1000-1500 bp` 更适合分箱和 MAG 质量控制。

如果样本 reads 总量偏少，不要一上来就用 `1500 bp`，否则容易直接把大量有效短 contig 过滤掉。

## Rationale

- **为什么 `meta-large` 是默认主选**：脚本给出的 k 值列表更适合肠道这类中高多样性宏基因组，通常能在连续性与复杂度之间取得较稳平衡。
- **为什么 `500 bp` 适合通用分析**：短 contig 虽然不一定适合分箱，但对基因预测、功能注释和病毒线索保留更友好。
- **为什么 MAG 工作流要提高到 `1000-1500 bp`**：较长 contig 的四核苷酸频率和覆盖深度模式更稳定，更利于 MetaBAT2、MaxBin2、SemiBin2 分箱。
- **为什么不能无脑用 `1500 bp`**：过滤太高会显著减少输入 contig 数量，特别是在低深度样本里，可能先损失召回，再谈不上高质量 bin。
- **为什么优先通过减少样本并发来控内存**：MEGAHIT 的主要瓶颈是内存与 I/O，单样本留足内存比压缩内存上限更稳。
- **为什么脚本用临时目录再搬运结果**：MEGAHIT 不允许直接写入已存在目录，这个处理规避了重跑时的目录冲突。
- **为什么删除中间 contigs 合理**：`intermediate_contigs/` 占盘很大，而本项目后续步骤只依赖 `final.contigs.fa` 和日志。
- **为什么要把“组装目标”写进实验设计**：组装参数不是独立选择，它直接决定后续分箱、注释和丰度回帖的输入分布。
- **为什么日志值得保留**：`*.megahit.log` 能帮助定位空输出是由 reads 太少、内存不足还是过滤阈值过高造成的。

## Verified

- validated — 已通过实际运行验证
- 2026-06-14 — User: local, Sample: S01-S06 ×6, Params: none, Durations: S01=102s S02=93s S03=106s S04=105s S05=100s S06=95s, Exit: 0, Duration: 102s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/16_bac_megahit.sh`
- `agents/skills/16_bac_megahit.yaml`
- 下游依赖：`scripts/17_bac_prodigal.sh`
- 下游依赖：`scripts/32_bac_coverm_depth.sh`
