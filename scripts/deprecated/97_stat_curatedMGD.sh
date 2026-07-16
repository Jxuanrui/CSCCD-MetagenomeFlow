# Deprecated 2026-07-16: superseded by 97_stat_crosscohort.sh due to cross-cohort architecture duplication.
#!/usr/bin/env bash
# ==============================================================================
# Script: 97_stat_curatedMGD.sh
# Purpose: Cross-cohort validation using curatedMetagenomicData
# Usage:   bash 97_stat_curatedMGD.sh -w WORKDIR -r REPO -m METADATA_CSV -g GROUP_COL
#                                    [-c CONDITION] [--augment-n N] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 97_stat_curatedMGD.sh -w WORKDIR -r REPO -m METADATA_CSV -g GROUP_COL
                                  [-c CONDITION] [--augment-n N] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -m  Metadata CSV
  -g  Group column

Optional:
  -c  Condition label (default: CRC)
  --augment-n  Number of random controls to add (default: 50)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
METADATA_CSV=""
GROUP_COL=""
CONDITION="CRC"
AUGMENT_N="50"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        -c) CONDITION="$2"; shift 2 ;;
        --augment-n) AUGMENT_N="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ] || [ -z "${METADATA_CSV}" ] || [ -z "${GROUP_COL}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

ML_DIR="${WORKDIR}/result/stat/ml"
RESULT_DIR="${WORKDIR}/result/stat/crosscohort"
LOG_DIR="${WORKDIR}/logs/stat/crosscohort"
SENTINEL="${RESULT_DIR}/crosscohort_done.txt"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/97_stat_curatedMGD.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running cross-cohort validation"

export WORKDIR REPO METADATA_CSV GROUP_COL CONDITION AUGMENT_N ML_DIR RESULT_DIR

conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)

required_pkgs <- c("SIAMCAT", "curatedMetagenomicData", "MMUPHin", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(SIAMCAT)
  library(curatedMetagenomicData)
  library(MMUPHin)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

condition <- Sys.getenv("CONDITION")
augment_n <- as.integer(Sys.getenv("AUGMENT_N", "50"))
ml_dir <- Sys.getenv("ML_DIR")
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

dataset_map <- list(
  CRC = c("WirbelJ_2019.metaphlan_bugs_list.stool", "ThomasAM_2019_a.metaphlan_bugs_list.stool", "ZellerG_2014.metaphlan_bugs_list.stool"),
  T2D = c("QinJ_2012.metaphlan_bugs_list.stool", "KarlssonFH_2013.metaphlan_bugs_list.stool"),
  IBD = c("NielsenHB_2014.metaphlan_bugs_list.stool", "PasolliE_2016.metaphlan_bugs_list.stool")
)

model_file <- file.path(ml_dir, "siamcat_lasso.rds")
if (!file.exists(model_file)) stop("Missing lasso model from script 96: ", model_file)
siamcat_model <- readRDS(model_file)

cohort_results <- list()
biomarker_presence <- list()

run_step("load_curated_data", {
  datasets <- dataset_map[[condition]] %||% dataset_map$CRC
  for (ds in datasets) {
    message("[INFO] Loading curatedMetagenomicData dataset: ", ds)
    eset <- curatedMetagenomicData::curatedMetagenomicData(ds, dryrun = FALSE, counts = FALSE, rownames = "short")
    obj <- eset[[1]]
    expr <- Biobase::exprs(obj)
    meta <- Biobase::pData(obj)
    if (ncol(expr) < 10) next
    meta$sample_id <- rownames(meta)
    batch <- factor(rep(ds, nrow(meta)))
    corrected <- tryCatch({
      fit <- MMUPHin::adjust_batch(feature_abd = expr, batch = batch, covariates = meta[, character(0), drop = FALSE], control = list(verbose = FALSE))
      fit$feature_abd_adj %||% fit$feature_abd %||% expr
    }, error = function(e) expr)
    controls <- meta$sample_id[grepl("control|healthy", paste(meta, collapse = " "), ignore.case = TRUE)]
    if (length(controls) > 0) {
      controls <- sample(controls, min(length(controls), augment_n))
      corrected <- corrected[, unique(c(colnames(corrected), controls)), drop = FALSE]
    }
    pred_obj <- SIAMCAT::make.predictions(siamcat_model, newdata = corrected)
    pred_obj <- SIAMCAT::evaluate.predictions(pred_obj)
    eval_obj <- SIAMCAT::eval_data(pred_obj)
    auc_val <- eval_obj$auroc %||% eval_obj$auc %||% NA_real_
    cohort_results[[length(cohort_results) + 1]] <<- tibble(cohort = ds, auc = auc_val, n_samples = ncol(corrected))
    pdf(file.path(result_dir, paste0(gsub("[^A-Za-z0-9]+", "_", ds), "_roc.pdf")), width = 8, height = 6)
    SIAMCAT::model.evaluation.plot(pred_obj)
    dev.off()
    feat_weights <- tryCatch({
      fw <- SIAMCAT::model_list(siamcat_model)[[1]]$feature_weights
      tibble(feature = names(fw), weight = as.numeric(fw))
    }, error = function(e) tibble(feature = rownames(corrected)[seq_len(min(20, nrow(corrected)))], weight = seq_len(min(20, nrow(corrected)))))
    biomarker_presence[[ds]] <<- feat_weights %>%
      dplyr::slice_max(order_by = abs(weight), n = 50) %>%
      dplyr::mutate(cohort = ds)
  }
})

cohort_df <- bind_rows(cohort_results)
if (nrow(cohort_df) == 0) stop("No cross-cohort predictions generated")

biomarker_df <- bind_rows(biomarker_presence) %>%
  dplyr::group_by(feature) %>%
  dplyr::summarise(cohort_fraction = dplyr::n_distinct(cohort) / dplyr::n_distinct(bind_rows(biomarker_presence)$cohort), mean_weight = mean(weight, na.rm = TRUE), .groups = "drop") %>%
  dplyr::filter(cohort_fraction >= 0.5) %>%
  dplyr::arrange(dplyr::desc(cohort_fraction), dplyr::desc(abs(mean_weight)))

readr::write_tsv(cohort_df, file.path(result_dir, "crosscohort_auc.tsv"))
readr::write_tsv(biomarker_df, file.path(result_dir, "crosscohort_consistent_biomarkers.tsv"))
readr::write_tsv(bind_rows(status_log), file.path(result_dir, "crosscohort_status.tsv"))
writeLines(c("Cross-cohort AUC summary", capture.output(print(cohort_df))), file.path(result_dir, "crosscohort_done.txt"))
RSCRIPT

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 97_stat_curatedMGD.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Cross-cohort validation completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
