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
- [Script Index](#script-index)
- [AI-Assisted Features](#ai-assisted-features)
- [Repository Layout](#repository-layout)
- [Disk Requirements](#disk-requirements)
- [Migrating to a New Server](#migrating-to-a-new-server)
- [Tools & References](#tools--references)

---

## Overview

Most published pipelines handle one kingdom at a time, depend on cloud infrastructure, or don't reproduce cleanly across servers. This platform takes a different approach: bacteria (scripts 11–43c), virome (51–72), and mycobiome (71–86) run side by side under one script convention and one Snakemake DAG, on a single server, with everything installed locally.

**Why it works:**

- **One preprocessing chain, three kingdoms.** Shared QC and host-removal steps; per-kingdom analysis branches off cleanly. No glue scripts or format conversion between steps.
- **Mechanism discovery is part of the pipeline, not an afterthought.** The `mechanism_kb` knowledge base carries 5,295 microbe → metabolite → host-gene relations (GutMGene v2.0 curated causal chains, OmniPath interactions, MicrobiomeKG 2025 cohort associations), each traceable to a publication. Queries like "which microbial functions produce butyrate and activate FFAR2?" resolve directly against it.
- **Runs anywhere.** 57 conda environments and ~1.2 TB of databases live under the project root. A new server is `git clone` + `bash 0Install.sh`.
- **Statistics-ready outputs.** Script 98b writes 11 integration tables per dimension — raw TPM, relative abundance, and CLR — that plug straight into LEfSe, ANCOM-BC2, MaAsLin2, and SIAMCAT.
- **Three run modes, one script layer.** Step-by-step for debugging, Bash pipelines with `--from`/`--skip` checkpointing for lightweight runs, Snakemake for production. All three call the same scripts underneath.

### Recent Updates

> Details: `git log v1.1.4-baseline..HEAD`

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

### Run Modes

**Step-by-step** — debugging, fine-grained control:

```bash
bash scripts/01_qc_fastp.sh       -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/Maxmetagenome
bash scripts/02_qc_kneaddata.sh   -s SAMPLE_ID -t 16 -w /path/to/project -r ~/Course/Maxmetagenome
```

**Bash pipeline** — lightweight, checkpointed:

```bash
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --from metaphlan4   # resume
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --force              # re-run
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

### Agent Workflow

The CLAUDE.md governance file defines the collaboration protocol (planning, review gates, provenance logging). Every integrated script has a skill card (`agents/skills/`) declaring inputs, outputs, dependencies, and known issues; every production run can be logged to `agents/provenance/` as machine-readable JSON. The `/mgx-*` skill files in `.claude/` (from the Claude Code era) remain as reference material.

---

## Repository Layout

```
CSCCD-MetagenomeFlow/
├── scripts/                  183 scripts + scripts/utils/ helpers
├── pipeline/                 Snakefile, config, hardware profiles, 11 rule files
├── agents/                   registry.yaml, 138 skill cards, provenance records
├── docs/                     experience docs (RAG source), tool references
├── mcp/                      RAG indexers, bridges, MCP servers
├── db/                       ~1.2 TB analysis databases (not in git)
├── envs/                     57 conda environments (not in git)
├── 0Install.sh               environment + database installation
├── CLAUDE.md                 agent governance and collaboration protocol
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
