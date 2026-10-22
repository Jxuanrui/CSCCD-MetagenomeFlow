#!/usr/bin/env bash
# ==============================================================================
# Script: 96_stat_ml_siamcat.sh
# Purpose: SIAMCAT machine-learning biomarker discovery
# Usage:   bash 96_stat_ml_siamcat.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                    -g GROUP_COL [-d DIMENSION] [-M FUNGI_METHOD] [--folds N] [--force] [--skip-shap]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 96_stat_ml_siamcat.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                  -g GROUP_COL [-d DIMENSION] [-M FUNGI_METHOD] [--folds N]
                                  [--combination BLOCKS] [--force] [--skip-shap]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV
  -g  Group column

Optional:
  -d  Dimension: bacteria|virus|fungi|all (default: bacteria)
      'all' stacks BAC|/VIR|/FUN| features; the VIR| arm requires the 98c
      virus integration table (result/integration/virus/
      votu_annotation_matrix_relab.tsv, vOTU_TPM_<sample> columns - the
      full-precision TPM block, NOT the %.4f-rounded vOTU_RELAB_ render)
      and the FUN| arm requires the 98d fungi integration table
      (result/integration/fungi/normalized/funomic_species_relab.tsv)
  --combination BLOCKS
      Explicit feature-block selection: B|V|F|BV|BF|VF|BVF (or 'all' = BVF).
      Takes precedence over -d; -d stays as the dimension shorthand
      (bacteria=B, virus=V, fungi=F, all=BVF). Passing --combination
      explicitly switches the default sample set to 'BVF' (protocol: the
      seven runs share ONE sample set, single blocks included). Output
      dirs: B/V/F reuse the single-dimension dirs; BV/BF/VF go to
      result/stat/ml_<COMBINATION>/; BVF equals -d all (result/stat/ml/)
  --sample-set SET
      Shared sample set: auto (default) = intersection of the SELECTED
      blocks' input-table samples (non-protocol convenience); BVF = the
      B-V-F three-table intersection regardless of the selected blocks
      (A-2 protocol section 4 premise; default whenever --combination is
      passed explicitly). Sample names are sorted before use, so the
      split input order is deterministic and independent of the input
      tables' column order; the set and its size are logged and written
      to split_manifest.txt (sample_set=, combo_n_samples=)
  -M  Fungi input method: phf|funomic|metaphlan4 - NON-PROTOCOL override.
      Protocol runs (-d fungi, or any --combination containing F) pin the
      98d funomic integration table as the FUN| source; -M only takes
      effect when explicitly passed and then warns that the run leaves
      the protocol source contract
  --folds  Cross-validation folds (default: 10)
  --repeats N  Outer repeat loop: N independent split+train+evaluate passes
               (default: 1 = current single-pass behavior). Repeat i uses
               seed 20260928+(i-1); outputs siamcat_repeats_detail.tsv
               (one row per repeat) and a mean +/- sd auc summary
  --force  Re-run even if sentinel exists
  --skip-shap  Skip SHAP feature attribution for the randomForest model
               (SHAP is much slower than the other visualizations; skip on
               large cohorts if runtime matters more than interpretability)
  -h, --help  Show this help message
EOF
}

DIMENSION="bacteria"
FUNGI_METHOD="auto"
FOLDS="10"
REPEATS="1"
COMBINATION=""
SAMPLE_SET=""

# WC1R2 P0-3 (2026-10-01, user decisions #2/#3): --combination / --sample-set
# / -M change DEFAULTS when explicitly passed, and value equality cannot
# distinguish "explicitly given" from "left at default" (mgx_parse fills the
# same variables either way). Scan the raw args once, before parsing.
COMBINATION_EXPLICIT=0
SAMPLE_SET_EXPLICIT=0
FUNGI_METHOD_EXPLICIT=0
for _arg in "$@"; do
    case "${_arg}" in
        --combination|--combination=*) COMBINATION_EXPLICIT=1 ;;
        --sample-set|--sample-set=*) SAMPLE_SET_EXPLICIT=1 ;;
        -M|-M=*) FUNGI_METHOD_EXPLICIT=1 ;;
    esac
done

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:THREADS m:METADATA_CSV g:GROUP_COL d:DIMENSION M:FUNGI_METHOD"
export MGX_OPTS_FLAG="force skip-shap"
export MGX_OPTS_LONG="folds:FOLDS repeats:REPEATS combination:COMBINATION sample-set:SAMPLE_SET"
mgx_parse "$@"
mgx_require WORKDIR REPO THREADS METADATA_CSV GROUP_COL

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
# WC1R2 P0-1 (2026-10-01, user decision #1): the virus input is the 98c
# integration product votu_annotation_matrix_relab.tsv, consumed through its
# vOTU_TPM_<sample> columns (not the raw script-60 votu_table.tsv, which is
# fully retired, and not the table's vOTU_RELAB_ columns - see
# read_vir_tpm_matrix for the precision rationale).
VIR_TABLE="${WORKDIR}/result/integration/virus/votu_annotation_matrix_relab.tsv"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
PHF_FUNGI_TABLE="${WORKDIR}/result/fungi/phf_profiler/merged_abundance_with_taxonomy.tsv"
# 98d_fun_integration_tables.sh writes the FunOMIC species relab under
# result/integration/fungi/normalized/ (Step6 normalize_table output).
FUNOMIC_FUNGI_TABLE="${WORKDIR}/result/integration/fungi/normalized/funomic_species_relab.tsv"
# W-C1(2): -d all fungi input = the 98d integration table (species x samples,
# relative abundance), stacked with the FUN| feature prefix alongside BAC|/VIR|.
FUN_TABLE="${FUNOMIC_FUNGI_TABLE}"
FUNGI_ABUND_TABLE=""
case "${DIMENSION}" in
    all|bacteria|virus|fungi) ;;
    *)
        echo "[ERROR] Invalid dimension: ${DIMENSION}"
        show_help
        exit 1
        ;;
esac
# B3-PREQ①-R #4 (2026-09-30, user decision #4): --combination B|V|F|BV|BF|VF|BVF
# explicitly selects the feature blocks; when absent it is derived from -d
# (the retained dimension shorthand). --combination takes precedence.
if [ -z "${COMBINATION}" ]; then
    case "${DIMENSION}" in
        all) COMBINATION="BVF" ;;
        bacteria) COMBINATION="B" ;;
        virus) COMBINATION="V" ;;
        fungi) COMBINATION="F" ;;
    esac
fi
case "${COMBINATION}" in
    B|V|F|BV|BF|VF|BVF) ;;
    all) COMBINATION="BVF" ;;
    *)
        echo "[ERROR] Invalid --combination: ${COMBINATION} (expected B|V|F|BV|BF|VF|BVF|all)"
        show_help
        exit 1
        ;;
esac
COMBO_MULTI=0
[ "${#COMBINATION}" -gt 1 ] && COMBO_MULTI=1

