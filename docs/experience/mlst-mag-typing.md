---
tool: "mlst 2.11"
dimension: "bacteria"
category: "wgs-integration"
author: ""
date: "2026-06-14"
tags: [mlst, mag, sequence-typing, strain-typing, wgs-integration]
scenario: [gut-microbiome, dereplicated-mags, strain-comparison]
---

# MLST MAG 序列型分析建议

## Scenario

> 适用于 dRep 去冗余 MAG 的 sequence typing；工具 `mlst 2.11`，脚本 `41b_bac_mlst.sh`，环境 `prokaWGS`，输入 `result/binning/drep/dereplicated_genomes/*.fa`，聚合运行且默认不加 `-s`，可选 `--scheme` 指定方案，输出 `result/wgs/mlst/mlst.tsv`；依赖 dRep(38) 和 Prokka(41) 后续整合。

MLST 适合在 MAG 层面快速识别特定病原或机会致病菌的 sequence type，例如在同种 MAG 中筛查 ST131 *E. coli* 候选，并用于跨研究或公共数据库的粗粒度 strain comparison。

## Recommendation

默认让 `mlst` 自动识别 scheme，适合多个物种 MAG 混合输入：

```bash
# Run aggregate MLST typing for dereplicated MAGs.
bash scripts/41b_bac_mlst.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16
```

如果已经确定所有输入为同一物种或只想使用某个 scheme，可以显式指定：

```bash
# Run MLST with an explicit scheme.
bash scripts/41b_bac_mlst.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16 \
  --scheme ecoli
```

结果表 `mlst.tsv` 中重点查看 `SCHEME`、`ST` 和 allele profile。未命中或 `-` 不一定表示没有该菌株，可能是 MAG 缺失 MLST 位点、污染、物种不在 scheme 中，或 assembly fragment 不完整。

## Rationale

- **为什么输入 dRep MAG**：MLST 是 genome-level typing，对去冗余代表 MAG 运行可避免同一近重复基因组被重复计数。
- **为什么默认不加 `-s`**：混合 MAG catalog 可能包含多个物种，自动检测 scheme 比强行指定单一 scheme 更安全。
- **什么时候指定 `--scheme`**：当研究对象明确为同一物种，或要比较特定公共 MLST scheme 时，显式 scheme 能减少自动检测歧义。
- **为什么依赖 dRep 与 Prokka 阶段**：dRep 提供代表 MAG；Prokka 输出可用于后续把 MLST 结果与基因组注释、物种分类和功能特征合并。
- **为什么适合 ST131 等问题**：MLST 的 ST 编号是跨研究常用标签，能把 MAG 与临床或公共数据库中的已知 sequence type 联系起来。
- **MAG 局限性**：MAG 可能缺失部分 housekeeping loci，因此阴性或 incomplete allele profile 需要结合完整度、污染度和分类结果解释。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References

- `scripts/41b_bac_mlst.sh`
- `scripts/38_bac_drep.sh`
- `scripts/41_bac_prokka.sh`

