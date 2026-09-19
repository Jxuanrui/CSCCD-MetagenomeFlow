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
                                  -g GROUP_COL [-d DIMENSION] [-M FUNGI_METHOD] [--folds N] [--force] [--skip-shap]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV
  -g  Group column

Optional:
  -d  Dimension: bacteria|virus|fungi|all (default: bacteria)
  -M  Fungi input method: auto|phf|funomic|metaphlan4 (default: auto)
  --folds  Cross-validation folds (default: 10)
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

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:THREADS m:METADATA_CSV g:GROUP_COL d:DIMENSION M:FUNGI_METHOD"
export MGX_OPTS_FLAG="force skip-shap"
export MGX_OPTS_LONG="folds:FOLDS"
mgx_parse "$@"
mgx_require WORKDIR REPO THREADS METADATA_CSV GROUP_COL

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/votu_table.tsv"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
PHF_FUNGI_TABLE="${WORKDIR}/result/fungi/phf_profiler/merged_abundance_with_taxonomy.tsv"
FUNOMIC_FUNGI_TABLE="${WORKDIR}/result/integration/fungi/funomic_species_relab.tsv"
FUNGI_ABUND_TABLE=""
case "${DIMENSION}" in
    all) RESULT_DIR="${WORKDIR}/result/stat/ml" ;;
    bacteria|virus|fungi) RESULT_DIR="${WORKDIR}/result/stat/${DIMENSION}/ml" ;;
    *)
        echo "[ERROR] Invalid dimension: ${DIMENSION}"
        show_help
        exit 1
        ;;
esac
VIZ_ML_DIR="${RESULT_DIR}"
LOG_DIR="${WORKDIR}/logs/stat/ml"
SENTINEL="${RESULT_DIR}/siamcat_done.txt"

mkdir -p "${RESULT_DIR}" "${VIZ_ML_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/96_stat_ml_siamcat.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

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

echo "[INFO] Fungi input: METHOD=${FUNGI_METHOD} TABLE=${FUNGI_ABUND_TABLE:-${FUNGI_DIR}}"

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    run_ml_visualization
    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] 96_ml_visualization.R failed with exit code ${EXIT_CODE}"
        exit ${EXIT_CODE}
    fi
    exit 0
fi

echo "[INFO] Running SIAMCAT ML analysis"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL DIMENSION FOLDS BACT_TABLE VIR_TABLE FUNGI_DIR FUNGI_ABUND_TABLE RESULT_DIR

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
folds <- as.integer(Sys.getenv("FOLDS", "10"))
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
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

