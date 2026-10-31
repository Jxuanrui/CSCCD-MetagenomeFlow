# 统计功效与口径披露（POWER_DISCLOSURE）

> Project_demo 全链演示项目 · 2026-10-18 定稿 · 本文件为 98 终版报告的前置引用
> 质量审核第 9/10 轮审核要求落盘（`review16_cp2_review.md` P1、`review18_cp3_plan_review.md` W0）

## 一、3v3 设计的统计功效上限

**事实**：本项目 6 样本（treat×3 / control×3），定位为**流程使用演示**，非确证性研究。

- **三个概念分开表述**（CP3 终审 P0-5）：
  a) **置换空间**：组标签重排方式共 C(6,3) = 20 种（含原标签）；
  b) **p 值分辨率**：置换检验可达到的最小 p 值受置换空间限制（数量级 ~1/20，
     具体下限取决于检验实现与是否含原标签，此处不给无条件断言）；
  c) **统计功效**：n=3/组下检出中等效应量的功效本身不足（这与置换空间是
     两回事——即便置换空间够大，3/组的功效仍低）。
  **对小样本+多重检验场景，任何"显著"结果都应视为待更大队列验证的假设**，
  而非断言"校正后必然不显著"。
- 实测：`result/stat/diversity/permanova_results.tsv` 细菌 Pr(>F)=1、病毒 0.8（6 样本下
  独立标签置换仅 10 种）。
- LEfSe 三水平如时报 "No significant feature found"（`differential_status.tsv`）、
  Wilcoxon/MaAsLin2 n_sig=0——**这是功效上限的诚实体现，不是流程故障**。
- **解读纪律**：任何组间差异结果（含 DESeq2 的各 2 个显著特征：细菌 GGB33469_SGB15236
  p=7.87e-08、病毒 Sample3__k127_34328）在 n=3/组下仅具**探索性**价值，
  不得作为生物学结论引用。

## 二、共现网络与组间比较口径

- **网络本体**（5/5，`result/stat/network/network_summary.tsv`）：基于 6 样本全量构建
  （MetaNet spearman，特征预筛上限 300/域），**筛边使用未校正 p 值**——网络为
  探索性描述，不宜解读为确证性关联。
- **组间比较（NetCoMi）**：按质量审核第 6/7 轮裁定**有界披露**——
  a) 细菌域：3v3 逐组 SparCC 网络退化（`network/bacteria/group_compare.txt` 为退化
     诊断，"Status: unavailable"，非成功比较）；
  b) 其余 4 目标：2 小时总预算点终止 = SKIPPED(overall-timeout)；
  c) 根因与业界门槛：NetCoMi 默认 nPerm=1000（官方文档，**candidate_research**：逐次置换重建网络的机制为文档+推断）且量级为数天，而
     C(6,3)=20 使 ~98% 置换为重复计算；文献建议网络组间比较**每组 ≥25-30 样本**
     （Matchado et al. 2021, Front Microbiol，引用 426+；**candidate_research**：该 25-30/组 门槛来自综述与实务建议，非官方标准）。
  - 调研存档：`docs/research/2026-10-17_network_comparison_small_n.md`；
  - 未来方向（不列入本演示）：microeco 同系 meconetcomp、FlashWeave、SPIEC-EASI。

## 三、GEM 代谢模型链（9/10）

- 43 gapseq 10/10 ✓；**43b carveme 9/10**：Sample1__bin.025_sub 因 reframed 的 SCIP
  求解器 gapfill 空解（`TypeError: 'NoneType' object is not subscriptable`，
  `result/gem/carveme/Sample1__bin.025_sub/carveme.log`）失败，其 43c FBA 相应缺席
  （`result/gem/fba/` 实数 9 个 MAG 目录）。
- 口径：按演示定位不重试（工具内部数值问题，非流程缺陷）；名单为 CheckM2
  comp−cont 前 10（`logs/evidence/gem_top10.txt`）。

## 四、真菌统计双源口径

- **真菌分类数据仅 1/6 样本有内容**（Sample4：0.71% S. cerevisiae 全链一行到底；
  其余 5 样本 metaphlan4 谱 100% UNCLASSIFIED）。
- 两个统计消费者用**不同数据源**：
  - 91 多样性/92 差异：metaphlan4 谱 → fungi_mt 因 common=1<2 正确 SKIPPED；
  - 93 网络：`result/integration/fungi/funomic_species_count.tsv`（FunOMIC 检测计数，
    6 样本 ×11,941 taxa）→ 真菌网络可建（300 节点/13,853 边）。
- 口径：**真菌维度不产出多样性/差异结论**；真菌网络为检测计数口径的探索性描述，
  两源不可直接互相印证。

---

### 附：SIAMCAT 机器学习（SKIPPED-by-guard）

`96_stat_ml_siamcat` 输入治理守卫要求 **≥10 个元数据匹配样本**（实测 6/6），
按守卫拒绝执行并留痕（`logs/stat/ml/96_stat_ml_siamcat.run.log`）——与上述功效
上限同族，n=6 下 10 折交叉验证不具证据力，**不做也不应做**。
