---
tool: "ANCOM-BC2"
dimension: "statistics"
category: "differential_abundance"
author: ""
date: "2026-06-13"
tags: [ancombc2, differential-abundance, compositional-data, maaslin2]
scenario: [disease-vs-control, metagenomics, covariate-adjusted-modeling]
---

# ANCOM-BC2 差异丰度分析建议

## Scenario

> 适用于完成多样性分析后，需要在疾病组与对照组之间识别差异 taxa 或功能基因，并在 compositional metagenomics 前提下控制协变量和多重检验。

这类分析不能再把每个特征当作独立绝对丰度做普通 `t-test` 或 `Wilcoxon`。宏基因组矩阵本质上是 compositional data，测到的是相对份额而不是真实总量，因此主分析应优先使用 ANCOM-BC2 这类显式处理 sampling fraction 与偏差校正的方法。

项目当前 `scripts/92_stat_differential.sh` 已经集成 `ANCOMBC`, `ALDEx2`, `MaAsLin2` 和 `LinDA`。本文把 `ANCOM-BC2` 作为主推荐方法，同时把 `DESeq2`、`MaAsLin2` 和 `LEfSe` 放在补充层：`DESeq2` 适合原始 count 风格矩阵，`MaAsLin2` 适合连续型或多协变量元数据，`LEfSe` 更适合探索性 biomarker 筛查而不是单独作为最终证据。

**关键参数速查**：Tool = `ANCOMBC2(formula=~group+covariate)`；Depends on = diversity step `91` 产物与同批 metadata；Key params = `p_adj_method="BH"`, `alpha=0.05`, `max_iter=100`；Supplementary = `DESeq2` for count data, `MaAsLin2` for continuous metadata, `LEfSe` for exploratory biomarker discovery；Rule = consensus taxa from `>=2` methods are most reliable.

## Recommendation

```bash
# Run the project differential abundance wrapper after diversity analysis.
THREADS=16                        # compute threads
WORKDIR=/path/to/project          # project workdir with merged abundance tables
REPO=/path/to/CSCCD-MetagenomeFlow       # repo root with envs/r_stat
META=/path/to/project/metadata.csv  # metadata containing group and confounders
bash scripts/92_stat_differential.sh -w "$WORKDIR" -r "$REPO" -t "$THREADS" -m "$META" -g group -d all
```

推荐在 R 层显式把模型写成 `ANCOMBC2(formula = ~ group + age + sex + BMI, p_adj_method = "BH", alpha = 0.05, max_iter = 100)`，不要只放 `group` 一个变量。只要存在年龄、性别、BMI、批次、抗生素使用等潜在混杂因素，就应放进固定效应公式，否则所谓“差异丰度”很可能只是协变量分布不平衡。

结果解释上，建议把 ANCOM-BC2 作为主结论来源，再查看 DESeq2、MaAsLin2 或 ALDEx2 是否支持同方向变化。至少被两种方法重复检出的 taxa 或基因更可靠；LEfSe 可以用于可视化和探索性筛查，但不建议把它单独当成核心统计证据。

如果比较不是单纯二分类，而是连续表型、时间序列或多水平暴露变量，`MaAsLin2` 往往比 `LEfSe` 更适合作为补充模型。相反，`LEfSe` 适合快速生成候选 biomarker 列表，但应在正式结论前再经 ANCOM-BC2 或其他可调整协变量的方法复核。

报告层面应同时给出效应方向、效应量和校正后 `q-value`，不要只列显著与否。

## Rationale

- **为什么 ANCOM-BC2 优于普通 `t-test`/`Wilcoxon`**：普通检验默认比较的是独立绝对量，而宏基因组表是 compositional，相对丰度之间存在闭合约束，直接套用常规检验会产生系统性偏差。
- **为什么 compositional data 需要特殊处理**：一个类群相对丰度上升，可能只是其他类群下降导致的份额变化；ANCOM-BC2 通过偏差校正和 sampling fraction 建模，减少这类伪差异。
- **为什么公式里必须放协变量**：年龄、性别、BMI、批次、药物使用等变量常常与疾病状态共变，不显式建模就无法把真正的组效应和混杂效应区分开。
- **为什么使用 BH 多重校正**：宏基因组差异分析通常同时测试成百上千个特征，若不控制 FDR，显著结果会被大量偶然命中淹没；BH 是当前最常用且可解释的标准做法。
- **为什么强调多方法共识**：不同方法对零值、归一化、离群点和模型假设的敏感性不同，至少两种方法一致的特征通常比单一方法阳性更稳健。
- **为什么 LEfSe 只能算探索性**：LEfSe 对参数、预过滤和分层结构较敏感，且更偏 biomarker ranking，不适合作为 compositional metagenomics 的唯一推断依据。
- **为什么 `5% FDR` 是常见标准**：`q < 0.05` 在组学研究中是平衡发现率和假阳性的通用门槛，过宽会放大噪声，过严则容易错失中等效应但稳定的特征。
- **为什么 DESeq2 和 MaAsLin2 仍然值得保留**：DESeq2 对 count-like 数据和离散度建模成熟，MaAsLin2 对连续元数据和多协变量回归更灵活，作为补充视角可以帮助评估结果稳健性。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/92_stat_differential.sh`
- `agents/skills/92_stat_differential.yaml`
