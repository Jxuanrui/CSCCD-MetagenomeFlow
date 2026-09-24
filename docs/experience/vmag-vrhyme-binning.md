---
tool: "vRhyme v1.1+"
dimension: "virome"
category: "binning"
author: ""
date: "2026-06-13"
tags: [vrhyme, vmag, viral-binning, coverage, checkv]
scenario: [virome, votu, viral-metagenome-assembled-genome]
---

# vRhyme vMAG 病毒分箱建议

## Scenario

> 适用于已经获得跨样本 vOTU 序列和 reads-to-vOTU BAM 后，需要把病毒 contigs 组合成 vMAG，以恢复分段或碎片化病毒基因组。

vMAG binning 的核心信息不是单条 contig 的序列相似性，而是多个样本中 contigs 的共丰度模式和蛋白特征。对病毒而言，组装经常把同一病毒基因组拆成多个片段，vRhyme 可以利用 multi-sample coverage signals 把这些片段重新归入同一个 viral Metagenome-Assembled Genome。

该步骤只有在样本数足够时才值得做。单样本 vRhyme 缺少覆盖度变化信号，结果往往不稳定；实践上建议至少 3 个样本，更理想是有成组样本或时间序列。分箱后必须再用 CheckV 评估完整度、污染和 provirus 情况。

**关键参数速查**：Tool = `vRhyme v1.1+`；Depends on = `{sample}.bam` from Salmon/BWA alignment of vOTU reads and cross-sample vOTU FASTA；Key params = `vRhyme -i virus.fasta`, `-b {sample}.bam` multi-sample BAM files, `--threads 16`, `--method longest` keep longest contig as representative, minimum contig length 1500bp；Input = `virus.fasta`；Output = `vRhyme_best_bins/` directory；Threshold = only attempt if ≥3 samples available, validate with CheckV after binning。

## Recommendation

```bash
# Run vRhyme vMAG binning through the project wrapper.
bash scripts/61_vir_vmag.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果直接运行 vRhyme，建议先确认每个样本的 BAM 已按同一套 vOTU reference 生成：

```bash
# Direct vRhyme command with multi-sample BAM coverage.
vRhyme \
  -i /path/to/project/result/virus/votu/contigs/virus.fasta \
  -b /path/to/project/result/virus/votu/bam/*.bam \
  -o /path/to/project/result/virus/vmag/vRhyme_best_bins \
  --threads 16 \
  --method longest \
  -l 1500
```

输出的 bins 不能直接视为最终高质量 vMAG。推荐在 vRhyme 后接 CheckV，按 completeness、contamination 和 quality tier 再过滤；只有通过质控的 bin 才进入宿主预测、功能注释或生态解释。

## Rationale

- **为什么使用 multi-sample coverage**：不同样本中的协同丰度变化是把病毒 contigs 归入同一基因组的重要信号，单样本缺少这种维度。
- **为什么至少需要 3 个样本**：少于 3 个样本时 coverage covariance 很难稳定估计，分箱更容易由噪声或测序深度驱动。
- **为什么 vMAG 能补充 vOTU**：vOTU 定义的是代表序列或聚类单元，vMAG 则尝试恢复同一病毒基因组的多 contig 组合，二者解决的问题不同。
- **为什么设置最小 contig length 1500bp**：过短 contig 的覆盖度和蛋白信息都不稳定，进入分箱后容易造成错误连接。
- **为什么使用 `--method longest`**：保留最长 contig 作为代表更利于后续追踪和去冗余，通常比随机代表更稳定。
- **为什么 BAM 必须来自同一 vOTU reference**：如果不同样本比对到不同参考，coverage matrix 不可比较，vRhyme 的共丰度信号会失真。
- **为什么分箱后必须 CheckV**：vRhyme 只负责 binning，不评估完整度和污染；CheckV 是判断 vMAG 是否可报告的必要质控步骤。
- **为什么不建议所有病毒 contig 都强行分箱**：低覆盖、孤立或样本特异 contig 缺少足够支持，强行分箱会制造伪 vMAG。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/61_vir_vmag.sh`
- `agents/skills/61_vir_vmag.yaml`
