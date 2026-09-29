---
tool: "MaxBin2 v2.2.7"
dimension: "bacteria"
category: "binning"
author: ""
date: "2026-06-13"
tags: [binning, maxbin2, marker-genes, em, mag]
scenario: [gut-microbiome, assembled-contigs, mag-recovery]
---

# MaxBin2 分箱参数建议

## Scenario

> 适用于已经有 contigs 和对应 depth 文件，需要用 marker gene 加 abundance 的思路恢复 MAG，并把结果作为 DAS_Tool 的补充输入。MaxBin2 不应只被当成单独成品，更常见的价值是和 MetaBAT2、SemiBin2 形成互补。

典型输入是 MEGAHIT contigs 与由 CoverM 深度表提取出的二维 abundance 文件，典型输出是一组 `bin.*.fasta` 和用于 DAS_Tool 的 `{sample}.maxbin2.tsv`。和主要依赖 tetranucleotide 组成的 MetaBAT2 不同，MaxBin2 会借助 universal single-copy marker genes 为候选 bins 建立初始种子，再用 EM 迭代细化分配。

在高质量、覆盖度相对充分且物种边界较清晰的样本里，MaxBin2 往往能给出较整洁的 bins；但在低深度或高度近缘菌共存的场景下，它也更容易表现得保守。因此最佳实践通常不是只信 MaxBin2，而是把它作为 consensus binning 的一条独立证据链。

**关键参数速查**：Tool = `MaxBin2 v2.2.7`；Depends on = MEGAHIT contigs + CoverM `depth.txt` converted to 2-column `contig<TAB>depth`；Key params = `run_MaxBin.pl -contig {sample}.contigs.fa -abund depth.txt -out {sample}`, `-thread 16`, `-min_contig_len 1000`；Outputs = `{sample}.maxbin2.tsv` for DAS_Tool + `bin.*.fasta`；Method = 107 universal single-copy marker genes + abundance + EM algorithm

## Recommendation

项目里已经把 depth 转换和 contig2bin 表构建封装好了，推荐按样本直接运行：

```bash
# Run MaxBin2 on one assembly with CoverM-derived abundance.
bash scripts/34_bac_maxbin2.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果需要显式记录 MaxBin2 的核心参数，建议先从 CoverM 深度表提取二维 abundance，再运行主程序：

```bash
# Extract the 2-column abundance file required by MaxBin2.
tail -n +2 result/binning/coverm/S01/depth.txt | cut -f1,4 > result/binning/maxbin2/S01/abundance.txt

# Run marker-gene + abundance based binning.
run_MaxBin.pl \
  -contig result/assembly/megahit/S01/S01.contigs.fa \
  -abund result/binning/maxbin2/S01/abundance.txt \
  -out result/binning/maxbin2/S01/S01 \
  -thread 16 \
  -min_contig_len 1000
```

仓库当前脚本还加入了 `-max_iteration 50` 并自动把输出 bin 转成 `{sample}.maxbin2.tsv`。如果你的终点是 DAS_Tool，而不是手工检查每个 `bin.*.fasta`，那么 contig2bin 表才是最关键的交付物，因为它决定了 MaxBin2 能否被后续 consensus 步骤正确吸收。

## Rationale

- **为什么 MaxBin2 适合作为补充而不是唯一答案**：它和 MetaBAT2、SemiBin2 利用的信号不同，单独使用会受方法偏好限制，但并入 DAS_Tool 后能提供额外可恢复的 contig 组合。
- **为什么 marker gene 思路有独特价值**：107 个 universal single-copy marker genes 能帮助建立更稳定的初始 bin 种子，这一点与纯组成或纯深度方法不同。
- **为什么还必须结合 abundance**：只靠 marker genes 无法把所有 contigs 精细分配，覆盖度为 EM 迭代提供了额外维度，尤其有助于扩大 bin 边界。
- **为什么推荐 `-min_contig_len 1000`**：过短 contigs 的组成和深度波动都更不稳定，纳入太多短片段通常只会抬高污染率和误分配概率。
- **为什么需要先把 CoverM depth 转成 2 列**：MaxBin2 不直接消费 MetaBAT 风格的完整深度表，它只接受简化 abundance 文件，因此这一步格式转换不能省。
- **为什么高质量、分离度好的样本更适合 MaxBin2**：当 genomes 覆盖度足够且群落结构不太拥挤时，marker seeds 更容易扩展成完整 bins，结果通常更干净。
- **为什么低深度或近缘菌场景下会变弱**：丰度信号不稳定、序列边界相近时，EM 容易变得保守，导致 bins 数量偏少或碎片回收不足。
- **为什么最终目标应放在 DAS_Tool 整合**：MaxBin2 的最大价值往往不是单独产出多少 bins，而是它能为 consensus refinement 提供 MetaBAT2 不一定覆盖到的 contig 证据。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/34_bac_maxbin2.sh`
- `agents/skills/34_bac_maxbin2.yaml`
