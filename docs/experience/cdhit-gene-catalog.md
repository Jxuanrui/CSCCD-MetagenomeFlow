---
tool: "CD-HIT-EST v4.8.1"
dimension: "bacteria"
category: "assembly"
author: ""
date: "2026-06-13"
tags: [assembly, cdhit, gene-catalog, deduplication, cross-sample]
scenario: [gut-microbiome, gene-catalog, multi-sample-integration]
---

# CD-HIT 非冗余基因目录构建建议

## Scenario

> 适用于所有样本都已经完成 Prodigal 基因预测，需要把全队列基因集合并、过滤并聚类，构建可复用的跨样本非冗余基因目录。这个步骤是标准的 aggregate step，必须等所有样本的 `.fna` 到齐后再运行。

典型做法是先收集所有样本的 Prodigal `.fna`，再做最短长度过滤，最后用 CD-HIT-EST 在核苷酸层面聚类，得到 `nucleotide_nr.fa`。随后再把非冗余核酸序列翻译为 `protein_nr.fa`，一次性供所有功能注释工具共享，避免对重复基因反复注释。

`95%` identity 配合 `90%` coverage 是国际基因目录常用阈值，既能压缩明显冗余的同源 ORF，又不会像更高阈值那样保留过多近重复序列。对边界案例，`-g 1` 的精确聚类比贪心近似更稳，尤其适合做最终发布版 gene catalog。

**关键参数速查**：Tool = `CD-HIT-EST v4.8.1`；Depends on = all per-sample Prodigal `.fna` files concatenated；Pre-filter = minimum gene length `100 bp`；Key params = `cd-hit-est -c 0.95 -aS 0.9 -g 1 -n 8 -M 64000 -T 16`；Meaning = `-g 1` accurate mode, `-aS 0.9` shorter-sequence coverage `90%`；Outputs = `nucleotide_nr.fa` + `protein_nr.fa`；Downstream = `protein_nr.fa` feeds all annotation tools `21-31`

## Recommendation

项目里已经把“合并样本、过滤短基因、CD-HIT 聚类、翻译蛋白”串成一个聚合脚本，优先直接使用：

```bash
# Aggregate all Prodigal .fna files into a non-redundant gene catalog.
bash scripts/18_bac_cdhit.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如果需要把关键阈值写死在命令中，推荐把过滤、聚类和翻译拆开显式执行：

```bash
# Filter short genes before catalog construction.
seqkit seq -m 100 result/assembly/cdhit/all_genes.fna > result/assembly/cdhit/all_genes_min100.fna

# Build a nucleotide-level non-redundant catalog.
cd-hit-est \
  -i result/assembly/cdhit/all_genes_min100.fna \
  -o result/assembly/cdhit/nucleotide_nr.fa \
  -c 0.95 \
  -aS 0.9 \
  -g 1 \
  -n 8 \
  -M 64000 \
  -T 16

# Translate the final catalog once for downstream annotation.
seqkit translate --trim result/assembly/cdhit/nucleotide_nr.fa > result/assembly/cdhit/protein_nr.fa
```

仓库当前脚本为了适配大项目和完整 header，实际还加入了长度过滤、完整 ID 保留和本地翻译步骤；如果你的目标是复现实验报告中的标准 gene catalog，关键是守住 `95% identity / 90% coverage` 这一组核心阈值，而不是拘泥于某个包装脚本的辅助参数细节。

## Rationale

- **为什么这是跨样本聚合步骤**：gene catalog 的价值在于为整批样本提供统一坐标系，如果只对单样本去冗余，会失去跨样本比较和共享注释的意义。
- **为什么阈值用 `95% / 90%`**：这组阈值是宏基因组基因目录中最常见的折中，既减少近重复 ORF，又保留真实变体，适合后续丰度矩阵和功能注释。
- **为什么要先过滤 `<100 bp` 的基因**：极短 ORF 更容易是碎片、假阳性或注释价值很低的片段，保留它们只会放大聚类规模并污染目录。
- **为什么强调 `-g 1`**：精确模式在边界相似序列上更稳，虽然比快速贪心模式慢，但更适合作为最终对外使用的非冗余目录。
- **为什么在核苷酸层面聚类**：gene catalog 通常先在核酸层面定义冗余关系，再翻译为蛋白；这样更符合序列同源阈值的传统做法，也便于后续核酸定量。
- **为什么 `protein_nr.fa` 非常重要**：只要完成一次非冗余蛋白翻译，后续所有功能注释都可以复用同一个输入，显著降低计算量和注释重复度。
- **为什么所有样本必须先完成 Prodigal**：只要漏掉一个样本，该样本独有基因就不会进入目录，后面再补会导致目录版本变化、定量矩阵失配和注释重复。
- **为什么文档建议和脚本参数可能略有差异**：脚本往往会加入内存、header 保留或工具兼容性参数，文档则应先固定决定目录生物学含义的核心阈值，便于复现与方法描述。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/18_bac_cdhit.sh`
- `agents/skills/18_bac_cdhit.yaml`
