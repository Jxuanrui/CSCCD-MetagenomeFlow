---
tool: "Roary 3.12"
dimension: "bacteria"
category: "wgs-integration"
author: ""
date: "2026-06-14"
tags: [roary, pangenome, prokka, core-genome, accessory-genome]
scenario: [gut-microbiome, same-species-mags, wgs-integration]
---

# Roary 同种 MAG 泛基因组分析建议

## Scenario

> 适用于同种 MAG 的 core/accessory/unique genome 分析；工具 Roary 3.12，脚本 `41c_bac_pangenome.sh`，环境 `prokaWGS`，输入 Prokka GFF `result/binning/prokka/*.gff` 且需嵌入序列，聚合运行，参数 `--identity 95`、`--core-definition 99`，要求 ≥3 个同种基因组，输出 `result/wgs/pangenome/summary_statistics.txt`、`pan_genome_reference.fa`、`gene_presence_absence.csv`。

Roary 应用于同一物种或非常近缘的 MAG 集合，用来划分核心基因、辅助基因和样本特异基因。它不适合把跨属、跨科甚至混合物种 MAG 直接放在一起运行，否则泛基因组结果主要反映分类差异而不是同种内基因内容差异。

## Recommendation

项目脚本会收集 Prokka GFF 并执行聚合泛基因组分析：

```bash
# Run Roary pan-genome analysis on Prokka GFF files.
bash scripts/41c_bac_pangenome.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16 \
  --identity 95 \
  --core-definition 99
```

直接运行时，必须确认 GFF 是 Prokka/Bakta 风格且文件末尾包含 FASTA 序列：

```bash
# Direct Roary command for same-species MAG annotations.
roary \
  -p 16 \
  -e \
  --mafft \
  -i 95 \
  -cd 99 \
  -f result/wgs/pangenome \
  result/binning/prokka/*.gff
```

运行前建议先按 GTDB-Tk 或其他分类结果筛选同种 MAG。若同种 MAG 少于 3 个，泛基因组统计不稳定，脚本也会把该情况视为不满足 Roary 输入条件。

## Rationale

- **为什么需要同种 MAG**：Roary 的 ortholog clustering 假设输入基因组足够近缘，跨物种输入会夸大 accessory genes 并削弱 core genome 解释。
- **为什么要求至少 3 个基因组**：少于 3 个 genome 时无法稳定区分 core、shell、cloud 或 unique gene，结果更像 pairwise comparison。
- **为什么使用 `--identity 95`**：95% protein identity 是 Roary 常用默认值，适合同种菌株层面 ortholog 聚类。
- **为什么使用 `--core-definition 99`**：≥99% genomes 出现的基因定义为 core gene，适合保留几乎全体成员共有的核心集合。
- **为什么输入 Prokka GFF**：Roary 要求 GFF 中包含注释特征和嵌入序列，Prokka/Bakta 输出格式能满足这一要求。
- **为什么关注 `gene_presence_absence.csv`**：该矩阵是后续差异基因、基因存在缺失热图和 phenotype association 的主要输入。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References

- `scripts/41c_bac_pangenome.sh`
- `scripts/41_bac_prokka.sh`

