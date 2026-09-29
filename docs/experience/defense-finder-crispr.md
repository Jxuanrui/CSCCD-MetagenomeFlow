---
tool: "DefenseFinder 1.x + MacSyFinder 2.x"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [defense-finder, macsyfinder, crispr, restriction-modification, phage-defense]
scenario: [gut-microbiome, protein-catalog, defense-system-annotation]
---

# DefenseFinder 宏基因组 NR 蛋白防御系统注释建议

## Scenario

> 适用于从 CD-HIT 步骤 18 得到 `protein_nr.fa` 后，用 `29_bac_defense_finder.sh` 检测细菌 CRISPR、Restriction/Modification 和 phage defense systems；关键参数：DefenseFinder 1.x + MacSyFinder 2.x，`--db-type unordered`，输入 `result/assembly/cdhit/protein_nr.fa`，输出 `defense_finder_systems.tsv`、`defense_finder_genes.tsv`。

宏基因组 NR 蛋白集通常已经失去连续基因组坐标和局部邻域信息，因此不应按完整染色体或完整 contig 的坐标上下文解释。DefenseFinder 在这里的定位是对非冗余蛋白目录进行防御系统候选注释，再结合 MAG 或 contig 来源做下游汇总。

## Recommendation

项目流程中建议直接使用脚本，并保持 `--db-type unordered`：

```bash
# Run DefenseFinder on the non-redundant protein catalog.
bash scripts/29_bac_defense_finder.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接运行时，应显式指定 DefenseFinder 数据库和 unordered 模式：

```bash
# Direct DefenseFinder command for metagenome NR proteins.
defense-finder run \
  --models-dir /path/to/CSCCD-MetagenomeFlow/db/defense-finder/defense-finder-db/models \
  --db-type unordered \
  --workers 16 \
  --out-dir result/annotation/defense_finder \
  result/assembly/cdhit/protein_nr.fa
```

主结果优先查看 `defense_finder_systems.tsv` 的系统级汇总；需要追踪具体命中蛋白、系统组成和后续 abundance 汇总时，再使用 `defense_finder_genes.tsv`。

## Rationale

- **为什么使用 `unordered`**：NR 蛋白集没有可靠的 genome coordinate context，ordered-replicon 模式假设输入序列来自可排序的连续 replicon，不适合 CD-HIT 后的蛋白目录。
- **为什么不使用 `ordered-replicon`**：该模式需要相邻基因和连续坐标来判断系统结构；宏基因组蛋白被聚类后，邻域关系会被打散，容易产生不合理的系统边界。
- **为什么输入 `protein_nr.fa`**：先用 CD-HIT 去冗余能减少重复蛋白带来的计算量和重复注释，同时让防御系统统计更接近 gene catalog 层面的候选集合。
- **为什么关注系统表和基因表**：系统表适合按 defense type 统计，基因表适合回溯具体 protein ID、模型命中和后续定量。
- **为什么适合 CRISPR/Restriction/Phage defense 初筛**：DefenseFinder 聚合多类细菌防御系统模型，比只看单个 marker gene 更适合做系统级候选注释。
- **下游注意点**：如果要解释系统完整性或基因邻域，应回到 MAG/contig 坐标层面复核，而不是只依赖 NR 蛋白结果。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References

- `scripts/29_bac_defense_finder.sh`
- `scripts/18_bac_cdhit.sh`

