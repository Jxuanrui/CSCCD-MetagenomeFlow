# Beghini et al. 2021 — HUMAnN3 Functional Profiling in bioBakery 3

**Citation**: Beghini F, McIver LJ, Blanco-Miguez A, Dubois L, Asnicar F, Maharjan S, Mailyan A, Manghi P, Scholz M, Thomas AM, Valles-Colomer M, Weingart G, Zhang Y, Zolfo M, Huttenhower C, Franzosa EA, Segata N. "Integrating taxonomic, functional, and strain-level profiling of diverse microbial communities with bioBakery 3." *eLife* 10:e65088 (2021). DOI: 10.7554/eLife.65088, PMID: 33830980

## Summary

HUMAnN3 is the functional profiling engine in CSCCD-MetagenomeFlow for bacterial pathway quantification, with cross-dimension reuse for fungi-stratified pathways. It links species-aware taxonomic profiling to gene-family and pathway abundance estimation through a staged nucleotide-then-protein search strategy.

The paper's core design is a **3-step workflow**:

1. **MetaPhlAn prescreen** to identify taxa present in the sample
2. **ChocoPhlAn + UniRef90 alignment** using nucleotide search first, translated search second
3. **MinPath pathway reconstruction** to quantify MetaCyc pathways with species stratification

## Key Technical Innovations

1. **Taxonomy-guided functional search**: MetaPhlAn output restricts the ChocoPhlAn search space, reducing runtime and improving species-aware assignment.

2. **Two-stage alignment strategy**: Known organisms are handled efficiently by nucleotide alignment, while novel or divergent functions are recovered with DIAMOND translated search against UniRef90.

3. **Species-stratified pathway output**: HUMAnN reports not only total pathway abundance but also which species contributed to each pathway, enabling cross-domain reuse in project post-processing.

## CSCCD-MetagenomeFlow Integration

HUMAnN is used in two scripts:

- **13_bac_humann3.sh**: primary bacterial pathway quantification
- **73_fun_humann4_fungi.sh**: extraction of fungi-stratified pathways from HUMAnN stratified output

Project integration preserves the paper's architecture but adds practical cohort-speed adaptations:

- reuse of external **MetaPhlAn4** profiles via `--taxonomic-profile`
- `--bypass-nucleotide-index` logic via direct database configuration
- project-defined `standard / balanced / fast` modes for throughput tuning

**Parameter Deviation**: The repository script is optimized for large gut metagenome cohorts. It keeps the HUMAnN design intact but introduces prescreen thresholds and optional R1-only processing in `fast` mode, which is more aggressive than the publication's canonical presentation.

## Performance Benchmarks

| Metric | HUMAnN3 |
|--------|---------|
| Pathways quantified | **95%** |
| Runtime with 16 cores | **<1 hour/sample** |
| Search strategy | nucleotide first, translated fallback |
| Output detail | community + species-stratified pathways |

## Relevance to CSCCD-MetagenomeFlow

HUMAnN is the **functional interpretation layer** for the bacterial branch and a useful bridge into fungi:

- converts taxonomic composition into pathway-level biological interpretation
- provides stratified outputs that can be reused for downstream taxon-specific summaries
- scales better when prescreening is available from MetaPhlAn

For this project, HUMAnN is especially valuable because it connects species-resolved profiling to pathway abundance in a way that remains comparable across large cohorts while still supporting cross-dimension post-processing.
