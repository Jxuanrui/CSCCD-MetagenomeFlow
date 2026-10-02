# Jie et al. 2026 — Global Vaginal Metagenome-assembled Genomes (GVMG)

**Citation**: Jie Z et al. "Genomic landscape of the human vaginal microbiome is linked to host genetics and population of origin." *Nature Genetics* (2026). DOI: 10.1038/s41588-026-02639-2

## Summary

This paper presents the **Global Vaginal Metagenome-assembled Genomes (GVMG) catalog**, constructed by integrating 10,665 in-house Chinese metagenomes, 2,967 publicly available metagenomes, and 1,433 bacterial isolates — totaling **13,632 metagenomes**. The resulting catalog contains **65,055 MAGs** representing 890 prokaryotic species across 18 bacterial phyla, 11 eukaryotic species, and 6,590 viral taxonomic units, with 53,679,109 protein-coding sequences.

## Pipeline Methods

The MAG construction pipeline closely mirrors CSCCD-MetagenomeFlow's bacterial pipeline:

- **QC**: fastp v0.20.1 (--length_required 51) + Bowtie2 v2.4.2 host removal (GRCh38 + CHM13v2.0)
- **Assembly**: metaSPAdes v3.14.0 for paired-end; MEGAHIT v1.2.9 (--presets meta-sensitive) for single-end
- **Binning**: MetaBAT2 v2.15 + MaxBin2 v2.2.7 + CONCOCT v1.1.0 with Mash-based 19-nearest-neighbor multi-coverage strategy → DAS_Tool integration → dRep at 99% ANI
- **Quality**: CheckM2 v1.0.1 with completeness ≥50%, contamination <5%, quality score ≥50 (formula: completeness − 5×contamination ≥ 50)
- **Taxonomy**: GTDB-Tk
- **Virome**: geNomad + DeepVirFinder + VIBRANT three-tool consensus → CheckV (completeness >50%)
- **Annotation**: Prodigal v2.6.3 (-p meta), KEGG, CAZy, VFDB, AMRFinder, BGC analysis

## Key Findings

- **M-GWAS**: 7 host genetic loci significantly associated with vaginal microbial species (p < 5×10⁻⁸)
- **OPRK1 – Ureaplasma urealyticum**: strongest genetic-microbiome association discovered
- Population-specific genomic variation patterns between Chinese and other populations
- Conserved phage-host associations identified via viral-bacterial co-occurrence analysis

## Relevance to CSCCD-MetagenomeFlow

1. **Pipeline benchmark**: validates that CSCCD-MetagenomeFlow's MAG pipeline (scripts 33/34/36/37/38/40) is consistent with large-scale catalog construction at the 10k-sample scale
2. **Parameter reference**: CheckM2 thresholds (≥50/5/50) and dRep 99% ANI provide validated filtering criteria
3. **Multi-sample binning**: Mash-based 19-nearest-neighbor coverage strategy is more rigorous than single-sample coverage; consider adopting for large cohorts
4. **Virome expansion**: three-tool virus consensus (geNomad+DeepVirFinder+VIBRANT) provides a validation benchmark for our two-tool approach (scripts 52+53)
