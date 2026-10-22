---
tool: "Snippy 4.0.2"
dimension: "bacteria"
category: "wgs-integration"
author: ""
date: "2026-06-14"
tags: [snippy, snp, indel, core-genome, phylogeny, microevolution]
scenario: [gut-microbiome, dereplicated-mags, intra-species-variation]
---

# Snippy MAG SNP/InDel 检测建议

## Scenario

> 适用于 dRep 去冗余 MAG 的同种内 SNP/InDel 分析；工具 Snippy 4.0.2，脚本 `41d_bac_snippy.sh`，环境 `snippy` 或 `prokaWGS`，输入 `result/binning/drep/dereplicated_genomes/*.fa`，参考基因组 `-R` 可选且默认最大 MAG，先逐 MAG 运行再 `snippy-core` 合并，输出 `result/wgs/snippy/core.tsv` 和 `core.full.aln`。

Snippy 适合分析近缘 MAG 之间的核心 SNP/InDel 差异，用于构建系统发育树、识别微进化信号或比较同种菌株在不同样本中的变异。它不应混合距离过远的基因组，否则 mapping、core alignment 和 SNP 解释都会变差。

## Recommendation

未提供参考基因组时，项目脚本会自动选择最大的 dereplicated MAG 作为参考：

```bash
# Run Snippy on dereplicated MAGs with auto-selected reference.
bash scripts/41d_bac_snippy.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16
```

如果已有高质量同种参考基因组，建议显式传入 `-R`，结果更容易跨项目解释：

```bash
# Run Snippy with an explicit reference genome.
bash scripts/41d_bac_snippy.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16 \
  -R /path/to/reference.fa
```

主结果用 `core.tsv` 查看核心 SNP 位点表，用 `core.full.aln` 或清理后的 alignment 进行系统发育分析。运行前应先按 taxonomy/ANI 筛选同种或近同种 MAG。

## Rationale

- **为什么依赖 dRep 输出**：Snippy 需要代表 MAG 集合做变异比较，dRep 后输入能减少近重复基因组造成的冗余信号。
- **为什么参考基因组重要**：SNP/InDel 调用相对参考坐标展开，参考质量和与样本的亲缘距离会直接影响 mapping 与 core SNP 数。
- **为什么默认最大 MAG**：没有外部参考时，最大 MAG 通常更完整，能提供较多可比对区域；但这只是自动 fallback，不等于最佳参考。
- **为什么先逐 MAG 再 `snippy-core`**：单个 MAG 的变异先独立调用，随后用 `snippy-core` 汇总为所有样本共享坐标下的 core SNP/alignment。
- **为什么适合同种内分析**：近缘基因组之间 SNP 差异可用于 phylogeny 和 microevolution；远缘输入会把缺失、结构差异和比对失败混入 SNP 解释。
- **下游注意点**：用于建树前应检查 `core.full.aln`、清理后的 alignment、成功样本数和 SNP 数，避免低质量 MAG 主导分支结构。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References

- `scripts/41d_bac_snippy.sh`
- `scripts/38_bac_drep.sh`

