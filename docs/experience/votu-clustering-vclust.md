---
tool: "vclust v1.3+"
dimension: "virome"
category: "clustering"
author: "team"
date: "2026-06-13"
tags: [votu, virus, ani, leiden, clustering]
scenario: [virome, checkv-filtered-contigs, cross-sample-clustering]
---

# vclust 病毒 vOTU 聚类建议

## Scenario

> 适用于完成 CheckV 质控后，需要把所有样本的病毒 contigs 放在一起做跨样本聚类，生成 species-level 的 vOTU 代表序列集合。

vOTU 不是单样本概念，而是整个队列共享的病毒操作分类单元。因此这一步必须把所有样本的 `viruses.fna` 先合并，再做统一的相似性筛选和聚类。若先按样本各自聚类，后面再合并，会把同一种病毒拆成多个局部簇，直接影响丰度矩阵和下游差异分析。

当前项目脚本按 `prefilter -> align -> cluster` 三步运行 `vclust`，并采用 Leiden 社区检测而不是传统单链聚类。对病毒而言，ANI 相似性往往不完全满足传递性，Leiden 更适合处理局部高相似但全局不闭合的网络结构。

这一步的本质不是“压缩 contig 数量”，而是定义后续全项目共享的病毒物种参考框架。

因此只要新增样本并补进了新的高质量病毒 contigs，原则上就应重新做全队列 vOTU 聚类。

**关键参数速查**：Tool = `vclust prefilter` + `vclust align` + `vclust cluster`；Depends on = step `54_vir_checkv_contig` 后全样本 CheckV-filtered `viruses.fna`；Key params = `--min-ani 0.95`, `--min-qcov 0.85`, Leiden community detection；Input = pooled all-sample `viruses.fna`；Output = vOTU representative sequences and `votu_representatives.tsv`.

## Recommendation

```bash
# Run cross-sample vOTU clustering through the project wrapper.
THREADS=16                        # compute threads
WORKDIR=/path/to/project          # project workdir with CheckV-filtered viruses.fna
REPO=/path/to/CSCCD-MetagenomeFlow       # repo root with envs/vclust
bash scripts/56_vir_votu_gen.sh -t "$THREADS" -w "$WORKDIR" -r "$REPO"
```

仓库脚本 `scripts/56_vir_votu_gen.sh` 会先把 `result/virus/checkv/*/viruses.fna` 收集为统一的 `result/virus/votu/contigs/virus.fasta`，再执行上述三步并导出代表序列列表。若你要复现实验，关键不是“某个样本的阈值怎么调”，而是一定要保证聚类输入已经覆盖全队列。

`95% ANI + 85% qcov` 是当前病毒组学里常用的 species-level vOTU 边界，尤其适合噬菌体。这里选择 Leiden 而不是 complete-linkage 或 single-linkage，是为了避免非传递性 ANI 网络把边缘 contig 错误并入，或因局部连接方式造成过度碎片化。

聚类完成后，应优先保留代表序列 FASTA 和代表序列到 cluster 的映射表。

这两个文件分别服务于下游定量和结果追溯，缺一都会让后续分析变得难以复现。

如果发现某些 cluster 只由极短 contig 组成，应回头检查 CheckV 过滤阈值，而不是先动 ANI 阈值。

## Rationale

- **为什么使用 `95% ANI`**：这是病毒组学中广泛采用的 species-level 近似阈值，对噬菌体 vOTU 的可比性最好，也最利于和公开研究对齐。
- **为什么使用 `0.85 qcov`**：只看 ANI 不够，覆盖度过低时短片段或局部保守区域也会给出高相似；`0.85` 能过滤掉只在局部对齐的伪近邻。
- **为什么必须先汇总所有样本再聚类**：vOTU 是项目级参考单元，只有全样本同时聚类，才能保证同一病毒在不同样本里共享同一个代表序列和同一个 ID。
- **为什么用 Leiden 而不是 complete-linkage**：病毒 ANI 图存在非传递性，Leiden 基于图社区划分，通常比简单层次聚类更能处理桥接节点和局部连接异常。
- **为什么 vclust 优于 `cd-hit-est`**：病毒基因组更容易受 mosaic 结构和局部保守区域影响，vclust 的 ANI+覆盖度框架比纯序列聚类更贴近病毒学定义。
- **为什么代表序列选择很重要**：后续 Salmon 建索引、丰度定量、功能注释和宿主预测都依赖代表序列，如果代表序列不稳定，整个下游矩阵都会漂移。
- **为什么要先做 CheckV 过滤**：低质量、宿主污染或大量截断 contig 会扭曲 ANI 网络，先用 CheckV 清理输入能提高 vOTU 边界的生物学可信度。
- **为什么脚本分成三步而不是一步完成**：`prefilter` 先缩小候选对，`align` 再精算 ANI，`cluster` 最后做图聚类，这种拆分更高效，也更便于排查异常样本。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_votu=48, Exit: 0, Duration: 9s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/56_vir_votu_gen.sh`
- `agents/skills/56_vir_votu_gen.yaml`
