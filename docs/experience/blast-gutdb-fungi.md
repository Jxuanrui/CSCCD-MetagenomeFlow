---
tool: "diamond-blastx"
dimension: "mycobiome"
category: "taxonomy"
author: ""
date: "2026-06-14"
tags: [blastx, fungi-reference, high-precision-taxonomy]
scenario: [gut-microbiome, whole-genome-metagenomics, per-sample-analysis]
---

# DIAMOND blastx 肠道真菌库分类建议

## Scenario

> 适用于 FunOMIC 不可用或需要高精度参考比对时，直接把 KneadData clean reads 合并后做 `diamond blastx`；核心参数是 gut fungi reference、`--evalue 1e-5`、6-frame translation，输出 `result/fungi/blast_gutdb/{sample}/{sample}_blast.tsv`。

这个步骤面对的是肠道真菌参考基因组库，而不是通用 marker 或 k-mer 数据库。它更慢，但对已收录、表征较好的 gut fungi 往往更稳。

## Recommendation

推荐在需要更高特异性、又暂时无法使用 FunOMIC 时使用该方案。直接输入去宿主 clean reads，脚本会合并 R1/R2 后调用 `diamond blastx`，不需要先做蛋白预测。

```bash
# Protein-level comparison by translating reads in six frames.
bash scripts/74_fun_blast_gutdb.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

如果要离线复现核心参数，最关键的是确认这里用的是 `blastx` 而不是 `blastp`，因为输入是 reads 而非蛋白序列。

```bash
diamond blastx \
  --db db/fungi/gut_fungi.dmnd \
  --query sample_merged.fastq.gz \
  --out sample_blast.tsv \
  --outfmt 6 qseqid sseqid pident length evalue bitscore \
  --evalue 1e-5 \
  --max-target-seqs 5 \
  --threads 16 \
  --sensitive
```

## Outputs

每样本主输出为：

```text
result/fungi/blast_gutdb/{sample}/{sample}_blast.tsv
```

数据库来自 gut fungi 参考库；当前脚本默认优先查找：

```text
db/fungi/gut_fungi.dmnd
```

该 `.dmnd` 对应的源文件是 `combined.fasta` 一类核苷酸基因组序列，构库时使用 `diamond makedb --ignore-warnings`。也因此这里必须用 `blastx`，由 reads 做 6 框翻译后再和 protein-level 索引比较。

## Rationale

- **为什么是 `blastx` 不是 `blastp`**：输入仍是清洗后的 reads，没有 ORF 预测结果，只能先做六框翻译再比较。
- **为什么适合做高精度补充**：参考比对策略通常比宽松 k-mer 分类更保守，对 well-characterized gut fungi 的解释更直接。
- **为什么适合作为 FunOMIC fallback**：它不依赖 FunOMIC 专用 CLI，但仍能给出 protein-level similarity hit，适合工具缺失时保留真菌证据链。
- **为什么 `--evalue 1e-5` 合理**：这是常见的 protein similarity 起点阈值，能在召回与特异性之间取得较稳平衡。
- **为什么数据库覆盖决定上限**：gut fungi 库对已知肠道真菌很好用，但没有收录的物种不会被识别出来，因此它不是开放世界分类器。
- **为什么速度会慢于快速筛查法**：每条 read 都要走翻译搜索，计算量明显高于 Kraken2 或 marker-based first-pass screen。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/74_fun_blast_gutdb.sh`
- `docs/tools_ref/blast_gutdb.md`
- `docs/project_structure.md`
