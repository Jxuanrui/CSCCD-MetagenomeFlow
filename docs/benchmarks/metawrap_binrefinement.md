---
tool: "metaWRAP bin_refinement"
category: "benchmark"
source: "Uritskiy et al. 2018 Microbiome; metaWRAP official tutorial; Bowers et al. 2017 Nat Biotechnol; Sieber et al. 2018 Nat Microbiol"
date: "2026-06-12"
tags: [benchmark, parameter-recommendation]
---

## Summary

`metaWRAP bin_refinement` consolidates two or three bin sets by selecting the version of each genome that best satisfies user-defined completeness and contamination thresholds. In practice, it is most useful when MetaBAT2, MaxBin2, and one additional binner such as SemiBin2 or CONCOCT each recover overlapping but non-identical MAGs.

The official tutorial states that the defaults are `-c 70` and `-x 5`, but explicitly recommends relaxing them to `-c 50 -x 10` for most real datasets. Those relaxed thresholds line up with MIMAG medium-quality draft standards and are the best default for discovery-oriented gut metagenome work.

## Recommended Parameters

### Core Command

```bash
metawrap bin_refinement \
  -o BIN_REFINEMENT \
  -t 32 \
  -A metabat2_bins \
  -B maxbin2_bins \
  -C semibin2_bins \
  -c 50 \
  -x 10
```

### Threshold Selection Guide

| Goal | Recommended thresholds | Why |
| --- | --- | --- |
| Exploratory MAG recovery | `-c 50 -x 10` | Best first pass; matches MIMAG medium-quality drafts |
| Balanced production set | `-c 70 -x 5` | Official metaWRAP default; fewer but cleaner bins |
| High-quality reporting set | `-c 90 -x 5` | Good for near-complete MAGs before final manual review |
| Strain-rich, difficult gut assemblies | Run both `50/10` and `70/5` | Lets you compare recall versus purity explicitly |

### Practical Rationale

- Use at least two input bin sets; three is better.
- Prefer complementary binners rather than multiple near-identical runs of the same algorithm.
- Keep `-c 50 -x 10` as the main discovery setting, then re-run a stricter pass for reporting subsets.
- Run CheckM2 after refinement for final QC, because metaWRAP refinement is historically CheckM-based.

## Performance Metrics

### MIMAG Thresholds Used Most Often in Practice

| Quality tier | Completeness | Contamination |
| --- | ---: | ---: |
| Medium-quality draft | `>=50%` | `<=10%` |
| High-quality draft | `>=90%` | `<=5%` |

### Official metaWRAP Tutorial Example

The tutorial demo reported the following counts of bins above `>50%` completeness and `<10%` contamination:

| Bin set | Good bins |
| --- | ---: |
| CONCOCT | 10 |
| MaxBin2 | 7 |
| MetaBAT2 | 11 |
| metaWRAP refined set | 13 |

### Comparison with DAS Tool

| Aspect | metaWRAP bin_refinement | DAS Tool |
| --- | --- | --- |
| Main optimization target | User-selected completeness and contamination cutoffs | Single-copy-gene score optimization |
| Typical input count | 2 to 3 bin sets | 2 or more bin sets |
| Default strictness | User supplies `-c/-x` | `--score_threshold 0.5` by default |
| Strength | Very transparent thresholding tied to MAG-quality goals | Excellent at large multi-binner integration |
| Weakness | Less scalable when many binners or many threshold sweeps are compared | Score threshold is less intuitive than direct completeness and contamination cutoffs |

## Notes

- MIMAG high-quality drafts also require rRNA and tRNA evidence; completeness and contamination alone are not sufficient for the formal label.
- For gut cohorts, `-c 50 -x 10` is usually the right first-pass setting because many biologically useful bins will be lost by starting at `70/5` or `90/5`.
- If two refined sets look similar, choose the one that produces more non-redundant MAGs after downstream dereplication, not just the one with the highest raw bin count.
- DAS Tool is often the better choice when integrating many binners or many parameter sweeps. metaWRAP is often easier to justify when the project wants direct control over MIMAG-aligned thresholds.
- Sources:
  - metaWRAP paper: https://microbiomejournal.biomedcentral.com/articles/10.1186/s40168-018-0541-1
  - metaWRAP tutorial: https://github.com/bxlab/metaWRAP/blob/master/Usage_tutorial.md
  - MIMAG standards: https://www.nature.com/articles/nbt.3893
  - DAS Tool paper: https://www.nature.com/articles/s41564-018-0171-1
