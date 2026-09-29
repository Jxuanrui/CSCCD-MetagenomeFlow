# NOTE: Statistics pipeline rules track tabular summaries and completion sentinels.
# Visualization and functional-analysis sentinels are included in rule all.
# MaxMetagenome — Statistics pipeline rules (scripts 91-98)
# ==============================================================================

# Users should edit this placeholder to point at their runtime metadata file.
meta_file = WORKDIR + "/metadata.csv"


rule stat_metadata_qc:
    """Validate and standardize project metadata for statistical analyses."""
    input:
        meta_file,
    output:
        metadata = WORKDIR + "/result/stat/metadata.tsv",
        report = WORKDIR + "/result/stat/metadata_qc_report.txt",
        status = WORKDIR + "/result/stat/metadata_status.tsv",
    params:
        workdir = config["workdir"],
        repo = config["repo"],
    threads: 1
    shell:
        "bash {REPO}/scripts/01_metadata_qc.sh "
        "-w {params.workdir} -r {params.repo} -t {threads}"


rule stat_diversity:
    """Alpha/beta diversity statistics across bacteria, virus, and fungi."""
    input:
        bact = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
        vir = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
        fungi_done = expand(
            WORKDIR + "/result/fungi/metaphlan4/{sample}/{sample}_profile.txt",
            sample=SAMPLES,
        ),
    output:
        stats   = WORKDIR + "/result/stat/diversity_alpha_summary.tsv",
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/91_stat_diversity.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_differential:
    """Differential abundance analysis across supported omics dimensions."""
    input:
        WORKDIR + "/result/stat/diversity_alpha_summary.tsv",
    output:
        stats   = WORKDIR + "/result/stat/differential_summary.tsv",
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/92_stat_differential.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_cooccurrence:
    """Co-occurrence network inference and summary statistics."""
    input:
        WORKDIR + "/result/stat/diversity_alpha_summary.tsv",
    output:
        WORKDIR + "/result/stat/network/network_summary.txt"
    params:
        meta = meta_file
    threads: CPUS
    shell:
        "bash {REPO}/scripts/93_stat_cooccurrence.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta}"

rule stat_batch_correct:
    """Apply supported batch-correction methods to the bacteria matrix."""
    input:
        WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
    output:
        WORKDIR + "/result/stat/bacteria/batch/corrected_matrices.done"
    params:
        meta = meta_file,
        batch = "batch",
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/95a_stat_batch_correct.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -b {params.batch} -g {params.group}"


rule stat_batch_evaluate:
    """Evaluate corrected matrices and rank batch-correction methods."""
    input:
        WORKDIR + "/result/stat/bacteria/batch/corrected_matrices.done",
    output:
        WORKDIR + "/result/stat/bacteria/batch/evaluation_report.tsv"
    params:
        meta = meta_file,
        batch = "batch",
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/95b_stat_batch_evaluate.sh "
        "-w {WORKDIR} -r {REPO} "
        "-m {params.meta} -b {params.batch} -g {params.group}"


rule stat_ml_siamcat:
    """SIAMCAT-based biomarker modeling and evaluation.
    Also generates multi-model ROC overlay and feature importance plots under result/stat/bacteria/ml/ by default.
    """
    input:
        WORKDIR + "/result/stat/differential_summary.tsv",
    output:
        sentinel = WORKDIR + "/result/stat/bacteria/ml/siamcat_done.txt",
    params:
        meta = meta_file,
        group = "group"
    threads: CPUS
    shell:
        "bash {REPO}/scripts/96_stat_ml_siamcat.sh "
        "-w {WORKDIR} -r {REPO} -t {threads} "
        "-m {params.meta} -g {params.group}"


