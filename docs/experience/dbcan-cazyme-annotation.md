---
tool: "dbCAN3"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-13"
tags: [dbcan, cazyme, cazy, hmmer, diamond, ecami]
scenario: [gut-microbiome, gene-catalog, carbohydrate-active-enzyme]
---

# dbCAN3 CAZyme 注释参数建议

## Scenario

> 适用于完成基因预测和蛋白去冗余后，需要对 assembled gene catalog 做 CAZyme 注释，并评估肠道微生物群的碳水化合物降解与合成潜力。

CAZyme 注释不应只依赖单一搜索工具，因为 HMM profile、序列相似性和 signature rule 对不同家族的敏感性与特异性不同。dbCAN3 的核心价值是把 HMMER、DIAMOND 和 eCAMI 三路证据合并，用三工具投票减少假阳性，最终把高可信结果集中到 `overview.txt`。

在肠道微生物组研究中，CAZyme 结果通常不是逐条基因解释，而是汇总到 GH、GT、PL、CE、AA 和 CBM 等 family 层级。特别是 GH glycoside hydrolase 和 GT glycosyltransferase 的分布，常用于解释复杂多糖利用、宿主黏液降解、膳食纤维响应和菌群代谢生态位。

**关键参数速查**：Tool = `dbCAN3`；Depends on = step `18_bac_cdhit` 输出的 `protein_nr.fa`；Key params = three-tool voting (`HMMER + DIAMOND + eCAMI`, ≥2/3 = high confidence), HMMER HMM search, DIAMOND blastp, eCAMI signature, `--db_dir db/dbcan`；Input = `protein_nr.fa` from step 18；Output = `overview.txt` voted results。

## Recommendation

```bash
# Run dbCAN3 CAZyme annotation on the non-redundant protein catalog.
bash scripts/25_bac_dbcan.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如需直接运行并显式启用三工具投票，建议写出完整命令，确保 `overview.txt` 来自 HMMER、DIAMOND 和 eCAMI 的综合结果：

```bash
# Direct dbCAN3 command with all evidence channels enabled.
run_dbcan \
  /path/to/project/result/assembly/cdhit/protein_nr.fa \
  protein \
  --tools all \
  --db_dir /path/to/CSCCD-MetagenomeFlow/db/dbcan \
  --out_dir /path/to/project/result/dbcan \
  --dia_cpu 16 \
  --hmm_cpu 16
```

报告层面建议优先使用 `overview.txt` 作为高可信 CAZyme 主表，再按 CAZy family 统计 GH、GT 等类别丰度。若研究问题更偏向发现潜在新家族，可以补充查看 `hmmer.out`，但不应把单工具结果直接等同于最终 CAZyme 注释。

## Rationale

- **为什么使用三工具投票**：单一 CAZyme 识别工具可能有约 30% 假阳性，至少 2/3 工具一致能显著提升最终调用的保守性。
- **为什么 `overview.txt` 作为主结果**：该文件整合 HMMER、DIAMOND 和 eCAMI 证据，只保留投票后的高可信调用，比单独输出更适合下游统计。
- **为什么保留 HMMER HMM search**：HMM profile 对远缘同源蛋白更敏感，能捕捉序列相似性较低但结构域保守的 CAZyme。
- **为什么同时运行 DIAMOND blastp**：DIAMOND 提供快速序列相似性证据，对已知 CAZy 家族成员的近缘匹配速度快、解释直接。
- **为什么加入 eCAMI signature**：signature-based 判断能补充 motif 与家族特异位点信息，降低仅靠全局相似性带来的误判。
- **为什么输入用 `protein_nr.fa`**：对去冗余蛋白集注释一次即可映射回丰度矩阵，避免重复注释同源蛋白并减少计算量。
- **为什么关注 GH 和 GT 分布**：GH 直接反映多糖水解潜力，GT 反映糖基转移和细胞表面糖链合成能力，是肠道 CAZyme 结果最常报告的两类。
- **为什么不直接用单工具全量结果做图**：单工具敏感性高但假阳性也高，直接进入差异分析会放大噪声并误导 family-level 解释。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/25_bac_dbcan.sh`
- `agents/skills/25_bac_dbcan.yaml`
