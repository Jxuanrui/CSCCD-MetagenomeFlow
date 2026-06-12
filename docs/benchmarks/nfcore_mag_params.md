---
tool: "nf-core/mag"
category: "benchmark"
source: "nf-core/mag official documentation and schema; MEGAHIT, SPAdes, SemiBin2, CheckM2, and QUAST tool documentation"
date: "2026-06-12"
tags: [benchmark, parameter-recommendation]
---

## Summary

This document distills the nf-core/mag community defaults that matter most for gut metagenomes and adds the most common expert overrides. The main design pattern in nf-core/mag is conservative preprocessing, parallel assembly and binning, then post hoc QC instead of aggressive early filtering.

As of `2026-06-12`, the official schema still exposes the most important practical defaults: `clip_tool=fastp`, `fastp_qualified_quality=15`, `fastp_cut_mean_quality=15`, `min_contig_size=1500`, `semibin_environment=global`, and optional `run_checkm2`.

## Recommended Parameters

### Preprocessing

- Keep `--clip_tool fastp` for short-read gut datasets.
- Keep the schema defaults `--fastp_qualified_quality 15` and `--fastp_cut_mean_quality 15`.
- Turn on `--fastp_trim_polyg` for NovaSeq-style data with poly-G tails.
- Avoid `--skip_shortread_qc` unless reads were already cleaned upstream with documented settings.

Recommended baseline:

```bash
--clip_tool fastp \
--fastp_qualified_quality 15 \
--fastp_cut_mean_quality 15 \
--fastp_trim_polyg
```

### Host Removal

- Use `--host_fasta` plus `--host_fasta_bowtie2index` for human gut studies when you control the reference build.
- Add `--host_removal_verysensitive` when host carryover is non-trivial or ethics rules require aggressive depletion.
- Add `--save_hostremoved_reads` when downstream auditability matters.

Recommended baseline:

```bash
--host_fasta /refs/GRCh38_masked.fa \
--host_fasta_bowtie2index /refs/GRCh38_bowtie2/ \
--host_removal_verysensitive \
--save_hostremoved_reads
```

### Assembly

- Keep both assemblers enabled unless you already know one is unsuitable for the cohort.
- For routine short-read MAG recovery, use MEGAHIT as the robust baseline and add `--megahit_options '--presets meta-sensitive'`.
- For smaller, deeper, or strain-rich projects, keep SPAdes enabled for comparison and use `--spades_options '-k 21,33,55,77'` only if you need explicit k-mer control.
- Keep `spades_downstreaminput=scaffolds` unless you see obvious chimera inflation and want a stricter `contigs` downstream handoff.
- Do not `--skip_quast` during method comparison runs.

Recommended baseline:

```bash
--megahit_options '--presets meta-sensitive' \
--spades_options '-k 21,33,55,77'
```

### Binning

- Keep all three binners on: do not use `--skip_metabat2`, `--skip_maxbin2`, or `--skip_semibin` for discovery runs.
- Keep `--min_contig_size 1500`; it matches common MAG-recovery practice and the pipeline default.
- For single-sample gut assemblies, set `--semibin_environment human_gut` or `mouse_gut` instead of the default `global`.
- Leave `--semibin_environment global` for mixed cohorts or coassemblies, because the pre-trained environment hint is ignored once several samples inform one assembly.
- Only set `--shortread_percentidentity` or `--longread_percentidentity` when spurious cross-mapping is clearly inflating depth profiles.

Recommended baseline:

```bash
--min_contig_size 1500 \
--semibin_environment human_gut
```

### QC and Reproducibility

- Turn on `--run_checkm2` for modern MAG QC.
- Keep QUAST enabled during parameter tuning and workflow benchmarking.
- Retain fixed seeds for reproducibility: `metabat_rng_seed=1` and `semibin_rng_seed=1`.
- Use `megahit_fix_cpu_1` only when strict bitwise reproducibility matters more than speed.

Recommended baseline:

```bash
--run_checkm2
```

## Performance Metrics

Use these as workflow-level acceptance targets rather than leaderboard claims:

| Stage | Metric | Practical target for gut metagenomes |
| --- | --- | --- |
| Preprocessing | Read survival after QC | Usually `>80%` unless host contamination is extreme |
| Host removal | Non-host read retention | Highest possible while host reads approach zero |
| Assembly | Contigs passed to binning | Focus on contigs `>=1500 bp` |
| Assembly | Assembly comparison | Prefer the assembler giving more medium/high-quality bins, not just the highest N50 |
| Binning | MQ MAG threshold | Completeness `>=50%`, contamination `<=10%` |
| Binning | HQ MAG threshold | Completeness `>=90%`, contamination `<=5%` |
| QC | Taxonomic classification readiness | GTDB-Tk defaults in nf-core/mag assume at least `50%` completeness and at most `10%` contamination |

## Notes

- The nf-core/mag schema explicitly documents `min_contig_size=1500`, `clip_tool=fastp`, `fastp_qualified_quality=15`, `fastp_cut_mean_quality=15`, and `semibin_environment=global`.
- The same schema notes that `host_removal_verysensitive` switches Bowtie2 host filtering from `--sensitive` to `--very-sensitive`.
- SemiBin2 environment models are most useful for single-sample assemblies from a matched biome; `human_gut` is usually the right choice for human stool and `mouse_gut` for murine stool.
- SPAdes is more expensive but still worth retaining for smaller benchmark panels because it can win on downstream bin recovery even when MEGAHIT is the faster default.
- Sources:
  - Current nf-core/mag docs: https://nf-co.re/mag
  - Current nf-core/mag schema: https://raw.githubusercontent.com/nf-core/mag/master/nextflow_schema.json
  - MEGAHIT: https://github.com/voutcn/megahit
  - SPAdes/metaSPAdes: https://github.com/ablab/spades
  - SemiBin2: https://github.com/BigDataBiology/SemiBin
  - CheckM2: https://github.com/chklovski/CheckM2
  - QUAST/metaQUAST: https://github.com/ablab/quast