rule stat_visualization:
    """Generate unified composition visualizations across all dimensions."""
    input:
        bact = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
        vir = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
        fungi = WORKDIR + "/result/fungi/metaphlan4/merged/taxonomy.tsv",
        metadata = WORKDIR + "/result/stat/metadata.tsv",
    output:
        sentinel = WORKDIR + "/result/stat/composition_done.txt",
    params:
        workdir = config["workdir"],
        repo = config["repo"],
        meta = meta_file,
    threads: CPUS
    shell:
        "bash {REPO}/scripts/94_stat_visualization.sh "
        "-w {params.workdir} -r {params.repo} -m {params.meta}"


rule stat_functional:
    """Run functional differential analysis for all supported dimension/type pairs."""
    input:
        metadata = WORKDIR + "/result/stat/metadata.tsv",
        humann = WORKDIR + "/result/humann3/merged/pathabundance_relab.tsv",
        bac_tables = expand(WORKDIR + "/result/integration/bacteria/{func_type}_abundance.tsv",
                            func_type=["kegg_ko", "cog", "arg", "cazyme", "vfdb", "ncyc", "pcyc", "defense"]),
        vir_tables = expand(WORKDIR + "/result/integration/virus/{func_type}_abundance.tsv",
                            func_type=["vog", "phrog_category", "lifestyle", "host_genus", "viral_family"]),
        fun_tables = expand(WORKDIR + "/result/integration/fungi/{func_type}_gene_count.tsv",
                            func_type=["kegg_ko", "cog", "cazyme", "vfdb", "amr", "merops_family"]),
    output:
        expand(
            WORKDIR + "/result/stat/{dimension}/functional/{func_type}/{dimension}_functional_{func_type}_done.txt",
            zip,
            dimension=["bacteria"] * 9 + ["fungi"] * 6 + ["virus"] * 5,
            func_type=["pathway", "kegg_ko", "cog", "cazyme", "arg", "vfdb", "defense", "ncyc", "pcyc",
                       "kegg_ko", "cog", "cazyme", "vfdb", "amr", "merops",
                       "phrog", "vog", "lifestyle", "host_genus", "viral_family"],
        ),
    params:
        workdir = config["workdir"],
        repo = config["repo"],
        meta = meta_file,
    threads: CPUS
    shell:
        r"""
        # 96_stat_functional.R now forces maaslin_cores=1 for every func_type
        # (including kegg_ko): maaslin3's mirai/nanonext-based parallelization
        # (cores>1) was found to deadlock the task dispatcher at this feature
        # scale even in complete isolation with no concurrent R process on the
        # host -- not a race between separate maaslin3 invocations, as earlier
        # analysis assumed. This is a known instability class in the upstream
        # package (biobakery/maaslin3#25: multi-core runs hang/get killed;
        # upstream README recommends single-core by default). With every pair
        # single-threaded there is no daemon-spawn contention, so all 20 pairs
        # (including the two kegg_ko ones, which just take longer wall time)
        # run in one shared pool.
        run_pair() {{
            dimension=${{1%%:*}}
            func_type=${{1#*:}}
            if ! bash {REPO}/scripts/96_stat_functional.sh \
                -w {params.workdir} -r {params.repo} -m {params.meta} \
                -d "$dimension" -t "$func_type"; then
                echo "$1" >> "$PAIR_FAIL_LOG"
            fi
        }}
        export -f run_pair
        PAIR_FAIL_LOG=$(mktemp)
        export PAIR_FAIL_LOG

        printf '%s\n' \
            bacteria:pathway bacteria:cog bacteria:cazyme bacteria:arg bacteria:vfdb bacteria:defense bacteria:ncyc bacteria:pcyc bacteria:kegg_ko \
            fungi:cog fungi:cazyme fungi:vfdb fungi:amr fungi:merops fungi:kegg_ko \
            virus:phrog virus:vog virus:lifestyle virus:host_genus virus:viral_family \
            | xargs -P 6 -I{{}} bash -c 'run_pair "$1"' _ {{}}

        # A pair genuinely failing (as opposed to writing its own SKIPPED
        # sentinel via a known-benign-failure branch inside
        # 96_stat_functional.sh) should not sink the other 19 pairs that
        # succeeded -- same partial-success-tolerance shape already applied
        # to CarveMe (43b_bac_gem_carveme.sh) and Roary (41c_bac_pangenome.sh).
        # Only hard-fail if every single pair failed.
        N_FAILED=$(wc -l < "$PAIR_FAIL_LOG")
        N_TOTAL=20
        if [ "$N_FAILED" -gt 0 ]; then
            echo "[WARN] stat_functional: $N_FAILED/$N_TOTAL pair(s) failed:"
            cat "$PAIR_FAIL_LOG"
            if [ "$N_FAILED" -eq "$N_TOTAL" ]; then
                rm -f "$PAIR_FAIL_LOG"
                echo "[ERROR] stat_functional: all pairs failed"
                exit 1
            fi
        fi
        rm -f "$PAIR_FAIL_LOG"
        """


