# Nayfach et al. 2021 — CheckV: Viral Genome Quality and Completeness Assessment

**Citation**: Nayfach S, Camargo AP, Schulz F, Eloe-Fadrosh E, Roux S, Kyrpides NC. "CheckV assesses the quality and completeness of metagenome-assembled viral genomes." *Nature Biotechnology* 39(5):578-585 (2021). DOI: 10.1038/s41587-021-01100-6, PMID: 34816326

## Summary

CheckV is the quality-control layer for viral contigs and vMAGs in CSCCD-MetagenomeFlow. It estimates completeness without relying on universal single-copy markers, detects host contamination in proviruses, and identifies complete genomes from terminal repeat signals.

The core innovation is an **AAI-based completeness estimator** backed by a curated complete-virus reference database, with HMM support for more divergent genomes. This makes CheckV the standard post-caller QC tool after geNomad and VirSorter2.

## Key Technical Innovations

1. **AAI-based completeness estimation**: Viral genomes rarely contain universal marker genes, so CheckV estimates expected genome length from related complete references rather than bacterial-style marker completeness.

2. **Terminal repeat detection for complete genomes**: Direct terminal repeats and inverted terminal repeats provide sequence-level evidence that a viral contig is complete or circular.

3. **Provirus boundary modeling**: Host and viral HMM markers are combined to identify host-virus transitions and excise prophage regions from longer microbial contigs.

## CSCCD-MetagenomeFlow Integration

CheckV is used in two places:

- **54_vir_checkv_contig.sh**: quality assessment of deduplicated viral contigs after geNomad and VirSorter2 prediction.
- **62_vir_checkv_mag.sh**: per-bin quality evaluation of vMAGs, retaining complete/high/medium-quality bins.

Project filtering follows the paper's practical quality logic:

- **High-confidence contigs/vMAGs**: completeness `>=50%` and contamination `<5%`
- **Complete genomes**: DTR/ITR-supported circular or terminally repeated sequences
- **Proviruses**: host flanks removed before downstream cataloging

**Parameter Deviation**: The paper commonly benchmarks contigs `>=5000 bp`, but CSCCD-MetagenomeFlow does not enforce that minimum inside CheckV. This is intentional for gut virome work, where fragmented phages below 5 kb are still informative after upstream caller intersection.

## Performance Benchmarks

| Metric | CheckV |
|--------|--------|
| Completeness sensitivity | **92%** |
| Completeness specificity | **99.7%** |
| Provirus detection recall | **90%** |
| Completeness logic | AAI + HMM fallback |

## Relevance to CSCCD-MetagenomeFlow

CheckV is the **primary virome QC standard** in the project because it solves three practical problems at once:

- removes bacterial contamination from viral calls
- standardizes completeness reporting for catalogs and vMAGs
- provides publishable quality categories for downstream interpretation

Without CheckV, virus discovery output from geNomad or VirSorter2 would be much harder to compare across samples, especially when assemblies contain fragmented genomes and embedded prophages.
