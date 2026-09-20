# CSCCD-MetagenomeFlow

> A comprehensive, reproducible metagenomics platform for parallel profiling of the gut microbiome across three kingdoms — bacteria, viruses, and fungi — from raw reads to publication-ready statistics, with AI-assisted workflow and mechanistic host-microbe interaction discovery.

**Developed by:**  
[China-Saudi Arabia Joint Laboratory for Cardiovascular and Cerebrovascular Diseases](https://example.org) (中(阿)沙心脑血管疾病联合实验室)

[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://ubuntu.com)
[![Snakemake](https://img.shields.io/badge/Snakemake-9.22-green)](https://snakemake.readthedocs.io)
[![Conda](https://img.shields.io/badge/conda%20envs-57-orange)](https://github.com/conda-forge/miniforge)
[![Scripts](https://img.shields.io/badge/scripts-183-blue)]()
[![RAG](https://img.shields.io/badge/RAG-12242%20chunks-purple)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║    ███╗   ███╗  ██████╗ ██╗  ██╗                                          ║
║    ████╗ ████║ ██╔════╝ ╚██╗██╔╝                                          ║
║    ██╔████╔██║ ██║  ███╗ ╚███╔╝                                           ║
║    ██║╚██╔╝██║ ██║   ██║ ██╔██╗                                           ║
║    ██║ ╚═╝ ██║ ╚██████╔╝██╔╝ ██╗                                          ║
║    ╚═╝     ╚═╝  ╚═════╝ ╚═╝  ╚═╝                                          ║
║                                                                           ║
║    MaxMetagenome Platform                                                 ║
║    完整宏基因组多维度分析平台  ·  版本 1.1.2                                 ║
║                                                                           ║
║    183 分析脚本  ·  143 Snakemake 规则  ·  57 conda 环境  ·  ~1.2TB 数据库  ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Table of Contents

- [Overview](#overview)
- [Platform](#platform)
- [Quick Start](#quick-start)
- [Run Modes](#run-modes)
- [Analysis Dimensions](#analysis-dimensions)
- [Bacteria Dimension](#bacteria-dimension--pipeline--outputs)
- [Virome Dimension](#virome-dimension--pipeline--outputs)
- [Mycobiome Dimension](#mycobiome-dimension--pipeline--outputs)
- [Script Index](#script-index)
- [AI-Assisted Features](#ai-assisted-features)
- [Repository Layout](#repository-layout)
- [Disk Requirements](#disk-requirements)
- [Migrating to a New Server](#migrating-to-a-new-server)
- [Tools & References](#tools--references)

---

## Overview

Gut microbiome research increasingly demands joint analysis of bacteria, viruses, and fungi, especially in the context of cardiovascular and cerebrovascular diseases where microbe-host interactions play critical roles in inflammation, metabolite signaling, and immune modulation. Yet most published pipelines address only one kingdom at a time, require cloud infrastructure, or are difficult to reproduce across servers. **CSCCD-MetagenomeFlow** addresses this by providing a self-contained, single-server platform that runs all three dimensions in parallel with a unified script convention, a shared Snakemake DAG, and built-in mechanistic discovery capabilities linking microbial functions to host gene targets.

**Why CSCCD-MetagenomeFlow?**

- **Three kingdoms, one platform.** Bacteria (scripts 11–42b), Virome (51–72), and Mycobiome (71–86) share the same preprocessing steps, project directory layout, and Snakemake configuration — no glue scripts, no format conversion between steps.
- **Mechanistic discovery built-in.** The `mechanism_kb` RAG collection bridges 5,295 curated + cohort-verified gut microbe → metabolite → host gene relationships (GutMGene v2.0 + OmniPath + MicrobiomeKG 2025), enabling direct queries like "which microbial functions produce butyrate and activate FFAR2?" — critical for cardiovascular research where short-chain fatty acids modulate inflammation and blood pressure.
- **Portable and reproducible.** All 57 conda environments and ~1.2 TB of databases install locally under the project root via a single `0Install.sh`. Moving to a new server is a `git clone` + `bash 0Install.sh`.
- **Three run modes.** Step-by-step (fine-grained debugging), Bash pipeline (lightweight, no extra deps, `--from`/`--skip` checkpointing), or Snakemake DAG (production, HPC-ready, native resume). All three modes call the identical underlying scripts.
- **Functional integration built-in.** Script `98b` generates 11 integration tables per dimension at the end of each analysis — raw (Σ TPM), relative abundance, and CLR-normalized versions — ready for LEfSe, ANCOM-BC2, MaAsLin2, SIAMCAT, and Aitchison-distance ordination without any manual post-processing.
- **AI-assisted with MCP protocol.** Project-level MCP servers (GLM dual-model router, figure library, RAG retrieval) back an agent-assisted workflow covering pipeline planning, execution, visualization, and new-script integration, over a quad-source RAG knowledge base (38,111 chunks: 1,860 experience_kb + 30,826 literature_kb + 130 skill_design_kb + 5,295 mechanism_kb) indexed with `BAAI/bge-small-zh-v1.5`, with incremental indexing (20-50x faster iteration).

---

## 最近更新 | Recent Updates

> 完整变更明细见 git 历史（`git log v1.1.4-baseline..HEAD`）与 `docs/CHANGELOG_v1.1_patch.md`。

**🔧 v1.2.1 (2026-09-19/20)** — 清理与 RAG 扩容：
- 磁盘清理回收 ~770G（可再生中间产物 / conda 缓存 / 测试遗留，provenance 留痕）
- antiSMASH 8.0.4 全量重跑 Project01（分块并行方案绕过其逐记录微批缺陷），v8 较 v7 region 数 +40–45%
- SemiBin 2.5.0 质量持平 → **生产冻结 v1.1.4 MAG 集，新项目用新链**（决策门裁决，provenance 留痕）
- RAG 扩容：literature_kb +25,434 chunks（microbiome-fm 开源语料，CC 许可逐条审计）；mechanism_kb +435 记录（MicrobiomeKG 2025 TRAPI 收获，全部带 PMID）
- RAG 基准题集版本化（30→45 题，结果带索引指纹）；修复 16b PHRED bug；新增 28 号脚本 level2 测试

**🔧 v1.2.0 (2026-09-19)** — 工程加固与工具链刷新：
- 治理迁移 ZCode + GLM（Ponytail 极简纪律三重落地）
- 154 个脚本接入共享库 `libcommon.sh`：净删 ~2,300 行，shellcheck 31→0 全绿，顺带修复 5 个致命 bug
- 工具链升级：antiSMASH 7→8.0.4、SemiBin 1.5→2.5.0（均 A/B 验证、旧环境冻结）；新增 16b metaSPAdes 双组装验证轨道、67b PhaStyle 噬菌体生活方式第三票
- 远程 CI（GitHub Actions）+ README 计数自动同步；bge-m3 A/B 评估后裁决不切换

**🔧 v1.1.4 (2026-09-16)** — 分箱链数据完整性治理：23% 陈旧 bin 污染定位修复、Project01 MAG 重建（213 个）、4 个输出清理 bug。

**🔧 v1.1.3 (2026-09-15)** — MetaX 跨域验证层、kingdoms 可配置架构、一致性检查器、仓库清理。

**🔧 v1.1.1–v1.1.2 (2026-08)** — 错误处理加固、98g 跨域丰度关联、8 个诊断/运维工具、GEM 模块全量验证。

**🎉 v1.1 (2026-08)** — 真核 QC/分箱（79b–79f）、跨域聚类（98e/98f）、BGC 新颖性打分（28b）、bin 重装配（36b/02b）。

**🎉 v1.0 (2026-07)** — 首版发布，依托中(阿)沙心脑血管疾病联合实验室。

### 分析能力 | Analysis Capacity
- **181 scripts**（158 `.sh` + 16 `.R` + 7 `.py`）覆盖三界全链路 + 跨域分析 + 诊断运维
- **140+ 脚本支持 `--force`** 幂等重跑；全库 shellcheck 零告警（165/165）
- 菌株级：inStrain 微多样性（39b–39d）、WGS（MLST/泛基因组/SNP，42b–42d）
- 噬菌体生活方式三票表决：BACPHLIP + PhaGCN3 + ProkBERT-PhaStyle（67b，opt-in）
- GEM 代谢建模（43–43c）；真菌 PHF 数据库（760 基因组）；11 张整合表 × 3 界自动生成

### AI 基础设施 | AI-Assisted Infrastructure
- **RAG 混合检索**（BM25 + 向量 + RRF）：**38,111 chunks** — experience_kb 1,860 / literature_kb 30,826 / skill_design_kb 130 / mechanism_kb 5,295
- mechanism_kb 双源：GutMGene v2.0 策划因果 + MicrobiomeKG 2025 队列关联（含 PMID 与统计量）
- 基准治理：45 题版本化题集 + 索引指纹戳；混合检索 R@3 = 0.98 / MRR = 0.917
- MCP 服务：glm-router（GLM-5.3/5.3-Flash 双模型路由）、figure-library、RAG 检索

### 平台成熟度 | Platform Maturity
- Snakemake 141 规则 / 261 任务 DAG 全量验证（Test_CI_fixture 三层 CI：shellcheck + 集成测试 + DAG 连通）
- 57 conda 环境自包含（~1.2 TB 数据库），单服务器迁移 = git clone + 0Install.sh
- 三种运行模式：逐步调试 / Bash 流水线（断点续跑）/ Snakemake DAG（HPC 就绪）

---

## Platform

| Component | Details |
|-----------|---------|
| OS | Linux x86_64 · Ubuntu 22.04 |
| Environment manager | Miniforge3 (self-contained, under project root) |
| Workflow engine | Snakemake 9.22.0 |
| Analysis scripts | 183 (01–98g + diagnostic/ops utilities, including .sh/.R/.py) |
| Snakemake rules | 143 across 11 rule files |
| Conda environments | 57 isolated tool environments |
| Databases | ~1.2 TB (ChocoPhlAn, UniRef90, GTDB R226, VOGDB, EukDB, UniProt Swiss-Prot, Pfam-A, ISfinder, ICEberg, integrall, transposase-db, etc.) |
| RAG knowledge base | **12,242 chunks** across 4 collections (ChromaDB + bge-small-zh-v1.5 + BM25 hybrid retrieval) |
| MCP server | Official Model Context Protocol compliance, registered with Claude Code & Codex CLI |

### RAG Collections

| Collection | Chunks | Content | Use Case |
|------------|--------|---------|----------|
| `experience_kb` | 1,860 | Team experience docs (tool best practices, troubleshooting, parameter tuning) | Quick lookup for "how to run CheckM2" or "fix MetaPhlAn4 segfault" |
| `literature_kb` | 5,392 | Extracted Methods sections from 500+ gut microbiome papers (PubMed/PMC) | Evidence-based parameter selection: "what sequencing depth do similar studies use for fungi?" |
| `skill_design_kb` | 130 | Agent skill definitions (prompt engineering, skill metadata, design patterns) | Build new Claude Code slash commands or optimize existing skills |
| `mechanism_kb` | 4,860 | Gut microbe → metabolite → host gene relationships (GutMGene v2.0 + OmniPath downstream interactions) | Mechanistic hypothesis: "which microbes produce TMAO precursors that activate FMO3?" |

**Incremental indexing:** All indexers support `--incremental` mode, skipping unchanged files and reducing reindex time from 2-3 minutes to 2-14 seconds during development iterations.

---

## Quick Start

```bash
# Activate project environment (required before every session)
source ~/Course/Maxmetagenome/scripts/activate.sh

# First time on a new server — run once after activation
bash ~/Course/Maxmetagenome/scripts/checkm_config.sh
```

### Run Modes

**Mode 1 — Step-by-step** (debugging, fine-grained parameter control)

```bash
bash scripts/01_qc_fastp.sh       -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/Maxmetagenome
bash scripts/02_qc_kneaddata.sh   -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/Maxmetagenome
bash scripts/11_bac_metaphlan4.sh -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/Maxmetagenome
```

**Mode 2 — Bash pipeline** (lightweight, no extra dependencies)

```bash
# Full bacteria pipeline
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16

# Resume from a specific step
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --from metaphlan4

# Parallel samples (requires rush)
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 -j 2

# Force re-run (ignore existing outputs) — supported by 137/146 scripts (93.8%)
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --force
bash scripts/11_bac_metaphlan4.sh -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/Maxmetagenome --force
```

**Mode 3 — Snakemake** (production, HPC, recommended for large cohorts)

```bash
# Edit per-run parameters in pipeline/config/config.yaml:
#   samplesheet: path to your project samplesheet.csv
#   workdir:     path to your project directory
#   threads_per_job: threads each tool uses internally (default 16, same as -t in Mode 2)
#   max_jobs:    concurrent jobs (default 1; set to 4 on a 64-core server → 4×16=64 threads)
vim pipeline/config/config.yaml

# Dry run — inspect the DAG without executing
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml --dry-run

# Run — set -j to match max_jobs in config.yaml
# Single server (64 cores): -j 4 (4 jobs × 16 threads = 64 threads)
# Large HPC:                -j 8 (8 jobs × 16 threads = 128 threads)
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml \
  -j $(python3 -c "import yaml; print(yaml.safe_load(open('pipeline/config/config.yaml'))['max_jobs'])") \
  --rerun-incomplete

# Or simply specify -j directly:
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml -j 4 --rerun-incomplete
```

---

## Analysis Dimensions

| Dimension | Scripts | Pipeline script |
|-----------|---------|----------------|
| 🦠 Bacteria | 11–42b | `00_pipeline_bacteria.sh` |
| 🦠 Virome | 51–72 | `00_pipeline_virome.sh` |
| 🍄 Mycobiome | 71–86 | `00_pipeline_fungi.sh` |
| 📊 Statistics | 91–98 | — |
| 🔗 Full | 01–98 | `00_pipeline_full.sh` |

---

## Bacteria Dimension — Pipeline & Outputs

```
Raw reads (*.fastq.gz)
    │
    ├── 01 fastp        Quality control (adapter trimming, low-quality filtering)
    └── 02 kneaddata    Host removal (bowtie2 alignment + read filtering)
            │
            ├─────────────────────────────────────────────────────────────────┐
            │  Read-based profiling                                           │  Assembly-based
            │                                                                 │
            │  11  MetaPhlAn4       Species composition (strain-level)        │  16  MEGAHIT        Assembly
            │  11b MetaPhlAn4 merge Multi-sample merged profile               │  17  Prodigal       Gene prediction
            │  12  StrainPhlAn4     Strain tracking & phylogeny               │  18  CD-HIT         Gene catalog (95% ANI)
            │  13  HUMAnN3          Functional pathway abundance (v3.9)       │  19  Salmon build   Index construction
            │  13b HUMAnN3 merge    Merged pathway tables                     │  20  Salmon quant   TPM quantification
            │  14  Kraken2+Bracken  Fast k-mer classification                 │
            │  14b Kraken2 merge    Multi-sample merged table                 │
            │  15  Centrifuger      Protein-level classification (GTDB R226)  │
            │  15b Centrifuger merge                                          │
            │                                                                 │
            │                                    ┌────────────────────────────┴──────────────────┐
            │                                    │  Functional annotation (gene catalog, pooled)  │  MAG recovery (per-sample)
            │                                    │                                                │
            │                                    │  21 eggNOG         COG / KEGG KO / EC / GO    │  32 CoverM       Coverage depth
            │                                    │  22 KEGG diamond   KO pathway hits             │  33 MetaBAT2     Binning
            │                                    │  23 AMRFinder      Antibiotic resistance genes  │  34 MaxBin2      Binning
            │                                    │  24 CARD / RGI     Resistance gene catalogue   │  35 SemiBin2     ML-based binning
            │                                    │  25 dbCAN3         CAZyme families             │  36 DAS_Tool     Multi-binner refinement
            │                                    │  26 VFDB           Virulence factors           │  37 CheckM2      MAG quality (ML)
            │                                    │  27 BacMet         Metal resistance genes      │  38 dRep         De-replication (97% ANI)
            │                                    │  28 antiSMASH      BGC / secondary metabolites │  39  CoverM       MAG abundance
            │                                    │  29 Defense-Finder Bacterial defense systems   │  39b inStrain map Reads → MAGs mapping
            │                                    │  30 NCyc           Nitrogen cycling genes      │  39c inStrain profile Strain-level microdiversity
            │                                    │  31 PCyc           Phosphorus cycling genes    │  39d inStrain compare Population SNV comparison
            │                                    │  31b SCyc          Sulfur cycling genes        │  40  GTDB-Tk      Phylogenetic classification
            │                                    │ 31c Pfam-A        Protein domain annotation   │ 41  Prokka       Genome annotation
            │                                    │  31d UniProt       Swiss-Prot high-precision   │  41b mlst         MLST typing
            │                                    │  31e FeGenie       Iron metabolism genes       │  41c Roary        Pan-genome
            │                                    │                                                │  41d Snippy       SNP / InDel calling
            │                                    │                                                │  42  MGE          Mobile genetic elements
            │                                    │                                                │  42b PlasmidFinder Plasmid identification
            │                                    │                                                │  43  gapseq       GEM reconstruction (3-step)
            │                                    │                                                │  43b CarveMe      GEM reconstruction (fast)
            │                                    │                                                │  43c COBRApy FBA  Metabolic simulation
            │                                    └────────────────────────────┬──────────────────┘
            │                                                                 │
            └─────────────────────────────────────────────────────────────────┘
                                                                    │
                                                                    ▼
                                            98b  Functional integration (98b_bac_integration_tables.sh)
                                                                    │
                                    ┌───────────────────────────────┼────────────────────────────────┐
                                    ▼                               ▼                                ▼
                           Raw integration tables          Normalized tables               HUMAnN3 pathway tables
                     result/integration/bacteria/       .../normalized/               result/humann3/merged/
```

### Phyloseq Objects (`result/stat/{bacteria,virus,fungi}/phyloseq/`)

**New in Phase 1 (2026-07-02):** Standard phyloseq RDS files for seamless R ecosystem integration.

| File | Contents | Compatible with |
|------|----------|----------------|
| `bacteria_phyloseq.rds` | OTU table + sample metadata + taxonomy table (MetaPhlAn4 species) + phylogenetic tree | phyloseq · MicrobiotaProcess · ANCOMBC · DESeq2 · microbiome · vegan |
| `virus_phyloseq.rds` | vOTU table + sample metadata + geNomad taxonomy | phyloseq · all R statistical packages |
| `fungi_phyloseq.rds` | Fungi species table + sample metadata + taxonomy | phyloseq · all R statistical packages |

**Why phyloseq?**
- Universal format for microbiome analysis in R
- Direct input for differential abundance (ANCOM-BC2, DESeq2, edgeR)
- Compatible with 100+ Bioconductor packages
- Automatic conversion from microeco via `file2meco::meco2phyloseq()`

All downstream analysis scripts (92–98) can read these phyloseq objects directly, eliminating format conversion overhead.

### Integration Outputs (`result/integration/bacteria/`)

Generated by `scripts/98b_bac_integration_tables.sh`. All tables follow **rows = functional features, columns = samples**.

#### Raw tables (Σ TPM per feature per sample)

| File | Feature axis | Annotation source |
|------|-------------|-------------------|
| `kegg_ko_abundance.tsv` | KEGG KO identifiers | eggNOG-mapper |
| `cog_abundance.tsv` | COG functional categories | eggNOG-mapper |
| `arg_abundance.tsv` | Antibiotic resistance genes (AMRFinder + CARD merged) | AMRFinder / CARD |
| `cazyme_abundance.tsv` | CAZyme families (GH / GT / PL / CE / AA) | dbCAN3 |
| `vfdb_abundance.tsv` | Virulence factor genes | VFDB |
| `ncyc_abundance.tsv` | Nitrogen cycling genes (e.g. amoA, nirK, nosZ) | NCyc HMM |
| `pcyc_abundance.tsv` | Phosphorus cycling genes | PCyc HMM |
| `defense_abundance.tsv` | Bacterial defense system types (RM, CRISPR, etc.) | Defense-Finder |
| `gene_annotation_matrix.tsv` | NR genes × (TPM × 6 samples + 12 annotation columns) | All sources merged |
| `pathway_community.tsv` | Community-level pathway relative abundance | HUMAnN3 merged |
| `pathway_species_contrib.tsv` | Pathway × contributing-species matrix | HUMAnN3 stratified |

> Salmon TPM sums to 1,000,000 per sample by design. Column sums differ across functional tables because annotation coverage varies per sample — this is expected. **Use `normalized/` tables for any cross-sample comparison.**

#### Normalized tables (`normalized/`, 17 files — use these for statistics)

| Suffix | Method | Use for |
|--------|--------|---------|
| `*_relab.tsv` | Relative abundance (column sum = 1) | LEfSe · MaAsLin2 · heatmaps · Spearman correlation |
| `*_clr.tsv` | Centered Log-Ratio (ε = 0.01) | PCoA (Aitchison) · PERMANOVA · ANCOM-BC2 · SIAMCAT |
| `gene_annotation_matrix_relab.tsv` | Wide matrix with added `RELAB_S01..S06` columns | Gene-level association analyses |

`pathway_community.tsv` and `pathway_species_contrib.tsv` are already in relative abundance from HUMAnN3 — no further normalization needed.

---

## Virome Dimension — Pipeline & Outputs

```
Raw reads (*.fastq.gz)
    │
    ├── 01 fastp        Quality control
    └── 02 kneaddata    Host removal
            │
            ▼
        51  MEGAHIT         Viral-optimized assembly (≥1.5 kb contigs)
            │
            ├── 52  geNomad         Viral / plasmid identification (neural network)
            └── 53  VirSorter2      Viral sequence prediction (intersection with geNomad)
                        │
                        ▼
                    54  CheckV      Contig quality assessment (completeness / contamination)
                        │
                        ▼
                   54b  Quality filter  MIUVIG standard: keep Complete/HQ/MQ/LQ +
                        │              Not-determined with viral genes ≥1; length ≥2000 bp
                        ▼
                    55  Prodigal-gv Viral protein prediction (viral genetic code)
                        │
            ┌───────────┴────────────────────────────────────────┐
            │  Read-based vOTU pipeline                          │  vMAG reconstruction
            │                                                    │
            │  56  vclust       vOTU clustering (95% ANI, 0.85   │  61  vRhyme       vMAG generation
            │                   qcov) → 20 cluster reps          │  62  CheckV       vMAG QC & filtering
            │  57  geNomad      vOTU taxonomy annotation         │  63  CoverM       vMAG abundance
            │  58  Salmon build vOTU quantification index        │
            │  59  Salmon quant TPM per sample                   │
            │  60  vOTU abundance matrix (contig-level TPM agg.) │
            └───────────┬────────────────────────────────────────┘
                        │
                        ▼
            ┌───────────────────────────────────────────────────┐
            │  Annotation & Ecology                             │
            │                                                   │
            │  64  PHAROKKA      End-to-end genome annotation   │
            │  65  PHOLD         Structural dark-matter ORFs    │
            │  66  VOGDB         VOG HMM cross-kingdom scan     │
            │  67  BACPHLIP      Lifestyle prediction           │
            │                   (lytic / lysogenic)             │
            │  68  iPHoP         Virus-host range prediction    │
            │  69  vConTACT3     Taxonomic gene-sharing network │
            │  70  PhaBox2       End-to-end classification      │
            │                   (virus/plasmid + lineage + host)│
            │  71  DRAM-v        Viral functional annotation    │
            │                   + AMG (auxiliary metabolic gene)│
            │  72  PhaGCN3       Deep-learning phage taxonomy   │
            │                   (graph convolutional network)   │
            └───────────────────────────────────────────────────┘
                        │
                        ▼
            98c  Functional integration (98c_vir_integration_tables.sh)
                        │
        ┌───────────────┼───────────────────────────────┐
        ▼               ▼                               ▼
  Raw tables      Normalized tables           vOTU annotation matrix
  result/         .../normalized/             votu_annotation_matrix.tsv
  integration/    *_relab + *_clr             (77 contig rows × 17 cols)
  virus/
```

### Annotation Outputs (`result/virus/`)

| Path | Content |
|------|---------|
| `assembly/${SAMPLE}/${SAMPLE}.contigs.fa` | All assembled contigs (≥1.5 kb, MEGAHIT) |
| `genomad/${SAMPLE}/*_virus_summary.tsv` | geNomad viral prediction scores + lifestyle |
| `virsorter2/${SAMPLE}/final-viral-score.tsv` | VirSorter2 confidence scores per contig |
| `checkv/${SAMPLE}/quality_summary.tsv` | Contig quality (completeness, contamination, genome type) |
| `checkv/${SAMPLE}/viruses_filtered.fna` | **Step 54b**: MIUVIG-standard quality-filtered contigs (42 total across 6 samples) |
| `checkv/${SAMPLE}/filter_summary.tsv` | Per-sample filter stats (pass/fail count per quality tier) |
| `votu/contigs/virus.fasta` | 42 quality-filtered contigs pooled for vOTU clustering |
| `votu/votu_representatives.tsv` | 20 vOTU cluster representatives (95% ANI, 0.85 qcov) |
| `votu/votu_table.tsv` | CDS × sample abundance (Salmon TPM; aggregated to contig level by 98c) |
| `votu/taxonomy/genomad_taxonomy.tsv` | Taxonomic annotation of representative vOTUs |
| `vmag/bins/.done` | vMAG sentinel (soft-fail on small datasets) |
| `pharokka/${SAMPLE}/pharokka_cds_final_merged_output.tsv` | Per-CDS function annotation (PHROG database) |
| `phold/vOTU_per_cds_predictions.tsv` | Structural annotation of dark-matter ORFs |
| `vog/vog_hits.tsv` | VOG HMM scan hits across kingdoms |
| `bacphlip/bacphlip_results.tsv` | Lifestyle probability per vOTU (lytic vs lysogenic) |
| `iphop/Host_prediction_to_genus_m90.csv` | Host genus-level predictions (≥90% confidence) |
| `vcontact3/exports/final_assignments.csv` | Taxonomic cluster assignments from gene-sharing network |
| `phabox2/phabox2_summary.tsv` | PhaBox2 end-to-end classification (virus/non-virus + full lineage + host + lifestyle per vOTU) |
| `dram/DRAM_annotations.tsv` | DRAM-v functional annotation table (per-gene: KO / PFAM / VOGDB / AMG flags) |
| `dram/DRAM_amg_summary.tsv` | AMG summary: auxiliary metabolic genes with pathway and AMG type per vOTU |
| `phagcn3/phagcn3_prediction.tsv` | PhaGCN3 deep-learning family-level classification with confidence score |

> vMAG reconstruction (steps 61–63) requires sufficient assembly depth. For low-biomass or shallow-sequencing samples, these steps soft-fail gracefully and the vOTU-level outputs (steps 54b–60, 64–69) remain fully valid.

> **vOTU counting note**: The 77-row `votu_annotation_matrix.tsv` represents all unique contigs with Prodigal-gv CDS predictions across all 6 samples. Of these, 42 passed the MIUVIG quality filter (step 54b) and were clustered into **20 vOTU representatives**. The annotation matrix retains all 77 contigs to preserve full quantitative information; downstream statistics should use the quality-filtered set (42) or representative set (20) as appropriate.

### Integration Outputs (`result/integration/virus/`)

Generated by `scripts/98c_vir_integration_tables.sh`. Quantification unit is **contig-level TPM** (Σ CDS TPM per contig, aggregated from Salmon CDS-level quantification). All tables: rows = functional features, columns = samples.

#### Raw tables (Σ contig TPM per feature per sample)

| File | Feature axis | Rows | Annotation source |
|------|-------------|------|-------------------|
| `phrog_category_abundance.tsv` | PHROG functional categories | 12 | PHAROKKA (majority vote per contig) |
| `vog_abundance.tsv` | VOG identifiers (cross-kingdom viral markers) | 208 | VOGDB HMM scan |
| `lifestyle_abundance.tsv` | Virulent / Temperate / Unclassified | 2 | BACPHLIP (threshold 0.5) |
| `host_genus_abundance.tsv` | Predicted bacterial host genera | 8 | iPHoP (≥90% confidence) |
| `viral_family_abundance.tsv` | Viral family assignments | 17 | vConTACT3 gene-sharing network |
| `votu_annotation_matrix.tsv` | 77 contigs × (TPM × 6 samples + 8 annotation cols) | 77 | All sources merged + CheckV quality |

#### Normalized tables (`normalized/`, 10 files — use these for statistics)

| Suffix | Method | Use for |
|--------|--------|---------|
| `*_relab.tsv` | Relative abundance (column sum = 1) | LEfSe · MaAsLin2 · heatmaps |
| `*_clr.tsv` | Centered Log-Ratio (ε = 0.01) | PCoA (Aitchison) · PERMANOVA · ANCOM-BC2 · SIAMCAT |
| `votu_annotation_matrix_relab.tsv` | Wide matrix + `vOTU_RELAB_S01..S06` columns | contig-level association analyses |

---

## Mycobiome Dimension — Pipeline & Outputs

The mycobiome dimension runs three parallel routes that complement each other. **Route A** is the primary abundance quantification method (Yan et al. 2024, *Cell* 187). Routes B and C provide complementary classification and functional context.

```
Raw reads (*.fastq.gz)
    │
    ├── 01 fastp        Quality control
    └── 02 kneaddata    Host removal
            │
            ├─────────────────────────────────────────────────────┐
            │                                                     │
            ▼                                                     │
    ┌─────────────────────────────────────────────────────┐      │
    │  Route A — PHF abundance profiling (PRIMARY) ✅     │      │
    │  Yan et al. 2024 Cell 187 — recommended             │      │
    │                                                     │      │
    │  74a  Bowtie2 index build  One-time index for       │      │
    │       (4 indexes)          760-genome gene set      │      │
    │         │                                           │      │
    │         ▼                                           │      │
    │  74e  PHF profiler   5-step Bowtie2 filter          │      │
    │       (per sample)   (host → bacteria → rRNA →      │      │
    │                       re-map k=1000, id=0.95)       │      │
    │       + GPA.py       Singular/Escrow abundance      │      │
    │         │                                           │      │
    │         ▼                                           │      │
    │  74f  Aggregation    Multi-sample .rc matrix        │      │
    │                      + taxonomy join (317 clusters) │      │
    └────────────────────────────┬────────────────────────┘      │
                                 │                               │
                                 ▼                               ▼
    ┌────────────────────────────────────────────────────────────────────┐
    │  Route B — Complementary classification (run in parallel) ✅       │
    │                                                                    │
    │  71  Kraken2+Bracken   Fast k-mer classification (PlusPF-fungi)   │
    │  72  MetaPhlAn4        Eukaryote-inclusive profiling (strain-level)│
    │  73  HUMAnN4           Fungal pathway extraction (stratified)     │
    │  74  BLAST             High-accuracy alignment vs gut fungi DB     │
    │  75  FunOMIC           Dedicated fungal WGS pipeline (1.6M markers)│
    │  76  CCMetagen         ⚠ Requires NCBI nt DB (>200 GB) — pending  │
    │  77  MicroFisher       Multi-hypervariable region (ITS/18S/28S)   │
    └───────────────────────────────────┬────────────────────────────────┘
                                        │
                                        ▼
    ┌───────────────────────────────────────────────────────────────────────┐
    │  Route C — Assembly + MAG + functional annotation ✅ all complete          │
    │                                                                       │
    │  78  MEGAHIT        Fungal-enriched assembly (reads from 71/72)      │
    │  79  Eukfinder      Eukaryotic MAG recovery (EukDB 628 genomes,      │
    │                     12.8 GB, built 2026-06-17; ✅ verified on S01)   │
    │  80b Prodigal       Fungal gene prediction on assembly contigs        │
    │                     (runs on 78 output; independent of 79)           │
    └────────────────────┬──────────────────────────────────────────────────┘
                         │
                         ▼
    ┌───────────────────────────────────────────────────────────────────────┐
    │  Functional annotation (gene catalog, pooled across samples)          │
    │                                                                       │
    │  81  eggNOG-mapper  COG / KEGG KO / GO / EC                         │
    │  82  KEGG diamond   KO pathway hits                                  │
    │  83  dbCAN3         CAZyme families (GH / GT / PL / CE / AA)        │
    │  84  VFDB           Virulence factors (Candida / Aspergillus etc.)   │
    │  85  AMRFinder      Antifungal resistance genes (CYP51, FKS, etc.)  │
    │  86  MEROPS         Protease families (invasion-related)             │
    └───────────────────────────────────────────────────────────────────────┘
                         │
                         ▼
            98d  Functional integration (98d_fun_integration_tables.sh)
                         │
    ┌────────────────────┬──────────────────────┬──────────────────────────┐
    ▼                    ▼                      ▼
Raw count tables    Normalized tables     Gene annotation matrix
result/             .../normalized/       gene_annotation_matrix.tsv
integration/        *_relab + *_clr       (1768 genes × 13 cols)
fungi/
```

> **Quantification note**: Route A (PHF profiler) produces cluster-level relative abundance using the Singular/Escrow algorithm, consistent with Yan et al. 2024. Routes B/C functional tables use **gene count per sample** (not TPM). Normalized tables (`*_relab` / `*_clr`) are suitable for all downstream statistics.

> **Known issues / pending steps**:
> - **75b FunOMIC aggregate**: Per-sample classification complete (6/6); multi-sample matrix aggregation (`75b_fun_funomics_aggregate.sh`) not yet run.
> - **76 CCMetagen**: Requires full NCBI nt database (>200 GB). Not currently configured.

### Annotation Outputs (`result/fungi/`)

| Path | Content |
|------|---------|
| `phf_profiler/{sample}/{sample}.rc` | Per-sample Singular/Escrow read counts (Route A) |
| `phf_profiler/merged_abundance_with_taxonomy.tsv` | Multi-sample PHF abundance matrix + 7-rank taxonomy |
| `kraken2/{sample}/` | Kraken2 reports + Bracken re-estimation (S/G/P levels) |
| `metaphlan4/{sample}/` | MetaPhlAn4 species profiles (eukaryotes included) |
| `humann4/{sample}/` | HUMAnN4 pathway abundance (fungal-stratified) |
| `blast_gutdb/{sample}/` | BLAST hits vs gut fungi reference DB |
| `funomic/{sample}/` | FunOMIC per-sample classification results |
| `microfisher/{sample}/` | MicroFisher ITS/18S/28S marker profiles |
| `assembly/{sample}/` | MEGAHIT fungal-enriched contigs (.contigs.fa) |
| `eukfinder/{sample}/` | Eukaryotic MAG bins (EukDB 628 genomes, 12.8 GB; low-biomass samples yield 0 MAGs — expected) |
| `prodigal/{sample}/` | Per-sample predicted genes (.faa / .fna / .gff) |
| `eggnog/eggnog.emapper.annotations` | Combined COG / KEGG / GO / EC annotations |
| `kegg/kegg_diamond.tsv` | KEGG KO diamond hits |
| `dbcan/overview.txt` | CAZyme overview (DIAMOND + HMMER consensus) |
| `vfdb/vfdb_hits.tsv` | Virulence factor hits |
| `amr/amrfinder_results.tsv` | Antifungal resistance genes |
| `merops/merops_hits.tsv` | MEROPS protease hits |

### Integration Outputs (`result/integration/fungi/`)

Generated by `scripts/98d_fun_integration_tables.sh`. Values = **gene count per sample** (integer in raw tables).

#### Raw tables (gene count per feature per sample)

| File | Feature axis | Annotation source |
|------|-------------|-------------------|
| `kegg_ko_gene_count.tsv` | KEGG KO identifiers | eggNOG-mapper |
| `cog_gene_count.tsv` | COG functional categories | eggNOG-mapper |
| `cazyme_gene_count.tsv` | CAZyme families (GH / GT / PL / CE / AA) | dbCAN3 |
| `vfdb_gene_count.tsv` | Virulence factor genes | VFDB |
| `amr_gene_count.tsv` | Antifungal resistance gene symbols | AMRFinderPlus |
| `merops_family_gene_count.tsv` | MEROPS protease families | MEROPS |
| `gene_annotation_matrix.tsv` | 1,768 genes × (sample presence 0/1 × 6 + 6 annotation columns) | All sources merged |

#### Normalized tables (`normalized/`, 12 files)

| Suffix | Method | Use for |
|--------|--------|---------|
| `*_relab.tsv` | Relative abundance (column sum = 1) | LEfSe · MaAsLin2 · heatmaps |
| `*_clr.tsv` | Centered Log-Ratio (ε = 0.01) | PCoA (Aitchison) · PERMANOVA · ANCOM-BC2 · SIAMCAT |

---

## Script Index

### Shared preprocessing

| No. | Function | Tool |
|-----|----------|------|
| 01 | Quality control | fastp |
| 02 | Host removal | KneadData + bowtie2 |

### 🦠 Bacteria (11–42b)

| No. | Function | Tool |
|-----|----------|------|
| 11 / 11b | Species composition + multi-sample merge | MetaPhlAn4 |
| 12 | Strain tracking & phylogeny | StrainPhlAn4 |
| 13 / 13b | Functional pathway abundance + merge | HUMAnN3 v3.9 |
| 14 / 14b | Fast k-mer classification + merge | Kraken2 + Bracken |
| 15 / 15b | Protein-level classification + merge | Centrifuger (GTDB R226) |
| 16–20 | Assembly → gene prediction → catalog → quantification | MEGAHIT · Prodigal · CD-HIT · Salmon |
| 21–31 | Functional annotation (COG / KEGG / AMR / CAZyme / VF / BGC / defense / nutrient cycling) | eggNOG · KEGG · AMRFinder · CARD · dbCAN3 · VFDB · BacMet · antiSMASH · Defense-Finder · NCyc · PCyc |
| 28b | BGC novelty scoring (vs. MIBiG 3.1, no antiSMASH re-run) | DIAMOND blastp |
| 31b–31e | Functional annotation supplement (S/N/P cycling · protein domains · high-precision · iron metabolism) | SCyc · Pfam-A · UniProt Swiss-Prot · FeGenie |
| 42 / 42b | Mobile genetic elements + plasmid identification | ISfinder · ICEberg · integrall · transposase · mobileOG · PlasmidFinder |
| 43 / 43b / 43c | GEM reconstruction + FBA simulation | gapseq · CarveMe · COBRApy |
| 32–41 | MAG recovery (binning → refinement → QC → dereplication → abundance → taxonomy → annotation) | CoverM · MetaBAT2 · MaxBin2 · SemiBin2 · QuickBin · DAS_Tool · CheckM2 · dRep · GTDB-Tk · Prokka |
| 39b–39d | Strain-level microdiversity analysis (reads mapping → SNV profiling → population comparison) | inStrain |
| 41b–41d | WGS integration: MLST · pan-genome · SNP/InDel calling | mlst · Roary · Snippy |
| 98b | Functional integration tables (11 output files) | Python (pandas-free, stdlib only) |

### 🦠 Virome (51–72)

| No. | Function | Tool |
|-----|----------|------|
| 51–54b | Assembly → dual-engine identification → QC → MIUVIG quality filter | MEGAHIT · geNomad · VirSorter2 · CheckV · seqkit |
| 55–60 | Protein prediction → vOTU clustering → taxonomy → abundance → count matrix | Prodigal-gv · vclust · geNomad · Salmon |
| 61–63 | vMAG reconstruction → QC → abundance | vmag · CheckV · CoverM |
| 64–69 | Annotation → lifestyle prediction → host range → taxonomic network | PHAROKKA · PHOLD · VOGDB · BACPHLIP · iPHoP · vConTACT3 |
| 70 | End-to-end classification (virus/non-virus + full lineage + host + lifestyle) | PhaBox2 2.1.12 |
| 71 | Viral functional annotation + AMG prediction | DRAM-v 1.5.0 |
| 72 | Deep-learning phage family classification (supplements vConTACT3) | PhaGCN3 3.1 |

### 🍄 Mycobiome (71–86)

| No. | Function | Tool | Status |
|-----|----------|------|--------|
| 71 | Fast k-mer classification (PlusPF-fungi) | Kraken2 + Bracken | ✅ |
| 72 | Eukaryote-inclusive profiling | MetaPhlAn4 | ✅ |
| 73 | Fungal pathway extraction (stratified) | HUMAnN4 | ✅ |
| 74 | High-accuracy alignment vs gut fungi DB | BLAST | ✅ |
| 74a | Bowtie2 index build (4 indexes, one-time) | Bowtie2 | ✅ |
| 74e | PHF per-sample profiling — **primary quantification** (Yan 2024 Cell 187) | Bowtie2 + GPA.py | ✅ |
| 74f | Multi-sample PHF abundance aggregation + taxonomy join | Python | ✅ |
| 75 | Dedicated fungal WGS pipeline (1.6M markers) | FunOMIC | ✅ |
| 75b | FunOMIC multi-sample matrix aggregation | Python | ⚠ pending |
| 76 | Eukaryote + prokaryote combined classification | CCMetagen | ⚠ requires NCBI nt DB |
| 77 | Multi-hypervariable region extraction (ITS/18S/28S) | MicroFisher | ✅ |
| 78–80b | Fungal assembly → gene prediction (Prodigal on contigs) | MEGAHIT · Prodigal | ✅ |
| 79 | Eukaryotic MAG recovery | Eukfinder | ✅ EukDB built 2026-06-17 (628/667 genomes, 12.8 GB) |
| 79b | Eukaryotic candidate QC (Tiara domain re-confirmation + BUSCO completeness) | Tiara + BUSCO | ✅ VEBA `binning-eukaryotic` methodology reference |
| 79c–79e | Real eukaryotic binning: coverage depth → MetaBAT2 binning → per-bin BUSCO | CoverM · MetaBAT2 · BUSCO | ✅ |
| 79f | Per-bin eukaryotic MAG protein prediction | MetaEuk | ✅ |
| 81–86 | Functional annotation (COG / KEGG / CAZyme / VF / AMR / protease) | eggNOG · KEGG · dbCAN3 · VFDB · AMRFinder · MEROPS | ✅ |

### 📊 Statistics (91–98)

| No. | Function | Tool |
|-----|----------|------|
| 91 | Alpha / Beta diversity | vegan · phyloseq (R) |
| 92 | Differential abundance (LEfSe / ANCOM-BC2 / DESeq2 / edgeR / MaAsLin2) | R |
| 93 | Cross-kingdom co-occurrence network | FastSpar / SparCC |
| 94 | Unified visualization (heatmap / PCoA / Sankey / UpSet) | ggplot2 (R) |
| 95a / 95b | Batch correction (top-10 methods) → evaluation report | MBECS · ConQuR · MMUPHin (R) |
| 96 | ML biomarker selection + ROC (lasso / RF / SVM / enet, 10-fold CV; ≥10 samples required) | SIAMCAT 2.10.0 (R) |
| 97 | Cross-cohort replication — local multi-cohort mode (meta-analysis + 8 visualizations) | SIAMCAT · R · random effects model | ✅ local mode |
| 97 (online) | Cross-cohort via curatedMetagenomicData | curatedMetagenomicData · SIAMCAT (R) — requires online Bioconductor access | ⚠ offline only |
| 98 | Timestamped analysis snapshot report | bash + Rscript |
| 98e | Cross-domain (bacteria/virus/fungi) genome ANI clustering | FastANI + networkx (Louvain) | ✅ VEBA `cluster` methodology reference |
| 98f | Cross-domain protein orthogroup detection | MMseqs2 `easy-cluster` | ✅ |

---

## AI-Assisted Features

### Claude Code Slash Commands (22 skills)

| Command | Function | Category |
|---------|----------|----------|
| `/mgx-welcome` | Platform overview and quick-start guide | 🚀 Entry |
| `/mgx-ask <query>` | Query the RAG knowledge base (experience + literature + mechanism) | 🔍 Query |
| `/mgx-plan` | Generate a per-project analysis plan | 📋 Planning |
| `/mgx-run` | Execute analysis commands with guided parameter selection | ⚙️ Execution |
| `/mgx-status` | Inspect pipeline progress and output completeness | 📊 Monitoring |
| `/mgx-integrate` | Integrate a new analysis script into Snakemake + skill library | 🔧 Development |
| `/mgx-review` | Review a Snakemake rule integration for correctness | ✅ QC |
| `/mgx-learn` | Record a run result to the provenance log | 📝 Logging |
| `/mgx-tune` | Hardware-aware parameter recommendation (threads + max_jobs) | 🎛️ Optimization |
| `/mgx-replicate` | Generate reproducible skill package from a paper / GitHub repo | 📄 Replication |
| `/mgx-index` | Incremental / full RAG knowledge base rebuild | 🗄️ Indexing |
| `/mgx-core` | Core microbiome analysis (alpha/beta diversity, rarefaction) | 📈 Statistics |
| `/mgx-lefse` | LEfSe differential abundance analysis | 📈 Statistics |
| `/mgx-pathway` | Functional pathway enrichment (KEGG/MetaCyc) | 📈 Statistics |
| `/mgx-redundancy` | Redundancy analysis (RDA/CCA) for microbiome-environment association | 📈 Statistics |
| `/mgx-plot-ordination` | PCoA / NMDS ordination plots | 📊 Visualization |
| `/mgx-plot-composition` | Species composition bar / stacked charts | 📊 Visualization |
| `/mgx-plot-diversity` | Alpha diversity plots | 📊 Visualization |
| `/mgx-plot-heatmap` | Annotation abundance heatmaps | 📊 Visualization |
| `/mgx-plot-network` | Co-occurrence network visualization | 📊 Visualization |
| `/mgx-plot-phylotree` | Phylogenetic tree rendering | 📊 Visualization |
| `/mgx-plot-volcano` | Differential abundance volcano plots | 📊 Visualization |
| `/graphify` | Build project knowledge graph (NetworkX + Leiden community detection) | 🕸️ Knowledge Graph |

### Knowledge Graph (graphify)

`graphify 0.8.38` (package `graphifyy`) is pre-installed in the project's miniforge3 base environment. It turns source files, docs, and skill cards into a queryable knowledge graph:

```bash
# Build knowledge graph from docs + skills + pipeline rules
/graphify docs/ agents/skills/ pipeline/rules/

# Query the graph
graphify path "metaphlan4" "humann3"
graphify explain "vOTU clustering"

# Incremental update after new scripts are integrated
graphify update . --force
```

### RAG Knowledge Base (12,242 chunks, 4 collections)

| Collection | Size | Source | Query Use Case |
|------------|------|--------|----------------|
| `experience_kb` | 1,860 chunks | Team experience docs (`docs/experience/`, 86 Markdown files) · tool docs · script headers · skill cards | "How to troubleshoot MetaPhlAn4 out-of-memory errors?" |
| `literature_kb` | 5,392 chunks | Methods sections from 237 OA metagenomics papers (Europe PMC fullTextXML) | "What sequencing depth do similar gut virome studies use?" |
| `skill_design_kb` | 130 chunks | Agent skill definitions (`.claude/skills/`, 24 Markdown files with prompt engineering patterns) | "Show me examples of multi-step skill design for pipeline orchestration" |
| `mechanism_kb` | 4,860 chunks | Gut microbe → metabolite → host gene relationships (GutMGene v2.0 + OmniPath downstream interactions) | "Which microbes produce butyrate and activate FFAR2 in cardiovascular disease?" |

**Embedding model:** `BAAI/bge-small-zh-v1.5` (bilingual, 512-dim). **Retrieval:** Hybrid (dense + BM25 sparse + reciprocal rank fusion).

**Incremental indexing:** All indexers support `--incremental` mode (20-50x faster when most files unchanged):

```bash
# Full rebuild (2-3 minutes for all collections)
python3 mcp/indexer.py --repo . --force
python3 mcp/index_skill_design_kb.py --repo . --force
python3 mcp/index_mechanism_kb.py --repo . --force

# Incremental update (2-14 seconds, only reindex changed files)
python3 mcp/indexer.py --repo . --incremental
python3 mcp/index_skill_design_kb.py --repo . --incremental
python3 mcp/index_mechanism_kb.py --repo . --incremental
```

**MCP server (Model Context Protocol):** Registered with Claude Code and Codex CLI, exposes `meta-server_rag_search` tool with collection routing:

```python
# Example: Query mechanism_kb for butyrate-related host targets
{
  "query": "butyrate FFAR2 activation cardiovascular",
  "collection": "mechanism_kb",
  "retrieval_mode": "hybrid",
  "n_results": 5
}
```

All collections are queryable via `/mgx-ask` slash command or direct MCP tool calls.

---

## Repository Layout

```
CSCCD-MetagenomeFlow/
├── scripts/                  181 scripts (01–98g + diagnostic/ops utilities)
├── pipeline/
│   ├── Snakefile             DAG entry point
│   ├── config/config.yaml    Per-run parameters (samples / workdir / threads)
│   ├── profiles/             Hardware presets (auto / local_16c / 48c / 96c / hpc_slurm)
│   └── rules/                11 rule files:
│                               preprocessing · bacteria_taxonomy · bacteria_assembly
│                               bacteria_annotation · bacteria_binning · bacteria_gem
│                               virome · mycobiome · statistics · rag · crosscohort
├── agents/
│   ├── registry.yaml         Global script status tracker (140 entries)
│   ├── skills/               136 tool skill cards (YAML / Markdown)
│   └── provenance/           188 run records (auto-generated by /mgx-learn)
├── docs/
│   ├── experience/           86 team experience documents (RAG source, editable)
│   └── tools_ref/            Auto-generated tool parameter docs (WebSearch cache)
├── mcp/                      RAG MCP server (ChromaDB + BM25 hybrid, RRF fusion, 4 collections)
│   ├── server.py             MCP protocol server (registered with Claude Code & Codex CLI)
│   ├── indexer.py            experience_kb indexer (--incremental support)
│   ├── index_skill_design_kb.py   skill_design_kb indexer
│   ├── index_mechanism_kb.py      mechanism_kb indexer
│   ├── gutmgene_bridge.py    GutMGene v2.0 + OmniPath bridge table builder
│   ├── chromadb_data/        ChromaDB persistent storage (12,242 chunks)
│   ├── bm25_data/            BM25 sparse index (4 PKL files, one per collection)
│   └── data/
│       ├── gutmgene/         GutMGene v2.0 CSVs (4,860 microbe-metabolite-gene triples)
│       └── gutmgene_bridge/  Bridge table JSON+TSV (Task 3 output, consumed by Task 4)
├── .claude/skills/           18 /mgx-* + /graphify Claude Code skill files
├── db/                       ~1.1 TB analysis databases
├── envs/                     40 conda environment definitions
├── 0Install.sh               Environment + database installation
├── CLAUDE.md                 CC + Codex collaboration guide
└── README.md
```

---

## Disk Requirements

| Component | Space |
|-----------|-------|
| miniforge3 + 40 conda envs | ~52 GB |
| `db/` databases | ~1.1 TB |
| 100-sample project data (raw + intermediates + results) | ~2 TB |
| `scripts/` + `pipeline/` + `docs/` (git-tracked) | < 100 MB |

---

## Migrating to a New Server

```bash
# 1. Clone the repository
git clone git@gitee.com:JXR1314/meta-servergenome.git
cd meta-servergenome

# 2. Install all environments and databases (~hours, depending on bandwidth)
bash 0Install.sh

# 3. Activate and verify
source scripts/activate.sh
bash scripts/checkm_config.sh       # reconfigure CheckM2 database path

# 4. Verify Claude Code integration (development environment)
claude mcp list                     # should show: codex: ✓ Connected
```

---

## Tools & References

MetaPhlAn4 · StrainPhlAn4 · HUMAnN3 · Kraken2/Bracken · Centrifuger · sylph · MetaX · MEGAHIT · Prodigal · CD-HIT · Salmon · eggNOG-mapper · AMRFinderPlus · CARD/RGI · dbCAN3 · antiSMASH · Defense-Finder · NCyc · PCyc · BacMet · VFDB · CoverM · MetaBAT2 · MaxBin2 · SemiBin2 · QuickBin · DAS_Tool · CheckM2 · dRep · GTDB-Tk · Prokka · mlst · Roary · Snippy · geNomad · VirSorter2 · CheckV · Prodigal-gv · vclust · PHAROKKA · PHOLD · VOGDB · BACPHLIP · iPHoP · vConTACT3 · FunOMIC · CCMetagen · MicroFisher · Eukfinder · MEROPS · SIAMCAT · DESeq2 · MMUPHin · ConQuR · FastSpar · MBECS · curatedMetagenomicData · UniProt Swiss-Prot · Pfam-A · ISfinder · ICEberg · integrall · transposase-db · FeGenie
