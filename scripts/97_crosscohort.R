#!/usr/bin/env Rscript
# ==============================================================================
# Script: 97_crosscohort.R
# Purpose: Cross-cohort validation (external + in-sample roles) of the SIAMCAT
#          model trained by script 96, plus 8 visualizations.
#
# Defect batch P3-U-01..P3-U-05 (2026-09-30):
#   U-01 positive class is read from the trained model's label object
#       (label$model$info == 1; identical to 96's levels()[2] rule because 96
#       passes case=levels(label)[2] into siamcat()). A cohort whose label set
#       differs from the training classes fails hard.
#   U-02 every pROC::roc() call uses explicit levels=c(control, case) and
#       direction="<", so a bad model reports AUC < 0.5 instead of being
#       silently auto-flipped above 0.5.
#   U-03 the training cohort is predicted with role=in_sample and excluded
#       from external aggregation; --test-cohorts is consumed (explicit test
#       set, default = all loaded cohorts except train); MMUPHin batch
#       correction is retained but reported as "computed including the
#       training cohort".
#   U-04 T-11 failure semantics: prediction/plot failures write
#       crosscohort_FAILED.txt and quit(status=1); the done sentinel is
#       written LAST, after every declared output exists. Upstream 96 SKIPPED
#       => explicit SKIPPED sentinel + header-only tables + exit 0.
#   U-05 the PCoA cohort vector no longer clobbers the per-cohort label list
#       used by the calibration section.
#
# W2 batch (2026-09-30, supervisor W1 review + user decision #2):
#   W2-1 (user decision #2) UNCORRECTED is the PRIMARY result
#       (batch_correction=none); the MMUPHin-corrected matrix is co-reported
#       as a SENSITIVITY arm (batch_correction=mmuphin). Both arms are rows
#       in auc_summary.tsv / crosscohort_metrics.tsv; plots, the external
#       pooled line and the meta-analysis use the primary (none) arm only.
#       --no-mmuphin (MMUPHIN_SENSITIVITY=0) disables the sensitivity arm.
#   W2-2 (P3-U-08) meta-analysis SE on logit scale via delta method:
#       se_logit = (ci_high - ci_low) / 3.92 / (auc * (1 - auc)); rows with
#       logit-unbounded AUC/CI (AUC == 0/1, CI touching 0/1) are dropped
#       with an INFO note instead of crashing.
#   W2-3 (P3-U-09) sample IDs shared across cohorts fail hard (duplicate ID +
#       conflicting cohort names in the message).
#   W2-4 metrics table gains n_features_zero_filled per cohort (taxa the
#       frozen normalization zero-fills because the cohort lacks them).
#   W2-5 when the MMUPHin arm runs, mmuphin_colsums.tsv records per-sample
#       colSums before/after correction (consistency evidence).
# ==============================================================================

options(stringsAsFactors = FALSE, warn = 1)

options(device = function(...) grDevices::pdf(file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...))

# Same lib-path fix as script 96: Rlib/ (R_LIBS_USER) carries a Matrix build
# with an incompatible ABI against the conda R, which breaks loading of
# SIAMCAT/PRROC namespaces. Prefer the conda env library first.
conda_r_lib <- file.path(R.home("home"), "library")
project_r_lib <- Sys.getenv("R_LIBS_USER", unset = "")
lib_paths <- .libPaths()
if (nzchar(project_r_lib)) {
  lib_paths <- lib_paths[normalizePath(lib_paths, winslash = "/", mustWork = FALSE) !=
    normalizePath(project_r_lib, winslash = "/", mustWork = FALSE)]
}
if (dir.exists(conda_r_lib)) .libPaths(unique(c(conda_r_lib, lib_paths)))