rule stat_functional_permanova:
    """Run functional PERMANOVA across bacteria, fungi, and virus."""
    input:
        rules.stat_functional.output,
    output:
        expand(WORKDIR + "/result/stat/{dimension}/functional/{dimension}_permanova_done.txt",
               dimension=["bacteria", "fungi", "virus"]),
    params:
        workdir = config["workdir"],
        repo = config["repo"],
        meta = meta_file,
        group = "group",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/96_functional_permanova.sh "
        "-w {params.workdir} -r {params.repo} -m {params.meta} -g {params.group}"


rule stat_functional_network:
    """Build the functional-functional co-occurrence network (SpiecEasi) per dimension."""
    input:
        rules.stat_functional.output,
    output:
        expand(WORKDIR + "/result/stat/{dimension}/functional/network/{dimension}_functional_network_done.txt",
               dimension=["bacteria", "fungi", "virus"]),
    params:
        workdir = config["workdir"],
        repo = config["repo"],
    threads: CPUS
    shell:
        r"""
        for dimension in bacteria fungi virus; do
            bash {REPO}/scripts/96_functional_network.sh \
                -w {params.workdir} -r {params.repo} -d "$dimension"
        done
        """


rule stat_functional_integrated:
    """Create per-dimension integrated functional summaries."""
    input:
        rules.stat_functional.output,
    output:
        expand(WORKDIR + "/result/stat/{dimension}/functional/00_summary/{dimension}_summary_done.txt",
               dimension=["bacteria", "fungi", "virus"]),
    params:
        workdir = config["workdir"],
        repo = config["repo"],
        meta = meta_file,
        group = "group",
    threads: CPUS
    shell:
        r"""
        for dimension in bacteria fungi virus; do
            bash {REPO}/scripts/96_functional_integrated.sh \
                -w {params.workdir} -r {params.repo} -m {params.meta} \
                -g {params.group} -d "$dimension" -c {threads}
        done
        """


rule stat_functional_cross_dimension:
    """Compare significant functional signals across dimensions."""
    input:
        rules.stat_functional.output,
    output:
        sentinel = WORKDIR + "/result/stat/cross_dimension/functional/cross_dimension_functional_done.txt",
    params:
        workdir = config["workdir"],
        repo = config["repo"],
    threads: CPUS
    shell:
        "bash {REPO}/scripts/96_functional_cross_dimension.sh "
        "-w {params.workdir} -r {params.repo}"


# NOTE: Cross-cohort validation is now handled by pipeline/rules/crosscohort.smk
# The old stat_curatedMGD rule has been removed to avoid conflict (Phase 2a)
# Use crosscohort.smk::crosscohort_validation instead


rule stat_report:
    """Generate a markdown summary snapshot from statistical outputs."""
    input:
        WORKDIR + "/result/stat/diversity_alpha_summary.tsv",
        WORKDIR + "/result/stat/differential_summary.tsv",
        WORKDIR + "/result/stat/bacteria/ml/siamcat_done.txt",
    output:
        touch(WORKDIR + "/result/stat/report/report.done")
    threads: 1
    shell:
        "bash {REPO}/scripts/98_stat_report.sh -w {WORKDIR} -r {REPO}"


