---
tool: "binning-workflow"
dimension: "bacteria"
category: "binning"
author: ""
date: "2026-06-11"
tags: [multi-binner, dastool, mag-recovery]
scenario: [gut-microbiome, high-depth, paired-end]
---

# 多算法分箱与 DAS_Tool 整合建议

## Scenario

> 适用于已经得到 `>=1000-1500 bp` contig 和覆盖度信息的样本，希望尽量提高 MAG 回收率而不是依赖单一分箱器。

本项目的设计不是“选一个最好的 binner”，而是让 MetaBAT2、MaxBin2、SemiBin2 各自出结果，再由 DAS_Tool 做整合。

因此经验重点不是某个算法单点调参，而是输入统一、算法互补和整合阈值的把控。

## Recommendation

推荐工作流保持三路并行，然后进入 DAS_Tool：

```bash
metabat2  -m 1500 -a depth.txt -i contigs.fa
run_MaxBin.pl -max_iteration 50 -abund abundance.txt -contig contigs.fa
SemiBin2 single_easy_bin --self-supervised --input-bam sample.bam
DAS_Tool --score_threshold 0.3 --write_bins 1
```

MetaBAT2 建议保留脚本默认 `-m 1500`，与上游 assembly 的 MAG 目标保持一致。

MaxBin2 建议继续使用从 `depth.txt` 提取的两列表达丰度文件，不要直接把 MetaBAT2 格式的全表硬塞进去。

SemiBin2 建议保留 `--self-supervised`，并明确依赖 BAM 而不是仅有深度矩阵。

DAS_Tool 建议至少接入 `2` 个 binner，正式分析优先凑齐 `3` 个；少于两个时不建议把结果当作整合 bin 使用。

`--score_threshold 0.3` 建议作为默认起点保留；只有在整合后 bins 明显过少时，再考虑小幅下调做对照测试。

对资源有限的项目，优先顺序是 MetaBAT2 + SemiBin2 + DAS_Tool；MaxBin2 可作为第三补充，而不是先砍掉 SemiBin2。

## Rationale

- **为什么要多算法并行**：三种分箱器依据不同。MetaBAT2 偏 tetranucleotide + depth，MaxBin2 偏 EM 聚类，SemiBin2 引入自监督表征，互补性强于替代性。
- **为什么 MetaBAT2 保持 `1500 bp`**：短 contig 的组成与覆盖噪声更大，会拖低分箱边界稳定性。
- **为什么 MaxBin2 的 abundance 需要转换**：它要求的是 `contig, depth` 两列输入，格式错了会得到表面成功、实则异常的 bin 结果。
- **为什么 SemiBin2 必须保留 BAM**：它利用原始比对信息构建特征，单纯深度表无法替代。
- **为什么 DAS_Tool 至少要两个 binner**：整合的本质是比较和裁决；只有一个输入时，DAS_Tool 失去“择优整合”的意义。
- **为什么 `0.3` 是合理默认**：该阈值允许保留一部分边缘 bin，同时不过早放大单一算法的噪声结果。
- **为什么不建议只跑单一 MetaBAT2**：MetaBAT2 通常很稳，但会漏掉一些 coverage 模式不典型或组成信号较弱的 genome bin。
- **为什么 SemiBin2 值得保留**：在复杂群落里，它常能补回传统 composition+coverage 方法遗漏的 bin，尤其对非典型 genome 更有价值。
- **为什么要统一上游 contig 长度策略**：如果 assembly 还停留在 `500 bp` 通用设定，后续三种分箱器的输入质量会先天偏弱。
- **为什么整合后仍需质量评估**：DAS_Tool 解决的是“候选 bin 选择”，不是 completeness/contamination 终判，后面仍要走 CheckM2 和 dRep。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/33_bac_metabat2.sh`
- `scripts/34_bac_maxbin2.sh`
- `scripts/35_bac_semibin2.sh`
- `scripts/36_bac_dastool.sh`
- `agents/skills/33_bac_metabat2.yaml`
- `agents/skills/34_bac_maxbin2.yaml`
- `agents/skills/35_bac_semibin2.yaml`
- `agents/skills/36_bac_dastool.yaml`
