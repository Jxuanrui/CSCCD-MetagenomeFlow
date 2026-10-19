---
tool: "PHOLD 1.0+"
dimension: "virome"
category: "annotation"
author: "team"
date: "2026-06-14"
tags: [phold, viral-dark-matter, structure-search, pharokka, annotation]
scenario: [virome, votu-representatives, structural-annotation]
---

# PHOLD 病毒暗物质结构注释建议

## Scenario

> 适用于 PHAROKKA `64` 已完成后，用 `65_vir_phold.sh` 对 vOTU `virus.fasta` 做结构辅助注释；关键依赖：PHAROKKA output；关键方法：ProstT5/PDB structure-based search；输入 `result/virus/votu/contigs/virus.fasta`；输出 `result/virus/phold/vOTU_phold.tsv`。

PHOLD 的价值在于补充 PHAROKKA/PHROG 没能解释的 hypothetical proteins，尤其是病毒组中常见的“dark matter” ORF。

PHAROKKA 更偏向病毒数据库和已知蛋白家族比对；PHOLD 利用结构相似性，把序列层面没有明显同源的蛋白映射到 PDB 等结构证据上。两者不是替代关系，而是前后衔接的注释层。

本项目脚本把 PHOLD 定义为 aggregate step，输入是 vOTU representative sequences，而不是每样本 contigs。这能避免对冗余病毒序列重复做昂贵的结构搜索。

## Recommendation

推荐在 PHAROKKA 完成后运行 PHOLD：

```bash
# Run PHOLD on vOTU representative sequences.
bash scripts/65_vir_phold.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

主输出为 `result/virus/phold/vOTU_phold.tsv`。下游解释时建议把 PHOLD 命中标记为“结构支持的功能候选”，而不是与高置信序列同源注释完全等价。

对 PHAROKKA 中仍为 hypothetical protein 的 ORF，PHOLD 结果尤其值得优先查看。如果结构同源指向 capsid、tail fiber、polymerase、integrase 等病毒核心功能，可以显著提高功能解释覆盖率。

若项目缺少 PHOLD 数据库或 ProstT5/PDB 资源，应把缺失记录为数据库限制，而不是解释为“没有暗物质功能可恢复”。

## Rationale

- **为什么依赖 PHAROKKA**：PHAROKKA 提供常规病毒注释背景，PHOLD 的主要作用是补充其中未被 PHROG 等数据库解释的 ORF。
- **为什么结构搜索有价值**：蛋白结构比氨基酸序列更保守，远缘同源关系可能在序列比对中消失，但仍能通过结构相似性发现。
- **为什么关注 hypothetical proteins**：病毒组中未知功能 ORF 比例高，dark matter 注释能改善生态功能解释和机制假设生成。
- **为什么对 vOTU 运行**：代表序列已去冗余，能减少结构搜索成本，并保证输出对应最终 catalogue。
- **为什么不能过度解释**：结构相似提供功能线索，但不等同于实验验证；报告中应区分 evidence type。
- **为什么输出单一汇总表**：`vOTU_phold.tsv` 便于和 PHAROKKA、VOG、vOTU abundance table 合并，形成多证据功能注释。
- **为什么缺库不是阴性结果**：PHOLD 高度依赖模型和结构数据库，数据库不完整会降低可注释比例。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: none, Exit: 0, Duration: 1800s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/65_vir_phold.sh`
- `scripts/64_vir_pharokka.sh`
- 输入：`result/virus/votu/contigs/virus.fasta`
- 输出：`result/virus/phold/vOTU_phold.tsv`