# WC1R2 P0-3 (user decision #2): sample-set normalization. auto keeps the
# per-combination intersection of the selected blocks' input tables (current
# behavior, non-protocol convenience); an explicitly passed --combination
# flips the default to BVF, so the seven protocol runs (B/V/F/BV/BF/VF/BVF)
# share ONE sample set = the B-V-F three-table intersection - single-block
# protocol runs included - and paired comparisons never compare different
# cohorts. An explicit --sample-set always wins over both defaults.
if [ -z "${SAMPLE_SET}" ]; then
    if [ "${COMBINATION_EXPLICIT}" -eq 1 ]; then
        SAMPLE_SET="BVF"
    else
        SAMPLE_SET="auto"
    fi
fi
case "${SAMPLE_SET}" in
    auto|BVF) ;;
    *)
        echo "[ERROR] Invalid --sample-set: ${SAMPLE_SET} (expected auto|BVF)"
        show_help
        exit 1
        ;;
esac

case "${COMBINATION}" in
    B) RESULT_DIR="${WORKDIR}/result/stat/bacteria/ml" ;;
    V) RESULT_DIR="${WORKDIR}/result/stat/virus/ml" ;;
    F) RESULT_DIR="${WORKDIR}/result/stat/fungi/ml" ;;
    BV|BF|VF) RESULT_DIR="${WORKDIR}/result/stat/ml_${COMBINATION}" ;;
    BVF) RESULT_DIR="${WORKDIR}/result/stat/ml" ;;
esac
VIZ_ML_DIR="${RESULT_DIR}"
LOG_DIR="${WORKDIR}/logs/stat/ml"
SENTINEL="${RESULT_DIR}/siamcat_done.txt"

mkdir -p "${RESULT_DIR}" "${VIZ_ML_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/96_stat_ml_siamcat.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# WC1R2 P0-3: sample-set contract line (into the run log; the intersection
# size follows from the R stage once the tables are read)
if [ "${SAMPLE_SET}" = "BVF" ]; then
    echo "[INFO] sample_set=BVF: shared sample pool = B-V-F input-table intersection (protocol: explicit --combination defaults to BVF; --sample-set explicitly passed=${SAMPLE_SET_EXPLICIT})"
else
    echo "[INFO] sample_set=auto: per-combination input-table intersection (non-protocol default)"
fi

run_ml_visualization() {
    export RESULT_DIR VIZ_ML_DIR
    export FORCE
    # If SIAMCAT was skipped (too few samples), generate placeholder PDFs
    if grep -q "^SKIPPED" "${RESULT_DIR}/siamcat_done.txt" 2>/dev/null; then
        echo "[INFO] SIAMCAT was skipped — generating placeholder visualization PDFs"
        mgx_conda r_stat Rscript - <<'PLACEHOLDER_R'
viz_ml <- Sys.getenv("VIZ_ML_DIR")
dir.create(viz_ml, recursive=TRUE, showWarnings=FALSE)
for (fname in c("roc_multimodel_comparison.pdf", "feature_importance_with_sd.pdf")) {
  pdf(file.path(viz_ml, fname), width=8, height=6)
  plot.new()
  text(0.5, 0.5, "SIAMCAT requires >=10 samples\nInsufficient samples in this run", cex=1.2)
  dev.off()
}
cat("[INFO] Placeholder PDFs written\n")
PLACEHOLDER_R
        return 0
    fi
    set +e
    (cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/96_ml_visualization.R")
    local viz_exit=$?
    set -e
    if [ ${viz_exit} -ne 0 ]; then
        return ${viz_exit}
    fi
    if [ ${SKIP_SHAP} -eq 1 ]; then
        echo "[INFO] --skip-shap set, skipping SHAP feature attribution"
        return 0
    fi
    echo "[INFO] Computing SHAP feature attribution (randomForest only)..."
    mgx_conda r_stat Rscript "${REPO}/scripts/96_ml_shap.R"
    return 0
}

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

# WC1R2 P0-3 (user decision #3): the FUN| arm is PINNED to the 98d funomic
# integration table for protocol use (-d fungi, or any --combination
# containing F). The old -M auto source switching no longer applies by
# default; -M takes effect ONLY when explicitly passed, and such a run is
# warned as leaving the protocol source contract (table existence for the
# pinned source is gated after the resume gate below).
if [ "${FUNGI_METHOD_EXPLICIT}" -eq 1 ]; then
    echo "[WARN] -M ${FUNGI_METHOD}: non-protocol fungi source (explicit -M overrides the pinned 98d funomic table)"
    case "${FUNGI_METHOD}" in
        auto)
            if [ -f "${PHF_FUNGI_TABLE}" ]; then
                FUNGI_METHOD="phf"
                FUNGI_ABUND_TABLE="${PHF_FUNGI_TABLE}"
            elif [ -f "${FUNOMIC_FUNGI_TABLE}" ]; then
                FUNGI_METHOD="funomic"
                FUNGI_ABUND_TABLE="${FUNOMIC_FUNGI_TABLE}"
            else
                FUNGI_METHOD="metaphlan4"
                FUNGI_ABUND_TABLE="${WORKDIR}/result/fungi/metaphlan4/merged_abundance_table.txt"
            fi
            ;;
        phf)
            FUNGI_ABUND_TABLE="${PHF_FUNGI_TABLE}"
            if [ ! -f "${FUNGI_ABUND_TABLE}" ]; then
                echo "[ERROR] PHF fungi abundance table not found: ${FUNGI_ABUND_TABLE}"
                exit 1
            fi
            ;;
        funomic)
            FUNGI_ABUND_TABLE="${FUNOMIC_FUNGI_TABLE}"
            if [ ! -f "${FUNGI_ABUND_TABLE}" ]; then
                echo "[ERROR] FunOMIC fungi abundance table not found: ${FUNGI_ABUND_TABLE}"
                exit 1
            fi
            ;;
        metaphlan4)
            FUNGI_ABUND_TABLE="${WORKDIR}/result/fungi/metaphlan4/merged_abundance_table.txt"
            if [ ! -f "${FUNGI_ABUND_TABLE}" ]; then
                echo "[ERROR] MetaPhlAn4 fungi abundance table not found: ${FUNGI_ABUND_TABLE}"
                exit 1
            fi
            ;;
        *)
            echo "[ERROR] Invalid fungi method: ${FUNGI_METHOD}"
            show_help
            exit 1
            ;;
    esac
    echo "[INFO] Fungi input: METHOD=${FUNGI_METHOD} TABLE=${FUNGI_ABUND_TABLE:-${FUNGI_DIR}} (non-protocol: explicit -M)"
else
    FUNGI_METHOD="funomic"
    FUNGI_ABUND_TABLE="${FUNOMIC_FUNGI_TABLE}"
    echo "[INFO] Fungi input: METHOD=funomic TABLE=${FUNGI_ABUND_TABLE} (protocol-pinned 98d; -M overrides only when explicitly passed)"
fi

