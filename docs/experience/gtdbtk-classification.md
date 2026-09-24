---
tool: "gtdbtk"
dimension: "bacteria"
category: "taxonomy"
author: ""
date: "2026-06-11"
tags: [mag-classification, gtdb, reference-consistency]
scenario: [gut-microbiome, cross-cohort, high-depth]
---

# GTDB-Tk MAG 分类与数据库一致性建议

## Scenario

> 适用于 dRep 去冗余后的 MAG 集合，需要给代表基因组分配统一、可比较的系统发育标签。

GTDB-Tk 在这里服务的是 MAG catalogue，而不是 raw reads 分类，因此它的稳定性首先依赖输入 MAG 质量与数据库路径一致性。

本项目脚本默认跑 `classify_wf`，并启用 `--skip_ani_screen`。

## Recommendation

默认推荐直接沿用脚本设置：

```bash
gtdbtk classify_wf \
  --genome_dir result/binning/drep/dereplicated_genomes \
  --out_dir result/binning/gtdbtk \
  -x fa \
  --cpus 16 \
  --skip_ani_screen \
  --force
```

在项目环境中，优先确保 `GTDBTK_DATA_PATH` 指向仓库内固定数据库目录 `db/gtdbtk/`。

正式项目建议始终对 dRep 之后的代表 MAG 运行 GTDB-Tk，而不是对未去冗余的全量 MAG 批量分类。

如果主要对象是细菌 MAG，优先以 `gtdbtk.bac120.summary.tsv` 为主表；古菌则单独查看 `gtdbtk.ar53.summary.tsv`。

`--skip_ani_screen` 可以保留，尤其在 MAG 数量较多时，这能减少额外比对时间。

如果团队后续要做系统树展示，保留 `align/gtdbtk.bac120.user_msa.fasta.gz`，不要只存 summary 表。

## Rationale

- **为什么先 dRep 再 GTDB-Tk**：重复 MAG 会造成重复分类和解释噪声，先压缩代表集更高效，也更接近 catalogue 思路。
- **为什么数据库路径一致性最重要**：GTDB-Tk 的分类结果是强参考依赖的；数据库目录错位或版本混乱，会直接导致不可比结果。
- **为什么脚本自动设置 `GTDBTK_DATA_PATH`**：这是该工具最常见的环境坑之一，自动绑定仓库路径能降低“环境能跑但结果不一致”的风险。
- **为什么 `--skip_ani_screen` 可以接受**：对大批 MAG 来说，主价值在 marker-based 分类框架；跳过 ANI 预筛能显著节省时间。
- **为什么仍要保留 MSA**：summary 只给标签，MSA 才支持系统发育树、异常分类复核和代表 MAG 关系展示。
- **为什么要区分 bac120 与 ar53**：细菌和古菌使用不同 marker 集，混着看 summary 会模糊解释边界。
- **为什么 GTDB-Tk 结果不是质量担保**：它能给分类，不代表 MAG 本身高完整、低污染；质量判读仍要回到 CheckM2/dRep 输入阶段。
- **为什么代表 MAG 数量会影响耗时**：`classify_wf` 在数量上近似线性扩展，去冗余后的规模控制能直接缩短整体 wall time。
- **为什么适合做跨项目对比**：GTDB 标签体系比各自手工命名的 bin 更统一，适合作为后续丰度、功能、宿主关联分析的索引键。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/40_bac_gtdbtk.sh`
- `agents/skills/40_bac_gtdbtk.yaml`
- 输入目录：`result/binning/drep/dereplicated_genomes`
- 输出主表：`classify/gtdbtk.bac120.summary.tsv`
