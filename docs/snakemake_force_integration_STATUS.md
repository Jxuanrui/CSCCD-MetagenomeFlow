# Snakemake --force Parameter Integration - Progress Report

**Last Updated**: 2026-07-30 02:58  
**Status**: ⏳ Partial Implementation (2/73 rules completed)

## Completed Work

### ✅ Infrastructure (100%)
- [x] `pipeline/config/config.yaml`: `force: false` parameter added
- [x] Documentation: `docs/snakemake_force_integration_TODO.md` created
- [x] Pattern verified: manual update of 2 rules in `preprocessing.smk` successful
- [x] Syntax validation: `snakemake --dry-run` passes without errors

### ✅ Files Updated (1/7)
1. **preprocessing.smk** (2/2 rules) ✅
   - `fastp_qc`: params.force_flag added, shell command updated
   - `kneaddata`: params.force_flag added, shell command updated
   - Verified: Snakemake DAG builds successfully

### ⏳ Files Remaining (6/7)
2. **bacteria_taxonomy.smk** (0/11 rules) - 11 rules pending
3. **bacteria_assembly.smk** (0/5 rules) - 5 rules pending
4. **bacteria_binning.smk** (0/18 rules) - 18 rules pending
5. **bacteria_annotation.smk** (0/16 rules) - 16 rules pending
6. **mycobiome.smk** (0/20 rules) - 20 rules pending
7. **crosscohort.smk** (0/1 rule) - 1 rule pending

**Total remaining**: 71 rules across 6 files

## Pattern Established

**Verified working pattern**:
```python
rule example:
    input: ...
    output: ...
    log: ...
    params:                                                     # ADD THIS SECTION
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/XX_script.sh "
        "-s {wildcards.sample} -t {threads} "
        "-w {WORKDIR} -r {REPO} {params.force_flag} "          # ADD {params.force_flag}
        "> {log} 2>&1"
```

## Workaround (Current State)

**Mode 1/2 (Bash pipeline) already fully supports --force**:
```bash
# Mode 1: Step-by-step
bash scripts/01_qc_fastp.sh -s SAMPLE -t 16 -w /path -r ~/Course/Maxmetagenome --force

# Mode 2: Bash pipeline
bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --force
```

**Mode 3 (Snakemake) workarounds**:
1. Use `--forceall` to rerun entire workflow
2. Use `--forcerun RULE_NAME` to force specific rules
3. Delete specific output files before running (manual force)

## Effort Estimation

**Remaining work** (to complete all 73 rules):
- Manual approach: 71 rules × 1-2 min/rule = 71-142 minutes
- Semi-automated: 30-45 minutes (careful sed/awk with validation)
- Fully automated script: 15 minutes coding + 15 minutes testing = 30 minutes

**Risk**: syntax errors in 71 rules would break Snakemake DAG

## Recommendation

**Option A**: Complete now (CC manual execution)
- Pros: Full feature parity with Mode 1/2
- Cons: 1-2 hours of careful editing

**Option B**: Complete later (on-demand)
- Pros: Mode 1/2 already work, Snakemake has native --forceall
- Cons: Feature gap between modes remains

**Option C**: Semi-automated (CC + script)
- Pros: Faster than manual, safer than fully automated
- Cons: Still requires 30-45 minutes

**Current decision**: Defer to user preference (Option B temporarily adopted)

## Next Steps

When ready to complete:
1. Read remaining 6 rule files
2. Apply verified pattern to each bash-calling rule
3. Run `snakemake --dry-run` after each file
4. Commit incrementally (per file or per group)
5. Final validation with full dry-run

## References
- Original task: Task #1 (task_20260730_024035_001)
- Codex attempt: k1haa8993 (timed out)
- CC takeover: Partial completion (2/73 rules)
- Pattern documentation: docs/snakemake_force_integration_TODO.md
