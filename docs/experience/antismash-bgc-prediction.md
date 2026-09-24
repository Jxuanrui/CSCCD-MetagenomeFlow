---
tool: "antismash"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [bgc, secondary-metabolites, antismash, per-sample]
scenario: [gut-microbiome, assembled-contigs, per-sample]
---

# antiSMASH 次级代谢基因簇预测建议

## Scenario

> 关键参数速查：适用于 megahit 组装后的单样本 contigs，重点分析 `>=1000 bp` 序列中的 BGC；脚本 `28_bac_antismash.sh` 按样本运行：`-s SAMPLE -t CPUS -w WORKDIR -r REPO`；核心参数 `--taxon bacteria --minimal --cpus {CPUS}`；输出 `result/annotation/antismash/{sample}/` 下的 `{sample}.gbk`、`index.html`、`.json`；成功后写入 `.done`，失败也会创建 sentinel 以允许流水线继续。

antiSMASH 适合在肠道宏基因组中探索多样的次级代谢潜力，尤其是 polyketides、NRPs 和 terpenes 等经典 BGC 类型。

它更偏“发现型”分析，而不是常规必跑注释项，因此通常在 taxonomy、AMR 和基础功能注释完成后再进入。

## Recommendation

推荐按样本运行 antiSMASH，并直接沿用脚本的 `--minimal` 设定，除非你的项目明确需要更完整但更慢的注释细节。

```bash
# Run antiSMASH per sample on megahit contigs.
bash scripts/28_bac_antismash.sh \
  -s SRR28210342 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

主结果建议优先查看 `index.html` 进行人工浏览，再结合 `{sample}.gbk` 和 `.json` 做结构化提取。对宏基因组项目，`--minimal` 通常已经足够支持 BGC 类型级发现。

如果你的重点是高通量扫描整个队列的代谢潜力，保留当前脚本逻辑是合理的；如果你的重点是少量高价值样本的精细化 BGC 注释，可考虑在后续对候选 contig 单独做更完整的再分析。

## Rationale

- **为什么按样本运行**：脚本输入是 `megahit/{sample}/{sample}.contigs.fa`，说明 antiSMASH 的目标是单样本组装结果，而不是全项目合并目录。
- **为什么要求 `>=1000 bp` contigs**：过短 contig 难以覆盖完整或近完整 BGC 结构，预测结果稳定性明显更差。
- **为什么使用 `--taxon bacteria`**：这是细菌宏基因组最常见且最贴合本项目数据类型的设定。
- **为什么默认 `--minimal`**：脚本注释已明确它能跳过 NCBI taxonomy 查询、显著提速，代价是损失部分注释细节；对 metagenomics 很合适。
- **为什么 `--minimal` 的损失可以接受**：宏基因组 BGC 分析常先关心是否存在 PKS、NRPS、terpene 等类型信号，而不是一次性做到最完整注释。
- **为什么要注意 `.done` sentinel 行为**：脚本即使失败也会创建 `.done` 让流水线继续，因此批量运行后不能只看 sentinel，仍需检查结果目录是否真正生成核心文件。
- **为什么先看 `index.html`**：可视化页面最适合快速人工判断 BGC 类型、分布和是否值得深入追踪。
- **为什么适合做发现型分析**：gut metagenome 中的次级代谢潜力往往是机制探索问题，不像基础 taxonomy 那样属于所有项目的强制主线。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/28_bac_antismash.sh`
- Blin et al. 2023 NAR
- antiSMASH 7
