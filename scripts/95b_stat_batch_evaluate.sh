#!/usr/bin/env bash
# ==============================================================================
# Script: 95b_stat_batch_evaluate.sh
# Purpose: Evaluate corrected matrices and recommend a batch correction method
# Usage:   bash 95b_stat_batch_evaluate.sh -w WORKDIR -r REPO -m METADATA_CSV
#                                        -b BATCH_COL [-g GROUP_COL] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 95b_stat_batch_evaluate.sh -w WORKDIR -r REPO -m METADATA_CSV
                                      -b BATCH_COL [-g GROUP_COL] [--force]

Required:
  -w  Project work directory
  -r  Repository root
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
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV b:BATCH_COL g:GROUP_COL"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO METADATA_CSV BATCH_COL

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
BATCH_DIR="${WORKDIR}/result/stat/bacteria/batch"
RESULT_DIR="${WORKDIR}/result/stat/bacteria/batch"
LOG_DIR="${WORKDIR}/logs/stat/batch"
SENTINEL="${RESULT_DIR}/evaluation_report.tsv"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/95b_stat_batch_evaluate.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running batch correction evaluation"

export WORKDIR REPO METADATA_CSV BATCH_COL GROUP_COL BACT_TABLE BATCH_DIR RESULT_DIR

set +e
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

required_pkgs <- c("vegan", "cluster", "ggplot2", "patchwork", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(vegan)
  library(cluster)
  library(ggplot2)
  library(patchwork)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

metadata_csv <- Sys.getenv("METADATA_CSV")
batch_col <- Sys.getenv("BATCH_COL")
group_col <- Sys.getenv("GROUP_COL")
bact_table <- Sys.getenv("BACT_TABLE")
batch_dir <- Sys.getenv("BATCH_DIR")
result_dir <- Sys.getenv("RESULT_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

read_metadata <- function(path) {
  meta <- readr::read_csv(path, show_col_types = FALSE)
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)
  meta$sample_id <- as.character(meta$sample_id)
  if (!batch_col %in% names(meta)) {
    message("[INFO] Batch column '", batch_col, "' not found in metadata; skipping batch evaluation (single-batch data assumed)")
    return(NULL)
  }
  rownames(meta) <- meta$sample_id
  meta
}

coerce_numeric_df <- function(df) {
  for (i in seq_along(df)) df[[i]] <- suppressWarnings(as.numeric(df[[i]]))
  df
}

read_matrix_file <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  feature_col <- names(raw)[1]
  sample_cols <- setdiff(names(raw), feature_col)
  raw[sample_cols] <- coerce_numeric_df(raw[sample_cols])
  mat <- as.matrix(raw[, sample_cols, drop = FALSE])
  rownames(mat) <- raw[[feature_col]]
  mat[is.na(mat)] <- 0
  mat
}

load_baseline <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  feature_col <- names(raw)[1]
  numeric_cols <- names(raw)[vapply(raw, function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0, logical(1))]
  sample_cols <- setdiff(numeric_cols, feature_col)
  raw[sample_cols] <- coerce_numeric_df(raw[sample_cols])
  mat <- as.matrix(raw[, sample_cols, drop = FALSE])
  rownames(mat) <- raw[[feature_col]]
  mat[is.na(mat)] <- 0
  mat
}

score_matrix <- function(mat, meta, method) {
  common <- intersect(colnames(mat), rownames(meta))
  mat <- mat[, common, drop = FALSE]
  meta <- meta[common, , drop = FALSE]
  bc <- vegan::vegdist(t(mat + 1e-06), method = "bray")
  batch_fit <- vegan::adonis2(stats::as.formula(paste0("bc ~ `", batch_col, "`")), data = meta)
  batch_r2 <- as.data.frame(batch_fit)$R2[1]
  group_r2 <- NA_real_
  if (nzchar(group_col) && group_col %in% names(meta) && length(unique(meta[[group_col]])) > 1) {
    grp_fit <- vegan::adonis2(stats::as.formula(paste0("bc ~ `", group_col, "`")), data = meta)
    group_r2 <- as.data.frame(grp_fit)$R2[1]
  }
  ord <- stats::cmdscale(bc, k = 2)
  sil <- tryCatch({
    mean(cluster::silhouette(as.integer(as.factor(meta[[batch_col]])), dist(ord))[, "sil_width"], na.rm = TRUE)
  }, error = function(e) NA_real_)
  tibble(method = method, batch_R2 = batch_r2, group_R2 = group_r2, silhouette = sil)
}

plot_pcoa <- function(mat, meta, title) {
  common <- intersect(colnames(mat), rownames(meta))
  mat <- mat[, common, drop = FALSE]
  meta <- meta[common, , drop = FALSE]
  bc <- vegan::vegdist(t(mat + 1e-06), method = "bray")
  ord <- stats::cmdscale(bc, k = 2)
  df <- tibble(sample_id = rownames(ord), Axis1 = ord[, 1], Axis2 = ord[, 2], batch = meta[[batch_col]], group = if (nzchar(group_col) && group_col %in% names(meta)) meta[[group_col]] else "NA")
  ggplot(df, aes(Axis1, Axis2, color = batch, shape = group)) +
    geom_point(size = 2.4, alpha = 0.85) +
    theme_bw(base_size = 10) +
    labs(title = title, color = batch_col, shape = if (nzchar(group_col)) group_col else "group")
}

meta <- read_metadata(metadata_csv)
if (is.null(meta)) {
  message("[INFO] No batch column found; writing placeholder evaluation report and exiting (single-batch data)")
  readr::write_tsv(
    tibble(method = "uncorrected", batch_R2 = NA_real_, group_R2 = NA_real_, silhouette = NA_real_),
    file.path(result_dir, "evaluation_report.tsv")
  )
  quit(save = "no", status = 0)
}
matrices <- list(uncorrected = load_baseline(bact_table))
corrected_files <- Sys.glob(file.path(batch_dir, "*_corrected.tsv"))
for (fp in corrected_files) {
  nm <- gsub("_corrected\\.tsv$", "", basename(fp))
  matrices[[nm]] <- read_matrix_file(fp)
}

scores <- bind_rows(lapply(names(matrices), function(nm) score_matrix(matrices[[nm]], meta, nm)))
if (nrow(scores) == 0) stop("No matrices available for evaluation")
scores <- scores %>%
  dplyr::mutate(
    batch_component = dplyr::min_rank(batch_R2),
    group_component = dplyr::min_rank(dplyr::desc(replace_na(group_R2, -Inf))),
    rank = dplyr::min_rank(batch_component + group_component)
  ) %>%
  dplyr::arrange(rank, batch_R2, dplyr::desc(group_R2))

readr::write_tsv(scores, file.path(result_dir, "evaluation_report.tsv"))

top3 <- head(scores$method, 3)
before_after_plots <- lapply(top3, function(nm) plot_pcoa(matrices[[nm]], meta, paste("PCoA:", nm)))
if (length(before_after_plots) > 0) {
  combo <- patchwork::wrap_plots(before_after_plots, ncol = 1)
  ggsave(file.path(result_dir, "batch_pcoa_top3.pdf"), combo, width = 10, height = 8)
}

cat(scores$method[1], "\n")
RSCRIPT
)

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 95b_stat_batch_evaluate.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Recommended batch method:"
awk 'NR==2{print $1}' "${SENTINEL}" 2>/dev/null || true
mgx_end "batch_evaluate"