read_fungi_profiles <- function(dir_path) {
  files <- Sys.glob(file.path(dir_path, "*", "*_profile.txt"))
  if (length(files) == 0) stop("No fungi profile files found")
  prof <- lapply(files, function(fp) {
    tab <- readr::read_tsv(fp, show_col_types = FALSE, comment = "#")
    feature_col <- c("clade_name", "taxonomy", names(tab)[1])[c("clade_name", "taxonomy", names(tab)[1]) %in% names(tab)][1]
    abundance_col <- c("relative_abundance", "abundance", "fraction_total_reads", names(tab)[ncol(tab)])[c("relative_abundance", "abundance", "fraction_total_reads", names(tab)[ncol(tab)]) %in% names(tab)][1]
    tibble(feature = tab[[feature_col]], sample_id = basename(dirname(fp)), abundance = suppressWarnings(as.numeric(tab[[abundance_col]])))
  })
  merged <- bind_rows(prof) %>%
    dplyr::filter(!is.na(feature), !is.na(abundance)) %>%
    dplyr::group_by(feature, sample_id) %>%
    dplyr::summarise(abundance = sum(abundance, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = sample_id, values_from = abundance, values_fill = 0)
  rn <- merged$feature
  merged <- as.matrix(merged[, -1, drop = FALSE])
  rownames(merged) <- rn
  merged[rowSums(merged) > 0, , drop = FALSE]
}

load_matrix <- function(dimension) {
  if (dimension == "bacteria") return(read_abundance_table(bact_table))
  if (dimension == "virus") return(read_abundance_table(vir_table))
  if (dimension == "fungi") {
    if (nzchar(fungi_abund_table)) return(read_abundance_table(fungi_abund_table))
    return(read_fungi_profiles(fungi_dir))
  }
  if (dimension == "all") {
    bac <- read_abundance_table(bact_table)
    vir <- read_abundance_table(vir_table)
    common <- intersect(colnames(bac), colnames(vir))
    if (length(common) < 4) stop("Insufficient common samples for all-dimension ML")
    return(rbind(
      `rownames<-`(bac[, common, drop = FALSE], paste0("BAC|", rownames(bac))),
      `rownames<-`(vir[, common, drop = FALSE], paste0("VIR|", rownames(vir)))
    ))
  }
  stop("Unsupported dimension: ", dimension)
}

meta <- read_metadata(metadata_csv, group_col)
mat <- load_matrix(dimension)
common <- intersect(colnames(mat), rownames(meta))
if (length(common) < 10) {
  cat("[WARN] Only", length(common), "overlapping samples; SIAMCAT requires >=10.",
      "Writing placeholder sentinel and skipping ML.\n")
  writeLines(c(paste0("SKIPPED: only ", length(common), " samples (need >=10 for SIAMCAT)"),
               "Re-run with actual cohort data (>=10 samples per group)."),
             file.path(result_dir, "siamcat_done.txt"))
  quit(status = 0)
}
mat <- mat[, common, drop = FALSE]
meta <- meta[common, , drop = FALSE]
meta$label <- droplevels(as.factor(meta$label))
if (nlevels(meta$label) < 2) stop("Need at least two classes")
positive_level <- levels(meta$label)[2]

filtered <- mat[rowMeans(mat > 0) >= 0.05 & rowMeans(mat / pmax(colSums(mat)[col(mat)], 1)) >= 1e-4, , drop = FALSE]
if (nrow(filtered) < 5) stop("Too few features after filtering")

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
  siamcat_obj <<- SIAMCAT::filter.features(siamcat_obj, filter.method = "abundance", cutoff = 1e-04)
  siamcat_obj <<- SIAMCAT::normalize.features(siamcat_obj, norm.method = "log.std", norm.param = list(log.n0 = 1e-06, sd.min.q = 0.1))
  siamcat_obj <<- SIAMCAT::create.data.split(siamcat_obj, num.folds = folds, num.resample = 1)
})

models <- list(
  lasso = "lasso",
  ridge = "ridge",
  enet = "enet",
  randomForest = "randomForest"
)
aucs <- list()

for (nm in names(models)) {
  success <- run_step(paste0("train_", nm), {
    model_obj <- SIAMCAT::train.model(siamcat_obj, method = models[[nm]])
    model_obj <- SIAMCAT::make.predictions(model_obj)
    model_obj <- SIAMCAT::evaluate.predictions(model_obj)
    saveRDS(model_obj, file.path(result_dir, paste0("siamcat_", nm, ".rds")))
    pdf(file.path(result_dir, paste0("siamcat_", nm, "_evaluation.pdf")), width = 10, height = 8)
    SIAMCAT::model.evaluation.plot(model_obj)
    dev.off()
    pdf(file.path(result_dir, paste0("siamcat_", nm, "_interpretation.pdf")), width = 10, height = 8)
    SIAMCAT::model.interpretation.plot(model_obj, consens.thres = 0.5, limits = c(0, 20))
    dev.off()
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
      aucs[[nm]] <- tibble(model = nm, auc = as.numeric(auc_val))
    }
  }
}

auc_df <- bind_rows(aucs)
if (nrow(auc_df) == 0) stop("No model AUCs generated")
readr::write_tsv(auc_df, file.path(result_dir, "siamcat_auc_summary.tsv"))
readr::write_tsv(bind_rows(status_log), file.path(result_dir, "siamcat_status.tsv"))
writeLines(c("SIAMCAT AUC summary", capture.output(print(auc_df))), file.path(result_dir, "siamcat_done.txt"))
RSCRIPT
)

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    if grep -q "not enough for SIAMCAT to proceed\|No model AUCs generated" "${RUN_LOG}"; then
        echo "[WARN] ${DIMENSION}: sample size too small for SIAMCAT cross-validation, writing skip sentinel"
        echo "SKIPPED: insufficient samples per class for SIAMCAT model training (${DIMENSION})" > "${SENTINEL}"
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

mgx_end "siamcat"
echo "[INFO] Sentinel: ${SENTINEL}"
echo "[INFO] Visualizations: ${VIZ_ML_DIR}"
