#!/usr/bin/env bash
# ==============================================================================
# Script: 95a_stat_batch_correct.sh
# Purpose: Apply multiple batch correction methods to bacteria abundance matrix
# Usage:   bash 95a_stat_batch_correct.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                        -b BATCH_COL [-g GROUP_COL] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 95a_stat_batch_correct.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                      -b BATCH_COL [-g GROUP_COL] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV
  -b  Batch column

Optional:
  -g  Biological group column
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

GROUP_COL=""

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:THREADS m:METADATA_CSV b:BATCH_COL g:GROUP_COL"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO THREADS METADATA_CSV BATCH_COL

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
RESULT_DIR="${WORKDIR}/result/stat/bacteria/batch"
LOG_DIR="${WORKDIR}/logs/stat/batch"
SENTINEL="${RESULT_DIR}/corrected_matrices.done"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/95a_stat_batch_correct.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running batch correction methods"

export WORKDIR REPO THREADS METADATA_CSV BATCH_COL GROUP_COL BACT_TABLE RESULT_DIR

(cd "${WORKDIR}" && mgx_conda r_stat Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
      normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("MMUPHin", "ConQuR", "sva", "MBECS", "phyloseq", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(MMUPHin)
  library(ConQuR)
  library(sva)
  library(MBECS)
  library(phyloseq)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

metadata_csv <- Sys.getenv("METADATA_CSV")
batch_col <- Sys.getenv("BATCH_COL")
group_col <- Sys.getenv("GROUP_COL")
bact_table <- Sys.getenv("BACT_TABLE")
result_dir <- Sys.getenv("RESULT_DIR")
threads <- as.integer(Sys.getenv("THREADS", "1"))

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

status_log <- list()
summary_rows <- list()

log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- tibble(step = step, status = status, message = message)
}

mark_failed <- function(prefix, message) {
  writeLines(message, paste0(prefix, ".FAILED"))
}

run_method <- function(step, outfile, expr) {
  tryCatch(
    {
      mat <- force(expr)
      readr::write_tsv(tibble::rownames_to_column(as.data.frame(mat), "feature"), outfile)
      log_status(step, "OK", outfile)
      summary_rows[[length(summary_rows) + 1]] <<- tibble(method = basename(outfile), status = "OK", output = outfile)
      TRUE
    },
    error = function(e) {
      mark_failed(outfile, conditionMessage(e))
      log_status(step, "FAILED", conditionMessage(e))
      summary_rows[[length(summary_rows) + 1]] <<- tibble(method = basename(outfile), status = "FAILED", output = conditionMessage(e))
      message("[WARN] ", step, ": ", conditionMessage(e))
      FALSE
    }
  )
}

read_metadata <- function(path, batch_col, group_col) {
  meta <- readr::read_csv(path, show_col_types = FALSE)
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)
  if (!batch_col %in% names(meta)) {
    message("[INFO] Batch column '", batch_col, "' not found in metadata; skipping batch correction (single-batch data assumed)")
    return(NULL)
  }
  meta$sample_id <- as.character(meta$sample_id)
  meta[[batch_col]] <- as.factor(meta[[batch_col]])
  if (nzchar(group_col) && group_col %in% names(meta)) meta[[group_col]] <- as.factor(meta[[group_col]])
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

align_inputs <- function(mat, meta) {
  common <- intersect(colnames(mat), rownames(meta))
  if (length(common) < 4) stop("Insufficient overlapping samples")
  list(mat = mat[, common, drop = FALSE], meta = meta[common, , drop = FALSE])
}

ensure_matrix <- function(x) {
  x <- as.matrix(x)
  x[is.na(x)] <- 0
  x
}

baseline_transform <- function(mat) log1p(mat)

meta <- read_metadata(metadata_csv, batch_col, group_col)
if (is.null(meta)) {
  message("[INFO] No batch column found; creating sentinel and exiting (single-batch data)")
  writeLines("No batch correction applied: batch column not present in metadata",
             file.path(result_dir, "corrected_matrices.done"))
  quit(save = "no", status = 0)
}
mat <- read_abundance_table(bact_table)
aligned <- align_inputs(mat, meta)
mat <- aligned$mat
meta <- aligned$meta

covariates <- if (nzchar(group_col) && group_col %in% names(meta)) stats::model.matrix(stats::as.formula(paste0("~", group_col)), data = meta) else matrix(1, nrow = nrow(meta), ncol = 1)

run_method("ConQuR", file.path(result_dir, "conqur_corrected.tsv"), {
  fit <- ConQuR::ConQuR(
    taxa_abund = t(mat),
    batchid = meta[[batch_col]],
    covariates = as.data.frame(meta[, intersect(names(meta), group_col), drop = FALSE]),
    batch_ref = levels(meta[[batch_col]])[1],
    num_core = threads
  )
  corrected <- fit$taxa_corrected %||% fit$corrected_data %||% stop("ConQuR output not recognized")
  ensure_matrix(t(corrected))
})

run_method("MMUPHin", file.path(result_dir, "mmuphin_corrected.tsv"), {
  fit <- MMUPHin::adjust_batch(
    feature_abd = mat,
    batch = meta[[batch_col]],
    covariates = as.data.frame(meta[, intersect(names(meta), group_col), drop = FALSE]),
    control = list(verbose = FALSE)
  )
  corrected <- fit$feature_abd_adj %||% fit$feature_abd %||% fit$adjusted_data %||% stop("MMUPHin output not recognized")
  ensure_matrix(corrected)
})

run_method("ComBat", file.path(result_dir, "combat_corrected.tsv"), {
  combat <- sva::ComBat(dat = baseline_transform(mat), batch = meta[[batch_col]], mod = covariates, par.prior = TRUE, prior.plots = FALSE)
  ensure_matrix(exp(combat) - 1)
})

run_method("ruv3", file.path(result_dir, "ruv3_corrected.tsv"), {
  fit <- MBECS::mbecCorrection(as.data.frame(t(mat)), batch = meta[[batch_col]], method = "RUVIII")
  corrected <- fit$corrected %||% fit$batchCorrected %||% stop("MBECS RUVIII output not recognized")
  ensure_matrix(t(corrected))
})

run_method("PercentileNorm", file.path(result_dir, "pn_corrected.tsv"), {
  fit <- MBECS::mbecCorrection(as.data.frame(t(mat)), batch = meta[[batch_col]], method = "PercentileNorm")
  corrected <- fit$corrected %||% fit$batchCorrected %||% stop("MBECS PercentileNorm output not recognized")
  ensure_matrix(t(corrected))
})

run_method("BatchMeanCentering", file.path(result_dir, "bmc_corrected.tsv"), {
  fit <- MBECS::mbecCorrection(as.data.frame(t(mat)), batch = meta[[batch_col]], method = "BMC")
  corrected <- fit$corrected %||% fit$batchCorrected %||% stop("MBECS BMC output not recognized")
  ensure_matrix(t(corrected))
})

run_method("DEBIAS-M", file.path(result_dir, "debiasm_corrected.tsv"), {
  debiasm_bin <- Sys.which("python")
  if (!nzchar(debiasm_bin)) stop("python executable not available for DEBIAS-M")
  temp_in <- file.path(result_dir, "debiasm_input.tsv")
  temp_meta <- file.path(result_dir, "debiasm_meta.tsv")
  temp_out <- file.path(result_dir, "debiasm_output.tsv")
  readr::write_tsv(tibble::rownames_to_column(as.data.frame(t(mat)), "sample_id"), temp_in)
  readr::write_tsv(meta %>% tibble::rownames_to_column("sample_id"), temp_meta)
  cmd <- c("-m", "debiasm", "--input", temp_in, "--metadata", temp_meta, "--batch-col", batch_col, "--output", temp_out)
  status <- system2(debiasm_bin, cmd)
  if (status != 0 || !file.exists(temp_out)) stop("DEBIAS-M unavailable or failed")
  out <- readr::read_tsv(temp_out, show_col_types = FALSE)
  rn <- out[[1]]
  out <- as.matrix(out[, -1, drop = FALSE])
  rownames(out) <- rn
  ensure_matrix(t(out))
})

readr::write_tsv(bind_rows(summary_rows), file.path(result_dir, "batch_correction_summary.tsv"))
readr::write_tsv(bind_rows(status_log), file.path(result_dir, "batch_correction_status.tsv"))
writeLines("done", file.path(result_dir, "corrected_matrices.done"))
RSCRIPT
)

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 95a_stat_batch_correct.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

mgx_end "batch_correct"
echo "[INFO] Sentinel: ${SENTINEL}"
