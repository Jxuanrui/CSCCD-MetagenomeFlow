# Guo et al. 2021 — VirSorter2: Multi-Classifier Virus Identification

**Citation**: Guo J, Bolduc B, Zayed AA, Varsani A, Dominguez-Huerta G, Delmont TO, Pratama AA, Gazitua MC, Vik D, Sullivan MB, Roux S. "VirSorter2: a multi-classifier, expert-guided approach to detect diverse DNA and RNA viruses." *Microbiome* 9:37 (2021). DOI: 10.1186/s40168-020-00990-y, PMID: 33522966

## Summary

VirSorter2 is the broad-recall virus caller in CSCCD-MetagenomeFlow. It was designed to move beyond dsDNA phage-centric detection and support **RNA viruses, ssDNA viruses, NCLDVs, and lavidaviridae** through a classifier ensemble rather than a single model.

The method combines **hallmark HMM evidence** with **sequence composition and coding features**, then applies a calibrated final viral score. In practice, this makes VirSorter2 valuable as a complementary detector beside geNomad.

## Key Technical Innovations

1. **Five specialized classifiers**: Separate models are used for dsDNA phages, ssDNA viruses, RNA viruses, NCLDVs, and lavidaviridae instead of forcing all virus groups into one phage-oriented classifier.

2. **Hybrid feature design**: Viral hallmark genes provide biological specificity, while k-mer and coding statistics preserve sensitivity for divergent or weakly annotated contigs.

3. **Expert-guided scoring framework**: Final scores provide an interpretable precision/recall tradeoff and support downstream filtering rather than binary HMM-only rules.

## CSCCD-MetagenomeFlow Integration

VirSorter2 is used in:

- **53_vir_virsorter2.sh**: viral contig prediction from assembled virome contigs

Project settings keep the paper's **score threshold `0.5`** and broad classifier scope:

- `--include-groups dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae`
- consensus use with **geNomad** (script 52)
- downstream quality control with **CheckV** (script 54)

**Parameter Deviation**: The paper commonly recommends longer contigs around `>=5000 bp`, but the current project script uses `--min-length 1000` to keep short gut virome fragments. This increases candidate recall, and the precision cost is controlled by intersecting with geNomad before CheckV.

## Performance Benchmarks

| Metric | VirSorter2 |
|--------|------------|
| dsDNA phage recall | **95.4%** |
| dsDNA phage precision | **90.1%** |
| RNA virus recall vs DeepVirFinder | **Higher** |
| ssDNA virus recall vs DeepVirFinder | **Higher** |

## Relevance to CSCCD-MetagenomeFlow

VirSorter2 is the **recall-oriented virus discovery complement** in the virome branch:

- expands detection beyond classic dsDNA phages
- catches divergent viral fragments missed by single-family tools
- provides an independent signal that can be intersected with geNomad

This role fits the project design well: broad candidate detection first, then consensus and CheckV-based QC to keep the final viral catalog conservative.
