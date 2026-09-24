# Camargo et al. 2023 — geNomad: Identification of Mobile Genetic Elements

**Citation**: Camargo AP, Roux S, Schulz F, Babinski M, Xu Y, Hu B, Chain PSG, Nayfach S, Kyrpides NC. "Identification of mobile genetic elements with geNomad." *Nature Biotechnology* 42(8):1303-1312 (2023). DOI: 10.1038/s41587-023-01953-y, PMID: 37904079

## Summary

geNomad is a deep-learning-based classification framework that identifies plasmids and viruses in assembled metagenomic sequences. Combining gene content analysis with convolutional neural networks (CNN) and conditional random field (CRF) modeling, geNomad achieves Matthews correlation coefficients of **77.8% for plasmids** and **95.3% for viruses**, substantially outperforming VirSorter2 and VIBRANT.

## Key Technical Innovations

1. **Hybrid Deep Learning + CRF Architecture**: Unlike k-mer-only (VirSorter2) or HMM-only (VIBRANT) approaches, geNomad uses:
   - Convolutional neural network for sequence feature extraction
   - Conditional Random Field to capture gene-order dependencies (e.g., integrase-excisionase clusters)
   - This combination explains the performance gain: CRF models structured predictions vs. isolated HMM hits

2. **Comprehensive Marker Database**: >200,000 curated marker protein profiles covering viral hallmark genes, plasmid replication machinery, and chromosomal housekeeping genes. Enables simultaneous classification and functional annotation.

3. **Unified Mobile Element Framework**: Handles both plasmids and viruses in a single classification pipeline, addressing the biological reality of ambiguous elements (prophages, conjugative transposons).

## CSCCD-MetagenomeFlow Integration

geNomad is used in two scripts:

- **52_vir_genomad.sh**: Primary virus identification from assembled contigs
- **57_vir_votu_genomad.sh**: Taxonomic annotation of viral sequences via marker phylogenetics

**Parameter Deviation**: CSCCD-MetagenomeFlow uses `min_contig_length=1500` (vs. paper's 2500bp) to capture shorter viral fragments in gut metagenomes, where many phages are fragmented.

**Complementary Tools**: geNomad output is cross-validated with VirSorter2 (script 53) and quality-filtered via CheckV (script 54) to reduce false positives. BACPHLIP (script 67) complements geNomad's lifestyle prediction module.

## Performance Benchmarks

| Metric | geNomad | VirSorter2 | VIBRANT |
|--------|---------|------------|---------|
| Virus MCC | **0.953** | ~0.92 | ~0.92 |
| Plasmid MCC | **0.778** | N/A | N/A |
| Virus Precision | 0.987 | Similar | Similar |
| Virus Recall | 0.923 | Lower | Lower |

## Relevance to CSCCD-MetagenomeFlow

geNomad is the **primary virus identification tool** in the pipeline, chosen for its:
- High accuracy (MCC 95.3%) validated on diverse datasets
- Functional annotation output (marker genes + taxonomy)
- Active development and regular database updates (portal.nersc.gov/genomad/)
- Integration with CheckV quality standards
