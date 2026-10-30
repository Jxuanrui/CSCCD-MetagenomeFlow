---
tool: "checkv"
dimension: "virome"
category: "quality-control"
author: "team"
date: "2026-06-12"
tags: [parameter-tuning, virus-qc, completeness, contamination-trimming]
scenario: [gut-microbiome, assembled-contigs, vOTU-generation]
---

# CheckV 病毒 contig 质量分级与污染修剪建议

## Scenario

> 适用于 geNomad 和 VirSorter2 已完成候选病毒识别后，需要对病毒 contig 做完整度、污染、provirus 边界和近完整基因组状态评估。

典型样本是肠道 WGS metagenome 组装 contigs，输入应优先来自 geNomad 高分结果与 VirSorter2 共识集合，而不是未经筛选的全量组装序列。

CheckV 在这里承担类似 MIMAG 思路的病毒质量闸门：先判断序列是否足够完整、是否带有宿主污染，再决定能否进入 vOTU catalogue、宿主预测和生态统计。

## Recommendation

推荐将 geNomad 与 VirSorter2 候选合并去重后运行 `checkv end_to_end`，并使用 `quality_summary.tsv` 作为唯一过滤主表。

```bash
# Merge candidate viral contigs from geNomad and VirSorter2.
cat result/virus/genomad/sample/sample.contigs_virus.fna \
    result/virus/virsorter2/sample/final-viral-combined.fa \
  > result/virus/checkv/sample/_merged.fasta

# Remove duplicate sequences before CheckV.
seqkit rmdup -s \
  -o result/virus/checkv/sample/virus_contigs.fasta \
  result/virus/checkv/sample/_merged.fasta

# Run CheckV end-to-end quality assessment.
checkv end_to_end \
  result/virus/checkv/sample/virus_contigs.fasta \
  result/virus/checkv/sample \
  -d db/checkv \
  -t 16
```

主分析建议按 completeness 分层：`>=50%` 作为 high-quality vOTU 的最低门槛，`>=90%` 标记为 near-complete，`100%` 或存在可靠 DTR 的序列可作为 complete 候选。

```bash
# Keep high-quality viral contigs.
csvtk filter2 -t -f '$completeness >= 50 && $contamination <= 10' \
  result/virus/checkv/sample/quality_summary.tsv \
  > result/virus/checkv/sample/high_quality.min50.tsv

# Mark near-complete genomes.
csvtk filter2 -t -f '$completeness >= 90 && $contamination <= 5' \
  result/virus/checkv/sample/quality_summary.tsv \
  > result/virus/checkv/sample/near_complete.min90.tsv

# Extract trimmed provirus regions when CheckV reports host contamination.
cp result/virus/checkv/sample/proviruses.fna \
  result/virus/checkv/sample/proviruses.trimmed.fna
```

发现 DTR direct terminal repeat 时，建议把该 contig 标记为完整环状或末端闭合候选，但仍要检查 contamination 和 viral genes 数量，不应只凭 DTR 放行低质量序列。

含有明显宿主 flanking sequence 的 provirus，推荐使用 CheckV 输出的 `proviruses.fna` 和 `.bed` 边界作为修剪后版本；未修剪的原始 contig 不应直接进入宿主预测或丰度定量。

## Rationale

- **为什么 CheckV 要放在 geNomad/VirSorter2 之后**：识别器解决“像不像病毒”，CheckV 解决“病毒序列质量如何、是否完整、是否混入宿主片段”。
- **为什么 `>=50%` 可作为 high-quality 门槛**：病毒 contig 在宏基因组中常不完整，`50%` 以上完整度通常已足以支持 vOTU 构建和保守生态解释。
- **为什么 `>=90%` 标记 near-complete**：近完整病毒基因组更适合做基因组结构、生活方式、宿主关联和比较基因组分析。
- **为什么要限制 contamination**：宿主 flanking sequence 会导致长度、基因数和功能注释膨胀，也会误导后续宿主预测和丰度估计。
- **为什么 provirus trimming 很关键**：前病毒常嵌入细菌 contig，CheckV 修剪能去掉非病毒宿主边界，减少假细菌基因进入病毒 catalogue。
- **为什么 DTR 可提示完整性**：direct terminal repeat 常见于闭合或接近闭合的病毒基因组末端结构，是判断 complete candidate 的重要辅助证据。
- **为什么不能只看 DTR**：短重复、组装错误或低复杂度末端也可能产生类似信号，因此仍需要结合 completeness、contamination 和 hallmark genes。
- **为什么完整度估计有生物学依据**：CheckV 利用病毒 hallmark genes、参考基因组和基因内容模型估计完整度，比单纯按 contig 长度筛选可靠。
- **为什么输出表是过滤主接口**：`quality_summary.tsv` 集中包含完整度、污染、N50、病毒基因和前病毒状态，适合形成可复现的下游筛选规则。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: S01-S06 ×6, Params: none, Durations: S01=17s S02=19s S03=18s S04=18s S05=31s S06=19s, Exit: 0, Duration: 17s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/54_vir_checkv_contig.sh`
- `docs/experience/checkv-quality-filter.md`
- 上游来源：`scripts/52_vir_genomad.sh`
- 上游来源：`scripts/53_vir_virsorter2.sh`