# Load required packages
suppressPackageStartupMessages({
  library(SIAMCAT)
  library(tidyverse)
  library(pROC)
  library(metafor)
  library(forestplot)
  library(UpSetR)
  library(ComplexHeatmap)
  library(patchwork)
  library(GGally)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

# Read environment variables
workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
source_mode <- Sys.getenv("SOURCE", "local")
cohorts_str <- Sys.getenv("COHORTS")
train_cohort <- Sys.getenv("TRAIN_COHORT")
test_cohorts_str <- Sys.getenv("TEST_COHORTS", "")
condition <- Sys.getenv("CONDITION", "CRC")
meta_analysis <- as.logical(as.integer(Sys.getenv("META_ANALYSIS", "0")))
mmuphin_sensitivity <- as.logical(as.integer(Sys.getenv("MMUPHIN_SENSITIVITY", "1")))
ml_dir <- Sys.getenv("ML_DIR")
result_dir <- Sys.getenv("RESULT_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

SENTINEL_FILE <- file.path(result_dir, "crosscohort_done.txt")
FAILED_FILE <- file.path(result_dir, "crosscohort_FAILED.txt")
MMUPHIN_COLSUMS_FILE <- file.path(result_dir, "mmuphin_colsums.tsv")
# W2-1: uncorrected predictions are the primary result; the MMUPHin arm is a
# co-reported sensitivity analysis.
PRIMARY_ARM <- "none"
AUC_SUMMARY_HEADER <- c("cohort", "role", "batch_correction", "auc", "auc_ci_low",
                        "auc_ci_high", "n_case", "n_control", "n_samples")
METRICS_HEADER <- c("cohort", "role", "batch_correction", "decision_threshold",
                    "n_samples", "n_case", "n_control", "auroc", "auc_ci_low",
                    "auc_ci_high", "auprc", "sensitivity", "specificity", "ppv",
                    "n_features_zero_filled")

write_header_only <- function(path, header) {
  writeLines(paste(header, collapse = "\t"), path)
}

# T-11 semantics: explicit FAILED marker, sentinel removed, non-zero exit.
fail_hard <- function(step, message) {
  msg <- as.character(message)[1]
  cat("[FATAL] step", step, "failed:", msg, "\n")
  writeLines(c(
    paste0("step: ", step),
    "status: FAILED",
    paste0("message: ", msg),
    paste0("timestamp: ", Sys.time())
  ), FAILED_FILE)
  if (file.exists(SENTINEL_FILE)) file.remove(SENTINEL_FILE)
  quit(status = 1)
}

# Upstream (script 96) skipped training => 97 skips explicitly, exit 0,
# but still writes the declared outputs (header-only tables + sentinel).
skip_gracefully <- function(reason) {
  cat("[INFO] SKIPPED:", reason, "\n")
  write_header_only(file.path(result_dir, "auc_summary.tsv"), AUC_SUMMARY_HEADER)
  write_header_only(file.path(result_dir, "crosscohort_metrics.tsv"), METRICS_HEADER)
  writeLines(c(
    paste0("SKIPPED: ", reason),
    paste("Timestamp:", Sys.time()),
    "Upstream SIAMCAT model unavailable; no cross-cohort metrics computed."
  ), SENTINEL_FILE)
  quit(status = 0)
}

cat("[INFO] Starting cross-cohort analysis\n")
cat("  Source mode:", source_mode, "\n")
cat("  Cohorts:", cohorts_str, "\n")
cat("  Train cohort:", train_cohort, "\n")
cat("  Test cohorts (explicit):", if (nzchar(test_cohorts_str)) test_cohorts_str else "<default: all except train>", "\n")
cat("  Primary result arm: uncorrected (batch_correction=", PRIMARY_ARM, ")\n", sep = "")
cat("  MMUPHin sensitivity arm:", if (mmuphin_sensitivity) "enabled" else "disabled (MMUPHIN_SENSITIVITY=0)", "\n")

# ============================================================================
# Load SIAMCAT model from script 96 (or propagate its SKIPPED status)
# ============================================================================

model_file <- file.path(ml_dir, "siamcat_lasso.rds")
ml_sentinel <- file.path(ml_dir, "siamcat_done.txt")

if (!file.exists(model_file)) {
  upstream_skipped <- file.exists(ml_sentinel) &&
    any(grepl("^SKIPPED", readLines(ml_sentinel, warn = FALSE)))
  if (upstream_skipped) {
    skip_gracefully(paste("upstream SIAMCAT training skipped (see", ml_sentinel, ")"))
  }
  fail_hard("load_model", paste0("SIAMCAT model not found: ", model_file, " (run script 96 first)"))
}

siamcat_model <- readRDS(model_file)
cat("[INFO] Loaded SIAMCAT model from:", model_file, "\n")

# ============================================================================
# P3-U-01: positive class from the model's own label object
# ============================================================================

model_label <- tryCatch(SIAMCAT::label(siamcat_model), error = function(e) NULL)
if (is.null(model_label)) fail_hard("positive_class", "cannot read label() from the trained model")
if (!identical(model_label$type, "BINARY")) {
  fail_hard("positive_class", paste("model label type is", model_label$type, "- binary required"))
}
lab_info <- model_label$info
positive_level <- names(lab_info)[lab_info == 1]
negative_level <- names(lab_info)[lab_info == -1]
if (length(positive_level) != 1 || length(negative_level) != 1) {
  fail_hard("positive_class", "cannot determine positive/negative classes from model label$info")
}
cat("[INFO] Positive (case) class from model:", positive_level, "\n")
cat("[INFO] Negative (control) class from model:", negative_level, "\n")

# Features the frozen holdout normalization requires to be present.
norm_retained <- tryCatch(SIAMCAT::norm_params(siamcat_model)$retained.feat,
                          error = function(e) character(0))

# ============================================================================
# Helper Functions
# ============================================================================

coerce_numeric_matrix <- function(abund) {
  mat <- apply(abund, c(1, 2), function(x) suppressWarnings(as.numeric(x)))
  mat[is.na(mat)] <- 0
  mat
}

load_local_cohort <- function(cohort_name, parent_dir) {
  cat("[INFO] Loading local cohort:", cohort_name, "\n")
  cohort_path <- file.path(parent_dir, cohort_name)

  # Load abundance table (bacteria from MetaPhlAn4)
  abund_file <- file.path(cohort_path, "result/metaphlan4/merged/taxonomy.tsv")
  if (!file.exists(abund_file)) {
    fail_hard("load_cohort", paste0("abundance file not found for cohort ", cohort_name, ": ", abund_file))
  }

  abund <- read_tsv(abund_file, show_col_types = FALSE, comment = "#")
  # Assume first column is taxon, rest are samples
  taxa <- abund[[1]]
  abund_mat <- coerce_numeric_matrix(as.matrix(abund[, -1, drop = FALSE]))
  rownames(abund_mat) <- taxa
  # MetaPhlAn merged tables can carry duplicated taxon rows: sum them (same
  # rule as 96's read_abundance_table)
  if (anyDuplicated(rownames(abund_mat))) {
    abund_mat <- rowsum(abund_mat, group = rownames(abund_mat))
  }
  abund_mat <- abund_mat[rowSums(abund_mat) > 0, , drop = FALSE]

  # Load metadata
  meta_file <- file.path(cohort_path, basename(metadata_csv))
  if (!file.exists(meta_file)) {
    meta_file <- metadata_csv  # fallback to global metadata
  }
  meta <- read_csv(meta_file, show_col_types = FALSE)

  # Filter samples present in both
  common_samples <- intersect(colnames(abund_mat), meta$sample_id)
  if (length(common_samples) == 0) {
    fail_hard("load_cohort", paste0("no common samples between abundance and metadata for cohort ", cohort_name))
  }

  abund_mat <- abund_mat[, common_samples, drop = FALSE]
  meta <- meta %>% filter(sample_id %in% common_samples)

  # Add cohort label
  meta$cohort <- cohort_name

  list(abundance = abund_mat, metadata = meta, cohort = cohort_name)
}

load_curated_cohort <- function(dataset_name) {
  cat("[INFO] Loading curatedMetagenomicData:", dataset_name, "\n")

  if (!requireNamespace("curatedMetagenomicData", quietly = TRUE)) {
    fail_hard("load_cohort", "package curatedMetagenomicData not available (requires network)")
  }

  tryCatch({
    eset <- curatedMetagenomicData::curatedMetagenomicData(
      dataset_name, dryrun = FALSE, counts = FALSE, rownames = "short"
    )
    obj <- eset[[1]]
    abund <- Biobase::exprs(obj)
    meta <- Biobase::pData(obj)
    meta$sample_id <- rownames(meta)
    meta$cohort <- dataset_name

    list(abundance = abund, metadata = meta, cohort = dataset_name)
  }, error = function(e) {
    fail_hard("load_cohort", paste0("failed to load ", dataset_name, ": ", conditionMessage(e)))
  })
}

# P3-U-09: a sample ID shared by two loaded cohorts would silently alias
# samples in the merged matrix, the MMUPHin batch vector and every
# per-cohort table keyed by sample name - fatal, with the conflicting
# cohorts named in the message.
assert_no_duplicate_samples <- function(cohort_list) {
  all_ids <- unlist(lapply(cohort_list, function(x) colnames(x$abundance)),
                    use.names = FALSE)
  if (anyDuplicated(all_ids) == 0) return(invisible(TRUE))
  owner_of <- unlist(lapply(cohort_list, function(x) {
    stats::setNames(rep(x$cohort, ncol(x$abundance)), colnames(x$abundance))
  }), use.names = FALSE)
  names(owner_of) <- all_ids
  dup_ids <- unique(all_ids[duplicated(all_ids)])
  conflicts <- vapply(dup_ids, function(id) {
    paste0(id, " [", paste(unique(owner_of[all_ids == id]), collapse = " & "), "]")
  }, FUN.VALUE = character(1))
  fail_hard("duplicate_samples", paste0(
    "sample IDs shared across cohorts: ", paste(conflicts, collapse = "; "),
    " - cohort sample IDs must be disjoint"))
}

# P3-U-03: retained but annotated - the correction is computed jointly across
# all loaded cohorts, INCLUDING the training cohort. W2-1: this is now the
# SENSITIVITY arm; the primary result is computed on the uncorrected input.
# Failures fall back to the primary arm only with an explicit note (never
# silently reported as corrected).
perform_batch_correction <- function(cohort_list, train_cohort_name) {
  note <- "skipped_single_cohort"
  if (length(cohort_list) < 2) {
    cat("[INFO] Batch correction skipped: single cohort\n")
    return(list(cohorts = cohort_list, note = note))
  }
  if (!requireNamespace("MMUPHin", quietly = TRUE)) {
    cat("[INFO] MMUPHin not available, skipping batch correction\n")
    return(list(cohorts = cohort_list, note = "skipped_no_mmuphin"))
  }

  cat("[INFO] Performing batch correction across cohorts (SENSITIVITY arm)\n")
  cat("[INFO] NOTE: batch correction is computed jointly INCLUDING the training cohort (",
      train_cohort_name, ") - sensitivity metrics are conditional on this correction\n", sep = "")

  # Merge all abundance matrices. unname(): unlist() attaches a names
  # attribute that would propagate through dimnames and fail MMUPHin's
  # identical()-based sample-name check ("Sample names ... don't agree").
  all_samples <- unname(unlist(lapply(cohort_list, function(x) colnames(x$abundance))))
  all_taxa <- unique(unlist(lapply(cohort_list, function(x) rownames(x$abundance))))

  merged_mat <- matrix(0, nrow = length(all_taxa), ncol = length(all_samples),
                       dimnames = list(all_taxa, all_samples))

  for (cohort_data in cohort_list) {
    mat <- cohort_data$abundance
    merged_mat[rownames(mat), colnames(mat)] <- mat
  }

  # Create batch vector
  batch_vec <- unname(unlist(lapply(cohort_list, function(x) {
    rep(x$cohort, ncol(x$abundance))
  })))
  names(batch_vec) <- all_samples

  tryCatch({
    corrected <- MMUPHin::adjust_batch(
      feature_abd = merged_mat,
      batch = "batch",
      data = data.frame(batch = factor(batch_vec), row.names = all_samples),
      # diagnostic_plot = NULL: MMUPHin otherwise drops adjust_batch_diagnostic.pdf
      # into the session cwd (= WORKDIR) as an undeclared side effect
      control = list(verbose = FALSE, diagnostic_plot = NULL)
    )
    corrected_mat <- corrected$feature_abd_adj %||% merged_mat

    # W2-5: per-sample colSums before/after correction - consistency
    # evidence that the adjustment did (or did not) shift sample totals.
    cs_before <- colSums(merged_mat)
    cs_after <- colSums(corrected_mat)[colnames(merged_mat)]
    colsums_df <- tibble(
      sample_id = colnames(merged_mat),
      cohort = unname(batch_vec[colnames(merged_mat)]),
      colsum_before = as.numeric(cs_before),
      colsum_after = as.numeric(cs_after)
    )
    write_tsv(colsums_df, MMUPHIN_COLSUMS_FILE)
    cat("[INFO] MMUPHin colSums evidence (before/after) written:", MMUPHIN_COLSUMS_FILE, "\n")

    # Split back to cohorts
    for (i in seq_along(cohort_list)) {
      samples <- colnames(cohort_list[[i]]$abundance)
      cohort_list[[i]]$abundance <- corrected_mat[, samples, drop = FALSE]
    }

    cat("[INFO] Batch correction completed (included training cohort)\n")
    note <- paste0("MMUPHin_adjust_batch (computed including training cohort ", train_cohort_name, ")")
  }, error = function(e) {
    note <<- paste0("failed_no_correction (", conditionMessage(e)[1], ")")
    cat("[WARN] Batch correction failed, continuing with UNCORRECTED input:", conditionMessage(e), "\n")
  })

  list(cohorts = cohort_list, note = note)
}

# Top model features by |weight|. SIAMCAT 2.x feature_weights() returns a
# data.frame (rows = features); abs() on it errors ("cannot xtfrm data
# frames"), so extract the weight vector explicitly.
model_top_features <- function(siamcat_obj, n) {
  fw <- SIAMCAT::feature_weights(siamcat_obj)
  wts <- fw$mean.weight
  wts[is.na(wts)] <- 0
  names(wts) <- rownames(fw)
  n_eff <- min(n, length(wts))
  names(sort(abs(wts), decreasing = TRUE))[seq_len(n_eff)]
}

# ============================================================================
# Main Analysis
# ============================================================================

# Load cohorts based on source mode
cohort_list <- list()

if (source_mode == "local") {
  cohort_names <- trimws(strsplit(cohorts_str, ",")[[1]])
  cohort_names <- cohort_names[nzchar(cohort_names)]
  parent_dir <- dirname(workdir)

  # P3-U-03: the training cohort is always loaded (its prediction is reported
  # as role=in_sample); --cohorts without it is not an error.
  if (!(train_cohort %in% cohort_names)) {
    cohort_names <- c(train_cohort, cohort_names)
    cat("[INFO] Train cohort", train_cohort, "not in --cohorts; loading it additionally\n")
  }

  for (cohort_name in cohort_names) {
    cohort_list[[cohort_name]] <- load_local_cohort(cohort_name, parent_dir)
    assert_no_duplicate_samples(cohort_list)  # P3-U-09
  }

} else if (source_mode == "curated") {
  # curatedMetagenomicData datasets
  dataset_map <- list(
    CRC = c("WirbelJ_2019.metaphlan_bugs_list.stool",
            "ThomasAM_2019_a.metaphlan_bugs_list.stool",
            "ZellerG_2014.metaphlan_bugs_list.stool"),
    T2D = c("QinJ_2012.metaphlan_bugs_list.stool",
            "KarlssonFH_2013.metaphlan_bugs_list.stool"),
    IBD = c("NielsenHB_2014.metaphlan_bugs_list.stool",
            "PasolliE_2016.metaphlan_bugs_list.stool")
  )

  datasets <- dataset_map[[condition]] %||% dataset_map$CRC
  for (ds in datasets) {
    cohort_list[[ds]] <- load_curated_cohort(ds)
    assert_no_duplicate_samples(cohort_list)  # P3-U-09
  }
  if (identical(train_cohort, "first_available") || !nzchar(train_cohort)) {
    train_cohort <- names(cohort_list)[1]
  }
} else {
  fail_hard("config", paste0("unknown SOURCE mode: ", source_mode))
}

if (length(cohort_list) == 0) {
  fail_hard("load_cohort", "no cohorts loaded")
}
if (!(train_cohort %in% names(cohort_list))) {
  fail_hard("config", paste0("train cohort not loaded: ", train_cohort))
}

cat("[INFO] Loaded", length(cohort_list), "cohorts:\n")
for (name in names(cohort_list)) {
  n_samples <- ncol(cohort_list[[name]]$abundance)
  cat("  -", name, ":", n_samples, "samples\n")
}

# ----------------------------------------------------------------------------
# P3-U-03: roles - train cohort is in_sample; explicit --test-cohorts selects
# the external set (default: all loaded cohorts except train). Cohorts that
# are neither train nor test are dropped with an explicit notice.
# ----------------------------------------------------------------------------
if (nzchar(test_cohorts_str)) {
  test_cohorts <- trimws(strsplit(test_cohorts_str, ",")[[1]])
  test_cohorts <- test_cohorts[nzchar(test_cohorts)]
} else {
  test_cohorts <- setdiff(names(cohort_list), train_cohort)
}
test_cohorts <- setdiff(test_cohorts, train_cohort)  # train is never external

missing_test <- setdiff(test_cohorts, names(cohort_list))
if (length(missing_test) > 0) {
  fail_hard("config", paste0("--test-cohorts not loaded (missing/unloadable): ",
                             paste(missing_test, collapse = ", ")))
}
dropped <- setdiff(names(cohort_list), c(train_cohort, test_cohorts))
if (length(dropped) > 0) {
  cat("[INFO] Cohorts neither train nor test - not evaluated:", paste(dropped, collapse = ", "), "\n")
}
eval_cohorts <- intersect(names(cohort_list), c(train_cohort, test_cohorts))
cohort_roles <- stats::setNames(
  ifelse(eval_cohorts == train_cohort, "in_sample", "external"),
  eval_cohorts
)
cat("[INFO] Roles - train:", train_cohort, "| external:",
    if (length(test_cohorts) > 0) paste(test_cohorts, collapse = ", ") else "(none)", "\n")

# W2-1 (user decision #2): the UNCORRECTED input is the primary arm; the
# MMUPHin-corrected matrices are a co-reported sensitivity arm. cohort_list
# itself stays uncorrected (it feeds the primary arm and the descriptive
# plots); the correction runs on a shallow copy - R copy-on-modify semantics
# keep the raw matrices untouched.
arms <- list(none = cohort_list)
if (mmuphin_sensitivity) {
  bc <- perform_batch_correction(lapply(cohort_list, function(x) x), train_cohort)
  batch_correction_note <- bc$note
  if (startsWith(bc$note, "MMUPHin")) arms$mmuphin <- bc$cohorts
} else {
  batch_correction_note <- "disabled (MMUPHIN_SENSITIVITY=0)"
}
cat("[INFO] Analysis arms:", paste(names(arms), collapse = ", "),
    "- primary:", PRIMARY_ARM, "| MMUPHin sensitivity arm:", batch_correction_note, "\n")

# ============================================================================
# Model Transfer & Prediction (P3-U-04: failures are fatal, never warnings)
# ============================================================================

cat("[INFO] Performing model transfer and prediction\n")

cohort_results <- list()      # arm -> cohort -> auc tibble (W2-1)
cohort_metrics <- list()      # arm -> cohort -> metrics tibble (W2-1)
cohort_predictions <- list()  # arm -> cohort -> named prediction vector
cohort_labels <- list()       # arm -> cohort -> named label vector

DECISION_THRESHOLD <- 0.5

for (cohort_name in eval_cohorts) {
  cat("[INFO] Predicting on cohort:", cohort_name, "(role:", cohort_roles[[cohort_name]], ")\n")

  meta <- cohort_list[[cohort_name]]$metadata

  # P3-U-01: label set must match the training classes exactly.
  # Label validation is arm-independent (metadata is shared across arms).
  true_labels <- meta[[group_col]]
  names(true_labels) <- as.character(meta$sample_id)
  if (is.null(true_labels) || all(is.na(true_labels))) {
    fail_hard(paste0("labels_", cohort_name),
              paste0("group column '", group_col, "' missing or all NA in cohort ", cohort_name))
  }
  keep <- !is.na(true_labels)
  if (any(!keep)) cat("[INFO] ", cohort_name, ": dropping ", sum(!keep), " sample(s) with NA labels\n", sep = "")
  true_labels <- true_labels[keep]
  meta <- meta[keep, , drop = FALSE]
  kept_ids <- as.character(meta$sample_id)

  unexpected <- setdiff(unique(true_labels), c(positive_level, negative_level))
  if (length(unexpected) > 0) {
    fail_hard(paste0("labels_", cohort_name),
              paste0("label set of cohort ", cohort_name, " does not match training classes (case=",
                     positive_level, ", control=", negative_level, "); unexpected: ",
                     paste(unexpected, collapse = ", ")))
  }
  n_case <- sum(true_labels == positive_level)
  n_control <- sum(true_labels == negative_level)
  if (n_case < 1 || n_control < 1) {
    fail_hard(paste0("labels_", cohort_name),
              paste0("cohort ", cohort_name, " needs >=1 sample per class (case=", n_case,
                     ", control=", n_control, ")"))
  }

  # W2-4: model-retained taxa absent from this cohort's RAW matrix - the
  # count the frozen normalization zero-fills. A property of cohort vs
  # model, so the same value stamps every arm's rows.
  n_zero_filled <- length(setdiff(norm_retained,
                                  rownames(cohort_list[[cohort_name]]$abundance)))
  if (n_zero_filled > 0) {
    cat("[INFO] ", cohort_name, ": ", n_zero_filled,
        " model feature(s) absent from this cohort (zero-filled by frozen normalization)\n", sep = "")
  }

  meta_df <- as.data.frame(meta)
  rownames(meta_df) <- as.character(meta_df$sample_id)

  for (arm_name in names(arms)) {
    abund <- arms[[arm_name]][[cohort_name]]$abundance[, kept_ids, drop = FALSE]

    tryCatch({
      # Frozen normalization requires every training-retained feature to exist in
      # the holdout matrix: zero-fill taxa absent from this cohort.
      union_feats <- union(rownames(abund), norm_retained)
      filled <- matrix(0, nrow = length(union_feats), ncol = ncol(abund),
                       dimnames = list(union_feats, colnames(abund)))
      filled[rownames(abund), ] <- abund

      holdout_obj <- SIAMCAT::siamcat(
        feat = filled, meta = meta_df,
        label = group_col, case = positive_level, verbose = 0
      )
      pred_obj <- SIAMCAT::make.predictions(
        siamcat = siamcat_model, siamcat.holdout = holdout_obj,
        normalize.holdout = TRUE, verbose = 0
      )

      pred_matrix <- SIAMCAT::pred_matrix(pred_obj)
      pred_vector <- rowMeans(pred_matrix, na.rm = TRUE)
      if (all(is.na(pred_vector))) {
        fail_hard(paste0("predict_", cohort_name, "_", arm_name), "predictions are all NA")
      }

      # Align predictions and labels BY SAMPLE NAME (never by position)
      common_ids <- sort(intersect(names(pred_vector), names(true_labels)))
      if (length(common_ids) == 0) {
        fail_hard(paste0("align_", cohort_name), "no overlapping sample names between predictions and labels")
      }
      if (length(common_ids) < length(pred_vector)) {
        cat("[INFO] ", cohort_name, ": ", length(pred_vector) - length(common_ids),
            " prediction(s) without metadata label dropped\n", sep = "")
      }
      pred_vector <- pred_vector[common_ids]
      y_labels <- true_labels[common_ids]

      # P3-U-02: explicit levels/direction - no auto-flip of bad models
      roc_obj <- pROC::roc(response = y_labels, predictor = pred_vector,
                           levels = c(negative_level, positive_level),
                           direction = "<", quiet = TRUE)
      auc_val <- as.numeric(pROC::auc(roc_obj))
      ci_val <- as.numeric(pROC::ci.auc(roc_obj))

      y01 <- as.integer(y_labels == positive_level)
      auprc_val <- NA_real_
      if (requireNamespace("PRROC", quietly = TRUE)) {
        pr_obj <- PRROC::pr.curve(scores.class0 = pred_vector,
                                  weights.class0 = y01, curve = FALSE)
        auprc_val <- as.numeric(pr_obj$auc.integral)
      }

      pred_class <- as.integer(pred_vector >= DECISION_THRESHOLD)
      tp <- sum(pred_class == 1 & y01 == 1); fn <- sum(pred_class == 0 & y01 == 1)
      fp <- sum(pred_class == 1 & y01 == 0); tn <- sum(pred_class == 0 & y01 == 0)

      cohort_results[[arm_name]][[cohort_name]] <- tibble(
        cohort = cohort_name,
        role = cohort_roles[[cohort_name]],
        batch_correction = arm_name,
        auc = auc_val,
        auc_ci_low = ci_val[1],
        auc_ci_high = ci_val[3],
        n_case = n_case,
        n_control = n_control,
        n_samples = length(common_ids)
      )

      cohort_metrics[[arm_name]][[cohort_name]] <- tibble(
        cohort = cohort_name,
        role = cohort_roles[[cohort_name]],
        batch_correction = arm_name,
        decision_threshold = DECISION_THRESHOLD,
        n_samples = length(common_ids),
        n_case = n_case,
        n_control = n_control,
        auroc = auc_val,
        auc_ci_low = ci_val[1],
        auc_ci_high = ci_val[3],
        auprc = auprc_val,
        sensitivity = if (tp + fn > 0) tp / (tp + fn) else NA_real_,
        specificity = if (tn + fp > 0) tn / (tn + fp) else NA_real_,
        ppv = if (tp + fp > 0) tp / (tp + fp) else NA_real_,
        n_features_zero_filled = n_zero_filled
      )

      cohort_predictions[[arm_name]][[cohort_name]] <- pred_vector
      cohort_labels[[arm_name]][[cohort_name]] <- y_labels

      # Per-cohort ROC pdf: primary arm only, so file names stay stable; the
      # sensitivity arm is fully represented in the tables (W2-1).
      if (identical(arm_name, PRIMARY_ARM)) {
        pdf(file.path(result_dir, paste0(gsub("[^A-Za-z0-9]+", "_", cohort_name), "_roc.pdf")),
            width = 6, height = 6)
        plot(roc_obj, main = paste("ROC Curve:", cohort_name),
             col = "#d73027", lwd = 2)
        text(0.6, 0.2, sprintf("AUC = %.3f", auc_val), cex = 1.2)
        dev.off()
      }

      cat("    [", arm_name, "] AUC =", round(auc_val, 3), "| AUPRC =", round(auprc_val, 3),
          "| sens =", round(tp / (tp + fn), 3), "| spec =", round(tn / (tn + fp), 3),
          "| PPV =", round(if (tp + fp > 0) tp / (tp + fp) else NA, 3), "\n")
    }, error = function(e) {
      fail_hard(paste0("predict_", cohort_name, "_", arm_name), conditionMessage(e))
    })
  }
}

# Combine results (P3-U-04: empty tables are a failure, not a silent success).
# W2-1: both arms are rows of the tables; the primary (uncorrected) arm
# drives the pooled line, the plots and the meta-analysis.
results_df <- bind_rows(lapply(cohort_results, bind_rows))
metrics_df <- bind_rows(lapply(cohort_metrics, bind_rows))
if (nrow(results_df) == 0 || nrow(metrics_df) == 0) {
  fail_hard("summarize", "no per-cohort results produced")
}
write_tsv(results_df, file.path(result_dir, "auc_summary.tsv"))
write_tsv(metrics_df, file.path(result_dir, "crosscohort_metrics.tsv"))

results_primary <- results_df %>% filter(batch_correction == PRIMARY_ARM)
external_df <- metrics_df %>% filter(role == "external", batch_correction == PRIMARY_ARM)
external_summary_line <- if (nrow(external_df) > 0) {
  paste0(sprintf("External cohorts pooled mean AUROC = %.3f (k=%d, threshold=%.1f, primary arm=%s)",
                 mean(external_df$auroc), nrow(external_df), DECISION_THRESHOLD, PRIMARY_ARM))
} else {
  "0 external cohorts - in-sample only run (training cohort excluded from external aggregation by design)"
}

cat("[INFO] Cross-cohort AUC summary (batch_correction column: primary =",
    PRIMARY_ARM, "; mmuphin rows are the sensitivity arm; role marks the training cohort in_sample):\n")
print(results_df)
cat("[INFO]", external_summary_line, "\n")

# ============================================================================
# Visualization 1: Forest Plot (AUC) - primary (uncorrected) arm (W2-1)
# ============================================================================

cat("[INFO] Generating forest plot for AUC\n")

if (nrow(results_primary) > 0) {
  tryCatch({
    pdf(file.path(result_dir, "forest_plot_auc.pdf"), width = 10, height = max(6, nrow(results_primary) * 0.8))

    forest_data <- results_primary %>%
      mutate(
        mean = auc,
        lower = auc_ci_low,
        upper = auc_ci_high,
        cohort_label = paste0(cohort, " [", role, "] (n=", n_samples, ")")
      )

    forestplot::forestplot(
      labeltext = forest_data$cohort_label,
      mean = forest_data$mean,
      lower = forest_data$lower,
      upper = forest_data$upper,
      title = "Cross-Cohort AUC Comparison",
      xlab = "AUC (95% CI)",
      boxsize = 0.3,
      col = forestplot::fpColors(box = "#4575b4", line = "#4575b4"),
      xlog = FALSE,
      # U-02 扩展(监工 P0-2): 0.5-1.0 clip 会把 AUC<0.5 的差模型整段裁出图外,
      # 在图上抵消方向修复——改为全量程并加 0.5 参考线(grid=1)
      xticks = seq(0, 1.0, 0.1),
      clip = c(0, 1.0),
      grid = c(0.5, 1),
      grid.col = "gray60"
    )

    dev.off()
  }, error = function(e) fail_hard("plot_forest", conditionMessage(e)))
}

# ============================================================================
# Visualization 2: Waterfall Plot (AUC) - primary (uncorrected) arm (W2-1)
# ============================================================================

cat("[INFO] Generating waterfall plot for AUC\n")

if (nrow(results_primary) > 0) {
  tryCatch({
    p <- ggplot(results_primary %>% arrange(desc(auc)),
                aes(x = reorder(cohort, auc), y = auc, fill = role)) +
      geom_col(width = 0.7) +
      geom_errorbar(aes(ymin = auc_ci_low, ymax = auc_ci_high), width = 0.3) +
      geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey50") +
      coord_flip() +
      ylim(0, 1) +
      scale_fill_manual(values = c(external = "#4575b4", in_sample = "grey60")) +
      theme_bw(base_size = 12) +
      labs(x = NULL, y = "AUC", title = "Cross-Cohort AUC Waterfall", fill = NULL) +
      theme(panel.grid.major.y = element_blank())

    ggsave(file.path(result_dir, "waterfall_auc.pdf"), p,
           width = 8, height = max(4, nrow(results_df) * 0.5), units = "in", dpi = 300)
  }, error = function(e) fail_hard("plot_waterfall", conditionMessage(e)))
}

# ============================================================================
# Visualization 3: ROC Overlay (All Cohorts) - primary (uncorrected) arm (W2-1)
# ============================================================================

cat("[INFO] Generating ROC overlay plot\n")

if (length(cohort_predictions[[PRIMARY_ARM]]) > 0) {
  tryCatch({
    roc_list <- list()

    for (cohort_name in names(cohort_predictions[[PRIMARY_ARM]])) {
      pred <- cohort_predictions[[PRIMARY_ARM]][[cohort_name]]
      label <- cohort_labels[[PRIMARY_ARM]][[cohort_name]]

      # P3-U-02: explicit levels/direction here as well
      roc_obj <- pROC::roc(response = label, predictor = pred,
                           levels = c(negative_level, positive_level),
                           direction = "<", quiet = TRUE)
      auc_val <- as.numeric(pROC::auc(roc_obj))

      roc_list[[cohort_name]] <- list(
        roc = roc_obj,
        auc = auc_val,
        cohort = cohort_name
      )
    }

    # Plot
    pdf(file.path(result_dir, "roc_overlay_all_cohorts.pdf"), width = 8, height = 8)
    plot(NULL, xlim = c(0, 1), ylim = c(0, 1), xlab = "False Positive Rate",
         ylab = "True Positive Rate", main = "ROC Curves - All Cohorts")
    abline(0, 1, col = "grey60", lty = 2)

    colors <- RColorBrewer::brewer.pal(max(3, min(9, length(roc_list))), "Set1")[seq_along(roc_list)]

    for (i in seq_along(roc_list)) {
      lines(1 - roc_list[[i]]$roc$specificities, roc_list[[i]]$roc$sensitivities,
            col = colors[i], lwd = 2)
    }

    legend("bottomright",
           legend = sapply(roc_list, function(x) sprintf("%s (AUC=%.3f)", x$cohort, x$auc)),
           col = colors[seq_along(roc_list)],
           lwd = 2, cex = 0.9)

    dev.off()
  }, error = function(e) fail_hard("plot_roc_overlay", conditionMessage(e)))
}

# ============================================================================
# Visualization 4: UpSet - Shared Significant Features
# (Visualizations 4-6 and 8 describe the DATA, so they read the uncorrected
#  cohort matrices = the primary arm; W2-1)
# ============================================================================

cat("[INFO] Generating UpSet plot for shared features\n")

if (length(cohort_list) < 2) {
  cat("[INFO] UpSet plot skipped: needs >= 2 cohorts (single-cohort run)\n")
} else {
  tryCatch({
    # Top 50 features from model weights as proxy
    top_features <- model_top_features(siamcat_model, 50)

    # Create binary matrix: cohort x feature (1 if present, 0 if absent)
    upset_list <- lapply(names(cohort_list), function(cohort_name) {
      abund <- cohort_list[[cohort_name]]$abundance
      present_features <- intersect(rownames(abund), top_features)
      present_features
    })
    names(upset_list) <- names(cohort_list)

    # Convert to UpSetR format
    pdf(file.path(result_dir, "upset_shared_features.pdf"), width = 10, height = 6)
    UpSetR::upset(UpSetR::fromList(upset_list),
                  order.by = "freq",
                  nsets = length(upset_list),
                  main.bar.color = "#4575b4",
                  sets.bar.color = "#d73027")
    dev.off()
  }, error = function(e) fail_hard("plot_upset", conditionMessage(e)))
}

# ============================================================================
# Visualization 5: Feature Stability Heatmap
# ============================================================================

cat("[INFO] Generating feature stability heatmap\n")

tryCatch({
  # Calculate feature stability: presence across cohorts
  all_features <- unique(unlist(lapply(cohort_list, function(x) rownames(x$abundance))))

  stability_mat <- matrix(0, nrow = length(all_features), ncol = length(cohort_list),
                          dimnames = list(all_features, names(cohort_list)))

  for (i in seq_along(cohort_list)) {
    cohort_name <- names(cohort_list)[i]
    abund <- cohort_list[[cohort_name]]$abundance
    # Mark presence if mean abundance > threshold
    present <- rowMeans(abund) > 1e-5
    stability_mat[names(present)[present], cohort_name] <- 1
  }

  # Filter to top features
  feature_prevalence <- rowSums(stability_mat)
  top_stable_features <- names(sort(feature_prevalence, decreasing = TRUE)[1:min(50, length(feature_prevalence))])

  heat_mat <- stability_mat[top_stable_features, , drop = FALSE]

  # Plot with ComplexHeatmap
  library(circlize)
  col_fun <- circlize::colorRamp2(c(0, 1), c("white", "#4575b4"))

  pdf(file.path(result_dir, "heatmap_feature_stability.pdf"), width = 10, height = 12)
  draw(Heatmap(heat_mat,
               name = "Presence",
               col = col_fun,
               cluster_rows = TRUE,
               cluster_columns = FALSE,
               show_row_names = TRUE,
               row_names_gp = gpar(fontsize = 7),
               column_names_gp = gpar(fontsize = 10),
               border = TRUE,
               heatmap_legend_param = list(
                 title = "Present",
                 at = c(0, 1),
                 labels = c("Absent", "Present")
               )))
  dev.off()
}, error = function(e) fail_hard("plot_stability_heatmap", conditionMessage(e)))

# ============================================================================
# Visualization 6: PCoA with Batch Effect (Cohort Coloring)
# ==============================================================================

cat("[INFO] Generating PCoA with cohort coloring\n")

tryCatch({
  # Merge all cohorts
  all_samples <- unlist(lapply(cohort_list, function(x) colnames(x$abundance)))
  all_taxa <- unique(unlist(lapply(cohort_list, function(x) rownames(x$abundance))))

  merged_mat <- matrix(0, nrow = length(all_taxa), ncol = length(all_samples),
                       dimnames = list(all_taxa, all_samples))

  # P3-U-05: dedicated variable - never clobbers cohort_labels (the per-cohort
  # label list still needed by the calibration section below)
  pcoa_cohort_labels <- c()
  for (cohort_data in cohort_list) {
    mat <- cohort_data$abundance
    merged_mat[rownames(mat), colnames(mat)] <- mat
    pcoa_cohort_labels <- c(pcoa_cohort_labels, rep(cohort_data$cohort, ncol(mat)))
  }
  names(pcoa_cohort_labels) <- all_samples

  # Calculate Bray-Curtis distance
  library(vegan)
  dist_mat <- vegdist(t(merged_mat + 1e-6), method = "bray")

  # PCoA
  pcoa_obj <- cmdscale(dist_mat, k = 2, eig = TRUE)
  var_exp <- round(100 * pcoa_obj$eig[1:2] / sum(pcoa_obj$eig), 1)

  pcoa_df <- data.frame(
    Axis1 = pcoa_obj$points[, 1],
    Axis2 = pcoa_obj$points[, 2],
    Cohort = pcoa_cohort_labels[rownames(pcoa_obj$points)]
  )

  p <- ggplot(pcoa_df, aes(x = Axis1, y = Axis2, color = Cohort)) +
    geom_point(size = 3, alpha = 0.7) +
    stat_ellipse(aes(fill = Cohort), geom = "polygon", alpha = 0.1, level = 0.95) +
    theme_bw(base_size = 12) +
    labs(x = paste0("Axis 1 (", var_exp[1], "%)"),
         y = paste0("Axis 2 (", var_exp[2], "%)"),
         title = "PCoA - Batch Effect Assessment (Colored by Cohort)") +
    theme(legend.position = "right")

  ggsave(file.path(result_dir, "pcoa_batch_effect.pdf"), p, width = 8, height = 6, dpi = 300)
}, error = function(e) fail_hard("plot_pcoa", conditionMessage(e)))

# ============================================================================
# Visualization 7: Calibration Curves per Cohort - primary arm (W2-1)
# ============================================================================

cat("[INFO] Generating calibration curves\n")

if (length(cohort_predictions[[PRIMARY_ARM]]) > 0) {
  tryCatch({
    calib_plots <- list()

    for (cohort_name in names(cohort_predictions[[PRIMARY_ARM]])) {
      pred <- cohort_predictions[[PRIMARY_ARM]][[cohort_name]]
      label <- cohort_labels[[PRIMARY_ARM]][[cohort_name]]

      # Bin predictions; P3-U-01: positive class from the model, not
      # levels(factor(label))[1]
      pred_bins <- cut(pred, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
      calib_df <- data.frame(
        pred = pred,
        label = as.numeric(label == positive_level),
        bin = pred_bins
      ) %>%
        group_by(bin) %>%
        summarise(
          pred_mean = mean(pred, na.rm = TRUE),
          obs_freq = mean(label, na.rm = TRUE),
          n = n(),
          .groups = "drop"
        ) %>%
        filter(n >= 3)  # require at least 3 samples per bin

      if (nrow(calib_df) > 0) {
        p <- ggplot(calib_df, aes(x = pred_mean, y = obs_freq)) +
          geom_point(aes(size = n), alpha = 0.6, color = "#4575b4") +
          geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
          geom_smooth(method = "loess", se = TRUE, color = "#d73027", linewidth = 0.8) +
          xlim(0, 1) + ylim(0, 1) +
          theme_bw(base_size = 10) +
          labs(x = "Predicted Probability", y = "Observed Frequency",
               title = cohort_name, size = "n") +
          theme(legend.position = "none")

        calib_plots[[cohort_name]] <- p
      } else {
        cat("[INFO] Calibration: no bin with >=3 samples for cohort", cohort_name, "- skipped\n")
      }
    }

    if (length(calib_plots) > 0) {
      combined <- wrap_plots(calib_plots, ncol = 2)
      ggsave(file.path(result_dir, "calibration_per_cohort.pdf"),
             combined, width = 10, height = ceiling(length(calib_plots) / 2) * 4, dpi = 300)
    } else {
      cat("[INFO] Calibration plot skipped: no cohort had a bin with >=3 samples\n")
    }
  }, error = function(e) fail_hard("plot_calibration", conditionMessage(e)))
}

# ============================================================================
# Visualization 8: Effect Correlation Matrix (Cohort vs Cohort)
# ============================================================================

cat("[INFO] Generating effect correlation matrix\n")

if (length(cohort_list) < 2) {
  cat("[INFO] Effect correlation matrix skipped: needs >= 2 cohorts (single-cohort run)\n")
} else {
  tryCatch({
    # Mean abundance per cohort for top features as proxy
    top_features <- model_top_features(siamcat_model, 30)

    effect_mat <- matrix(NA, nrow = length(top_features), ncol = length(cohort_list),
                         dimnames = list(top_features, names(cohort_list)))

    for (i in seq_along(cohort_list)) {
      cohort_name <- names(cohort_list)[i]
      abund <- cohort_list[[cohort_name]]$abundance
      present_features <- intersect(top_features, rownames(abund))
      effect_mat[present_features, cohort_name] <- log10(rowMeans(abund[present_features, , drop = FALSE]) + 1e-6)
    }

    effect_df <- as.data.frame(effect_mat)
    effect_df$feature <- rownames(effect_df)

    # Use GGally for pairs plot
    pdf(file.path(result_dir, "effect_correlation_matrix.pdf"), width = 12, height = 12)
    print(ggpairs(effect_df[, names(cohort_list), drop = FALSE],
                  title = "Effect Size Correlation Across Cohorts",
                  upper = list(continuous = wrap("cor", size = 4)),
                  lower = list(continuous = wrap("points", alpha = 0.5, size = 0.8)),
                  diag = list(continuous = wrap("densityDiag", alpha = 0.5))))
    dev.off()
  }, error = function(e) fail_hard("plot_effect_corr", conditionMessage(e)))
}

# ============================================================================
# Meta-Analysis (Optional) - external cohorts only (P3-U-03)
# ============================================================================

if (meta_analysis) {
  ma_df <- results_df %>% filter(role == "external", batch_correction == PRIMARY_ARM)
  if (nrow(ma_df) == 0) {
    cat("[INFO] Meta-analysis skipped: no external cohorts (primary arm", PRIMARY_ARM, ")\n")
  } else {
    # P3-U-08: logit(AUC) is unbounded when AUC hits 0/1 or the CI touches
    # 0/1 - such rows cannot enter a logit-scale meta-analysis. Drop them
    # with an explicit INFO instead of producing Inf/NaN and crashing.
    ma_bounded <- ma_df %>%
      filter(auc > 0, auc < 1, auc_ci_low > 0, auc_ci_high < 1)
    ma_dropped <- setdiff(ma_df$cohort, ma_bounded$cohort)
    if (length(ma_dropped) > 0) {
      cat("[INFO] Meta-analysis: dropping cohort(s) with logit-unbounded AUC/CI",
          "(AUC=0/1 or CI touching 0/1):", paste(ma_dropped, collapse = ", "), "\n")
    }
    if (nrow(ma_bounded) >= 3) {
      cat("[INFO] Performing random-effects meta-analysis on", nrow(ma_bounded),
          "EXTERNAL cohorts (primary arm", PRIMARY_ARM, ")\n")

      tryCatch({
        # Transform AUC to logit for meta-analysis.
        # P3-U-08: SE via delta method - the AUC-scale CI width maps to the
        # logit scale divided by the derivative of logit at the point
        # estimate: se_logit = se_auc / (auc * (1 - auc)).
        ma_bounded <- ma_bounded %>%
          mutate(
            logit_auc = log(auc / (1 - auc)),
            se_logit = (auc_ci_high - auc_ci_low) / 3.92 / (auc * (1 - auc))
          )

        ma_model <- metafor::rma(yi = logit_auc, sei = se_logit, data = ma_bounded, method = "REML")

        # Save meta-analysis results
        ma_summary <- tibble(
          pooled_logit_auc = ma_model$beta[1],
          pooled_se = ma_model$se,
          pooled_ci_low = ma_model$ci.lb,
          pooled_ci_high = ma_model$ci.ub,
          I2 = ma_model$I2,
          Q = ma_model$QE,
          Q_pvalue = ma_model$QEp,
          tau2 = ma_model$tau2
        )

        # Back-transform to AUC scale
        ma_summary <- ma_summary %>%
          mutate(
            pooled_auc = exp(pooled_logit_auc) / (1 + exp(pooled_logit_auc)),
            pooled_auc_ci_low = exp(pooled_ci_low) / (1 + exp(pooled_ci_low)),
            pooled_auc_ci_high = exp(pooled_ci_high) / (1 + exp(pooled_ci_high))
          )

        write_tsv(ma_summary, file.path(result_dir, "meta_analysis_results.tsv"))

        # 监工 W2 P1-1: 剔除信息写入产物与哨兵（选择偏倚不得只存在于 stdout）
        ma_summary <- ma_summary %>%
          mutate(
            n_external_input = nrow(ma_df),
            n_dropped_unbounded = length(ma_dropped),
            dropped_cohorts = if (length(ma_dropped) > 0) paste(ma_dropped, collapse = ";") else NA_character_
          )
        write_tsv(ma_summary, file.path(result_dir, "meta_analysis_results.tsv"))
        cat("[INFO] Meta-analysis drop ledger written to meta_analysis_results.tsv",
            "(n_dropped_unbounded =", length(ma_dropped), ")\n")

        cat("[INFO] Meta-analysis summary:\n")
        cat("  Pooled AUC:", round(ma_summary$pooled_auc, 3), "\n")
        cat("  I2:", round(ma_summary$I2, 1), "%\n")
        cat("  Heterogeneity Q p-value:", format.pval(ma_summary$Q_pvalue, digits = 3), "\n")
      }, error = function(e) fail_hard("meta_analysis", conditionMessage(e)))
    } else {
      cat("[INFO] Meta-analysis skipped: needs >= 3 logit-bounded external cohorts, have",
          nrow(ma_bounded), "of", nrow(ma_df), "(primary arm", PRIMARY_ARM, ")\n")
    }
  }
}

# ============================================================================
# Write sentinel LAST (P3-U-04): only after every declared output exists
# ============================================================================

if (!file.exists(file.path(result_dir, "auc_summary.tsv")) ||
    !file.exists(file.path(result_dir, "crosscohort_metrics.tsv"))) {
  fail_hard("sentinel", "declared tables missing before sentinel write")
}
if (file.exists(FAILED_FILE)) file.remove(FAILED_FILE)

writeLines(c(
  "Cross-Cohort Validation Completed",
  paste("Timestamp:", Sys.time()),
  paste("Train cohort (role=in_sample):", train_cohort),
  paste("External cohorts:", if (nrow(external_df) > 0) paste(external_df$cohort, collapse = ", ") else "(none)"),
  paste("Positive (case) class:", positive_level),
  paste("Negative (control) class:", negative_level),
  paste("Decision threshold (sens/spec/PPV):", DECISION_THRESHOLD),
  paste0("PRIMARY result: batch_correction = ", PRIMARY_ARM,
         " (uncorrected); MMUPHin arm is a sensitivity analysis"),
  paste("MMUPHin sensitivity arm:", batch_correction_note),
  if (file.exists(MMUPHIN_COLSUMS_FILE)) {
    paste("MMUPHin colSums evidence (per-sample before/after):", MMUPHIN_COLSUMS_FILE)
  },
  paste("Metrics extra column: n_features_zero_filled per cohort (frozen-normalization zero-fill count)"),
  external_summary_line,
  "",
  "AUC Summary (batch_correction=none rows are the PRIMARY result; role=in_sample rows are the training cohort and are excluded from external aggregation):",
  capture.output(print(results_df))
), SENTINEL_FILE)

cat("[SUCCESS] Cross-cohort analysis completed\n")
cat("Results saved to:", result_dir, "\n")
