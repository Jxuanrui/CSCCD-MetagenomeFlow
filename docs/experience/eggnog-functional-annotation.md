---
tool: "eggNOG-mapper v2.1"
dimension: "bacteria"
category: "functional-annotation"
author: ""
date: "2026-06-13"
tags: [functional-annotation, eggnog, cog, kegg, go]
scenario: [gut-microbiome, gene-catalog, shotgun-metagenomics]
---

# eggNOG-mapper 综合功能注释参数建议

## Scenario

> 适用于宏基因组组装、基因预测和去冗余后，需要把蛋白序列统一注释到 COG、KEGG KO、GO、EC 和 Pfam 等功能体系。

**关键参数速查**：Tool = `eggNOG-mapper v2.1`；Depends on = Prodigal protein FASTA (`*.faa`) 或流程内 CD-HIT 后的 `protein_nr.fa`；Key params = `--itype proteins`, `--cpu 16`, `--go_evidence non-electronic`, `--target_orthologs all`, `--tax_scope auto`, `--override`；Outputs = COG, KEGG KO, GO terms, EC numbers, Pfam。

当目标是获得综合功能画像而不是只看单一通路库时，eggNOG 是最宽的单步注释入口。相比 KEGG-only 注释，它更适合作为基因目录的基础功能层，后续再按 KO、COG、GO 或 EC 分别汇总。

## Recommendation

项目流程推荐直接运行包装脚本，它读取去冗余蛋白集并写出统一注释表：

```bash
# Run eggNOG-mapper on the non-redundant protein catalog.
bash scripts/21_bac_eggnog.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果从 Prodigal 的 `*.faa` 直接运行 eggNOG-mapper，建议显式写出关键参数，便于审计和复现：

```bash
# Direct eggNOG-mapper v2.1 command for protein FASTA input.
emapper.py \
  -m diamond \
  --itype proteins \
  -i prodigal.genes.faa \
  --data_dir db/eggnog \
  --cpu 16 \
  --go_evidence non-electronic \
  --target_orthologs all \
  --tax_scope auto \
  -o eggnog \
  --output_dir result/eggnog \
  --temp_dir result/eggnog/tmp \
  --override
```

主要结果是 `eggnog.emapper.annotations`，其中可提取 COG category、KEGG KO、GO terms、EC numbers、Pfam 以及 seed ortholog 信息。

## Rationale

- **为什么输入用蛋白 FASTA**：Prodigal 已完成 ORF 预测，`--itype proteins` 避免 eggNOG 重新预测基因，减少不一致来源。
- **为什么优先注释去冗余基因集**：对 `protein_nr.fa` 注释一次即可复用到所有样本的丰度矩阵，避免每个样本重复跑相同蛋白。
- **为什么用 DIAMOND 模式**：宏基因组基因目录通常很大，`-m diamond` 在速度和灵敏度之间更适合批量项目。
- **为什么设置 `--go_evidence non-electronic`**：过滤纯电子推断 GO 证据能提升 GO 解释的保守性，减少低可信泛注释。
- **为什么使用 `--target_orthologs all`**：宏基因组物种来源复杂，保留所有目标 ortholog 比只取窄范围 ortholog 更不容易漏注释。
- **为什么保留 `--tax_scope auto`**：自动分类范围能让 eggNOG 根据命中情况选择合适的注释上下文，适合混合菌群。
- **为什么加 `--override`**：批量流程中重跑同一路径很常见，显式覆盖能避免旧结果残留导致任务中断。
- **为什么 eggNOG 优先于 KEGG-only**：eggNOG 同时给出 COG、KO、GO、EC、Pfam 等多维字段，是构建综合功能 profile 的更完整入口。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/21_bac_eggnog.sh`
- `agents/skills/21_bac_eggnog.yaml`