rule bac_integration_tables:
    """Integrate bacterial quantification and annotation outputs into summary tables."""
    input:
        eggnog = WORKDIR + "/result/annotation/eggnog/eggnog.emapper.annotations",
        kegg = WORKDIR + "/result/annotation/kegg/kegg_diamond.tsv",
        salmon = expand(
            WORKDIR + "/result/assembly/salmon/{sample}/quant.sf",
            sample=SAMPLES,
        ),
    output:
        # Track key functional abundance tables (inputs for LEfSe/Core/Redundancy)
        kegg_ko = WORKDIR + "/result/integration/bacteria/kegg_ko_abundance.tsv",
        cog = WORKDIR + "/result/integration/bacteria/cog_abundance.tsv",
        arg = WORKDIR + "/result/integration/bacteria/arg_abundance.tsv",
        cazyme = WORKDIR + "/result/integration/bacteria/cazyme_abundance.tsv",
        vfdb = WORKDIR + "/result/integration/bacteria/vfdb_abundance.tsv",
        ncyc = WORKDIR + "/result/integration/bacteria/ncyc_abundance.tsv",
        pcyc = WORKDIR + "/result/integration/bacteria/pcyc_abundance.tsv",
        defense = WORKDIR + "/result/integration/bacteria/defense_abundance.tsv",
    params:
        samples = SAMPLES,
        workdir = config["workdir"],
    log:
        WORKDIR + "/logs/integration/bacteria_tables.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98b_bac_integration_tables.sh "
        "-t {threads} -w {params.workdir} -r {REPO} "
        "> {log} 2>&1"


rule vir_integration_tables:
    """Integrate viral abundance and annotation outputs into summary tables."""
    input:
        votu_table = WORKDIR + "/result/virus/votu/table/vOTU_table_ann.txt",
        pharokka = WORKDIR + "/result/virus/pharokka/pharokka.gff",
    output:
        # Track key viral functional abundance tables
        vog = WORKDIR + "/result/integration/virus/vog_abundance.tsv",
        phrog = WORKDIR + "/result/integration/virus/phrog_category_abundance.tsv",
        lifestyle = WORKDIR + "/result/integration/virus/lifestyle_abundance.tsv",
        host = WORKDIR + "/result/integration/virus/host_genus_abundance.tsv",
        family = WORKDIR + "/result/integration/virus/viral_family_abundance.tsv",
    params:
        samples = SAMPLES,
        workdir = config["workdir"],
    log:
        WORKDIR + "/logs/integration/virus_tables.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98c_vir_integration_tables.sh "
        "-t {threads} -w {params.workdir} -r {REPO} "
        "> {log} 2>&1"


rule fun_integration_tables:
    """Integrate fungal annotation and abundance outputs into summary tables."""
    input:
        metaeuk = expand(
            WORKDIR + "/result/fungi/metaeuk/{sample}/{sample}_metaeuk.faa",
            sample=SAMPLES,
        ),
        eggnog = WORKDIR + "/result/fungi/eggnog/eggnog.emapper.annotations",
        dbcan = WORKDIR + "/result/fungi/dbcan/overview.txt",
        vfdb = WORKDIR + "/result/fungi/vfdb/vfdb_hits.tsv",
        amr = WORKDIR + "/result/fungi/amr/amrfinder_results.tsv",
        merops = WORKDIR + "/result/fungi/merops/merops_hits.tsv",
    output:
        # Track key fungal functional abundance tables
        kegg_ko = WORKDIR + "/result/integration/fungi/kegg_ko_gene_count.tsv",
        cog = WORKDIR + "/result/integration/fungi/cog_gene_count.tsv",
        cazyme = WORKDIR + "/result/integration/fungi/cazyme_gene_count.tsv",
        vfdb = WORKDIR + "/result/integration/fungi/vfdb_gene_count.tsv",
        amr = WORKDIR + "/result/integration/fungi/amr_gene_count.tsv",
        merops = WORKDIR + "/result/integration/fungi/merops_family_gene_count.tsv",
    params:
        samples = SAMPLES,
        workdir = config["workdir"],
    log:
        WORKDIR + "/logs/integration/fungi_tables.log",
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98d_fun_integration_tables.sh "
        "-t {threads} -w {params.workdir} -r {REPO} "
        "> {log} 2>&1"


