---
# Wacker et al. 2026, Nature Communications — TOFU-MAaPO replication skill package

**DOI**: 10.1038/s41467-026-74033-9

TOFU-MAaPO is a large-scale metagenome reanalysis workflow designed for the Sequence Read Archive. The paper positions the workflow as a fast, scalable, and reproducible Nextflow pipeline for high-throughput SRA processing, with Docker and Apptainer support and deployment patterns suitable for HPC execution. Its major processing path is: SRA download, read QC with `fastp`, host removal with `Bowtie2`, metagenome assembly with `metaSPAdes` or `MEGAHIT`, ensemble binning with `MetaBAT2`, `MaxBin2`, and `SemiBin2`, refinement with `DAS_Tool`, MAG quality control with `CheckM2`, taxonomic assignment with `GTDB-Tk`, and an assembly-free profiling branch using `MetaPhlAn4` and `Kraken2`.

The reported headline result is improved genome recovery at scale: 12% to 77% more high-quality MAGs than three comparison pipelines, and processing of 16,462 SRA samples in under 55 hours under the authors' execution environment. For CSCCD-MetagenomeFlow, this paper is most useful as a reference architecture for very large public-data reanalysis rather than a drop-in workflow component.

## TOFU-MAaPO vs CSCCD-MetagenomeFlow

TOFU-MAaPO and CSCCD-MetagenomeFlow overlap strongly in tool coverage. Both span QC, host filtering, assembly, binning, MAG QC, taxonomy, and profiling. The practical difference is framework and intent. TOFU-MAaPO is an upstream Nextflow system optimized for large-scale SRA ingestion, containerized portability, and HPC scheduling. CSCCD-MetagenomeFlow is Snakemake-based and oriented toward integrating comparable methods into a unified gut microbiome research platform. Because of that, this package is deliberately **reference-only**: it captures the paper's method structure, parameters, and provenance, but does not vendor the original workflow or create `code/original` or `code/adapted` subdirectories.

## Upstream resources

- Pipeline repository: `https://github.com/ikmb/TOFU-MAaPO`
- Paper analysis repository: `https://github.com/ikmb/TOFUpaper`

## Validation

Run:

```bash
bash skills/replications/statistics/Wacker2026_NatCommun/validate.sh .
```

The validation script checks package completeness, confirms both GitHub repositories are reachable, and verifies that the package remains reference-only.
