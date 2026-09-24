---
tool: "PCyc + DIAMOND"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [pcyc, diamond, phosphorus-cycling, phosphate, functional-annotation]
scenario: [gut-microbiome, protein-catalog, phosphorus-cycle]
---

# PCyc 磷循环功能基因注释建议

## Scenario

> 适用于从 `protein_nr.fa` 筛查磷循环基因；工具 PCyc + DIAMOND，脚本 `31_bac_pcyc.sh`，数据库 `db/pcyc/*.dmnd`，参数 `diamond blastp --evalue 1e-5 --max-target-seqs 1 --sensitive`，任务输出口径 `result/pcyc/pcyc_hits.tsv`，关注 `phoD`、`phnJ`、`ppx` 等 phosphate solubilization/transport 相关基因。

PCyc 在宏基因组项目中使用频率低于 NCyc，但对研究磷酸盐溶解、有机膦酸盐利用、polyphosphate metabolism 和 phosphate transport 很关键。肠道样本中建议把 PCyc 作为磷循环专项注释，而不是用通用 KO/eggNOG 结果完全替代。

## Recommendation

项目流程中使用脚本运行 PCyc 注释：

```bash
# Run PCyc annotation through the project wrapper.
bash scripts/31_bac_pcyc.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接运行时，建议沿用与 NCyc 一致的 DIAMOND 参数，便于两类生物地球化学功能结果比较：

```bash
# Direct DIAMOND search against PCyc.
diamond blastp \
  --db /path/to/CSCCD-MetagenomeFlow/db/pcyc/PCyc.dmnd \
  --query result/assembly/cdhit/protein_nr.fa \
  --out result/pcyc/pcyc_hits.tsv \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 1 \
  --sensitive \
  --threads 16
```

当前脚本变量使用 `result/annotation/pcyc/pcyc_hits.tsv` 作为实际输出目录；如果项目报告要求统一为 `result/pcyc/pcyc_hits.tsv`，需要在脚本或结果整理步骤中保持同一口径。

## Rationale

- **为什么使用 PCyc**：PCyc 面向 phosphorus cycling genes，可补充通用功能库对磷循环专项基因分类不够集中的问题。
- **为什么它仍然重要**：虽然 PCyc 不如 NCyc 常见，但在 phosphate solubilization、phosphonate metabolism 和 transport 研究中能提供更直接的功能标签。
- **为什么用 `protein_nr.fa`**：非冗余蛋白目录能减少重复命中，适合做 gene catalog 层面的磷循环功能潜力汇总。
- **为什么参数与 NCyc 保持一致**：相同的 `blastp`、`--evalue 1e-5` 和最佳命中策略便于在 N/P cycling 结果之间保持可比性。
- **为什么关注 `phoD`、`phnJ`、`ppx`**：这些基因分别代表有机磷矿化、膦酸盐利用和多聚磷代谢等常见磷循环过程。
- **解释限制**：PCyc 命中需要结合 identity、alignment length、coverage 和数据库注释字段复核，避免把短片段弱同源当作确定功能。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References

- `scripts/31_bac_pcyc.sh`
- `scripts/18_bac_cdhit.sh`

