---
tool: "DIAMOND blastp"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-13"
tags: [kegg, ko, pathway-reconstruction, diamond]
scenario: [gut-microbiome, gene-catalog, shotgun-metagenomics]
---

# KEGG 通路注释参数建议

## Scenario

> 适用于完成 CD-HIT 去冗余基因目录后，需要把聚类后的蛋白序列统一映射到 KEGG KO 编号，用于后续 pathway reconstruction 和模块汇总。

这一层最适合放在 step 18 之后统一做聚合注释，而不是对每个样本单独重复比对。对于宏基因组基因目录，KO 赋值的目标通常是给每条非冗余蛋白一个最可信的功能标签，再结合丰度矩阵回填到样本层。

项目当前实现使用本地 `db/kegg/` 下的授权 KEGG DIAMOND 数据库，并从 `result/assembly/cdhit/protein_nr.fa` 直接运行 `diamond blastp`。这和 eggNOG 的“多体系广覆盖”路线不同，KEGG 更适合你已经明确想做代谢通路、模块和 KO 层解释的场景。

如果你的终点是 KEGG module completeness、代谢通路热图或菌群代谢能力比较，这一步通常应该早于所有 pathway-level 汇总。

如果你的终点只是获得尽可能宽的功能标签集合，则应先跑 eggNOG，再把 KEGG 作为补充而不是替代。

**关键参数速查**：Tool = `DIAMOND blastp`；Depends on = step `18_bac_cdhit` 产物 `protein_nr.fa`；Key params = `--evalue 1e-5`, `--max-target-seqs 1`, `--outfmt 6`, `--sensitive`, `--threads 16`；DB = local licensed `db/kegg/*.dmnd`；Output = `result/kegg/kegg_diamond.tsv` with downstream KO mapping.

## Recommendation

```bash
# Run KEGG KO annotation through the project wrapper.
THREADS=16                        # compute threads
WORKDIR=/path/to/project          # project workdir with protein_nr.fa
REPO=/path/to/CSCCD-MetagenomeFlow       # repo root with db/kegg and envs
bash scripts/22_bac_kegg.sh -t "$THREADS" -w "$WORKDIR" -r "$REPO"
```

如果按仓库现有流程执行，直接调用 `scripts/22_bac_kegg.sh` 即可；它会自动发现 `db/kegg/` 目录下第一个 `.dmnd` 文件，并在结果已存在时跳过。推荐层面保留 `--max-target-seqs 1`，因为 KO 分配的首要目标是稳定而可解释，而不是保留一串竞争命中。

这里建议把显著性阈值固定在 `1e-5` 而不是放宽到 `1e-3`。对于环境样本的大型蛋白目录，宽松阈值会明显增加假阳性 KO 转移，尤其是在保守结构域跨家族共享的场景下。KEGG-only 注释的价值在于通路重建清晰，因此宁可略保守，也不要把噪声 KO 带进下游代谢图谱。

输出表本身通常还需要再经过 `sseqid -> KO` 的映射整理，才能进入 pathway aggregation。

因此建议把 `kegg_diamond.tsv` 视为中间证据表，而不是最终可解释结果。

## Rationale

- **为什么用 DIAMOND 不用 BLAST**：基因目录通常是十万到百万级蛋白，`diamond blastp` 在速度和资源占用上更适合批量宏基因组，而 KO 注释所需的同源搜索精度在 `--sensitive` 模式下通常已足够。
- **为什么 KO 分配采用 best-hit**：KO 注释的常见实践是每条蛋白取一个最可信命中，`--max-target-seqs 1` 能降低多重命中带来的歧义，便于后续 pathway reconstruction。
- **为什么 `--evalue 1e-5`**：相较 `1e-3`，`1e-5` 对弱同源更保守，可减少环境样本里远缘蛋白被误贴 KO 标签的概率。
- **为什么保留 `--sensitive`**：宏基因组目录里常有非模式菌和远缘蛋白，敏感模式能提升真正同源的召回率，代价仍明显低于 BLAST。
- **为什么使用本地 KEGG 数据库**：KEGG 数据库有授权限制，项目通过本地 `db/kegg/` 统一管理可用版本，既满足合规性，也避免在线依赖造成不可复现。
- **为什么做聚合注释而不是逐样本注释**：`protein_nr.fa` 已经是全项目去冗余后的蛋白集合，统一注释一次再回填丰度，计算量和结果一致性都更好。
- **为什么 KEGG 与 eggNOG 不是互相替代**：eggNOG 更适合一次性获得 KO、COG、GO、EC、Pfam 等综合字段；KEGG-only 更适合你明确关注通路、模块和代谢网络时做更直接的 KO 层解释。
- **为什么输出保留 BLAST m6 格式**：`--outfmt 6` 是最容易被后续解析脚本消费的交换格式，既便于抽取 `sseqid` 做 KO 映射，也便于手工审计命中质量。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/22_bac_kegg.sh`
- `agents/skills/22_bac_kegg.yaml`
