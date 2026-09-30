---
tool: "assembly-strategy"
dimension: "bacteria,virome,fungi"
category: "assembly"
author: "team"
date: "2026-06-17"
tags: [assembly-strategy, co-assembly, per-sample, votu, scaffolding, gap-filling]
scenario: [gut-microbiome, multi-sample, short-read, hybrid]
---

# 宏基因组组装策略选型与后处理工具指南

## Scenario

> 适用于多样本宏基因组项目（细菌/病毒/真菌），在单样本组装、多样本混合组装、多样本独立组装三种策略之间做取舍，以及组装后的 scaffolding、去冗余、gap filling 工具选择。

---

## 一、三种组装策略对比

| 维度 | 单样本组装 | 多样本混合组装（co-assembly） | 多样本独立组装（推荐） |
|------|-----------|------------------------------|----------------------|
| 计算消耗 | O(N×1) | O(1) | O(N×1 + M) |
| 内存需求 | 低，易管理 | 高，极易 OOM | 中等低 |
| 低丰度物种回收 | ❌ 差 | ✅ 极好 | ✅ 好 |
| 跨样本变异保留 | ✅ 保留 | ❌ 丢失 | ✅ 保留 |
| 嵌合体风险 | 低 | 高 | 中 |
| 适用样本数 | <10 | 任何 | 10-100 |
| vOTU 构建 | 需额外去冗余 | 直接可用 | 直接可用 |

**结论：多样本独立组装 + 跨样本 vOTU 聚类是兼顾质量与效率的推荐方案。混合组装（co-assembly）在样本数多时内存需求不可控，嵌合体风险高，不推荐作为常规策略。**

> N = 单样本组装消耗，M = 聚合消耗，O = 全局测序深度

---

## 二、推荐流程：多样本独立组装 + vOTU 聚类

```bash
# Step 1: 每个样本独立组装
for sample in S01 S02 S03 ... Sn; do
    megahit -1 ${sample}_R1.fastq.gz -2 ${sample}_R2.fastq.gz \
      --presets meta-large --min-contig-len 500 \
      -m 0.9 -t 16 -o assembly/${sample}/
done

# Step 2: 汇总所有 contigs（添加样本前缀避免 ID 冲突）
for sample in S01 S02 ... Sn; do
    sed "s/^>/>$sample_/" assembly/${sample}/final.contigs.fa
done > all_contigs.fa

# Step 3: 去冗余聚类（vsearch，95% ANI）
vsearch --cluster_fast all_contigs.fa \
  --id 0.95 --strand both \
  --centroids vOTU.fasta \
  --uc vOTU_clusters.uc

# Step 4: vOTU 定量（Salmon per-sample）
salmon index -t vOTU.fasta -i vOTU_index
for sample in S01 S02 ... Sn; do
    salmon quant -i vOTU_index \
      -1 ${sample}_R1.fastq.gz -2 ${sample}_R2.fastq.gz \
      -o quant/${sample}/ -p 16
done
```

**本项目对应脚本**：`scripts/16_bac_megahit.sh` → `scripts/18_bac_cdhit.sh` → `scripts/19_bac_salmon_build.sh` → `scripts/20_bac_salmon_quant.sh`

---

## 三、组装后处理工具

### Scaffolding 工具对比

| 工具 | 算法 | 输入要求 | 优势 | 缺点 | 适用场景 |
|------|------|---------|------|------|---------|
| OPERA-MS | 混合 reads + 参考库 | contigs + reads | 结构变异低，高连续 | 需要高质量短读长 | 短读长混合组装（Nanopore/PacBio） |
| SSPACE | 比对 reads 跨越 | contigs + reads | 经典易用 | 运行相对较慢 | 传统短读长 |
| BESST | De Bruijn 图 | contigs + reads | 速度快，内存友好 | 易断假接 | 资源受限时 |
| RagTag | 参考 genome | contigs + reference | 速度极快，有效利用参考库 | 需近源高质量参考 | 靶向物种 |
| MetaScaffolder | 混合 reads | contigs + reads | 专为宏基因组设计 | 维护较少 | 宏基因组 |

