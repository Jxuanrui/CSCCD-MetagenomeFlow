# CSCCD-MetagenomeFlow

A self-contained metagenomics platform that profiles gut bacteria, viruses, and fungi in parallel — from raw reads to publication-ready statistics — with built-in host-microbe mechanism discovery and an AI-assisted workflow.

Developed by the [China-Saudi Arabia Joint Laboratory for Cardiovascular and Cerebrovascular Diseases](https://example.org).

[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://ubuntu.com)
[![Snakemake](https://img.shields.io/badge/Snakemake-9.22-green)](https://snakemake.readthedocs.io)
[![Conda](https://img.shields.io/badge/conda%20envs-57-orange)](https://github.com/conda-forge/miniforge)
[![Scripts](https://img.shields.io/badge/scripts-183-blue)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

**183 scripts · 143 Snakemake rules · 57 conda envs · ~1.2 TB databases**

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Analysis Dimensions](#analysis-dimensions)
- [Figure Gallery](#figure-gallery)
- [Script Index](#script-index)
- [AI-Assisted Features](#ai-assisted-features)
- [Repository Layout](#repository-layout)
- [Disk Requirements](#disk-requirements)
- [Migrating to a New Server](#migrating-to-a-new-server)
- [Tools & References](#tools--references)

---

## Overview

*(The project was developed under the internal codename "mgx / MaxMetagenome" — tool names like `mgx-vis` and environment variables like `MGX_FIGURE_FORMATS` still use the short form. They refer to this repository, CSCCD-MetagenomeFlow.)*

Most published pipelines handle one kingdom at a time, depend on cloud infrastructure, or don't reproduce cleanly across servers. This platform takes a different approach: bacteria (scripts 11–43c), virome (51–72), and mycobiome (71–86) run side by side under one script convention and one Snakemake DAG, on a single server, with everything installed locally.

**Why it works:**

- **One preprocessing chain, three kingdoms.** Shared QC and host-removal steps; per-kingdom analysis branches off cleanly. No glue scripts or format conversion between steps.
- **Mechanism discovery is part of the pipeline, not an afterthought.** The `mechanism_kb` knowledge base carries 5,295 microbe → metabolite → host-gene relations (GutMGene v2.0 curated causal chains, OmniPath interactions, MicrobiomeKG 2025 cohort associations), each traceable to a publication. Queries like "which microbial functions produce butyrate and activate FFAR2?" resolve directly against it.
- **Runs anywhere.** 57 conda environments and ~1.2 TB of databases live under the project root. A new server is `git clone` + `bash 0Install.sh`.
- **Statistics-ready outputs.** Script 98b writes 11 integration tables per dimension — raw TPM, relative abundance, and CLR — that plug straight into LEfSe, ANCOM-BC2, MaAsLin2, and SIAMCAT.
- **Three run modes, one script layer.** Step-by-step for debugging, Bash pipelines with `--from`/`--skip` checkpointing for lightweight runs, Snakemake for production. All three call the same scripts underneath.

### Recent Updates

> Details: `git log v1.1.4-baseline..HEAD` (private dev history)

- **v1.3.0 (2026-09)** — First public release. mgx-vis MCP visualization module (publication PDF+PNG, CNS design system, 14-figure gallery reproducible from synthetic demo data); agent-driven metagenome mining loop; GitHub publishing pipeline with leak verification; environment lock manifests.

- **v1.2.1 (2026-09)** — Cleanup & RAG expansion: ~770 GB reclaimed; antiSMASH 8 full re-run (regions +41.5%); literature_kb 5.7x; mechanism_kb +435 records; BugSigDB signature_kb added.
- **v1.2.0 (2026-09)** — Engineering hardening: shared script library (-2,300 lines, shellcheck clean), antiSMASH 8 / SemiBin 2.5, metaSPAdes + PhaStyle opt-in tracks, remote CI, GLM dual-model routing.
- **v1.1.4 (2026-09)** — Binning-chain data-integrity remediation; Project01 MAG set rebuilt.
- **v1.1.3 (2026-09)** — MetaX cross-domain verification layer; configurable kingdoms.
- Earlier versions — see git history.

---

## Quick Start

```bash
# Activate (required before every session)
source scripts/activate.sh

# First time on a new server only
bash scripts/checkm_config.sh
```

### Install Footprint

What `bash 0Install.sh` (default `INSTALL_MODE=online`, official sources) costs on a fresh machine — all figures are order-of-magnitude:

| Resource | Scale |
|----------|-------|
| Disk — conda envs (`miniforge3/` + `envs/`, 57 environments) | ~60 GB |
| Disk — databases (`db/`, 58 database directories) | ~1.2 TB |
| Network download | ~0.5–1 TB total, dozens of official sources |
| Wall time | hours at 100 MB/s sustained; days on slower links (database downloads dominate) |

With a local database bank (`INSTALL_MODE=bank` + `DB_BANK`/`SIBLING_DB`), the database stage collapses to local copies. Per-database provenance: `docs/manifests/databases.yaml`; per-env software locks: `docs/manifests/envs/`.

Zero-database demo path: `bash mcp/vis/build_gallery.sh` renders the full figure gallery with only the `r_stat` env — no `db/` content required.

### Run Modes

**Step-by-step** — debugging, fine-grained control:

```bash
bash scripts/01_qc_fastp.sh       -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/02_qc_kneaddata.sh   -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/CSCCD-MetagenomeFlow
```

**Bash pipeline** — lightweight, checkpointed:

```bash
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 --from metaphlan4   # resume
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 --force              # re-run
```

**Snakemake** — production, large cohorts:

```bash
# Edit pipeline/config/config.yaml: samplesheet, workdir, threads_per_job, max_jobs
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml --dry-run
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml -j 4 --rerun-incomplete
```

---

## Analysis Dimensions

| Dimension | Scripts | Pipeline script |
|-----------|---------|----------------|
| Bacteria | 11–43c | `00_pipeline_bacteria.sh` |
| Virome | 51–72 | `00_pipeline_virome.sh` |
| Mycobiome | 71–86 | `00_pipeline_fungi.sh` |
| Statistics | 91–98 | — |
| Full chain | 01–98 | `00_pipeline_full.sh` |

### Bacteria

QC → host removal → two parallel branches. Read-based profiling: MetaPhlAn4, StrainPhlAn4, HUMAnN3, Kraken2, Centrifuger, sylph, MetaX. Assembly-based: MEGAHIT assembly → Prodigal gene prediction → CD-HIT catalog → Salmon quantification. The gene catalog feeds pooled annotation (eggNOG, KEGG, AMRFinder, CARD, dbCAN3, VFDB, BacMet, antiSMASH, Defense-Finder, NCyc/PCyc/SCyc, Pfam, UniProt, FeGenie); per-sample contigs feed MAG recovery (CoverM → MetaBAT2/MaxBin2/SemiBin → DAS_Tool → CheckM2 → dRep → GTDB-Tk → Prokka, plus inStrain strain tracking, MLST, Roary pan-genome, Snippy SNPs, MGE/plasmid annotation, and gapseq/CarveMe/COBRApy metabolic modeling). Everything converges in script 98b's integration tables.

### Virome

QC → host removal → MEGAHIT → geNomad + VirSorter2 → CheckV quality filter (MIUVIG standard) → Prodigal-gv. Then either the read-based vOTU track (vclust clustering → geNomad taxonomy → Salmon quantification → vOTU tables) or vMAG reconstruction (vRhyme → CheckV → CoverM). Annotation: PHAROKKA, PHOLD, VOGDB, BACPHLIP, PhaGCN3, PhaStyle, iPHoP host prediction, vConTACT3, DRAM, PhaBox2.

### Mycobiome

Multiple taxonomic profilers cross-validate each other: Kraken2, MetaPhlAn4-euk, HUMAnN4-fungi, BLAST against the gut-fungus database, FunOMIC, CCMetagen, MicroFisher, and the PHF profiler (760 gut fungal genomes, Yan et al. 2024 *Cell*). Downstream: fungal assembly → Eukfinder → Tiara/BUSCO QC → MetaBAT2 binning → MetaEuk protein prediction → eggNOG/KEGG/dbCAN/VFDB/AMR/MEROPS annotation.

### Statistics

Diversity (91), differential abundance (92, 99b LEfSe), co-occurrence networks (93, FastSpar), visualization (94), batch correction and evaluation (95a/b, 10 methods), functional profiling across 20 dimension × type combinations (96 series), cross-cohort replication (97), snapshot reports (98). phyloseq objects for each kingdom feed all downstream R packages directly.

---

## Figure Gallery

All figures below share one **CNS-style design system** (`mcp/vis/cns/theme_cns.R`: 0.3pt axes, Arial size hierarchy, muted Nature/NEJM-leaning palette, 89/183mm column widths, 600 dpi) and are drawn from a **synthetic 24-sample demo project** — no real data is used or distributed. The set is designed to composite directly into multi-panel figures. Every figure is stored in `docs/figures/` in **both PDF and PNG** (except the natively interactive Krona HTML). The entire gallery is reproducible with one command:

```bash
bash mcp/vis/build_gallery.sh            # CNS style (default), ~3 min
                                         # --with-ml adds ML figures (~7 min)
                                         # --orbit0 keeps the raw pipeline-script style
```

The same figures can be rendered on demand for any real project through the `mgx-vis` MCP server (`vis_scan` / `vis_render` / `vis_mining`) from any agent session; each CNS renderer is also a standalone script (`Rscript mcp/vis/cns/fig_<name>.R <workdir> <out_dir>`).

| Composition & network | Diversity | Differential & biomarkers |
|---|---|---|
| <img src="docs/figures/composition_barplot.png" width="270" alt="Taxonomic composition stacked barplot"/><br><sub>Composition barplot (94)</sub> | <img src="docs/figures/alpha_diversity.png" width="270" alt="Alpha diversity boxplots"/><br><sub>Alpha diversity (91)</sub> | <img src="docs/figures/volcano.png" width="270" alt="DESeq2 volcano plot"/><br><sub>Volcano (92)</sub> |
| <img src="docs/figures/composition_heatmap.png" width="270" alt="Genus composition heatmap"/><br><sub>Genus heatmap (94)</sub> | <img src="docs/figures/pcoa.png" width="270" alt="PCoA scatter with PERMANOVA"/><br><sub>PCoA + PERMANOVA (91)</sub> | <img src="docs/figures/lefse_barplot.png" width="270" alt="LEfSe LDA barplot"/><br><sub>LEfSe LDA (99b)</sub> |
| <img src="docs/figures/cross_dimension_network.png" width="270" alt="Bacteria-virus cross-kingdom network backbone"/><br><sub>Cross-kingdom network (93)</sub> | <img src="docs/figures/core_microbiome.png" width="270" alt="Core microbiome top-10 lollipop"/><br><sub>Core microbiome (99a)</sub> | <img src="docs/figures/shap_summary.png" width="270" alt="SHAP beeswarm via shapviz"/><br><sub>SHAP summary (96)</sub> |

| Functional profiling | Data mining registry | Interactive |
|---|---|---|
| <img src="docs/figures/pathway_activity.png" width="270" alt="Pathway activity butterfly bubbles"/><br><sub>Pathway activity (96b)</sub> | <img src="docs/figures/mining_attrs.png" width="270" alt="Seed registry attribute overview"/><br><sub>Seed registry (63,803 samples)</sub> | [Krona interactive plot](docs/figures/krona_plot.html)<br><sub>Taxonomic circle plot</sub> |
| <img src="docs/figures/ml_feature_weights.png" width="270" alt="Top-20 SIAMCAT feature weights lollipop"/><br><sub>ML feature weights (96)</sub> | <img src="docs/figures/mining_overlap.png" width="270" alt="Source overlap matrix"/><br><sub>Source overlap (3 databases)</sub> | <img src="docs/figures/ml_roc.png" width="270" alt="SIAMCAT multi-model ROC comparison"/><br><sub>ML ROC (96, `--with-ml`)</sub> |

Additional figure families (not pictured): SpiecEasi functional co-occurrence networks (96), batch-correction evaluation (95b), cross-cohort replication with meta-analysis (97), MAG-level reports (dRep/inStrain/DRAM HTML from the 32–43c chain), and QC reports (fastp/MultiQC/Krona).

---

## Script Index

Full index with per-script documentation lives in `Tutorial.md` (2,500+ lines, Chinese). Summary:

| Range | Content |
|-------|---------|
| 01–02b | Shared preprocessing (fastp, kneaddata, pair repair) |
| 11–15e | Bacteria read-based profiling (7 profilers + merges) |
| 16–20 | Assembly and quantification (incl. 16b metaSPAdes cross-check, opt-in) |
| 21–31e | Gene-catalog annotation (15 databases) |
| 28b | BGC novelty scoring against MIBiG |
| 32–43c | Binning, MAG QC/taxonomy/annotation, strain tracking, GEM modeling |
| 51–72 | Virome chain (incl. 67b PhaStyle third vote, opt-in) |
| 71–86 | Mycobiome chain (incl. 79b–79f eukaryotic QC/binning) |
| 91–99b | Statistics and reporting |
| 98e–98g | Cross-domain analyses (ANI clustering, orthogroups, correlation networks) |
| 00_* | Diagnostic and ops utilities |

---

## AI-Assisted Features

### RAG Knowledge Base (5 collections, 45,883 chunks)

| Collection | Chunks | Content |
|------------|--------|---------|
| `experience_kb` | 1,963 | Team experience: tool best practices, troubleshooting, parameter choices |
| `literature_kb` | 30,826 | Methods text from gut-microbiome papers (CC-audited open corpus) |
| `skill_design_kb` | 130 | Agent skill definitions and design patterns |
| `mechanism_kb` | 5,295 | Microbe → metabolite → host-gene relations (GutMGene + MicrobiomeKG) |
| `signature_kb` | 7,669 | Condition-stratified abundance signatures (BugSigDB; CVD-relevant) |

Retrieval is hybrid BM25 + dense vectors with reciprocal rank fusion (`BAAI/bge-small-zh-v1.5` embeddings). A versioned 45-question benchmark with per-index fingerprints guards retrieval quality (hybrid R@3 = 0.98); `scripts/utils/check_rag_drift.sh` flags when the index and the recorded benchmark diverge. Indexers support `--incremental` for 20-50x faster rebuilds during iteration.

### MCP Servers

- **glm-router** — GLM-5.3 / GLM-5.3-Flash dual-model routing (flagship for planning and review, Flash for high-frequency mechanical execution)
- **figure-library** — scientific figure template store
- **RAG retrieval** — the five collections above, via the official Model Context Protocol
- **mgx-vis** — publication figure orchestration (see [Figure Gallery](#figure-gallery))

Server registration lives in a local `.mcp.json` (not shipped — paths are machine-specific). Register `mcp/glm_router.py`, `mcp/server.py`, and `mcp/vis_server.py` with your MCP client using your own interpreter paths; `glm-router` reads its API key from the `GLM_API_KEY` environment variable, never from the repo.

### Agent Workflow

Every integrated script has a machine-readable skill card (`agents/skills/`) declaring inputs, outputs, dependencies, and known issues, so any MCP-capable coding assistant can discover and invoke the pipeline correctly. Production runs can optionally be logged to `agents/provenance/` as machine-readable JSON for reproducibility.

### Auto-Mining Subsystem (`mining/`)

An agent-driven gut-metagenome mining loop in the spirit of scBaseCount (Arc Institute): weekly seqout-based discovery maintains a growing sample index (two SQLite layers); AI curation maps metadata to ontologies (diseases to MONDO, body sites to UBERON); external resources (MGnify, AGP, iMSMS) can be bridged into the index; and disease signatures can be compared against BugSigDB over precomputed profiles with zero local compute. `mining/README.md` carries the operation manual and migration runbook.

---

## Repository Layout

```
CSCCD-MetagenomeFlow/
├── scripts/                  183 scripts + scripts/utils/ helpers
├── pipeline/                 Snakefile, config, hardware profiles, 11 rule files
├── agents/                   registry.yaml, skill cards, optional run provenance records
├── docs/                     experience docs (RAG source), tool references
├── mcp/                      RAG indexers, bridges, MCP servers
├── mining/                   auto-mining subsystem (discovery + curation + orchestrator)
├── db/                       ~1.2 TB analysis databases (not in git)
├── envs/                     57 conda environments (not in git)
├── 0Install.sh               environment + database installation
└── Tutorial.md               per-script documentation (Chinese)
```

---

## Disk Requirements

| Component | Space |
|-----------|-------|
| miniforge3 + conda envs | ~60 GB |
| `db/` databases | ~1.2 TB |
| 100-sample project (raw + intermediates + results) | ~2 TB |

---

## Migrating to a New Server

```bash
git clone <repo-url>
cd CSCCD-MetagenomeFlow
bash 0Install.sh                 # envs + databases; DB_BANK/SIBLING_DB env vars
                                  # override the local database-bank paths if you have one
source scripts/activate.sh
bash scripts/checkm_config.sh
```

---

## Tools & References

MetaPhlAn4 · StrainPhlAn4 · HUMAnN3 · Kraken2/Bracken · Centrifuger · sylph · MetaX · MEGAHIT · metaSPAdes · Prodigal · CD-HIT · Salmon · eggNOG-mapper · AMRFinderPlus · CARD/RGI · dbCAN3 · antiSMASH 8 · Defense-Finder · NCyc · PCyc · SCyc · BacMet · VFDB · CoverM · MetaBAT2 · MaxBin2 · SemiBin 2.5 · QuickBin · DAS_Tool · CheckM2 · GUNC · dRep · GTDB-Tk · Prokka · mlst · Roary · Snippy · geNomad · VirSorter2 · CheckV · vclust · PHAROKKA · PHOLD · VOGDB · BACPHLIP · PhaGCN3 · PhaStyle · iPHoP · vConTACT3 · DRAM · PhaBox2 · FunOMIC · CCMetagen · MicroFisher · Eukfinder · Tiara · BUSCO · MetaEuk · MEROPS · GutMGene v2.0 · MicrobiomeKG · BugSigDB · SIAMCAT · DESeq2 · ANCOM-BC2 · MaAsLin2 · MMUPHin · ConQuR · FastSpar · MBECS

---

## Community

Announcements and tutorials (in Chinese) are posted on the WeChat official account **肠动心弦**.