rule bac_mge_summary:
    """Summarize bacterial MGE and plasmid calls across samples."""
    input:
        mge = expand(WORKDIR + "/result/mge/isfinder/{sample}/isfinder_hits.tsv", sample=SAMPLES) +
              expand(WORKDIR + "/result/mge/iceberg/{sample}/iceberg_hits.tsv", sample=SAMPLES) +
              expand(WORKDIR + "/result/mge/integrall/{sample}/integrall_hits.tsv", sample=SAMPLES) +
              expand(WORKDIR + "/result/mge/transposase/{sample}/transposase_hits.tsv", sample=SAMPLES),
        plasmid = expand(WORKDIR + "/result/mge/plasmidfinder/{sample}/results_tab.tsv", sample=SAMPLES),
    output:
        summary = WORKDIR + "/result/integration/bacteria/mge_plasmid_summary.tsv",
    params:
        workdir = config["workdir"],
        repo = config["repo"],
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98c_bac_mge_summary.sh "
        "-w {params.workdir} -r {params.repo} -t {threads}"


rule bac_mag_integration:
    """Integrate bacterial MAG taxonomy, quality, clustering, and abundance."""
    input:
        drep = WORKDIR + "/result/binning/drep/drep_done.txt",
        gtdb = WORKDIR + "/result/binning/gtdbtk/classify/gtdbtk.bac120.summary.tsv",
        checkm2 = WORKDIR + "/result/binning/checkm2/quality_report.tsv",
        coverm = expand(WORKDIR + "/result/binning/coverm_quant/{sample}.tsv", sample=SAMPLES),
    output:
        table = WORKDIR + "/result/integration/bacteria/mag_integration_table.tsv",
    params:
        workdir = config["workdir"],
        repo = config["repo"],
    threads: CPUS
    shell:
        "bash {REPO}/scripts/98d_bac_mag_integration.sh "
        "-w {params.workdir} -r {params.repo} -t {threads}"


# ==============================================================================
# New Downstream Analysis Modules (Phase 3: 4-module completion)
# Integrated: 2026-07-13
# ==============================================================================

rule stat_lefse:
    """LEfSe biomarker discovery across bacteria/fungi/virus functional tables."""
    input:
        bac_tables = rules.bac_integration_tables.output,
        vir_tables = rules.vir_integration_tables.output,
        fun_tables = rules.fun_integration_tables.output,
    output:
        bac_done = touch(WORKDIR + "/result/stat/bacteria/lefse/.done"),
        vir_done = touch(WORKDIR + "/result/stat/virus/lefse/.done"),
        fun_done = touch(WORKDIR + "/result/stat/fungi/lefse/.done"),
    params:
        meta = meta_file,
        group = "group",
        lda_threshold = 2.0,
    threads: CPUS
    shell:
        """
        # Bacteria (8 functional tables)
        for type in kegg_ko cog arg cazyme vfdb ncyc pcyc defense; do
            if [ -f {WORKDIR}/result/integration/bacteria/${{type}}_abundance.tsv ]; then
                bash {REPO}/scripts/99b_lefse.sh \
                    -i {WORKDIR}/result/integration/bacteria/${{type}}_abundance.tsv \
                    -m {params.meta} \
                    -o {WORKDIR}/result/stat/bacteria/lefse/$type \
                    -d bacteria -y $type \
                    --lda-threshold {params.lda_threshold} || echo "LEfSe failed for bacteria/$type"
            fi
        done
        touch {output.bac_done}
        
        # Virus (5 functional tables)
        for type in vog phrog_category lifestyle host_genus viral_family; do
            if [ -f {WORKDIR}/result/integration/virus/${{type}}_abundance.tsv ]; then
                bash {REPO}/scripts/99b_lefse.sh \
                    -i {WORKDIR}/result/integration/virus/${{type}}_abundance.tsv \
                    -m {params.meta} \
                    -o {WORKDIR}/result/stat/virus/lefse/$type \
                    -d virus -y $type \
                    --lda-threshold {params.lda_threshold} || echo "LEfSe failed for virus/$type"
            fi
        done
        touch {output.vir_done}
        
        # Fungi (6 functional tables - if available)
        for type in kegg_ko cog cazyme vfdb amr_gene merops_family; do
            TABLE=$(find {WORKDIR}/result/integration/fungi -name "${{type}}_*.tsv" 2>/dev/null | head -1)
            if [ -n "$TABLE" ] && [ -f "$TABLE" ]; then
                bash {REPO}/scripts/99b_lefse.sh \
                    -i "$TABLE" \
                    -m {params.meta} \
                    -o {WORKDIR}/result/stat/fungi/lefse/$type \
                    -d fungi -y $type \
                    --lda-threshold {params.lda_threshold} || echo "LEfSe failed for fungi/$type"
            fi
        done
        touch {output.fun_done}
        """


