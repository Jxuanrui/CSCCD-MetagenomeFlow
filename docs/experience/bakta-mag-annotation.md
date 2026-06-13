---
tool: "Bakta v1.x"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-13"
tags: [bakta, mag, genome-annotation, prokaryote, prodigal-gv]
scenario: [gut-microbiome, mag-catalog, prokaryotic-genome-annotation]
---

# Bakta MAG 全基因组注释建议

## Scenario

> 适用于 dRep 去冗余后，需要对代表 MAG 做综合原核基因组注释，输出 CDS、rRNA、tRNA、CRISPR、regulatory elements 和标准交换格式。

Bakta 更适合作为现代 MAG catalog 的 genome annotation 工具，而不是继续把 Prokka 作为默认选择。它在 CDS 预测、数据库匹配、功能命名和标准格式输出上更适合批量原核基因组，尤其适合后续要提交、共享或和 GTDB taxonomy 联合展示的 MAG。

该步骤应只对去冗余 MAG 运行，不建议对所有原始 bin 运行。原始 bin 中存在大量近重复和低质量结果，会成倍增加运行时间，也会让最终注释表中出现重复基因组信号；如果 MAG 数量很多，应按 MAG 进行批处理或调度。

**关键参数速查**：Tool = `Bakta v1.x`；Depends on = dRep dereplicated MAG FASTA files；Key params = `bakta --db db/bakta/db`, `--threads 16`, `--prefix`, `--output`, `--genus` optional metadata, `--species` optional metadata；Input = individual dRep MAG FASTA files；Output per MAG = `.tsv` annotation table, `.gff3`, `.faa` proteins, `.ffn` nucleotide CDS, `.gbff` GenBank。

## Recommendation

```bash
# Run Bakta annotation for all dereplicated MAGs through the project wrapper.
bash scripts/41_bac_bakta.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/Maxmetagenome
```

如果只注释单个 MAG，建议把输出前缀、目录和可选分类元数据写清楚：

```bash
# Direct Bakta command for one dereplicated MAG.
bakta \
  --db /path/to/Maxmetagenome/db/bakta/db \
  --threads 16 \
  --prefix MAG_001 \
  --output /path/to/project/result/binning/bakta/MAG_001 \
  --genus Bacteroides \
  --species uniformis \
  /path/to/project/result/binning/drep/dereplicated_genomes/MAG_001.fa
```

批量项目中，最终应同时保留 per-MAG 输出目录和合并后的 summary table。`.tsv` 便于统计功能类别，`.gff3` 便于基因组浏览器和 feature 坐标追踪，`.faa` 和 `.ffn` 可继续用于功能注释、泛基因组或蛋白聚类，`.gbff` 则适合归档和交换。

## Rationale

- **为什么 Bakta 可替代 Prokka**：Bakta 更新、更重视标准化注释和数据库交叉引用，适合现代 MAG catalog 的可复现注释。
- **为什么只跑 dRep 后 MAG**：去冗余代表基因组才是最终 catalog 单元，对所有 bin 注释会重复计算并放大近重复基因组的影响。
- **为什么关注 Prodigal-gv**：Bakta 对病毒或噬菌体污染片段更友好，phage-contaminated MAG 中的 CDS 预测通常比传统流程更稳健。
- **为什么每个 MAG 单独输出**：MAG 是基因组级对象，独立目录能保留坐标、蛋白、核酸和 GenBank 文件，便于追溯单个代表基因组。
- **为什么保留 `.gff3` 和 `.gbff`**：前者适合程序化解析与浏览器展示，后者是常见 GenBank 交换格式，二者服务场景不同。
- **为什么可加入 `--genus` 和 `--species`**：若 GTDB 或其他分类结果足够可靠，元数据能改善注释命名和输出可读性，但不应强行填写不确定物种。
- **为什么需要批处理策略**：Bakta 对每个 MAG 独立运行，几十到上百个 MAG 时应自动跳过已完成结果并避免单进程串行拖慢项目。
- **为什么数据库路径要固定**：Bakta 注释内容依赖数据库版本和大小，固定 `db/bakta/db` 才能保证不同批次结果一致。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/41_bac_bakta.sh`
- `agents/skills/41_bac_bakta.yaml`
