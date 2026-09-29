# Blanco-Míguez et al. 2023 — MetaPhlAn 4: Uncharacterized Species Profiling

**Citation**: Blanco-Míguez A, Beghini F, Cumbo F, McIver LJ, Thompson KN, Zolfo M, Manghi P, Dubois L, Huang KD, Thomas AM, et al. "Extending and improving metagenomic taxonomic profiling with uncharacterized species using MetaPhlAn 4." *Nature Biotechnology* 41(11):1633-1644 (2023). DOI: 10.1038/s41587-023-01688-w, PMID: 37687556

## Summary

MetaPhlAn 4 revolutionizes metagenomic taxonomic profiling by integrating **>1.6 million microbial genomes**, including 5+ million metagenome-assembled genomes (MAGs), into a unified Species-Genome Bin (SGB) framework. This expansion explains **~20% more reads** in human gut metagenomes and **>40% more** in undercharacterized environments (rumen, soil, marine) compared to MetaPhlAn 3.

## Species-Genome Bin (SGB) Framework

The core innovation is the shift from traditional clade-specific markers to **SGBs**:

- **kSGBs (known SGBs)**: 21,978 species with NCBI taxonomy
- **uSGBs (unknown SGBs)**: 4,992 uncharacterized species from MAGs
- **Total**: 26,970 SGBs, each with curated clade-specific marker genes

Each SGB is defined by:
1. Genome clustering at 95% ANI threshold
2. Selection of 100-400 unique marker genes per SGB
3. Marker genes filtered to avoid cross-clade hits

## Technical Workflow

1. **Bowtie2 mapping**: Reads aligned to 1.01M marker genes (Bowtie2 `--very-sensitive`, MAPQ ≥5)
2. **SGB assignment**: Reads assigned to SGBs based on marker coverage
3. **Abundance estimation**: Relative abundance calculated from marker read counts with MAPQ and length normalization

## Key Improvements Over MetaPhlAn 3

| Aspect | MetaPhlAn 3 | MetaPhlAn 4 |
|--------|-------------|-------------|
| Reference genomes | ~100k isolates | **1.6M isolates + MAGs** |
| Uncharacterized species | Limited | **4,992 uSGBs** |
| Gut read assignment | Baseline | **+20%** |
| Rumen/soil read assignment | Baseline | **+42-45%** |
| Eukaryote markers | Basic | **Enhanced** |
| Backward compatibility | N/A | **❌ NOT compatible** |

**Critical Note**: MetaPhlAn 4 profiles **cannot be directly compared** with MetaPhlAn 3 due to the SGB framework change. Cohorts must be re-profiled for consistency.

## CSCCD-MetagenomeFlow Integration

MetaPhlAn 4 is used in three scripts:

- **11_bac_metaphlan4.sh**: Bacterial taxonomic profiling (primary use case)
- **11b_bac_metaphlan4_merge.sh**: Multi-sample abundance matrix generation
- **72_fun_metaphlan4_euk.sh**: Eukaryote profiling (`--kingdom Eukaryota` mode)

**Project Experience**: In Project_example (6 gut metagenomes), all fungi samples returned `UNCLASSIFIED` via MetaPhlAn4-euk, indicating very low fungal signal. PHF profiler (Yan et al. 2024 Cell 187, script 74e) was subsequently adopted as the primary fungi profiling method.

## Relevance to CSCCD-MetagenomeFlow

MetaPhlAn 4 is the **foundational bacterial taxonomic profiling tool** because:
- Highest species-level precision (>95%) among read-based methods
- Seamless integration with HUMAnN3 functional profiling (script 13)
- Active bioBakery ecosystem (StrainPhlAn4 for strain tracking, PhyloPhlAn for phylogenetics)
- Regular database updates incorporating new MAGs