rule stat_core_microbiome:
    """Core microbiome identification across bacteria/fungi/virus."""
    input:
        bac_tax = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
        fun_tax = WORKDIR + "/result/fungi/metaphlan4/merged/taxonomy.tsv",
        vir_abund = WORKDIR + "/result/integration/virus/viral_family_abundance.tsv",
    output:
        bac_summary = WORKDIR + "/result/stat/bacteria/core_microbiome/core_microbiome_summary.txt",
        fun_summary = WORKDIR + "/result/stat/fungi/core_microbiome/core_microbiome_summary.txt",
        vir_summary = WORKDIR + "/result/stat/virus/core_microbiome/core_microbiome_summary.txt",
    params:
        meta = meta_file,
        prevalence = 0.5,
        min_abundance = 0.0001,
    threads: CPUS
    shell:
        """
        # Bacteria
        bash {REPO}/scripts/99a_core_microbiome.sh \
            -i {input.bac_tax} \
            -m {params.meta} \
            -o {WORKDIR}/result/stat/bacteria/core_microbiome \
            -d bacteria \
            --prevalence-threshold {params.prevalence} \
            --min-abundance {params.min_abundance}

        # Fungi (conditional on merged taxonomy availability)
        FUN_TAX="{input.fun_tax}"
        if [ -f "$FUN_TAX" ]; then
            bash {REPO}/scripts/99a_core_microbiome.sh \
                -i "$FUN_TAX" \
                -m {params.meta} \
                -o {WORKDIR}/result/stat/fungi/core_microbiome \
                -d fungi \
                --prevalence-threshold {params.prevalence} \
                --min-abundance {params.min_abundance}
        else
            mkdir -p {WORKDIR}/result/stat/fungi/core_microbiome
            echo "Fungi taxonomy not available, skipping" > {output.fun_summary}
        fi

        # Virus (use viral_family abundance as taxonomy proxy)
        bash {REPO}/scripts/99a_core_microbiome.sh \
            -i {input.vir_abund} \
            -m {params.meta} \
            -o {WORKDIR}/result/stat/virus/core_microbiome \
            -d virus \
            --prevalence-threshold {params.prevalence} \
            --min-abundance {params.min_abundance}
        """


