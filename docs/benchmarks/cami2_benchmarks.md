---
tool: "cami2-benchmarks"
category: "benchmark"
source: "Meyer et al. 2022 Nat Methods; Blanco-Miguez et al. 2023 Nat Biotechnol; Chklovski et al. 2023 Nat Methods"
date: "2026-06-12"
tags: [benchmark, parameter-recommendation]
---

## Summary

This note combines two evidence layers:

- Official CAMI II benchmarking for assembly and genome binning, where MEGAHIT, MetaBAT2, and MaxBin2 were scored directly.
- CAMI2-based follow-up synthetic host-associated benchmarks from the MetaPhlAn 4 paper, which are the clearest published CAMI2 results for MetaPhlAn4 and Kraken2 plus Bracken.

For gut-focused work, the most transferable profiling results are the CAMI2 gastrointestinal-tract and mouse-gut synthetic communities. For assembly and MAG recovery, the official CAMI II marine and strain-madness datasets remain the standard published reference.

CheckM2 was not part of the original CAMI II leaderboard. Its metrics below come from the CheckM2 benchmark paper and are included because it is now the common downstream MAG-QC choice.

## Recommended Parameters

- `MetaPhlAn4`: use the current SGB database and default species-level profiling; the published CAMI2 benchmarks were strongest when the native SGB-aware output was kept intact.
- `Kraken2/Bracken`: always benchmark the exact database you plan to use. The CAMI2 follow-up results were highly database-sensitive. A practical baseline is `kraken2 --paired --report ...` followed by `bracken -l S -r <read_length>`.
- `MEGAHIT`: a good CAMI-aligned starting point is `--presets meta-sensitive` with a short-read metagenome k-mer ladder; for large pooled assemblies, the CAMI II submissions used `--k-min 21 --k-max 91` and `-m 0.8`.
- `MetaBAT2`: keep `-m 1500` as the default MAG-recovery threshold. CAMI II showed that raising the contig cutoff to 2500 bp usually improved purity slightly but traded away completeness.
- `MaxBin2`: run with multi-sample abundance when possible. In CAMI II, MaxBin2 recovered more base pairs than MetaBAT2 on MEGAHIT assemblies, but with lower purity.
- `CheckM2`: use it after bin refinement and report completeness plus contamination together with the tool version. For highly novel taxa, retain CheckM1 or marker-based cross-checks if a manuscript requires method triangulation.

## Performance Metrics

### Taxonomic Profiling on CAMI2 Host-Associated Synthetic Communities

| Tool | Dataset | Precision | Recall | F1 |
| --- | --- | ---: | ---: | ---: |
| MetaPhlAn4 (native output) | Gastrointestinal tract | 99.56% | 97.75% | 98.63% |
| MetaPhlAn4 (native output) | Mouse gut | 98.47% | 94.19% | 96.26% |
| MetaPhlAn4 (OPAL-normalized) | Gastrointestinal tract | 94.85% | 92.29% | 93.52% |
| MetaPhlAn4 (OPAL-normalized) | Mouse gut | 86.31% | 77.32% | 81.51% |
| Kraken2 plus Bracken GTDB | Gastrointestinal tract | 38.09% | 89.25% | 52.39% |
| Kraken2 plus Bracken RefSeq | Gastrointestinal tract | 63.89% | 88.19% | 73.49% |
| Kraken2 plus Bracken GTDB | Mouse gut | 63.94% | 89.73% | 74.24% |
| Kraken2 plus Bracken RefSeq | Mouse gut | 30.39% | 31.18% | 29.35% |

### MEGAHIT Assembly Metrics from Official CAMI II

| Assembler | Dataset | Strain recall | Strain precision | Genome fraction | NGA50 |
| --- | --- | ---: | ---: | ---: | ---: |
| MEGAHIT v1.2.7 | Marine short-read pooled | 11.98% | 49.47% | 42.44% | 10,897 bp |
| MEGAHIT v1.2.7 | Strain-madness short-read pooled | 0.00% | 90.91% | 6.79% | 2,641 bp |
| MEGAHIT v1.1.2 | Marine short-read pooled | 12.48% | 53.01% | 41.10% | 26,599 bp |
| MEGAHIT v1.1.2 | Strain-madness short-read pooled | 2.70% | 84.62% | 10.38% | 4,793 bp |

### Genome Binning on CAMI II MEGAHIT Assemblies

| Tool | Dataset | Completeness | Purity | F1 | ARI |
| --- | --- | ---: | ---: | ---: | ---: |
| MetaBAT2 A1 (`-m 1500`) | Marine MEGAHIT assembly | 19.0% | 87.9% | 31.2% | 87.1% |
| MetaBAT2 A2 (`-m 2500`) | Marine MEGAHIT assembly | 17.5% | 91.0% | 29.3% | 89.4% |
| MaxBin2 v2.2.7 | Marine MEGAHIT assembly | 20.6% | 68.6% | 31.7% | 61.7% |
| MaxBin2 v2.0.2 | Marine MEGAHIT assembly | 21.1% | 70.0% | 32.5% | 63.3% |
| MetaBAT2 v0.25.4 | Strain-madness MEGAHIT assembly | 4.4% | 79.0% | 8.3% | 88.7% |
| MaxBin2 v2.2.7 | Strain-madness MEGAHIT assembly | 4.8% | 57.6% | 8.9% | 48.2% |
| MaxBin2 v2.0.2 | Strain-madness MEGAHIT assembly | 4.8% | 58.1% | 8.8% | 44.3% |

### CheckM2 MAG-QC Benchmark

| Tool | Benchmark context | Metric |
| --- | --- | --- |
| CheckM2 | Novel lineage genomes in the CheckM2 paper | Mean absolute error for genome-quality prediction was reported as `2.9 +/- 2.6` for high-quality genomes and `4.7 +/- 3.8` for medium or low-quality genomes. |

## Notes

- The profiling numbers above are the most gut-relevant CAMI2 synthetic results now in print; they are not the same leaderboard as the official CAMI II marine and strain-madness challenge.
- Bracken performance in CAMI2 was dominated by database choice. For gut work, a GTDB-like or gut-curated database is usually safer than a generic RefSeq build, but the right answer is still project-specific.
- MetaBAT2 was the cleaner binner in CAMI II, while MaxBin2 usually recovered more total sequence. That is why many modern MAG workflows still run both and then refine or dereplicate.
- MEGAHIT remained a strong speed-memory baseline in CAMI II even when it was not the top assembler on every metric.
- CheckM2 should be treated as a post-benchmark MAG-QC tool here, not a CAMI II entrant.
- Sources:
  - CAMI II challenge paper: https://www.nature.com/articles/s41592-022-01431-4
  - MetaPhlAn 4 paper and supplementary CAMI2 tables: https://www.nature.com/articles/s41587-023-01688-w
  - CheckM2 paper: https://www.nature.com/articles/s41592-023-01940-w
