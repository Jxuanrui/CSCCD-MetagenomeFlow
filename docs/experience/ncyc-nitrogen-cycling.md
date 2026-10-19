---
tool: "NCyc + DIAMOND"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [ncyc, diamond, nitrogen-cycling, functional-annotation, biogeochemistry]
scenario: [gut-microbiome, protein-catalog, nitrogen-cycle]
---

# NCyc 氮循环功能基因注释建议

## Scenario

> 适用于肠道宏基因组 `protein_nr.fa` 中氮循环基因筛查；工具 NCyc + DIAMOND，脚本 `30_bac_ncyc.sh`，数据库 `db/ncyc/*.dmnd`，参数 `diamond blastp --evalue 1e-5 --max-target-seqs 1 --sensitive`，输出 `result/annotation/ncyc/ncyc_hits.tsv`，目标基因包括 `nifH`、`nirK`、`nosZ`、`amoA` 等。

NCyc 适合在非冗余蛋白目录上做 N-cycle gene 的候选注释，常用于比较样本或队列中固氮、硝化、反硝化、异化硝酸盐还原等功能潜力。肠道样本中命中数量通常不应直接等同于活性，需要结合 abundance、表达或宿主分类来源解释。

## Recommendation

项目流程中使用脚本自动查找 NCyc DIAMOND 数据库并输出标准表：

```bash
# Run NCyc annotation through the project wrapper.
bash scripts/30_bac_ncyc.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接运行时，建议保留脚本中的敏感模式和 `1e-5` 阈值：

```bash
# Direct DIAMOND search against NCyc.
diamond blastp \
  --db /path/to/CSCCD-MetagenomeFlow/db/ncyc/NCyc.dmnd \
  --query result/assembly/cdhit/protein_nr.fa \
  --out result/annotation/ncyc/ncyc_hits.tsv \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 1 \
  --sensitive \
  --threads 16
```

分析时建议把 NCyc 命中先按 gene family 或 pathway step 汇总，再和 protein abundance 或 gene catalog abundance 合并，避免只用原始 hit 数比较样本。

## Rationale

- **为什么使用 NCyc**：NCyc 是面向 nitrogen cycle genes 的 curated database，比通用功能库更适合解释 N-cycle 专项基因。
- **为什么用 DIAMOND `blastp`**：输入是 Prodigal/CD-HIT 得到的蛋白序列，蛋白级搜索对远缘同源更稳健，速度也适合大规模基因目录。
- **为什么使用 `--evalue 1e-5`**：该阈值在召回候选 N-cycle genes 和过滤明显随机命中之间较平衡，适合作为宏基因组筛查起点。
- **为什么保留 `--max-target-seqs 1`**：每个蛋白只保留最佳命中，便于后续按基因家族去重统计；如需保守注释，可再叠加 identity、coverage 过滤。
- **为什么常与 PCyc 一起运行**：NCyc 和 PCyc 分别覆盖氮、磷循环基因，联合使用更适合做 biogeochemical functional potential 分析。
- **解释限制**：`nifH`、`nirK`、`nosZ`、`amoA` 等命中表示功能潜力，不代表该功能在样本中一定表达或发生。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References

- `scripts/30_bac_ncyc.sh`
- `scripts/18_bac_cdhit.sh`

