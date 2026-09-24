---
tool: "metaphlan4"
dimension: "mycobiome"
category: "taxonomy"
author: ""
date: "2026-06-14"
tags: [fungi-screening, eukaryote-profiling, marker-based-taxonomy]
scenario: [gut-microbiome, whole-genome-metagenomics, per-sample-analysis]
---

# MetaPhlAn4 真菌真核保留分类建议

## Scenario

> 适用于已完成 KneadData 的单样本 WGS，希望直接复用现有 MetaPhlAn4 4.2.4+ 安装做真菌快速筛查；核心参数是 `--ignore_bacteria --ignore_archaea`，输出 `result/fungi/metaphlan4/{sample}/{sample}_profile.txt`，并优先复用步骤 11 的 `temp/metaphlan4/{sample}/{sample}.mapout.bz2`。

这个步骤和细菌版 MetaPhlAn4 用的是同一套数据库与程序环境，但目标完全不同：这里不是过滤掉真核，而是把真核 marker 保留下来，专门看 `k__Eukaryota`。

## Recommendation

推荐把它作为 mycobiome 的 rapid QC 或 first-pass screen。样本已经做过步骤 11 时，优先复用已有 `mapout`，避免 bowtie2 重跑；没有 `mapout` 时再把双端 reads 合并后直接跑。

```bash
# Reuse step 11 mapout when available, then keep only eukaryotic calls.
bash scripts/72_fun_metaphlan4_euk.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

如果目标是“先判断样本里是否有真菌，再决定是否投入 FunOMIC、BLAST 或组装”，它通常比 FunOMIC 更快，也更适合大队列前置筛查；但不要把极低丰度真菌阳性直接当作最终结论。

## Outputs

核心产物是每样本 profile：

```text
result/fungi/metaphlan4/{sample}/{sample}_profile.txt
```

若步骤 11 已跑过，当前实现会优先复用：

```text
temp/metaphlan4/{sample}/{sample}.mapout.bz2
```

脚本头注释仍把 `result/fungi/metaphlan4/{sample}/{sample}.sam.bz2` 列为流程资产，但当前实际实现并不重新生成 fungi 专属 `sam.bz2`；真要保留 read-to-marker 对齐证据，应继续保留步骤 11 的 MetaPhlAn4 比对中间文件。

## Rationale

- **为什么适合做真菌快速筛查**：它直接复用 MetaPhlAn4 marker 框架，不需要额外安装 FunOMIC 或大型 protein 数据库。
- **为什么和细菌版本质不同**：步骤 11 的主目标是细菌/古菌物种谱；这里显式使用 `--ignore_bacteria --ignore_archaea`，只保留真核信号。
- **为什么复用 `mapout` 很关键**：步骤 11 已完成 bowtie2 marker 比对时，真菌步骤只需重新解读已有命中，不必再次处理全量 reads。
- **为什么速度快但灵敏度有限**：MetaPhlAn4 仍是 marker-based profiling，不像 FunOMIC 那样专门围绕肠道真菌数据库设计，因此对低丰度 fungi 的召回通常更保守。
- **为什么适合作为 QC**：如果连这里都没有稳定的 `k__Eukaryota` 信号，后续更昂贵的真菌功能或组装分析往往收益有限。
- **为什么低丰度结果要谨慎**：真菌 reads 在肠道样本里常很少，单样本少量 marker 命中更适合与 Kraken2 PlusPF、FunOMIC 或 BLAST 交叉复核。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/72_fun_metaphlan4_euk.sh`
- `scripts/11_bac_metaphlan4.sh`
- `scripts/13_bac_humann3.sh`
- `docs/experience/metaphlan4-parameter-guide.md`
