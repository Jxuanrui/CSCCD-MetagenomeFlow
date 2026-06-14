# MaxMetagenome

> A comprehensive, reproducible metagenomics platform for parallel profiling of the gut microbiome across three kingdoms — bacteria, viruses, and fungi — from raw reads to publication-ready statistics.

[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://ubuntu.com)
[![Snakemake](https://img.shields.io/badge/Snakemake-9.22-green)](https://snakemake.readthedocs.io)
[![Conda](https://img.shields.io/badge/conda%20envs-38-orange)](https://github.com/conda-forge/miniforge)
[![Scripts](https://img.shields.io/badge/scripts-91-blue)]()
[![RAG](https://img.shields.io/badge/RAG-6769%20chunks-purple)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

---

## Overview

Gut microbiome research increasingly demands joint analysis of bacteria, viruses, and fungi — yet most published pipelines address only one kingdom at a time, require cloud infrastructure, or are difficult to reproduce across servers. **MaxMetagenome** addresses this by providing a self-contained, single-server platform that runs all three dimensions in parallel with a unified script convention and a shared Snakemake DAG.

**Why MaxMetagenome?**

- **Three kingdoms, one platform.** Bacteria (scripts 11–41), Virome (51–69), and Mycobiome (71–86) share the same preprocessing steps, project directory layout, and Snakemake configuration — no glue scripts, no format conversion between steps.
- **Portable and reproducible.** All 38 conda environments and ~700 GB of databases install locally under the project root via a single `0Install.sh`. Moving to a new server is a `git clone` + `bash 0Install.sh`.
- **Three run modes.** Step-by-step (fine-grained debugging), Bash pipeline (lightweight, no extra deps, `--from`/`--skip` checkpointing), or Snakemake DAG (production, HPC-ready, native resume). All three modes call the identical underlying scripts.
- **Functional integration built-in.** Script `98b` generates 11 integration tables per dimension at the end of each analysis — raw (Σ TPM), relative abundance, and CLR-normalized versions — ready for LEfSe, ANCOM-BC2, MaAsLin2, SIAMCAT, and Aitchison-distance ordination without any manual post-processing.
- **AI-assisted.** 15 Claude Code slash commands (`/mgx-*`) cover pipeline planning, execution, visualization, and new-script integration, backed by a dual-source RAG knowledge base: 1,377 chunks of team experience docs + 5,392 chunks of literature Methods sections, indexed with `BAAI/bge-small-zh-v1.5`.

---

## Platform

| Component | Details |
|-----------|---------|
| OS | Linux x86_64 · Ubuntu 22.04 |
| Environment manager | Miniforge3 (self-contained, under project root) |
| Workflow engine | Snakemake 9.22.0 |
| Analysis scripts | 91 (numbered 00–98b) |
| Snakemake rules | 85 across 9 rule files |
| Conda environments | 38 isolated tool environments |
| Databases | ~700 GB (ChocoPhlAn, UniRef90, GTDB R226, VOGDB, etc.) |
| RAG knowledge base | 6,769 chunks (ChromaDB + bge-small-zh-v1.5) |

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
```

**Mode 3 — Snakemake** (production, HPC, recommended for large cohorts)

```bash
# Edit per-run parameters: samples list, workdir, threads
vim pipeline/config/config.yaml

# Dry run — inspect the DAG without executing
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml --dry-run

# Run (auto-resume incomplete jobs)
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml -j 16 --rerun-incomplete
```

---

## Analysis Dimensions

| Dimension | Scripts | Pipeline script |
|-----------|---------|----------------|
| 🦠 Bacteria | 11–41d | `00_pipeline_bacteria.sh` |
| 🦠 Virome | 51–69 | `00_pipeline_virome.sh` |
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
            │                                    │  28 antiSMASH      BGC / secondary metabolites │  39 CoverM       MAG abundance
            │                                    │  29 Defense-Finder Bacterial defense systems   │  40 GTDB-Tk      Phylogenetic classification
            │                                    │  30 NCyc           Nitrogen cycling genes      │  41 Bakta        Genome annotation
            │                                    │  31 PCyc           Phosphorus cycling genes    │  41b mlst        MLST typing
            │                                    │                                                │  41c Roary       Pan-genome
            │                                    │                                                │  41d Snippy      SNP / InDel calling
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

## Script Index

### Shared preprocessing

| No. | Function | Tool |
|-----|----------|------|
| 01 | Quality control | fastp |
| 02 | Host removal | KneadData + bowtie2 |

### 🦠 Bacteria (11–41)

| No. | Function | Tool |
|-----|----------|------|
| 11 / 11b | Species composition + multi-sample merge | MetaPhlAn4 |
| 12 | Strain tracking & phylogeny | StrainPhlAn4 |
| 13 / 13b | Functional pathway abundance + merge | HUMAnN3 v3.9 |
| 14 / 14b | Fast k-mer classification + merge | Kraken2 + Bracken |
| 15 / 15b | Protein-level classification + merge | Centrifuger (GTDB R226) |
| 16–20 | Assembly → gene prediction → catalog → quantification | MEGAHIT · Prodigal · CD-HIT · Salmon |
| 21–31 | Functional annotation (COG / KEGG / AMR / CAZyme / VF / BGC / defense / nutrient cycling) | eggNOG · KEGG · AMRFinder · CARD · dbCAN3 · VFDB · BacMet · antiSMASH · Defense-Finder · NCyc · PCyc |
| 32–41 | MAG recovery (binning → refinement → QC → dereplication → abundance → taxonomy → annotation) | CoverM · MetaBAT2 · MaxBin2 · SemiBin2 · DAS_Tool · CheckM2 · dRep · GTDB-Tk · Bakta |
| 41b–41d | WGS integration: MLST · pan-genome · SNP/InDel calling | mlst · Roary · Snippy |
| 98b | Functional integration tables (11 output files) | Python (pandas-free, stdlib only) |

### 🦠 Virome (51–69)

| No. | Function | Tool |
|-----|----------|------|
| 51–55 | Assembly → dual-engine identification → QC → protein prediction | MEGAHIT · geNomad · VirSorter2 · CheckV · Prodigal-gv |
| 56–60 | vOTU clustering → taxonomy → abundance → count matrix | vclust · geNomad · Salmon |
| 61–63 | vMAG reconstruction → QC → abundance | vmag · CheckV · CoverM |
| 64–69 | Annotation → lifestyle prediction → host range → taxonomic network | PHAROKKA · PHOLD · VOGDB · BACPHLIP · iPHoP · vConTACT3 |

### 🍄 Mycobiome (71–86)

| No. | Function | Tool |
|-----|----------|------|
| 71–77 | Five complementary classification strategies | Kraken2 · MetaPhlAn4 · HUMAnN4 · BLAST · FunOMIC · CCMetagen · MicroFisher |
| 78–80 | Fungal assembly → eukaryotic MAG recovery → gene prediction | MEGAHIT · Eukfinder · Prodigal |
| 81–86 | Functional annotation (COG / KEGG / CAZyme / VF / AMR / protease) | eggNOG · KEGG · dbCAN3 · VFDB · AMRFinder · MEROPS |

### 📊 Statistics (91–98)

| No. | Function | Tool |
|-----|----------|------|
| 91 | Alpha / Beta diversity | vegan · phyloseq (R) |
| 92 | Differential abundance (LEfSe / ANCOM-BC2 / DESeq2 / edgeR / MaAsLin2) | R |
| 93 | Cross-kingdom co-occurrence network | FastSpar / SparCC |
| 94 | Unified visualization (heatmap / PCoA / Sankey / UpSet) | ggplot2 (R) |
| 95a / 95b | Batch correction (top-10 methods) → evaluation report | MBECS · ConQuR · MMUPHin (R) |
| 96 | ML biomarker selection + ROC (lasso / RF / SVM / enet, 10-fold CV) | SIAMCAT (R) |
| 97 | Cross-cohort replication | curatedMetagenomicData · SIAMCAT (R) |
| 98 | Timestamped analysis snapshot report | bash + Rscript |

---

## AI-Assisted Features

### Claude Code Slash Commands

| Command | Function |
|---------|----------|
| `/mgx-welcome` | Platform overview and quick-start guide |
| `/mgx-ask <query>` | Query the RAG knowledge base (experience + literature) |
| `/mgx-plan` | Generate a per-project analysis plan |
| `/mgx-run` | Execute analysis commands with guided parameter selection |
| `/mgx-status` | Inspect pipeline progress and output completeness |
| `/mgx-integrate` | Integrate a new analysis script into Snakemake + skill library |
| `/mgx-review` | Review a Snakemake rule integration for correctness |
| `/mgx-learn` | Record a run result to the provenance log |
| `/mgx-plot-ordination` | PCoA / NMDS ordination plots |
| `/mgx-plot-composition` | Species composition bar / stacked charts |
| `/mgx-plot-diversity` | Alpha diversity plots |
| `/mgx-plot-heatmap` | Annotation abundance heatmaps |
| `/mgx-plot-network` | Co-occurrence network visualization |
| `/mgx-plot-phylotree` | Phylogenetic tree rendering |
| `/mgx-plot-volcano` | Differential abundance volcano plots |

### RAG Knowledge Base

| Collection | Size | Source |
|------------|------|--------|
| `experience_kb` | 1,377 chunks | Team experience docs (`docs/experience/`, 78 Markdown files) · tool docs · script parameters · skill cards |
| `literature_kb` | 5,392 chunks | Methods sections from 237 OA metagenomics papers (Europe PMC fullTextXML) |

Embedding model: `BAAI/bge-small-zh-v1.5` (bilingual, 384-dim). Add a new experience doc to `docs/experience/` and re-run indexer:

```bash
conda run --prefix miniforge3 python mcp/indexer.py
```

---

## Repository Layout

```
MaxMetagenome/
├── scripts/                  91 analysis scripts (00–98b)
├── pipeline/
│   ├── Snakefile             DAG entry point
│   ├── config/config.yaml    Per-run parameters (samples / workdir / threads)
│   └── rules/                9 rule files:
│                               preprocessing · bacteria_taxonomy · bacteria_assembly
│                               bacteria_annotation · bacteria_binning
│                               virome · mycobiome · statistics · rag
├── agents/
│   ├── registry.yaml         Global script status tracker (91 entries)
│   └── skills/               81 tool skill cards (YAML)
├── docs/
│   ├── experience/           78 team experience documents (RAG source, editable)
│   └── tools_ref/            Auto-generated tool parameter docs (WebSearch cache)
├── mcp/                      RAG MCP server (ChromaDB + literature pipeline)
├── .claude/skills/           15 /mgx-* Claude Code skill files
├── db/                       ~700 GB analysis databases
├── envs/                     38 conda environment definitions
├── 0Install.sh               Environment + database installation (§1–§15)
├── CLAUDE.md                 CC + Codex collaboration guide
└── README.md
```

---

## Disk Requirements

| Component | Space |
|-----------|-------|
| miniforge3 + 38 conda envs | ~50 GB |
| `db/` databases | ~700 GB |
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

MetaPhlAn4 · StrainPhlAn4 · HUMAnN3 · Kraken2/Bracken · Centrifuger · MEGAHIT · Prodigal · CD-HIT · Salmon · eggNOG-mapper · AMRFinderPlus · CARD/RGI · dbCAN3 · antiSMASH · Defense-Finder · NCyc · PCyc · BacMet · VFDB · CoverM · MetaBAT2 · MaxBin2 · SemiBin2 · DAS_Tool · CheckM2 · dRep · GTDB-Tk · Bakta · mlst · Roary · Snippy · geNomad · VirSorter2 · CheckV · Prodigal-gv · vclust · PHAROKKA · PHOLD · VOGDB · BACPHLIP · iPHoP · vConTACT3 · FunOMIC · CCMetagen · MicroFisher · Eukfinder · MEROPS · SIAMCAT · DESeq2 · MMUPHin · ConQuR · FastSpar · MBECS · curatedMetagenomicData
