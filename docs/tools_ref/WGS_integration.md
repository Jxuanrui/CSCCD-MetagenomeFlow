# WGS 模块融入 CSCCD-MetagenomeFlow 说明

## 概述

本文档说明如何将原核生物全基因组测序（WGS）单基因组分析模块融入 CSCCD-MetagenomeFlow 宏基因组平台，实现 **MAG 深度精细化注释**。

**适用场景**：获得高质量 MAG（步骤 37-38）后，对感兴趣的物种进行单基因组级别的深度分析。

---

## 融入模块一览

| 脚本编号 | 脚本名 | 功能 | 依赖步骤 | 状态 |
|---------|--------|------|---------|------|
| `41b` | `41b_bac_mlst.sh` | MLST 多位点序列分型 | 步骤 38-41（MAG） | ⏳ 待开发 |
| `41c` | `41c_bac_pangenome.sh` | 泛基因组分析（Roary） | 步骤 41（Prokka GFF）| ⏳ 待开发 |
| `41d` | `41d_bac_snippy.sh` | SNP/InDel 变异检测 | 步骤 40（GTDB 分类）+ 参考基因组 | ⏳ 待开发 |

---

## 模块详解

### 41b：MLST 多位点序列分型

**功能**：对 MAG 进行多位点序列分型（Multi-Locus Sequence Typing），获得序列型（ST），用于分型、传播追踪和流行病学分析。

**工具**：`mlst v2.19+`

**适用条件**：
- 目标 MAG 来自已知 MLST 方案的物种（执行 `mlst --list` 查看支持的 134+ 种细菌）
- MAG 完整度 ≥ 90%（高质量 MAG 才能覆盖足够的 MLST 位点）

**典型命令**：
```bash
mlst --scheme ecoli --legacy *.fasta --threads 8 --nopath --quiet \
  | sed 's/\.fasta//' > result/mlst/mlst.tab
```

**输出**：`mlst.tab`（样本名、方案、ST 型、各位点等位基因编号）

---

### 41c：泛基因组分析

**功能**：对同一物种的多个 MAG 进行泛基因组分析，区分核心基因（Core）、软核心（Soft core）、壳基因（Shell）和云基因（Cloud），用于理解物种基因组多样性。

**工具**：`Roary v3.13+`（需要 Prokka 步骤输出的 GFF 文件作为输入）

**适用条件**：
- 同一物种（GTDB 分类相同）的 MAG ≥ 3 个
- 依赖步骤 41（Prokka 全基因组注释）的 `.gff` 文件

**典型命令**：
```bash
roary -p 8 -e --mafft -f result/pangenome/ result/gff/*.gff
```

**输出**：
- `pan_genome_reference.fa`：泛基因组参考序列
- `gene_presence_absence.csv`：各 MAG 基因有无矩阵
- `summary_statistics.txt`：核心/软核/壳/云基因统计
- `core_gene_alignment.aln`：核心基因 MSA（可用于建树）

---

### 41d：SNP/InDel 变异检测

**功能**：将样本 reads 回帖到参考 MAG，检测单核苷酸多态性（SNP）和小片段插入缺失（InDel），用于菌株微进化分析和感染溯源。

**工具**：`Snippy v4.6+`

**适用条件**：
- 需要参考基因组（目标物种的参考 MAG 或 NCBI 参考序列）
- 分析同一物种在不同样本/时间点的变异
- 适合感染病原体的流行病学调查场景

**典型命令**：
```bash
# 单样本变异检测
snippy --cpus 8 --outdir result/snippy/SAMPLE \
  --ref reference.fasta \
  --R1 reads_R1.fastq.gz --R2 reads_R2.fastq.gz

# 多样本核心 SNP 汇总
snippy-core --ref reference.fasta result/snippy/*/
```

**输出**：
- `snps.vcf`：VCF 格式变异文件
- `core.aln`：核心基因组 SNP 比对（可输入 FastTree/RAxML 建树）

---

## 与 StrainPhlAn4（步骤 12）的区别

| 维度 | StrainPhlAn4（步骤 12） | SNP 分析（步骤 41d） |
|------|------------------------|---------------------|
| 输入 | 宏基因组 reads（直接） | 分离纯培养或高质量 MAG |
| 分辨率 | marker gene 级（~1000个标记） | 全基因组 SNP 级 |
| 样本要求 | ≥4 个样本检测到该物种 | 2 个样本即可 |
| 计算量 | 中等 | 较大（全基因组比对） |
| 适合场景 | 宏基因组队列菌株多样性 | 单物种精细进化/溯源 |

**推荐策略**：
1. 宏基因组队列研究 → 首选 StrainPhlAn4（步骤 12）
2. 特定物种深度分析 → 补充 MLST（41b）+ 泛基因组（41c）
3. 感染源溯源/微进化 → 使用 SNP 分析（41d）

---

## 环境准备（待实现时参考）

上述工具需新建 `envs/wgs_tools` 环境：
```bash
mamba create --prefix envs/wgs_tools -y \
    mlst roary snippy \
    -c bioconda -c conda-forge
```

---

## 参考资料

- Roary 官方文档：https://sanger-pathogens.github.io/Roary/
- mlst 工具：https://github.com/tseemann/mlst
- Snippy 工具：https://github.com/tseemann/snippy
- MLST 数据库（PubMLST）：https://pubmlst.org/
