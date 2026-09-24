---
tool: "drep-threshold"
dimension: "bacteria"
category: "binning"
author: ""
date: "2026-06-11"
tags: [dereplication, ani-threshold, mag]
scenario: [gut-microbiome, cross-cohort, high-depth]
---

# dRep 去冗余 ANI 阈值选择建议

## Scenario

> 适用于 CheckM2 过滤后的 MAG 集合，需要在“非冗余代表基因组数量”和“保留菌株差异”之间做阈值决策。

这一环节通常发生在多样本或跨队列 MAG 汇总之后，因此阈值会直接改变最终 MAG catalogue 的粒度。

脚本已经把核心参数暴露为 `-a`，默认 `0.95`。

## Recommendation

默认推荐保留脚本默认值：`-a 0.95`。

推荐命令骨架如下：

```bash
dRep dereplicate result/binning/drep \
  -g result/binning/checkm2/drep_input/*.fa \
  -sa 0.95 \
  -pa 0.9 \
  -nc 0.30 \
  -p 16
```

如果项目目标是构建物种级 MAG catalogue、做 GTDB-Tk 分类、功能注释和生态分布分析，`0.95` 最稳。

如果目标是跟踪同一物种内的菌株差异，或研究个体内定植替换，建议另开一个并行结果集测试 `0.97`，而不是直接覆盖默认目录。

`0.99` 不建议作为主流程默认值；它更适合亚菌株级探索，不适合本项目的标准 catalogue。

保留脚本默认 `-pa 0.9` 与 `-nc 0.30`，不要在没有明确证据时随意放宽覆盖要求。

跨队列项目中，先统一质量过滤再做 dRep；不要把低质量 MAG 与高质量 MAG 混在一起仅靠 ANI 去裁决。

## Rationale

- **为什么 `0.95` 是主推荐**：它对应常用的物种级边界，能有效压缩冗余，同时保留跨样本可比较的代表 MAG。
- **为什么 `0.97` 只建议做并行分支**：菌株级去冗余会显著增加 catalogue 体积与后续注释负担，不一定改善统计解释。
- **为什么 `0.99` 容易过度分割**：非常细的 ANI 阈值会把原本生态意义接近的 genome 拆成大量近重复节点，增加下游稀疏性。
- **为什么还要保留 `-pa 0.9`**：主聚类 ANI 边界与配对比较阈值需要共同约束，不能只盯着 `-sa` 一个数。
- **为什么 `-nc 0.30` 不能太低**：覆盖不足时 ANI 比较可靠性下降，低覆盖比对更容易把噪声误当差异。
- **为什么不把低质量 MAG 一起交给 dRep 解决**：dRep 擅长去冗余，不负责修复污染和不完整性；质量问题应在 CheckM2 阶段先挡住。
- **为什么跨队列更需要默认值稳定**：阈值一旦频繁变化，后续 catalogue ID、GTDB 分类和功能注释都难以横向比较。
- **为什么建议并行目录而不是覆盖**：同一批 MAG 在 `0.95` 和 `0.97` 下的代表集数量通常差异明显，保留双版本更利于团队讨论。
- **为什么 dRep 处在 GTDB-Tk 之前**：先去冗余可以减少重复分类与注释计算，把资源集中到代表 MAG 上。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/38_bac_drep.sh`
- `agents/skills/38_bac_drep.yaml`
- 上游过滤：`scripts/37_bac_checkm2.sh`
- 下游分类：`scripts/40_bac_gtdbtk.sh`
