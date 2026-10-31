---
tool: "card-rgi"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [amr, card, rgi, diamond, aggregate-step]
scenario: [gut-microbiome, gene-catalog, antibiotic-resistance]
---

# CARD/RGI 抗性机制扩展注释建议

## Scenario

> 关键参数速查：适用于 step 18 已生成 `protein_nr.fa` 的全队列聚合注释；脚本 `24_bac_card.sh` 非按样本运行，仅需 `-t CPUS -w WORKDIR -r REPO`；`RGI 6.x + CARD 3.x` 使用 `--alignment_tool DIAMOND`、`--local`、`--clean`；输入 `result/assembly/cdhit/protein_nr.fa`；输出 `rgi_results.txt` 与 `rgi_results.json`，含 `Best_Hit_ARO`、resistance mechanism、drug class。

CARD/RGI 更适合在 resistome 分析里补充“机制层”的解释，尤其是外排泵、多药耐受和更宽泛的抗性相关蛋白家族。

如果目标是以 NCBI 整理命名为主的核心 ARG 清单，AMRFinder 更适合作为主表；如果目标是扩大对耐药机制空间的覆盖，CARD/RGI 应作为关键补充。

## Recommendation

推荐把 CARD/RGI 放在 `protein_nr.fa` 聚合层执行，而不是对每个样本重复跑一次。这样既符合脚本设计，也能避免对同源蛋白反复注释。

```bash
# Run CARD/RGI once on the merged non-redundant protein catalog.
bash scripts/24_bac_card.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

在项目报告中，建议把 `rgi_results.txt` 作为人工审阅主表，把 `rgi_results.json` 作为后续程序化抽取机制、药物类别和 ARO 标识的结构化来源。

如果同时运行 `23_bac_amrfinder.sh` 与 `24_bac_card.sh`，推荐用 AMRFinder 负责 NCBI-curated 基因家族主命名，用 CARD/RGI 负责扩展机制解释，尤其是 efflux pumps 及更宽的 resistance mechanism 注释。

## Rationale

- **为什么在 `protein_nr.fa` 层运行**：脚本就是围绕 `18_bac_cdhit.sh` 的非冗余蛋白目录设计，聚合执行能减少重复比对和注释漂移。
- **为什么使用 `DIAMOND`**：脚本明确指定 `--alignment_tool DIAMOND`，相较 BLAST 约快 `100x`，更适合大规模宏基因组蛋白集。
- **为什么使用 `--local`**：本地 CARD 数据库让流程离线、可复现，也避免运行时数据库版本不一致的问题。
- **为什么保留 `--clean`**：RGI 中间文件体积不小，脚本默认清理临时文件，更适合长期项目目录维护。
- **为什么 CARD/RGI 适合补充 AMRFinder**：CARD/RGI 对 broader resistance mechanisms 的覆盖更强，特别是 efflux pumps 等边界类型更有价值。
- **为什么 AMRFinder 仍适合做主表**：AMRFinder 更强调 NCBI-curated gene families，命名和家族边界通常更适合主结果整理。
- **为什么同时保留 `.txt` 与 `.json`**：文本结果方便人工检查命中细节，JSON 更适合后续自动抽取 `Best_Hit_ARO`、drug class 和机制字段。
- **为什么属于 aggregate step**：耐药注释面对的是全项目合并后的非冗余蛋白集，而不是单样本 reads 或 contigs。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/24_bac_card.sh`
- Alcock et al. 2023 NAR
- McArthur et al. 2013 AAC
