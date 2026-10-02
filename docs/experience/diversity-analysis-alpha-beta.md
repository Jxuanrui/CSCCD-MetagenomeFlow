---
tool: "phyloseq + vegan + ggplot2"
dimension: "statistics"
category: "diversity"
author: ""
date: "2026-06-13"
tags: [alpha-diversity, beta-diversity, phyloseq, vegan, permanova]
scenario: [bacteria-virus-fungi, merged-profiles, group-comparison]
---

# Alpha/Beta 多样性分析建议

## Scenario

> 适用于已经得到细菌 taxonomy、病毒 vOTU 和真菌 profile 后，需要在统一统计框架下计算 alpha/beta diversity，并比较病例组与对照组或其他分组之间的群落差异。

这一步本质上是把不同维度的丰度表整理成可比较的统计对象，再按相同元数据做组间检验与可视化。常规输出应同时包含 alpha diversity 指标、beta diversity 排序图以及正式统计检验结果，而不是只给一张 PCoA 图。

项目脚本 `scripts/91_stat_diversity.sh` 已经实现了 `Shannon`、`Chao1`、`Simpson`、`FaithPD`、Bray-Curtis、PCoA 和 `adonis2()`。推荐层面可进一步把 weighted UniFrac 和 NMDS 作为补充视角，并在报告中明确区分“alpha 需要考虑稀释公平性”和“beta 不建议机械稀释后再做距离分析”的统计逻辑。

**关键参数速查**：Tool = `phyloseq + vegan + ggplot2`；Input = merged `taxonomy.tsv` / `vOTU_table_ann.txt` / fungi profiles；Alpha metrics = `Shannon`, `Chao1`, `Simpson`；Beta metrics = `bray`, `wunifrac`；Rarefaction depth = min sample reads；Group tests = `Kruskal-Wallis` + `Wilcoxon`；Ordination = `PCoA` / `NMDS`；PERMANOVA = `adonis2()`.

## Recommendation

```bash
# Run the project diversity wrapper with shared metadata and group labels.
THREADS=16                        # compute threads
WORKDIR=/path/to/project          # project workdir containing merged abundance tables
REPO=/path/to/CSCCD-MetagenomeFlow       # repo root with envs/r_stat
META=/path/to/project/metadata.csv  # sample metadata for group comparison
bash scripts/91_stat_diversity.sh -w "$WORKDIR" -r "$REPO" -t "$THREADS" -m "$META" -g group
```

实际分析时，alpha diversity 建议在统一测序深度或统一抽样深度下比较，以免低深度样本把 richness 和 evenness 指标一起拉低。这里常用最小样本 reads 作为 rarefaction depth 的起点，但如果最小值异常低，应先剔除离群样本，再按剩余样本设定深度。

beta diversity 则不建议机械稀释后直接作为默认主分析。对于细菌和病毒的组成差异，Bray-Curtis 通常是最稳妥的丰度距离；若有可靠系统发育树，可再补充 weighted UniFrac。正式报告应同时给出 ordination 图和 `adonis2()` 结果，并增加 `betadisper` 检查组内离散度，避免把 dispersion 差异误读为 centroid 差异。

若样本量较小，`Kruskal-Wallis` 更适合作为多组 alpha 比较的总体检验，再按需要补做成对 `Wilcoxon`。而 `NMDS` 则适合在非线性分离或 PCoA 前两轴解释率偏低时作为补充图，不需要替代主分析，只需要帮助确认群落结构是否稳定分离。

建议最终把细菌、病毒和真菌三套结果分开成表，再在汇总页统一解释。

## Rationale

- **为什么 alpha 建议稀释而 beta 不建议默认稀释**：alpha 的 richness/evenness 对测序深度很敏感，统一深度更公平；beta 距离则更适合用相对丰度或组合数据方法处理，过度稀释会丢信息并增加随机性。
- **为什么 Shannon 和 Chao1 要一起看**：Shannon 更强调均匀度与常见类群分布，Chao1 更强调 richness 和稀有特征补偿，两者一起才能区分“更均匀”与“更丰富”。
- **为什么细菌和病毒常用 Bray-Curtis**：它直接基于丰度差异，解释简单，对零值较多的生态数据较稳健，适合作为 bacterial/viral community 的主 beta 距离。
- **为什么 UniFrac 需要系统发育树**：weighted UniFrac 依赖分支长度衡量共享演化历史，没有可靠树就无法给出生物学合理的距离解释。
- **为什么 `PERMANOVA` 要配合 `betadisper`**：`adonis2()` 对组中心差异和组内离散度变化都可能敏感，不检查 dispersion 就可能把异质性误判为真正的组间分离。
- **为什么按维度分别做多样性分析**：细菌、病毒和真菌的特征定义、稀疏度和系统发育信息不同，强行混在一个矩阵里会降低解释力，也会混淆统计前提。
- **为什么 rarefaction depth 选择很关键**：深度过高会丢掉太多样本，深度过低又会削弱 richness 分辨率，所以应先看样本测序量分布再定阈值。
- **为什么同时报告排序图和统计检验**：PCoA 或 NMDS 只提供可视化直觉，只有把图和正式检验放在一起，才能避免“看起来分开”但统计上不显著的误读。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/91_stat_diversity.sh`
- `agents/skills/91_stat_diversity.yaml`