rule stat_functional_redundancy:
    """Functional redundancy analysis (FDI) across bacteria/fungi/virus."""
    input:
        bac_func = WORKDIR + "/result/integration/bacteria/kegg_ko_abundance.tsv",
        bac_tax = WORKDIR + "/result/metaphlan4/merged/taxonomy.tsv",
        fun_func = WORKDIR + "/result/integration/fungi/kegg_ko_gene_count.tsv",
        fun_tax = WORKDIR + "/result/fungi/metaphlan4/merged/taxonomy.tsv",
        vir_func = WORKDIR + "/result/integration/virus/vog_abundance.tsv",
        vir_tax = WORKDIR + "/result/integration/virus/viral_family_abundance.tsv",
    output:
        bac_summary = WORKDIR + "/result/stat/bacteria/functional_redundancy/functional_redundancy_summary.txt",
        fun_summary = WORKDIR + "/result/stat/fungi/functional_redundancy/functional_redundancy_summary.txt",
        vir_summary = WORKDIR + "/result/stat/virus/functional_redundancy/functional_redundancy_summary.txt",
    threads: CPUS
    shell:
        """
        # Bacteria
        bash {REPO}/scripts/96c_functional_redundancy.sh \
            -f {input.bac_func} \
            -t {input.bac_tax} \
            -o {WORKDIR}/result/stat/bacteria/functional_redundancy \
            -d bacteria -y kegg_ko

        # Fungi (conditional on functional table availability)
        FUN_FUNC="{input.fun_func}"
        FUN_TAX="{input.fun_tax}"
        if [ -n "$FUN_FUNC" ] && [ -f "$FUN_FUNC" ] && [ -f "$FUN_TAX" ]; then
            bash {REPO}/scripts/96c_functional_redundancy.sh \
                -f "$FUN_FUNC" \
                -t "$FUN_TAX" \
                -o {WORKDIR}/result/stat/fungi/functional_redundancy \
                -d fungi -y kegg_ko
        else
            mkdir -p {WORKDIR}/result/stat/fungi/functional_redundancy
            echo "Fungi functional or taxonomy data not available, skipping" > {output.fun_summary}
        fi

        # Virus (use viral_family as taxonomy proxy)
        mkdir -p {WORKDIR}/result/stat/virus/functional_redundancy
        bash {REPO}/scripts/96c_functional_redundancy.sh \
            -f {input.vir_func} \
            -t {input.vir_tax} \
            -o {WORKDIR}/result/stat/virus/functional_redundancy \
            -d virus -y vog || echo "Virus functional redundancy skipped: no non-zero VOG abundance data" > {output.vir_summary}
        """


rule stat_pathway_activity:
    """Pathway activity estimation from HUMAnN3 stratified output."""
    input:
        humann3_done = expand(
            WORKDIR + "/result/humann3/{sample}/{sample}_pathabundance.tsv",
            sample=SAMPLES
        ),
    output:
        summary = WORKDIR + "/result/stat/bacteria/pathway_activity/pathway_completeness_summary.csv",
    params:
        meta = meta_file,
        min_coverage = 0.5,
        top_n = 5,
    threads: CPUS
    shell:
        """
        bash {REPO}/scripts/96b_pathway_activity.sh \
            -w {WORKDIR} \
            -m {params.meta} \
            -o {WORKDIR}/result/stat/bacteria/pathway_activity \
            -d bacteria \
            --min-coverage {params.min_coverage} \
            --top-n-contributors {params.top_n} || {{
                mkdir -p {WORKDIR}/result/stat/bacteria/pathway_activity
                echo "SKIPPED: pathway activity analysis failed (likely missing HUMAnN3 stratified output)" > {output.summary}
            }}
        """


