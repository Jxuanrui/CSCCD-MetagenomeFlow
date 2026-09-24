---
tool: "centrifuger"
dimension: "bacteria"
category: "taxonomy"
author: ""
date: "2026-06-14"
tags: [protein-level-classification, gtdb, refseq, species-resolution]
scenario: [gut-microbiome, paired-end, per-sample]
---

# Centrifuger 蛋白级高精度分类建议

## Scenario

> 关键参数速查：适用于已完成 kneaddata 的双端样本、需要更高种/株水平分类精度时使用；脚本 `15_bac_centrifuger.sh` 按样本运行：`-s SAMPLE -t CPUS -w WORKDIR -r REPO`；数据库 `db/centrifuger/cfr_gtdb_r226+refseq_hvfc`（GTDB R226 + RefSeq，约 `166G`）；内存建议 `>=100G`；输出 `{sample}.kreport.tsv` 与 `{sample}.classifications.tsv.gz`；速度约比 Kraken2 慢 `2.3x`。

Centrifuger 在本项目中的定位是正式分析阶段的高精度分类器，尤其适合需要把结果下沉到 species 或 strain 邻近层级时使用。

如果目标是快速获得广覆盖结果，Kraken2 更合适；如果目标是 marker-based 稳健物种谱，MetaPhlAn4 更保守；如果目标是尽量提高近缘物种区分能力，优先考虑 Centrifuger。

## Recommendation

推荐把 Centrifuger 用作高精度补充或正式 taxonomy 主结果，前提是节点具备足够内存，并接受比 Kraken2 更长的运行时间。

```bash
# Run Centrifuger per sample with the project GTDB R226 + RefSeq database.
bash scripts/15_bac_centrifuger.sh \
  -s SRR28210342 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

主结果建议优先使用 `{sample}.kreport.tsv`，因为它是 Kraken2 兼容格式，后续更容易并入现有统计和可视化流程。

`{sample}.classifications.tsv.gz` 建议保留为审计级输出，仅在需要追踪单条 read 分类、检查边界命中或做工具比较时再展开使用。

如果一个项目同时运行 MetaPhlAn4、Kraken2 和 Centrifuger，推荐把三者角色分清：MetaPhlAn4 作为保守 marker 参考，Kraken2 作为快速广谱扫描，Centrifuger 作为高精度 species/strain 判读依据。

## Rationale

- **为什么适合做高精度分类**：脚本说明其核心是 `FM-index + 蛋白级比对`，对近缘物种和属内区分通常比纯 k-mer 方法更稳。
- **为什么数据库值得保留为默认**：`GTDB R226 + RefSeq` 组合同时覆盖细菌、古菌及扩展参考序列，适合宏基因组正式分析场景。
- **为什么需要 `>=100G` 内存**：数据库体量约 `166G`，脚本已把高内存列为推荐前提，资源不足时更容易成为实际瓶颈。
- **为什么主看 `kreport.tsv`**：它是 Kraken2 兼容报告，便于进入下游汇总、矩阵化与跨工具对照，不必直接消费大体积逐 read 文件。
- **为什么保留 `classifications.tsv.gz`**：当 species 结果存在争议时，逐 read 输出能帮助核查 taxID、score 和单样本异常分类来源。
- **为什么不替代 Kraken2 的快速筛查角色**：脚本明确指出其速度约比 Kraken2 慢 `2-3x`，更适合精度优先而非吞吐优先。
- **为什么不替代 MetaPhlAn4 的保守主张**：MetaPhlAn4 依赖 marker gene，覆盖更窄但解释更保守；Centrifuger 更像高精度全量分类，而不是 marker-based 共识工具。
- **为什么适合种/株层分析**：脚本将其定位为“精度最高（尤其种/属级）”，因此更适合需要精细 taxonomy 解释的正式结果。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/15_bac_centrifuger.sh`
- Song & Langmead, Genome Biology 2024
- https://github.com/mourisl/centrifuger
