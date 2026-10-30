# MaxMetagenome — bacteria GEM (Genome-Scale Metabolic Models) rules (scripts 43, 43b, 43c)
# Executor: CC (single rules file, deterministic)
#
# Workflow: dRep dereplicated MAGs → CarveMe reconstruction → COBRApy FBA analysis
#
# DAG flow:
#   drep → gem_carveme (aggregate) → gem_fba (aggregate)
#
# Note: gapseq (43_bac_gem_gapseq.sh) excluded due to performance bottleneck (>4h per MAG)
#       CarveMe recommended for production pipeline (10-15 min per MAG)

GEM = WORKDIR + "/result/gem"

# ─── 43b: CarveMe GEM reconstruction (aggregate) ────────────────────────────

rule gem_carveme:
    input:
        drep = WORKDIR + "/result/binning/drep/drep_done.txt",
    output:
        done = GEM + "/carveme/carveme_done.txt",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        """
        # CarveMe processes all dereplicated MAGs in batch mode
        bash {REPO}/scripts/43b_bac_gem_carveme.sh \
            -m all \
            -w {WORKDIR} \
            -r {REPO} \
            {params.force_flag}

        # Create completion sentinel
        touch {output.done}
        """


# ─── 43c: COBRApy FBA metabolic simulation (aggregate) ──────────────────────

rule gem_fba:
    input:
        carveme = GEM + "/carveme/carveme_done.txt",
    output:
        done = GEM + "/fba/fba_done.txt",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        """
        # Find all CarveMe SBML models and run FBA analysis
        find {GEM}/carveme -name "*.xml" -type f | while read model; do
            mag_name=$(basename "$model" .xml)

            # Skip if already processed (unless --force)
            if [ -f "{GEM}/fba/${{mag_name}}/${{mag_name}}_growth_rate.txt" ] && [ -z "{params.force_flag}" ]; then
                echo "[FBA] Skipping ${{mag_name}} (already exists)"
                continue
            fi

            # Run FBA analysis
            bash {REPO}/scripts/43c_bac_gem_cobrapy_fba.sh \
                -m "$mag_name" \
                -t {threads} \
                -w {WORKDIR} \
                -r {REPO} \
                {params.force_flag}
        done

        # Create completion sentinel
        touch {output.done}
        """


# ─── Optional: Single MAG GEM rules (for testing/re-runs) ───────────────────

rule gem_carveme_single:
    """
    Single MAG CarveMe reconstruction (for selective re-runs or testing)

    Usage:
      snakemake --config mag=Sample10__111 result/gem/carveme/Sample10__111/Sample10__111.xml
    """
    input:
        mag_fa = WORKDIR + "/result/binning/drep/dereplicated_genomes/{mag}.fa",
    output:
        model = GEM + "/carveme/{mag}/{mag}.xml",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        """
        bash {REPO}/scripts/43b_bac_gem_carveme.sh \
            -m {wildcards.mag} \
            -t {threads} \
            -w {WORKDIR} \
            -r {REPO} \
            {params.force_flag}
        """


rule gem_fba_single:
    """
    Single MAG FBA analysis (for selective re-runs or testing)

    Usage:
      snakemake --config mag=Sample10__111 result/gem/fba/Sample10__111/Sample10__111_growth_rate.txt
    """
    input:
        model = GEM + "/carveme/{mag}/{mag}.xml",
    output:
        growth = GEM + "/fba/{mag}/{mag}_growth_rate.txt",
        flux = GEM + "/fba/{mag}/{mag}_flux_distribution.tsv",
        essential = GEM + "/fba/{mag}/{mag}_essential_genes.tsv",
        substrate = GEM + "/fba/{mag}/{mag}_substrate_utilization.tsv",
    params:
        force_flag = config.get("force", False) and "--force" or "",
    threads: CPUS
    shell:
        """
        bash {REPO}/scripts/43c_bac_gem_cobrapy_fba.sh \
            -m {wildcards.mag} \
            -t {threads} \
            -w {WORKDIR} \
            -r {REPO} \
            {params.force_flag}
        """
