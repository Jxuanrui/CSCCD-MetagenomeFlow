---
tool: "SemiBin2 v1.5+"
dimension: "bacteria"
category: "binning"
author: ""
date: "2026-06-13"
tags: [binning, semibin2, deep-learning, bam, mag]
scenario: [gut-microbiome, assembled-contigs, complex-community]
---

# SemiBin2 机器学习分箱建议

## Scenario

> 适用于群落复杂、近缘菌丰富或希望尽量回收小型和碎片化基因组的样本，需要结合序列组成与覆盖证据做自监督或预训练模型分箱。对标准肠道样本，SemiBin2 往往是最值得保留的一条分箱证据链。

典型输入是 MEGAHIT contigs 与 CoverM 生成的排序 BAM，典型输出是 SemiBin2 的分箱目录和用于 DAS_Tool 的 `{sample}.semibin2.tsv`。与只读取深度摘要的 MetaBAT2 和 MaxBin2 不同，SemiBin2 会直接消费 BAM，因此上游比对质量、排序状态和文件完整性都会直接影响模型侧表现。

如果样本属于常规人肠道菌群，使用 `--environment human_gut` 的预训练模型通常能显著减少运行时间，并且常常比现场自训练更稳定；只有在环境与预训练域差异较大，或你明确希望完全数据驱动时，才更值得切回 self-supervised 模式。

**关键参数速查**：Tool = `SemiBin2 v1.5+`；Depends on = MEGAHIT contigs + CoverM sorted BAM；Key params = `SemiBin2 single_easy_bin -i contigs.fa -b {sample}.bam -o output/ --threads 16 --environment human_gut`, `--min-len 1000`；Outputs = `{sample}.semibin2.tsv` for DAS_Tool；Benefit = pre-trained `human_gut` model skips self-training and is usually faster and accurate for gut samples；Requirement = BAM must be sorted

## Recommendation

如果目标是标准人肠道样本并且希望优先兼顾速度与效果，推荐直接使用预训练环境模型：

```bash
# Preferred command for standard human gut samples.
SemiBin2 single_easy_bin \
  -i result/assembly/megahit/S01/S01.contigs.fa \
  -b result/binning/coverm/S01/S01.bam \
  -o result/binning/semibin2/S01 \
  --threads 16 \
  --environment human_gut \
  --min-len 1000
```

如果要保持与当前仓库脚本一致，则应运行包装脚本；需要注意，仓库脚本目前走的是 `--self-supervised` 分支，而不是预训练 `human_gut`：

```bash
# Current project wrapper: self-supervised mode.
bash scripts/35_bac_semibin2.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

对肠道项目而言，这两种模式都能工作，但推荐优先级不同。如果你是在标准 human gut cohort 上做常规 MAG 回收，预训练模型通常更省时；如果数据类型偏离肠道、实验设计特殊，或你怀疑预训练分布和样本分布差距较大，再考虑切回自监督训练。

## Rationale

- **为什么 SemiBin2 特别适合复杂群落**：它不仅看 contig 组成和覆盖，还用深度学习方式整合这些信号，在近缘菌混杂时通常比传统启发式方法更有分辨力。
- **为什么推荐 `--environment human_gut`**：对标准人肠道数据，预训练模型已经见过相似分布，通常能省去自训练开销，同时维持甚至提升分箱质量。
- **为什么 BAM 是硬前提**：SemiBin2 直接读取比对结果，不像 MetaBAT2 和 MaxBin2 只要深度摘要，因此上游 CoverM 产生的排序 BAM 不能丢。
- **为什么还要设 `--min-len 1000`**：过短 contigs 对深度学习分箱的特征贡献有限，保留过多短片段通常会增加噪音，影响小 bin 的纯度。
- **为什么它常能回收小型或碎片化基因组**：在复杂样本里，传统方法容易把这些片段留在未分配集合中，而 SemiBin2 往往能从弱信号中拼出更完整的 contig 组合。
- **为什么仓库脚本和推荐命令不同**：脚本追求通用性，因此使用自监督模式覆盖更广环境；文档则针对当前肠道项目给出更贴近数据分布的优先建议。
- **为什么要把结果转成 `{sample}.semibin2.tsv`**：DAS_Tool 消费的是 contig2bin 关系，而不是某个工具私有目录结构，标准化 TSV 才能顺利参与 consensus binning。
- **为什么不建议跳过 CoverM 直接另行准备 BAM**：只要 BAM 的样本、assembly 或排序规则不一致，SemiBin2 的输入证据就会变脏，问题往往很难在后处理阶段纠正。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/35_bac_semibin2.sh`
- `agents/skills/35_bac_semibin2.yaml`
