---
tool: "VOGDB + HMMER 3.3+"
dimension: "virome"
category: "annotation"
author: "team"
date: "2026-06-14"
tags: [vogdb, hmmer, hmmsearch, viral-proteins, annotation]
scenario: [virome, pharokka-proteins, hmm-annotation]
---

# VOGDB HMMER 病毒蛋白注释建议

## Scenario

> 适用于 `64` PHAROKKA 已预测蛋白后，用 `66_vir_vog.sh` 对 `phanotate.faa` 做 VOGDB HMM 扫描；关键参数：HMMER3 `hmmsearch`、建议 `--cut_ga` 使用 profile GA threshold、aggregate run；输入 `result/virus/pharokka/phanotate.faa`；输出 `vog_hits.tsv` 与 `vog_annot.tsv`。

VOGDB HMM 扫描适合作为 PHAROKKA/PHROG 的补充注释层，尤其在研究对象不只限于噬菌体时更有价值。

PHROG 更偏 bacteriophage protein families；VOG 覆盖 bacterial、archaeal 和 eukaryotic viruses 的 orthologous groups，因此能为跨界病毒 catalogue 提供更宽的功能注释背景。

本项目脚本把 VOG 注释作为 aggregate step，输入来自 PHAROKKA 预测蛋白，而不是重新预测 ORF。这样可以让功能证据都回到同一套蛋白 ID 上。

## Recommendation

推荐在 PHAROKKA 输出 `phanotate.faa` 后运行：

```bash
# Run VOGDB HMM scan on PHAROKKA-predicted viral proteins.
bash scripts/66_vir_vog.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

主输出为 `result/virus/vog/vog_hits.tsv` 和 `result/virus/vog/vog_annot.tsv`。

如果直接调用 HMMER，建议优先使用 profile 自带阈值：

```bash
hmmsearch \
  --cut_ga \
  --cpu 16 \
  --tblout result/virus/vog/vog_hits.tsv \
  db/vogdb/VOG.hmm \
  result/virus/pharokka/phanotate.faa
```

若当前 wrapper 使用固定 E-value 阈值，也应在方法中记录该阈值，并在需要高特异性结果时优先切换到 `--cut_ga`。

## Rationale

- **为什么使用 HMM 而不是普通 BLAST**：HMM profile 能捕捉蛋白家族保守模式，对远缘同源比单条序列相似性更敏感。
- **为什么建议 `--cut_ga`**：GA threshold 是 profile 级别的 curated cutoff，通常比统一 E-value 更符合不同蛋白家族的判定边界。
- **为什么 VOG 能补充 PHROG**：VOGDB 覆盖细菌、古菌和真核病毒，适合跨界病毒注释；PHROG 更专注噬菌体。
- **为什么依赖 PHAROKKA 蛋白**：复用同一套 predicted proteins 可以避免不同 ORF caller 造成 ID 和边界不一致。
- **为什么这是 aggregate step**：vOTU catalogue 的功能注释应在代表蛋白集合上完成，避免样本级冗余污染最终注释表。
- **为什么保留 hits 与 annot 两张表**：命中表用于阈值和统计追溯，注释表用于下游合并和功能解释。
- **为什么不能只看命中数量**：HMM hit 数受数据库大小、阈值和蛋白预测质量影响，应结合 family function 与 coverage 解释。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_hits=557, Exit: 0, Duration: 300s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/66_vir_vog.sh`
- `scripts/64_vir_pharokka.sh`
- 输入：`result/virus/pharokka/phanotate.faa`
- 输出：`result/virus/vog/vog_hits.tsv`
- 输出：`result/virus/vog/vog_annot.tsv`
