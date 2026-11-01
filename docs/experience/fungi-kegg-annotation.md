---
tool: "KEGG + DIAMOND"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [fungi, kegg, ko, diamond, pathway]
scenario: [mycobiome, fungal-proteins, kegg-annotation]
---

# 真菌 KEGG KO 注释建议

## Scenario

> 关键参数速查：`82_fun_kegg.sh` 依赖 step 80，聚合收集全部真菌 FAA；`diamond blastp` 比对 `db/kegg/*.dmnd`；阈值 `--evalue 1e-5`；输出 `result/fungi/kegg/kegg_diamond.tsv`；建议与 eggNOG 同跑以交叉验证 KO。

这一步和细菌 `22_bac_kegg.sh` 的思路一致，都是把蛋白序列直接比对到本地 KEGG 蛋白数据库，再把命中整理到 KO 和 pathway 层。区别在于这里的查询序列来自 `result/fungi/prodigal/*/*.faa`，目标是解释 mycobiome 的代谢潜力。

KEGG-only 注释不应替代 eggNOG。更稳妥的做法是先用 eggNOG 获得宽覆盖功能表，再用 KEGG DIAMOND 输出验证关键 KO，尤其是要进入通路重建、模块完整度或代谢能力比较的 KO。

## Recommendation

推荐直接运行包装脚本，保持和细菌 KEGG 注释一致的 DIAMOND 参数框架。

```bash
# Run KEGG annotation on merged fungal proteins.
bash scripts/82_fun_kegg.sh \
  -t 16 \
  -w /path/to/project \
  -r ${PROJ_DIR}
```

脚本会自动选择 `db/kegg/` 下的第一个 `.dmnd` 数据库，合并所有真菌 `.faa`，并输出 BLAST m6 风格结果表。

```bash
diamond blastp \
  --db db/kegg/kegg.dmnd \
  --query result/fungi/kegg/combined_fungi.faa \
  --out result/fungi/kegg/kegg_diamond.tsv \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 1 \
  --sensitive \
  --threads 16
```

`kegg_diamond.tsv` 是同源搜索证据表，通常还需要通过 `sseqid -> KO` 映射整理后，才进入 pathway 或 module 汇总。

## Rationale

- **为什么使用 DIAMOND**：真菌蛋白集合可能很大，`diamond blastp` 比传统 BLAST 更适合批量宏基因组注释。
- **为什么 `--evalue 1e-5`**：该阈值与脚本一致，作为 KEGG 同源转移的默认过滤可减少弱随机命中。
- **为什么 `--max-target-seqs 1`**：KO 注释通常需要每条蛋白的最可信候选，best-hit 策略更便于后续通路解释。
- **为什么依赖 step 80**：`82_fun_kegg.sh` 不做基因预测，只消费 Prodigal 产生的真菌蛋白 FASTA。
- **为什么和 eggNOG 同跑**：eggNOG 与 KEGG DIAMOND 使用不同证据路径，KO 一致时可信度更高，不一致时可优先复核关键通路基因。
- **为什么沿用细菌脚本思路**：相同输出格式和阈值框架能降低 bacteria 与 mycobiome 多维功能结果的整合成本。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/82_fun_kegg.sh`
- `scripts/22_bac_kegg.sh`
- `docs/experience/kegg-pathway-annotation.md`
