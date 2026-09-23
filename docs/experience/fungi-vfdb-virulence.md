---
tool: "VFDB + DIAMOND"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [fungi, vfdb, virulence, diamond, pathogenicity]
scenario: [mycobiome, fungal-proteins, virulence-factors]
---

# 真菌 VFDB 毒力因子注释建议

## Scenario

> 关键参数速查：`84_fun_vfdb.sh` 依赖 step 80，聚合真菌 FAA；`diamond blastp` 比对 `db/vfdb/*.dmnd`；阈值 `--evalue 1e-5`；输出 `result/fungi/vfdb/vfdb_hits.tsv`；同一 VFDB 数据库用于细菌和真菌蛋白集。

这一步把 VFDB 从细菌注释扩展到真菌蛋白集合，重点寻找 Candida adhesins、Aspergillus gliotoxin 相关蛋白、Cryptococcus capsule genes 等潜在毒力线索。VFDB 数据库可包含细菌和真菌毒力因子，关键在于把查询蛋白集限定为真菌 Prodigal 产物。

VFDB 命中不是“真菌致病性”的直接判定。它更适合作为功能证据层，和真菌分类组成、丰度变化、AMR 结果以及宿主表型一起解释潜在风险。

## Recommendation

推荐直接运行包装脚本，保持和细菌 VFDB 注释一致的 DIAMOND 输出格式。

```bash
# Run VFDB search on merged fungal proteins.
bash scripts/84_fun_vfdb.sh \
  -t 16 \
  -w /path/to/project \
  -r ${PROJ_DIR}
```

脚本会合并所有 `result/fungi/prodigal/*/*.faa`，并对 `db/vfdb/*.dmnd` 执行 `diamond blastp`。

```bash
diamond blastp \
  --db db/vfdb/vfdb.dmnd \
  --query result/fungi/vfdb/combined_fungi.faa \
  --out result/fungi/vfdb/vfdb_hits.tsv \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 1 \
  --sensitive \
  --threads 16
```

结果整理时建议保留 identity、alignment length、e-value 和 bitscore，并对关键命中做人工复核，避免把保守结构域命中误解为完整毒力机制。

## Rationale

- **为什么 VFDB 可用于真菌集合**：项目使用同一 VFDB DIAMOND 数据库，但查询序列换成真菌蛋白，因此可筛选真菌相关毒力因子命中。
- **为什么关注 Candida、Aspergillus 和 Cryptococcus**：这些属包含临床相关机会致病真菌，其 adhesin、毒素、胶囊或分泌相关蛋白有明确解释价值。
- **为什么使用 `--evalue 1e-5`**：脚本内置阈值能过滤较弱命中，适合作为统一默认起点。
- **为什么不能直接下致病结论**：VFDB 是序列相似性证据，命中毒力相关蛋白不等于该菌株在样本中表达、完整或具备表型毒力。
- **为什么和细菌 VFDB 结果分开统计**：同一数据库可以共用，但 bacteria 和 mycobiome 的查询背景不同，混合统计会模糊来源。
- **为什么需要人工复核关键命中**：真菌毒力因子常涉及基因家族和保守结构域，重要结论应检查比对覆盖度和命中注释。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/84_fun_vfdb.sh`
- `scripts/26_bac_vfdb.sh`
- `docs/experience/vfdb-virulence-factors.md`
