---
tool: "vfdb"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [virulence, vfdb, diamond, pathogenicity]
scenario: [gut-microbiome, gene-catalog, pathogenicity]
---

# VFDB 毒力因子注释建议

## Scenario

> 关键参数速查：适用于 step 18 产生的 `protein_nr.fa`，用于评估肠道细菌潜在致病性；脚本 `26_bac_vfdb.sh` 为聚合注释：`-t CPUS -w WORKDIR -r REPO`；使用 `diamond blastp` 比对 `db/vfdb/*.dmnd`；关键阈值 `--evalue 1e-5`；输出 `result/annotation/vfdb/vfdb_hits.tsv`；重点关注 adhesins、toxins、invasion factors。

VFDB 在本流程中的用途不是给细菌贴“致病/非致病”二元标签，而是整理潜在毒力因子证据，为宿主互作、炎症相关机制或机会致病风险提供线索。

它特别适合与物种组成和耐药注释联动解释，例如某些扩增菌是否同时携带黏附、侵袭或毒素相关蛋白。

## Recommendation

推荐直接复用项目脚本，在 `protein_nr.fa` 非冗余蛋白目录上执行一次 VFDB 比对。

```bash
# Run VFDB annotation on the merged non-redundant protein catalog.
bash scripts/26_bac_vfdb.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

结果主文件是 `result/annotation/vfdb/vfdb_hits.tsv`。建议后续整理时至少保留 `qseqid`、`sseqid`、`pident`、`length`、`evalue` 和 `bitscore`，便于筛选高可信命中。

如果项目里已经在跑 BacMet、NCyc、PCyc 等基于 DIAMOND 的蛋白注释，VFDB 可以沿用相同的结果整理逻辑与阈值解释框架，保持 annotation pipeline 一致性。

## Rationale

- **为什么使用 `protein_nr.fa`**：脚本依赖 `18_bac_cdhit.sh` 的输出，说明 VFDB 注释设计目标是全项目非冗余蛋白集，而不是逐样本重复搜索。
- **为什么用 `diamond blastp`**：它在大规模蛋白比对上速度和资源效率都更适合宏基因组目录注释。
- **为什么 `--evalue 1e-5` 是合理起点**：这是脚本内置阈值，能够先压掉较弱随机命中，适合作为统一项目默认值。
- **为什么不能把 VFDB 命中直接解释为致病菌**：毒力相关蛋白存在保守结构域和环境同源物，单次序列命中只能作为功能线索，不能直接等价于表型结论。
- **为什么适合肠道潜在致病性分析**：adhesins、toxins 和 invasion factors 往往比泛泛功能注释更直接指向宿主互作与风险机制。
- **为什么强调与 taxonomy 联动**：同一毒力因子在不同菌群背景下意义不同，结合物种丰度变化解释更稳。
- **为什么与 BacMet/NCyc/PCyc 保持一致有价值**：相同 DIAMOND 工作流、类似输出格式和统一阈值框架，能降低多套注释结果整合成本。
- **为什么主结果应先做高可信筛选**：bitscore、identity 和比对长度共同决定命中可信度，原始全量命中不适合直接进入结论表。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/26_bac_vfdb.sh`
- VFDB
- Buchfink et al. 2015