# P0-1 (supervisor re-review): export the REAL fungi source for the R-side
# manifest audit line (previously the env var was exported empty, so every
# manifest falsely recorded fungi_method=auto).
export MGX_FUNGI_METHOD="${FUNGI_METHOD}"

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    # WC1R2-C2 (supervisor): the sentinel alone must not authorize silent
    # reuse across input-governance regimes. A completed result produced under
    # a different combination/sample_set must error and demand --force — P01
    # already carries pre-WC1R sentinels that protocol runs would otherwise
    # silently reuse in the 7-cell comparison.
    RESUME_MANIFEST="$(dirname "${SENTINEL}")/split_manifest.txt"
    RESUME_COMBO="$(grep -oE '^combination=[^[:space:]]*' "${RESUME_MANIFEST}" 2>/dev/null | tail -1 | cut -d= -f2)"
    RESUME_SET="$(grep -oE '^sample_set=[^[:space:]]*' "${RESUME_MANIFEST}" 2>/dev/null | tail -1 | cut -d= -f2)"
    RESUME_FUNGI="$(grep -oE '^fungi_method=[^[:space:]]*' "${RESUME_MANIFEST}" 2>/dev/null | tail -1 | cut -d= -f2)"
    WANT_COMBO="${COMBINATION}"
    WANT_SET="${SAMPLE_SET:-auto}"
    WANT_FUNGI="${FUNGI_METHOD}"
    if [ "${RESUME_COMBO}" != "${WANT_COMBO}" ] || [ "${RESUME_SET}" != "${WANT_SET}" ] || [ "${RESUME_FUNGI}" != "${WANT_FUNGI}" ]; then
        echo "[ERROR] Existing result was produced under a different input regime:"
        echo "[ERROR]   manifest: combination=${RESUME_COMBO:-<absent>} sample_set=${RESUME_SET:-<absent>} fungi_method=${RESUME_FUNGI:-<absent>}"
        echo "[ERROR]   requested: combination=${WANT_COMBO} sample_set=${WANT_SET} fungi_method=${WANT_FUNGI}"
        echo "[ERROR] Re-run with --force to rebuild under the requested regime."
        exit 1
    fi
    echo "[INFO] Sentinel exists (regime match: combination=${WANT_COMBO} sample_set=${WANT_SET} fungi_method=${WANT_FUNGI}), skipping: ${SENTINEL}"
    run_ml_visualization
    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] 96_ml_visualization.R failed with exit code ${EXIT_CODE}"
        exit ${EXIT_CODE}
    fi
    exit 0
fi

# WC1R2 P0-3 + B3-PREQ①-R #1/#4: input-table gates, all AFTER the resume
# gate (P2-2). Feature blocks: any combination containing V needs the 98c
# virus table; any PROTOCOL F arm needs the 98d fungi table (multi-block F
# is always the pinned 98d arm; single F is pinned unless -M was explicitly
# passed and warned non-protocol above). Sample pool: --sample-set BVF reads
# ALL THREE input tables for the shared pool regardless of the selected
# feature blocks.
NEED_V_TABLE=0
NEED_F_TABLE=0
if case "${COMBINATION}" in *V*) true ;; *) false ;; esac; then
    NEED_V_TABLE=1
fi
if case "${COMBINATION}" in *F*) true ;; *) false ;; esac; then
    if [ "${COMBO_MULTI}" -eq 1 ] || [ "${FUNGI_METHOD_EXPLICIT}" -eq 0 ]; then
        NEED_F_TABLE=1
    fi
fi
if [ "${SAMPLE_SET}" = "BVF" ]; then
    NEED_V_TABLE=1
    NEED_F_TABLE=1
fi
if [ "${NEED_V_TABLE}" -eq 1 ] && [ ! -f "${VIR_TABLE}" ]; then
    echo "[ERROR] --combination ${COMBINATION} / --sample-set ${SAMPLE_SET} requires the virus integration table: ${VIR_TABLE}"
    echo "[ERROR] Run scripts/98c_vir_integration_tables.sh first (96 consumes the vOTU_TPM_<sample> columns at full TPM precision (1e-4, ~1e-10 relative))"
    exit 1
fi
if [ "${NEED_F_TABLE}" -eq 1 ] && [ ! -f "${FUN_TABLE}" ]; then
    echo "[ERROR] --combination ${COMBINATION} / --sample-set ${SAMPLE_SET} requires the fungi integration table: ${FUN_TABLE}"
    echo "[ERROR] Run scripts/98d_fun_integration_tables.sh first (or pass -M explicitly for a non-protocol source)"
    exit 1
fi
if [ "${SAMPLE_SET}" = "BVF" ] && [ ! -f "${BACT_TABLE}" ]; then
    echo "[ERROR] --sample-set BVF requires the MetaPhlAn merged taxonomy table: ${BACT_TABLE}"
    exit 1
fi

echo "[INFO] Running SIAMCAT ML analysis"