### 去冗余/聚类工具对比

| 工具 | 算法 | 速度 | 内存 | 相似度阈值 | 推荐场景 |
|------|------|------|------|-----------|---------|
| **vsearch** | k-mer + 比对 | ⭐⭐⭐ 快 | 低 | 95-99% | **推荐 vOTU**（本项目使用） |
| CD-HIT-EST | 贪婪递增 + 比对 | ⭐⭐⭐ 快 | 低 | 90-99% | 传统去冗余经典 |
| MMseqs2 | k-mer + 比对 | ⭐⭐⭐⭐ 极快 | 中 | 可调 | 大规模聚类（>10万序列） |
| BLAST + MCL | 比对 + 聚类 | ⭐ 慢 | 高 | 可调 | 高精度聚类（小规模） |
| vclust | ANI-based | ⭐⭐⭐ 快 | 低 | 95%（MIUVIG标准） | **病毒 vOTU**（本项目使用） |

### Gap Filling 工具对比

| 工具 | 输入 | 优点 | 缺点 |
|------|------|------|------|
| GapFiller | scaffolds + reads | 经典易用，稳定 | 速度慢 |
| Sealer | scaffolds + k-mer | 速度快，内存消耗少 | 依赖高质量 k-mer |
| TGS-GapCloser | scaffolds + 长读长 | 利用长读长，效果好 | 需额外提供长读长数据 |

---

## 四、推荐整合方案

### 方案 A：常规短读数据集（高性价比，本项目采用）
```
单样本组装(MEGAHIT) → 合并所有 contigs → vsearch/vclust 去冗余(95% ANI) → vOTU 库 → Salmon 定量
```

### 方案 B：长短读混合测序
```
混合组装 + 独立组装 → OPERA-MS/RagTag Scaffolding → TGS-GapCloser Gap filling → vsearch 去冗余 → vOTU 库
```

### 方案 C：大规模队列（>100 样本）
```
多样本独立组装(MEGAHIT/MetaSPAdes) → MetaSPAdes Scaffolding → vsearch/MMseqs2 去冗余 → vOTU 库 → Salmon 定量
```

---

## 五、关键决策点

- **什么时候用 co-assembly**：几乎不推荐。只在样本数 <5 且明确需要低丰度物种最大化回收时考虑，且要有足够内存（>500 GB）。
- **vsearch vs vclust**：细菌 gene catalog 用 vsearch（CD-HIT 兼容参数）；病毒 vOTU 用 vclust（MIUVIG 标准，95% ANI + 0.85 query coverage）。
- **min-contig-len 选择**：功能注释用 500 bp；MAG binning 用 1000-1500 bp；病毒用 ≥1500 bp（MIUVIG 要求 ≥2000 bp，CheckV 过滤后执行）。
- **contigs 前缀处理**：多样本合并前必须在 contig ID 加样本前缀，否则 vsearch/Salmon 会因 ID 冲突报错。
- **scaffolding 必要性**：短读宏基因组样本通常 N50 <5 kb，scaffolding 收益有限。仅在有长读长辅助或靶向高质量参考基因组时再引入。

---

## Verified

- validated — 方案 A 已在 Project_example 6 样本全流程验证（2026-06-17）
- 细菌维度：scripts/16→18→19→20（MEGAHIT→CD-HIT→Salmon index→Salmon quant）
- 病毒维度：scripts/51→56（MEGAHIT→vclust vOTU）

## References

- `scripts/16_bac_megahit.sh` — 细菌组装
- `scripts/51_vir_megahit.sh` — 病毒组装
- `scripts/78_fun_megahit.sh` — 真菌组装
- `scripts/18_bac_cdhit.sh` — 细菌基因集去冗余
- `scripts/56_vir_votu_gen.sh` — 病毒 vOTU 聚类（vclust）
- `docs/experience/megahit-assembly-strategy.md` — MEGAHIT 参数详细经验
- `docs/experience/votu-clustering-vclust.md` — vOTU 聚类经验