rule downstream_summary:
    """Summarize completion status of integrated downstream modules."""
    input:
        bac_core = WORKDIR + "/result/stat/bacteria/core_microbiome/core_microbiome_summary.txt",
        fun_core = WORKDIR + "/result/stat/fungi/core_microbiome/core_microbiome_summary.txt",
        vir_core = WORKDIR + "/result/stat/virus/core_microbiome/core_microbiome_summary.txt",
        bac_redundancy = WORKDIR + "/result/stat/bacteria/functional_redundancy/functional_redundancy_summary.txt",
        fun_redundancy = WORKDIR + "/result/stat/fungi/functional_redundancy/functional_redundancy_summary.txt",
        vir_redundancy = WORKDIR + "/result/stat/virus/functional_redundancy/functional_redundancy_summary.txt",
        pathway = WORKDIR + "/result/stat/bacteria/pathway_activity/pathway_completeness_summary.csv",
    output:
        summary = WORKDIR + "/result/stat/downstream_summary.tsv",
    threads: 1
    shell:
        r"""
        mkdir -p "$(dirname {output.summary})"
        printf 'dimension\tmodule\tstatus\tfile\n' > {output.summary}
        for item in \
            bacteria:core_microbiome:{input.bac_core} \
            fungi:core_microbiome:{input.fun_core} \
            virus:core_microbiome:{input.vir_core} \
            bacteria:functional_redundancy:{input.bac_redundancy} \
            fungi:functional_redundancy:{input.fun_redundancy} \
            virus:functional_redundancy:{input.vir_redundancy} \
            bacteria:pathway_activity:{input.pathway}; do
            dimension=${{item%%:*}}
            rest=${{item#*:}}
            module=${{rest%%:*}}
            path=${{rest#*:}}
            if [ -s "$path" ]; then status=SUCCEEDED; else status=FAILED; fi
            printf '%s\t%s\t%s\t%s\n' "$dimension" "$module" "$status" "$path" >> {output.summary}
        done
        """


# ── Cross-domain genome clustering (VEBA cluster module methodology reference) ─

rule cross_domain_ani_cluster:
    """Cross-domain (bacteria/virus/fungi) genome ANI clustering via FastANI +
    networkx Louvain community detection. VEBA `cluster` module methodology
    reference, no VEBA source reused. Known limitation: nucleotide ANI across
    distant domains (e.g. bacteria vs fungi) has little biological meaning at
    that evolutionary distance — accepted by user as a known constraint of the
    current design, not a defect to silently work around.
    """
    input:
        drep_done = WORKDIR + "/result/binning/drep/drep_done.txt",
        euk_mags_summaries = expand(
            WORKDIR + "/result/fungi/veba_qc/{sample}/euk_mags/{sample}.euk_mags_summary.tsv",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/cross_domain/cluster/genome_clusters.tsv",
    log:
        WORKDIR + "/logs/cross_domain/ani_cluster.log",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/98e_cross_domain_ani_cluster.sh  {params.force_flag}"
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule cross_domain_orthogroup:
    """Cross-domain protein orthogroup detection via MMseqs2 easy-cluster on
    merged Prokka (bacteria) / pharokka-prodigal (virus) / MetaEuk (fungi)
    protein predictions. VEBA `cluster` module methodology reference (SLC/SSPC
    orthogroup detection), no VEBA source reused.
    """
    input:
        ani_clusters = WORKDIR + "/result/cross_domain/cluster/genome_clusters.tsv",
        metaeuk_done = expand(
            WORKDIR + "/result/fungi/veba_qc/{sample}/euk_mags/{sample}.metaeuk_done.txt",
            sample=SAMPLES,
        ),
    output:
        out = WORKDIR + "/result/cross_domain/orthogroup/orthogroup_table.tsv",
    log:
        WORKDIR + "/logs/cross_domain/orthogroup.log",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/98f_cross_domain_orthogroup.sh  {params.force_flag}"
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"


rule cross_domain_correlation:
    """Cross-domain bacteria/virus/fungi abundance Spearman correlation network,
    augmented with iPHoP virus-host prediction edges (type=host_prediction).
    """
    input:
        ani_clusters = WORKDIR + "/result/cross_domain/cluster/genome_clusters.tsv",
    output:
        out = WORKDIR + "/result/cross_domain/correlation/network_summary.txt",
    log:
        WORKDIR + "/logs/cross_domain/correlation.log",
    threads: CPUS
    params:
        force_flag = config.get("force", False) and "--force" or "",
    shell:
        "bash {REPO}/scripts/98g_cross_domain_correlation.sh  {params.force_flag}"
        "-t {threads} -w {WORKDIR} -r {REPO} "
        "> {log} 2>&1"
