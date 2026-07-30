# Snakemake --force Parameter Integration

**Status**: Partially implemented (config.yaml only)  
**Date**: 2026-07-30

## Current State

### ✅ Completed
1. **Bash scripts**: 123/125 scripts (98.4%) support `--force` parameter
   - Flow orchestrators propagate `--force` via `FORCE_FLAG` variable
   - Individual scripts check `FORCE=1` and skip output existence checks
   - Commit: `e29fa7c`

2. **config.yaml**: Added `force: false` parameter with documentation
   - Default: false (opt-in behavior)
   - Comment explains 123/125 script support
   - Users can set `force: true` to enable global force re-run

### ⏳ TODO: Snakemake Rule Updates

**Scope**: 73 rules across 7 files need `{params.force_flag}` integration

#### Files to update:
- `pipeline/rules/bacteria_taxonomy.smk` (11 rules)
- `pipeline/rules/bacteria_assembly.smk` (5 rules)
- `pipeline/rules/bacteria_binning.smk` (18 rules)
- `pipeline/rules/bacteria_annotation.smk` (16 rules)
- `pipeline/rules/mycobiome.smk` (20 rules)
- `pipeline/rules/preprocessing.smk` (2 rules)
- `pipeline/rules/crosscohort.smk` (1 rule)

#### Pattern to apply:

```python
rule example:
    input:
        r1 = ...,
        r2 = ...
    output:
        result = ...
    params:
        repo = REPO,
        force_flag = config.get("force", False) and "--force" or ""  # ADD THIS
    threads: CPUS
    shell:
        "bash {params.repo}/scripts/11_bac_metaphlan4.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {params.repo} {params.force_flag}"  # ADD THIS
```

#### Implementation notes:
1. Only modify rules that call `bash {REPO}/scripts/[0-9]*.sh`
2. Skip rules calling Python/R scripts directly
3. Add `force_flag` to params section (create section if missing)
4. Append `{params.force_flag}` to shell command (before closing quote)
5. Preserve indentation and formatting

#### Verification:
After updating, run:
```bash
snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml --dry-run
```

Expected: no syntax errors, DAG builds successfully

## Current Workaround

Users can manually pass `--force` to individual bash scripts when running step-by-step:
```bash
bash scripts/11_bac_metaphlan4.sh -s SAMPLE -t 16 -w /path -r ~/Course/Maxmetagenome --force
```

Or use Mode 2 bash pipeline with `--force`:
```bash
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --force
```

## Priority

**Medium** - Snakemake already supports `--rerun-incomplete` and `--forceall` for workflow-level control.  
The `--force` parameter is most valuable for Mode 1/2 (step-by-step and bash pipeline), which already work.

## Estimated Effort

- Manual update: ~30-45 minutes (review each rule carefully)
- Automated script: ~15 minutes coding + 15 minutes verification
- Risk: syntax errors in 73 rules would break Snakemake DAG

Recommend: manual update in a dedicated session with thorough testing.
