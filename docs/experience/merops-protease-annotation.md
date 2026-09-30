---
tool: "MEROPS + DIAMOND"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [fungi, merops, protease, diamond, virulence]
scenario: [mycobiome, fungal-proteins, protease-annotation]
---

# 真菌 MEROPS 蛋白酶注释建议

## Scenario

> 关键参数速查：`86_fun_merops.sh` 依赖 step 80，聚合真菌 FAA；`diamond blastp` 比对 `db/merops/*.dmnd`；阈值 `--evalue 1e-5`；输出 `result/fungi/merops/merops_hits.tsv`；MEROPS 按催化机制分类蛋白酶。

MEROPS 注释用于识别和分类真菌蛋白酶，尤其适合解释 Candida secreted aspartyl proteases、Aspergillus protease secretion 等与侵袭性、组织互作和营养获取相关的功能线索。它补充的是蛋白水解能力，不应被 KEGG 或 eggNOG 的泛功能注释完全替代。

MEROPS 的核心价值在于按 catalytic mechanism 和 family 层级组织蛋白酶，例如 serine protease、cysteine protease 和 metalloprotease。报告时应优先汇总 family/class，而不是只统计原始命中行数。

## Recommendation

推荐直接运行包装脚本，在全项目真菌蛋白集合上做一次 MEROPS 搜索。

```bash
# Run MEROPS protease annotation on merged fungal proteins.
bash scripts/86_fun_merops.sh \
  -t 16 \
  -w /path/to/project \
  -r ${PROJ_DIR}
```

脚本会自动查找 `db/merops/*.dmnd` 并输出精简的 DIAMOND 命中表。

```bash
diamond blastp \
  --db db/merops/merops.dmnd \
  --query result/fungi/merops/combined_fungi.faa \
  --out result/fungi/merops/merops_hits.tsv \
  --outfmt 6 qseqid sseqid pident length evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 1 \
  --sensitive \
  --threads 16
```

下游整理时建议把 `sseqid` 映射到 MEROPS family、clan 和 catalytic type，再与真菌物种来源和 VFDB 命中一起解释潜在侵袭性或宿主互作。

## Rationale

- **为什么单独做 MEROPS**：蛋白酶是许多真菌宿主互作和侵袭性机制的重要功能类，泛功能注释不一定能提供足够清晰的家族分类。
- **为什么使用 DIAMOND**：真菌蛋白集合规模大，DIAMOND 能快速完成 MEROPS 库的蛋白同源搜索。
- **为什么 `--evalue 1e-5`**：该阈值与脚本一致，适合作为蛋白酶候选命中的默认过滤。
- **为什么关注催化机制**：serine、cysteine 和 metalloprotease 等类别对应不同生物化学机制，比原始命中数量更可解释。
- **为什么与 VFDB 联动**：蛋白酶命中可以作为毒力或宿主互作的补充证据，但需要结合 VFDB、物种和丰度背景共同解释。
- **为什么依赖 step 80**：`86_fun_merops.sh` 不预测基因，只消费 Prodigal 生成并自动合并的真菌 `.faa` 文件。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/86_fun_merops.sh`