if ! [[ "${REPEATS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --repeats must be a positive integer, got: ${REPEATS}"
    exit 1
fi

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL DIMENSION COMBINATION SAMPLE_SET FOLDS REPEATS BACT_TABLE VIR_TABLE FUNGI_DIR FUNGI_ABUND_TABLE FUN_TABLE RESULT_DIR

RUN_LOG="${LOG_DIR:-${RESULT_DIR}}/96_stat_ml_siamcat.run.log"
mkdir -p "$(dirname "${RUN_LOG}")"
set +e
set -o pipefail
(cd "${WORKDIR}" && mgx_conda r_stat Rscript - <<'RSCRIPT' 2>&1 | tee "${RUN_LOG}"
options(stringsAsFactors = FALSE)
# Fix: Ensure working directory is WORKDIR (conda run may reset it)
workdir <- Sys.getenv("WORKDIR")
if (nzchar(workdir)) {
  message("[FIX] Setting working directory to: ", workdir)
  setwd(workdir)
}
options(warn = 1)

conda_r_lib <- file.path(R.home("home"), "library")
project_r_lib <- Sys.getenv("R_LIBS_USER", unset = "")
lib_paths <- .libPaths()
if (nzchar(project_r_lib)) {
  lib_paths <- lib_paths[normalizePath(lib_paths, winslash="/", mustWork=FALSE) !=
    normalizePath(project_r_lib, winslash="/", mustWork=FALSE)]
}
if (dir.exists(conda_r_lib)) .libPaths(unique(c(conda_r_lib, lib_paths)))

required_pkgs <- c("SIAMCAT", "phyloseq", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(SIAMCAT)
  library(phyloseq)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
dimension <- Sys.getenv("DIMENSION")
# B3-PREQ①-R #4: block selection letters (B/V/F) from --combination
combination <- Sys.getenv("COMBINATION", "BVF")
combo_letters <- strsplit(combination, "")[[1]]
folds <- as.integer(Sys.getenv("FOLDS", "10"))
repeats <- max(1L, as.integer(Sys.getenv("REPEATS", "1")))
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fun_table <- Sys.getenv("FUN_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
fungi_abund_table <- Sys.getenv("FUNGI_ABUND_TABLE")
result_dir <- Sys.getenv("RESULT_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

status_log <- list()

log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- tibble(step = step, status = status, message = message)
}

run_step <- function(step, expr) {
  tryCatch(
    {
      force(expr)
      log_status(step, "OK", "")
      TRUE
    },
    error = function(e) {
      log_status(step, "FAILED", conditionMessage(e))
      message("[WARN] ", step, ": ", conditionMessage(e))
      FALSE
    }
  )
}

read_metadata <- function(path, group_col) {
  meta <- readr::read_csv(path, show_col_types = FALSE)
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)
  if (!group_col %in% names(meta)) stop("Group column missing: ", group_col)
  meta <- meta %>%
    dplyr::mutate(sample_id = as.character(sample_id), label = as.factor(.data[[group_col]])) %>%
    dplyr::filter(!is.na(sample_id), !is.na(label))

  # Convert tibble to data.frame with rownames for SIAMCAT compatibility
  meta <- as.data.frame(meta)
  rownames(meta) <- meta$sample_id
  meta
}

coerce_numeric_df <- function(df) {
  for (i in seq_along(df)) df[[i]] <- suppressWarnings(as.numeric(df[[i]]))
  df
}

read_abundance_table <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  feature_col <- names(raw)[1]
  numeric_cols <- names(raw)[vapply(raw, function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0, logical(1))]
  sample_cols <- setdiff(numeric_cols, feature_col)
  tab <- raw %>%
    dplyr::select(all_of(c(feature_col, sample_cols))) %>%
    dplyr::rename(feature = !!feature_col)
  tab[sample_cols] <- coerce_numeric_df(tab[sample_cols])
  tab <- tab %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(dplyr::across(all_of(sample_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")
  mat <- as.matrix(tab[, sample_cols, drop = FALSE])
  rownames(mat) <- tab$feature
  mat[is.na(mat)] <- 0
  mat[rowSums(mat) > 0, , drop = FALSE]
}

# WC1R2 P0-1 (2026-10-01, user decision #1): virus input = 98c
# votu_annotation_matrix_relab.tsv TPM columns. The 98c table interleaves
# vOTU_TPM_<sample>, vOTU_RELAB_<sample> and ~20 annotation columns
# (vOTU_length, checkv_completeness, ...); the vOTU_TPM_ block is the
# abundance source. Precision rationale: 98c writes BOTH blocks through
# fmt_float (%.4f), so every RELAB cell below 0.00005 renders as "0.0000" -
# P01 static derivation: 28,349/42,137 vOTUs have ALL RELAB cells zero - and
# the 1e-4 prefilter threshold equals the RELAB rounding step, i.e. the
# rounded columns quantize exactly at the decision boundary. The TPM cells
# carry the same information at full TPM precision (1e-4, ~1e-10 relative); to_relab() below divides by
# the in-block column sum, which is the SAME formula 98c uses for RELAB
# (TPM / per-sample column total) computed without the 4-decimal loss
# (mathematically equivalent, full TPM precision (1e-4, ~1e-10 relative)). Column names are matched
# EXPLICITLY by the vOTU_TPM_ prefix (never by the generic numeric-column
# heuristic, which would swallow the annotation columns), the prefix is
# stripped to recover sample names, and vOTU_name is the feature id.
read_vir_tpm_matrix <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  if (!"vOTU_name" %in% names(raw)) {
    stop("98c virus table lacks the vOTU_name feature column: ", path)
  }
  tpm_cols <- grep("^vOTU_TPM_", names(raw), value = TRUE)
  if (length(tpm_cols) == 0) {
    stop("98c virus table has no vOTU_TPM_<sample> columns: ", path)
  }
  samples <- sub("^vOTU_TPM_", "", tpm_cols)
  tab <- raw %>%
    dplyr::select(feature = vOTU_name, dplyr::all_of(tpm_cols))
  names(tab) <- c("feature", samples)
  tab[samples] <- coerce_numeric_df(tab[samples])
  tab <- tab %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(dplyr::across(dplyr::all_of(samples), ~ sum(.x, na.rm = TRUE)), .groups = "drop")
  mat <- as.matrix(tab[, samples, drop = FALSE])
  rownames(mat) <- tab$feature
  mat[is.na(mat)] <- 0
  mat[rowSums(mat) > 0, , drop = FALSE]
}

# B3-PREQ①-R #1 defensive assertion: a block's sample columns must overlap the
# metadata by at least min_n samples, else a LOUD error naming the block and
# its input table (never a silent drop to zero features downstream). Sample
# columns present in the table but absent from metadata only WARN - the
# metadata intersection later in the script handles the actual subsetting.
assert_block_samples <- function(block_label, mat, meta_ids, src, min_n = 10L) {
  cols <- colnames(mat)
  matched <- intersect(cols, meta_ids)
  if (length(matched) < min_n) {
    stop(sprintf(
      "[INPUT-GOVERNANCE] %s block: only %d/%d sample column(s) match metadata sample ids (need >=%d). Input: %s | table samples: %s | metadata samples: %s",
      block_label, length(matched), length(cols), min_n, src,
      paste(utils::head(cols, 8), collapse = ","),
      paste(utils::head(meta_ids, 8), collapse = ",")))
  }
  unmatched <- setdiff(cols, meta_ids)
  if (length(unmatched) > 0) {
    message(sprintf("[WARN] %s block: %d sample column(s) not present in metadata (excluded from ML): %s",
                    block_label, length(unmatched), paste(utils::head(unmatched, 10), collapse = ",")))
  }
  invisible(matched)
}

# B3-PREQ①-R #2 (2026-09-30, user decision #3 / M-96-Q1): per-block relative
# abundance conversion. Each feature block (BAC|/VIR|/FUN|) is divided by its
# OWN column sums so every block lives on a 0-1 relative-abundance scale
# before the prevalence/mean-relab prefilter. This replaces the old stacked
# filter whose single colSums() denominator mixed blocks with incomparable
# magnitudes (metaphlan4 % vs 98c/98d relab), which could crush an entire
# block (observed: FUN| features wiped out). SIAMCAT input is now uniformly
# relab-valued; -d bacteria gets the same treatment so single-dimension runs
# never drift from all-mode semantics.
to_relab <- function(m) {
  cs <- colSums(m)
  cs[!is.finite(cs) | cs <= 0] <- 1
  sweep(m, 2, cs, "/")
}

# B3-PREQ①-R #3 (2026-09-30, user decision #3 / M-96-Q6): BAC| domain filter.
# MetaPhlAn merged tables carry every rank as its own row; only k__Bacteria
# lineages TERMINATING at the s__ (species) rank are ML features. Rows from
# other domains (k__Eukaryota/k__Archaea/k__Viruses), unranked rows
# (UNCLASSIFIED) and higher-rank bacteria rows are dropped BEFORE the
# per-block relab conversion, so the BAC| relative abundance is computed over
# the retained species universe. P01 counts are a STATIC DERIVATION over the
# merged table (regex accounting; not a live measurement): kept 786
# k__Bacteria s__-terminal rows, 1582 higher-rank bacteria rows (839 of them
# t__ strain-terminated, e.g. |s__X|t__SGB...), 23 non-bacteria-domain rows
# (8 k__Eukaryota + 15 k__Archaea). These supersede the earlier quoted
# "1625 kept / 743 higher-rank": that derivation used an UNANCHORED "|s__"
# containment match, which also counted the 839 t__-terminated rows as
# species (786 + 839 = 1625; 1582 - 839 = 743) - WC1R2 P0-4 correction.
filter_bac_domain <- function(m) {
  feat <- rownames(m)
  is_bacteria <- startsWith(feat, "k__Bacteria")
  is_species <- grepl("\\|s__[^|]*$", feat)
  keep <- is_bacteria & is_species
  dropped_domain <- sum(!is_bacteria & startsWith(feat, "k__"))
  dropped_unranked <- sum(!startsWith(feat, "k__"))
  dropped_rank <- sum(is_bacteria & !is_species)
  cat(sprintf(
    "[INPUT-GOVERNANCE] BAC| domain filter: kept %d k__Bacteria s__-terminal row(s) (t__-terminated strain rows count as higher rank); dropped %d non-bacteria-domain row(s), %d unranked row(s), %d higher-rank bacteria row(s)\n",
    sum(keep), dropped_domain, dropped_unranked, dropped_rank))
  log_status("bac_domain_filter", "OK",
             sprintf("kept_s_species=%d dropped_domain=%d dropped_unranked=%d dropped_higher_rank=%d",
                     sum(keep), dropped_domain, dropped_unranked, dropped_rank))
  m[keep, , drop = FALSE]
}

# B3-PREQ①-R #4 (2026-09-30, user decision #4) + WC1R2 P0-3 (2026-10-01,
# user decision #2): block selection is driven by --combination (letters
# B/V/F); the SAMPLE POOL is driven by --sample-set. auto = intersection of
# the selected blocks' input-table columns (recorded in split_manifest.txt);
# BVF = the B-V-F three-table intersection shared by all seven protocol runs
# (single-block runs included), so paired comparisons never compare
# different cohorts. Sample names are SORTED before any use, so the split
# input order is deterministic and independent of the input tables' column
# order.
load_matrix <- function() {
  sample_set <- Sys.getenv("SAMPLE_SET", "auto")
  block_of <- c(B = "BAC", V = "VIR", F = "FUN")
  pool_letters <- if (sample_set == "BVF") c("B", "V", "F") else combo_letters
  blocks <- list()
  sample_pools <- list()
  for (letter in pool_letters) {
    src <- ""
    m <- if (letter == "B") {
      # B3-PREQ①-R #3: species-level k__Bacteria rows only
      src <- bact_table
      filter_bac_domain(read_abundance_table(bact_table))
    } else if (letter == "V") {
      # WC1R2 P0-1: 98c TPM matrix (full TPM precision (1e-4, ~1e-10 relative); in-block relab conversion
      # below) + metadata defensive assertion
      src <- vir_table
      read_vir_tpm_matrix(vir_table)
    } else {
      # WC1R2 P0-3 (user decision #3): the FUN| arm is pinned to the 98d
      # funomic integration table for every protocol run; an explicit -M
      # redirects only a STANDALONE F feature arm (the bash stage already
      # warned non-protocol). Multi-block stacks and BVF pool reads always
      # use the pinned 98d table.
      src <- if (length(combo_letters) == 1L && letter %in% combo_letters) fungi_abund_table else fun_table
      read_abundance_table(src)
    }
    assert_block_samples(block_of[[letter]], m, rownames(meta), src)
    sample_pools[[letter]] <- colnames(m)
    if (letter %in% combo_letters) blocks[[block_of[[letter]]]] <- m
  }
  if (length(blocks) == 0) stop("Unsupported combination: ", combination)
  for (nm in names(blocks)) {
    blocks[[nm]] <- to_relab(blocks[[nm]])
    log_status(paste0("relab_convert_", nm), "OK",
               sprintf("n_features=%d n_samples=%d scale=0-1 (block column sums -> 1)",
                       nrow(blocks[[nm]]), ncol(blocks[[nm]])))
  }
  combo_samples <- sort(Reduce(intersect, sample_pools), method = "radix")  # locale-independent (supervisor P1)
  pool_counts <- paste(sprintf("%s=%d", names(sample_pools),
                               vapply(sample_pools, length, integer(1))), collapse = ", ")
  # WC1R2 P0-3: the protocol pool (BVF) and multi-block stacks must hold >=10
  # samples, and every pool's size is listed so the offending table is
  # identifiable. Single-block auto runs keep the historical >=10 metadata
  # overlap check further below.
  if ((sample_set == "BVF" || length(blocks) > 1) && length(combo_samples) < 10L) {
    stop(sprintf(
      "[INPUT-GOVERNANCE] sample_set=%s combination %s: input-table sample intersection = %d (<10 required for SIAMCAT). Per-table sample counts: %s",
      sample_set, combination, length(combo_samples), pool_counts))
  }
  cat(sprintf("[INFO] sample_set=%s: shared sample pool n=%d (per-table sample counts: %s)\n",
              sample_set, length(combo_samples), pool_counts))
  mat <- if (length(blocks) > 1) {
    do.call(rbind, Map(function(nm, m) {
      `rownames<-`(m[, combo_samples, drop = FALSE], paste0(nm, "|", rownames(m)))
    }, names(blocks), blocks))
  } else if (sample_set == "BVF") {
    # protocol single-block run: restrict to the shared BVF pool but keep the
    # historical unprefixed single-dimension feature names
    blocks[[1]][, combo_samples, drop = FALSE]
  } else {
    blocks[[1]]
  }
  list(mat = mat, combo_samples = combo_samples, sample_set = sample_set)
}

meta <- read_metadata(metadata_csv, group_col)
loaded <- load_matrix()
mat <- loaded$mat
combo_samples <- loaded$combo_samples
sample_set <- loaded$sample_set
# WC1R2 P0-3: sorted intersection -> the SIAMCAT split input order is
# deterministic and independent of the input tables' column order.
common <- sort(intersect(colnames(mat), rownames(meta)), method = "radix")  # SIAMCAT input column order, locale-independent (supervisor P1)
if (length(common) < 10) {
  cat("[WARN] Only", length(common), "overlapping samples; SIAMCAT requires >=10.",
      "Writing placeholder sentinel and skipping ML.\n")
  writeLines(c(paste0("SKIPPED: only ", length(common), " samples (need >=10 for SIAMCAT)"),
               "Re-run with actual cohort data (>=10 samples per group)."),
             file.path(result_dir, "siamcat_done.txt"))
  # P0-2 (supervisor re-review): SKIPPED runs must also stamp the regime so
  # resume keeps exit-0 semantics (a manifest-less sentinel would now error).
  writeLines(c(paste0("combination=", combination),
               paste0("sample_set=", sample_set),
               paste0("fungi_method=", Sys.getenv("MGX_FUNGI_METHOD", "auto"))),
             file.path(result_dir, "split_manifest.txt"))
  quit(status = 0)
}
mat <- mat[, common, drop = FALSE]
meta <- meta[common, , drop = FALSE]
meta$label <- droplevels(as.factor(meta$label))
if (nlevels(meta$label) < 2) stop("Need at least two classes")
positive_level <- levels(meta$label)[2]

# B3-PREQ①-R #2: with per-block relab conversion done in load_matrix, the
# second clause below is the mean per-sample relative abundance within the
# block (col sums are 1), i.e. the SAME threshold semantics as the historical
# rowMeans(mat/colSums(mat)) >= 1e-4 - but each block is now judged on its
# own scale, so no block can be crushed by another block's magnitude.
filtered <- mat[rowMeans(mat > 0) >= 0.05 & rowMeans(mat) >= 1e-4, , drop = FALSE]
if (nrow(filtered) < 5) stop("Too few features after filtering")

# Per-block surviving feature counts -> siamcat_status.tsv (spec #2:
# "per-block 转换与各块存活特征数写 status.tsv")
{
  multi_block <- length(combo_letters) > 1
  blk_names <- c(B = "BAC", V = "VIR", F = "FUN")[combo_letters]
  for (nm in blk_names) {
    pfx <- paste0(nm, "|")
    n_before <- if (multi_block) sum(startsWith(rownames(mat), pfx)) else nrow(mat)
    n_after <- if (multi_block) sum(startsWith(rownames(filtered), pfx)) else nrow(filtered)
    log_status(paste0("prefilter_", nm), "OK",
               sprintf("features_after=%d/%d (prevalence>=0.05 AND mean_relab>=1e-4, per-block relab scale)",
                       n_after, n_before))
  }
}

siamcat_obj <- NULL
run_step("siamcat_init", {
  siamcat_obj <<- SIAMCAT::siamcat(
    feat = filtered,
    meta = meta,
    label = group_col,
    case = positive_level
  )
})

run_step("check_confounders", {
  conf_plot <- file.path(result_dir, "siamcat_confounders.pdf")
  SIAMCAT::check.confounders(siamcat_obj, fn.plot = conf_plot)
})

run_step("normalize_filter_split", {
  # M-LEAK-01 注释更正（2026-09-30，B-1 审计 + 用户拍板 #3）：
  # (1) 上方 :341 的预过滤第二子句是【全队列】平均相对丰度阈值（rowMeans(mat/colSums)），
  #     本行 filter.features(abundance, 1e-04) 与 normalize.features(log.std) 的调用点
  #     也都在 create.data.split 之前——原注释"prevalence only / cutoff 在 SIAMCAT
  #     内部 post-split per fold 执行"的表述不实。三者均不用标签，属轻度泄漏
  #     （无监督全队列统计量参与特征保留与归一化尺度，方向偏乐观、幅度有界）。
  # (2) 处置：b1_preprocessing_timing_audit.md §6 已 verified（2026-09-30 源码
  #     查证，SIAMCAT 2.10.0/2.14.0 反编译逐字相同）：filter.features 与
  #     normalize.features 均在调用时对全对象立即生效、不按 fold 重做
  #     （train.model 只取已归一化全矩阵按 fold 选行）。泄漏定性成立；是否
  #     将过滤/归一化移入 fold 内由 M-LEAK-02 立项另行决定。
  # Subject-aware CV 语义不变：metadata 带 subject/id 列时同 subject 样本不跨 fold。
  siamcat_obj <<- SIAMCAT::filter.features(siamcat_obj, filter.method = "abundance", cutoff = 1e-04)
  siamcat_obj <<- SIAMCAT::normalize.features(siamcat_obj, norm.method = "log.std", norm.param = list(log.n0 = 1e-06, sd.min.q = 0.1))
})

models <- list(
  lasso = "lasso",
  ridge = "ridge",
  enet = "enet",
  randomForest = "randomForest"
)
aucs <- list()
metrics <- list()

# W-C1(3) outer repeat loop (A-2 protocol section 5, >=10 repeats):
# seed_i = base_seed + (i - 1), so repeat 1 keeps the historical anchor
# 20260928 and --repeats 1 (default) stays behavior-identical to the
# previous single-pass run. Each repeat redraws the split and retrains all
# models; filter/normalize stay OUTSIDE the loop (b1 section 6 verified:
# they take effect once on the whole object, not per fold). Per-repeat
# rds/PDF artifacts overwrite, so the canonical files hold the LAST
# repeat's model; per-repeat AUCs land in siamcat_repeats_detail.tsv and
# siamcat_auc_summary.tsv becomes the mean +/- sd aggregation (A-2: single
# repeat values are never quoted alone).
base_seed <- 20260928L
split_seeds_ok <- integer()
for (rep_i in seq_len(repeats)) {
  seed_rep <- base_seed + rep_i - 1L
  split_ok <- run_step(if (repeats == 1L) "data_split" else paste0("data_split_rep", rep_i), {
    set.seed(seed_rep)  # M-LEAK-01: reproducible split anchor (repeat-shifted)
    # M-LEAK-01: SIAMCAT refuses when test folds cannot hold >=1 sample per
    # class (e.g. 10 samples x 10 folds). Cap folds deterministically at the
    # minority-class size; only activates where the run would otherwise hard-
    # fail, and the effective value is written to the split manifest.
    folds_eff <- max(2L, min(folds, min(as.integer(table(meta$label)))))
    if (folds_eff != folds) cat(sprintf("[M-LEAK-01] folds capped %d -> %d (minority class)\n", folds, folds_eff))
    subject_col <- grep("^(subject_id|patient_id|subject|patient)$", names(meta), value = TRUE)[1]
    grouped <- FALSE
    if (!is.na(subject_col)) {
      n_per_sub <- table(meta[[subject_col]])
      if (max(n_per_sub) > 1) {
        # real grouping constraint: one subject's samples never straddle folds.
        # SIAMCAT contract: inseparable = metadata COLUMN NAME (meta is already
        # attached to the siamcat object at init), stratify must be FALSE.
        siamcat_obj <<- SIAMCAT::create.data.split(siamcat_obj, num.folds = folds_eff, num.resample = 1,
                                                   stratify = FALSE, inseparable = subject_col)
        grouped <- TRUE
        cat(sprintf("[M-LEAK-01] grouped split by %s (subjects=%d, max=%d samples/subject)\n",
                    subject_col, length(n_per_sub), max(n_per_sub)))
      } else {
        cat("[M-LEAK-01] subject column present but all 1:1 - grouping vacuous, sample-level split (declared)\n")
      }
    }
    if (!grouped) {
      siamcat_obj <<- SIAMCAT::create.data.split(siamcat_obj, num.folds = folds_eff, num.resample = 1)
    }
  })
  if (!isTRUE(split_ok)) next
  split_seeds_ok <- c(split_seeds_ok, seed_rep)

  for (nm in names(models)) {
  success <- run_step(paste0("train_", nm), {
    model_obj <- SIAMCAT::train.model(siamcat_obj, method = models[[nm]])
    model_obj <- SIAMCAT::make.predictions(model_obj)
    model_obj <- SIAMCAT::evaluate.predictions(model_obj)
    saveRDS(model_obj, file.path(result_dir, paste0("siamcat_", nm, ".rds")))
    # W-C1(1): diagnostic PDFs are non-fatal. model.interpretation.plot()
    # errors with "No features were selected for plotting!" on degenerate
    # (intercept-only) models; killing the whole train step there would make
    # the model vanish from the summary instead of being flagged
    # degenerate=yes below.
    tryCatch({
      pdf(file.path(result_dir, paste0("siamcat_", nm, "_evaluation.pdf")), width = 10, height = 8)
      SIAMCAT::model.evaluation.plot(model_obj)
      dev.off()
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cat(sprintf("[WARN] %s: evaluation plot failed: %s\n", nm, conditionMessage(e)))
    })
    tryCatch({
      pdf(file.path(result_dir, paste0("siamcat_", nm, "_interpretation.pdf")), width = 10, height = 8)
      SIAMCAT::model.interpretation.plot(model_obj, consens.thres = 0.5, limits = c(0, 20))
      dev.off()
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cat(sprintf("[WARN] %s: interpretation plot failed: %s\n", nm, conditionMessage(e)))
    })
    eval_obj <- SIAMCAT::eval_data(model_obj)
    auc_val <- eval_obj$auroc %||% eval_obj$auc %||% NA_real_
    list(model = nm, auc = auc_val)
  })
  if (isTRUE(success)) {
    result_file <- file.path(result_dir, paste0("siamcat_", nm, ".rds"))
    if (file.exists(result_file)) {
      model_obj <- readRDS(result_file)
      eval_obj <- SIAMCAT::eval_data(model_obj)
      auc_val <- eval_obj$auroc %||% eval_obj$auc %||% NA_real_
      # W-C1(1) degenerate guard: training "succeeded" but selected zero
      # effective features (intercept-only; e.g. cv.glmnet lambda.1se keeps
      # nothing). The rds stays on disk (97 reports it as-is), but the row is
      # flagged degenerate=yes and excluded from the successful-model count.
      degenerate <- "no"
      fw <- tryCatch(SIAMCAT::feature_weights(model_obj), error = function(e) NULL)
      if (is.null(fw) || nrow(fw) == 0 || all(is.na(fw$mean.weight)) || all(fw$mean.weight == 0)) {
        degenerate <- "yes"
        cat(sprintf("[WARN] %s: degenerate model (no selected features / intercept-only); flagged degenerate=yes\n", nm))
      }
      aucs[[paste0(nm, if (repeats > 1L) paste0("_rep", rep_i) else "")]] <-
        tibble(model = nm, rep = rep_i, seed = seed_rep, auc = as.numeric(auc_val),
               degenerate = degenerate, aligned_by = "sample_id")
      # M-METRICS-01: export the full evaluation panel, not AUC alone.
      # W-C1(1) label fix (A6, 2026-09-30): the old
      #   y <- as.integer(as.character(lbl) == names(table(as.character(lbl)))[2])
      #   y <- rep(y, length.out = nrow(p_obj))
      # deparse-compared the label OBJECT (3 fields), producing periodic
      # pseudo-labels - every panel metric was garbage. Labels are now taken
      # from SIAMCAT::label(siamcat_obj)$label (named +/-1 vector) and aligned
      # BY SAMPLE NAME against pred_matrix rownames (97's common_ids rule:
      # sort(intersect(...))); positional recycling is forbidden, and failed
      # alignment leaves the panel metrics NA with a WARN.
      # The removed first branch SIAMCAT::predict(model_obj, siamcat_obj) was
      # dead code: SIAMCAT 2.10.0 exports no predict(), the call always
      # errored into NULL, and the panel always used pred_matrix(model_obj)
      # (out-of-fold CV predictions - never a resubstitution path).
      # W-C1(4): every auc/metrics row carries aligned_by="sample_id" so the
      # alignment convention stays traceable in the artifacts (A-2 note;
      # column naming matches 97's crosscohort_metrics style).
      extra <- list(rep = rep_i, seed = seed_rep, model = nm, auc_roc = as.numeric(auc_val), auc_pr = NA_real_,
                    sensitivity = NA_real_, specificity = NA_real_, ppv = NA_real_,
                    n_predictions = 0L, calibration_error = NA_real_, aligned_by = "sample_id")
      p_obj <- tryCatch(SIAMCAT::pred_matrix(model_obj), error = function(e) NULL)
      lbl <- tryCatch(SIAMCAT::label(siamcat_obj)$label, error = function(e) NULL)
      if (!is.null(p_obj) && nrow(p_obj) > 0 && !is.null(lbl)) {
        ids <- sort(intersect(rownames(p_obj), names(lbl)))
        if (length(ids) == 0) {
          cat(sprintf("[WARN] %s: no sample-name overlap between pred_matrix and label - panel metrics stay NA\n", nm))
        } else {
          if (length(ids) < nrow(p_obj)) {
            cat(sprintf("[WARN] %s: %d prediction row(s) without a matching label dropped from the panel\n",
                        nm, nrow(p_obj) - length(ids)))
          }
          y <- as.integer(lbl[ids] == 1)
          scores <- p_obj[ids, 1]
          pr <- tryCatch(PRROC::pr.curve(scores.class0 = scores, weights.class0 = y), error = function(e) NULL)
          if (!is.null(pr)) extra$auc_pr <- as.numeric(pr$auc.integral)
          pred_class <- ifelse(scores >= 0.5, 1L, 0L)
          extra$n_predictions <- length(ids)
          tp <- sum(pred_class == 1 & y == 1); fn <- sum(pred_class == 0 & y == 1)
          fp <- sum(pred_class == 1 & y == 0); tn <- sum(pred_class == 0 & y == 0)
          extra$sensitivity <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
          extra$specificity <- if (tn + fp > 0) tn / (tn + fp) else NA_real_
          extra$ppv <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
          bins <- cut(scores, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
          obs <- tapply(y, bins, mean); pr_mean <- tapply(scores, bins, mean)
          ok <- !is.na(obs)
          extra$calibration_error <- if (any(ok)) mean(abs(obs[ok] - pr_mean[ok])) else NA_real_
        }
      }
      metrics[[paste0(nm, if (repeats > 1L) paste0("_rep", rep_i) else "")]] <- tibble::as_tibble(extra)
    }
  }
}
}

# Split manifest: numerically and format-compatible with the historical
# single-run layout when --repeats 1 (no longer byte-identical: the manifest
# gained combination/sample_set/combo_* lines across the WC1R/P0-3 batches);
# records every successful repeat seed when repeats > 1
# (A-2 section 5: seeds land on disk with the results).
# B3-PREQ①-R #4: the combination and its shared sample set (the
# intersection of the selected blocks' input-table samples, computed once
# before metadata subsetting) are recorded for A-2 protocol section 4.
if (length(split_seeds_ok) > 0) {
  writeLines(c(paste0("seed=", split_seeds_ok[1]),
               paste0("folds=", folds_eff), paste0("folds_requested=", folds), paste0("resample=1"),
               paste0("split_unit=", ifelse(grouped, paste0("SUBJECT(", subject_col, ")"), "SAMPLE")),
               paste0("subject_column=", ifelse(is.na(subject_col), "NONE", subject_col)),
               paste0("multi_sample_subjects=", ifelse(!is.na(subject_col), sum(table(meta[[subject_col]]) > 1), 0)),
               paste0("n_samples=", ncol(mat)),
               paste0("combination=", combination),
               paste0("sample_set=", sample_set),
               paste0("fungi_method=", Sys.getenv("MGX_FUNGI_METHOD", "auto")),
               paste0("combo_n_samples=", length(combo_samples)),
               paste0("combo_samples=", paste(combo_samples, collapse = ",")),
               if (repeats > 1L) paste0("repeats=", repeats),
               if (repeats > 1L) paste0("seed_rep", seq_along(split_seeds_ok), "=", split_seeds_ok)),
             file.path(result_dir, "split_manifest.txt"))
}

metrics_df <- bind_rows(metrics)
if (nrow(metrics_df) > 0) {
  metrics_df <- if (repeats > 1L) {
    dplyr::select(metrics_df, rep, seed, model, dplyr::everything())
  } else {
    dplyr::select(metrics_df, model, auc_roc, auc_pr, sensitivity, specificity, ppv, n_predictions, calibration_error, aligned_by)
  }
  readr::write_tsv(metrics_df, file.path(result_dir, "siamcat_metrics.tsv"))
  cat("[M-METRICS-01] siamcat_metrics.tsv:", nrow(metrics_df), "models x",
      ncol(metrics_df), "metrics (auc_roc/auc_pr/sens/spec/ppv/calibration)\n")
}

auc_detail <- bind_rows(aucs)
if (nrow(auc_detail) == 0) stop("No model AUCs generated")
if (repeats == 1L) {
  auc_df <- dplyr::select(auc_detail, model, auc, degenerate, aligned_by)
} else {
  readr::write_tsv(dplyr::select(auc_detail, rep, seed, model, auc, degenerate, aligned_by),
                   file.path(result_dir, "siamcat_repeats_detail.tsv"))
  auc_df <- auc_detail %>%
    dplyr::left_join(dplyr::select(metrics_df, rep, model, auc_pr), by = c("rep", "model")) %>%
    dplyr::group_by(model) %>%
    dplyr::summarise(auc_mean = mean(auc), auc_sd = stats::sd(auc),
                     auc_pr_mean = mean(auc_pr), auc_pr_sd = stats::sd(auc_pr),
                     n_repeats = dplyr::n_distinct(rep),
                     n_degenerate = sum(degenerate == "yes"), .groups = "drop") %>%
    # B3-PREQ①-R #5 (2026-09-30, user decision #5): the repeats>1 summary
    # discloses degenerate repeats via n_degenerate and adds stderr columns
    # (sd / sqrt(n_repeats)); the mean +/- sd aggregation INCLUDES degenerate
    # repeats - that is stated explicitly in siamcat_done.txt so nobody quotes
    # the mean as if it were degenerate-free.
    dplyr::mutate(auc_stderr = auc_sd / sqrt(n_repeats),
                  auc_pr_stderr = auc_pr_sd / sqrt(n_repeats),
                  degenerate = ifelse(n_degenerate == n_repeats, "yes", "no"),
                  aligned_by = "sample_id")
}
readr::write_tsv(auc_df, file.path(result_dir, "siamcat_auc_summary.tsv"))
n_degen <- sum(auc_df$degenerate == "yes")
if (n_degen > 0) {
  cat(sprintf("[WARN] %d degenerate model(s) (degenerate=yes): %s - rds kept, NOT counted as successful models\n",
              n_degen, paste(auc_df$model[auc_df$degenerate == "yes"], collapse = ", ")))
}
readr::write_tsv(bind_rows(status_log), file.path(result_dir, "siamcat_status.tsv"))
# B3-PREQ①-R #5: degenerate-disclosure note lines. When repeats > 1 and any
# repeat is degenerate, the mean +/- sd aggregation that INCLUDES those
# degenerate repeats is stated next to the summary itself.
degen_notes <- c(
  if (n_degen > 0) paste0("NOTE: ", n_degen, " model(s) degenerate=yes (no selected features / intercept-only); rds kept for 97 but NOT counted as successful models"),
  if (repeats > 1L && n_degen > 0) "NOTE: auc_mean +/- auc_sd (and auc_stderr) INCLUDE degenerate repeats - see the n_degenerate column here and per-repeat flags in siamcat_repeats_detail.tsv",
  if (repeats > 1L && n_degen == 0) "NOTE: repeats>1 aggregation auc_mean +/- auc_sd / auc_stderr; n_degenerate=0 for every model in this run")
writeLines(c("SIAMCAT AUC summary", capture.output(print(auc_df)), degen_notes),
           file.path(result_dir, "siamcat_done.txt"))
# WC1R2 Q3 persistence: the disclosure notes also land in a PERSISTENT file
# regenerated by every ML run - it does not depend on the siamcat_done.txt
# sentinel (which 96_ml_visualization.R overwrites with a timestamp) and is
# immune to resume/rerun flows. The bash stage below keeps re-appending the
# notes to the sentinel after visualization (B3-PREQ①-R #5 logic unchanged).
writeLines(c("SIAMCAT degenerate-model disclosure (regenerated by every ML run; independent of siamcat_done.txt)",
             if (length(degen_notes) > 0) degen_notes else "none: no degenerate model flags in this run"),
           file.path(result_dir, "siamcat_disclosure.txt"))
# 96_ml_visualization.R later overwrites siamcat_done.txt with a completion
# timestamp (its line 183); persist the disclosure notes so the bash stage can
# re-append them AFTER visualization and the final sentinel stays
# self-describing (B3-PREQ①-R #5). The scratch file is removed after use.
if (length(degen_notes) > 0) {
  writeLines(degen_notes, file.path(result_dir, "siamcat_done.notes"))
}
RSCRIPT
)

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    if grep -q "not enough for SIAMCAT to proceed\|No model AUCs generated" "${RUN_LOG}"; then
        echo "[WARN] ${DIMENSION}: sample size too small for SIAMCAT cross-validation, writing skip sentinel"
        echo "SKIPPED: insufficient samples per class for SIAMCAT model training (${DIMENSION}/combo=${COMBINATION})" > "${SENTINEL}"
        # P0-2 (supervisor re-review): stamp the regime so a SKIPPED sentinel
        # resumes with exit 0 (a manifest-less sentinel would now error).
        printf 'combination=%s\nsample_set=%s\nfungi_method=%s\n' \
            "${COMBINATION}" "${SAMPLE_SET:-auto}" "${FUNGI_METHOD}" \
            > "$(dirname "${SENTINEL}")/split_manifest.txt"
        exit 0
    fi
    echo "[ERROR] 96_stat_ml_siamcat.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

run_ml_visualization
EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 96_ml_visualization.R failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

# B3-PREQ①-R #5: 96_ml_visualization.R overwrites siamcat_done.txt with a
# completion timestamp; re-append the degenerate-disclosure notes stashed by
# the ML stage so the final sentinel carries them.
if [ -s "${RESULT_DIR}/siamcat_done.notes" ]; then
    cat "${RESULT_DIR}/siamcat_done.notes" >> "${SENTINEL}"
    rm -f "${RESULT_DIR}/siamcat_done.notes"
fi

mgx_end "siamcat"
echo "[INFO] Sentinel: ${SENTINEL}"
echo "[INFO] Visualizations: ${VIZ_ML_DIR}"
