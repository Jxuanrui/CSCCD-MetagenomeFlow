#!/usr/bin/env Rscript
# ==============================================================================
# Script: 96_ml_shap.R
# Purpose: SHAP feature attribution for the SIAMCAT randomForest model
#
# Scope: SHAP is computed only for siamcat_randomForest.rds. lasso/ridge/enet
# are linear (glmnet) models where SHAP degenerates to coefficient x value -
# already covered by feature_weights/feature_importance_with_sd.pdf in
# 96_ml_visualization.R. randomForest is genuinely non-linear, where SHAP
# adds real explanatory value over a plain importance ranking.
#
# Why iml (not fastshap): fastshap is not installed in envs/r_stat and its
# fast path is XGBoost-specific, not a general mlr3 adapter. iml integrates
# directly with the mlr3 Learner interface SIAMCAT trains under the hood.
#
# Why a single CV fold (not averaged across folds): SHAP via Monte Carlo
# sampling (iml::Shapley) is expensive per sample; averaging across folds
# would multiply the cost. Using models(sc)[[1]] (the first fold) keeps this
# tractable. Revisit if this fold turns out unrepresentative.
# ==============================================================================

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

suppressPackageStartupMessages({
  library(SIAMCAT); library(iml); library(shapviz)
  library(dplyr); library(tidyr)
})

workdir <- Sys.getenv("WORKDIR")
result_dir <- Sys.getenv("RESULT_DIR", unset = file.path(workdir, "result", "stat", "ml"))
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

rf_rds <- file.path(result_dir, "siamcat_randomForest.rds")
shap_tsv <- file.path(result_dir, "randomForest_shap_values.tsv")
shap_pdf <- file.path(result_dir, "randomForest_shap_summary.pdf")
status_tsv <- file.path(result_dir, "shap_status.tsv")

status_log <- data.frame(step = character(), status = character(), message = character())
log_status <- function(step, status, message = "") {
  status_log[nrow(status_log) + 1, ] <<- list(step, status, message)
  cat(sprintf("[%s] %s: %s\n", status, step, message))
}
write_status <- function() {
  utils::write.table(status_log, status_tsv, sep = "\t", row.names = FALSE, quote = FALSE)
}
on.exit(write_status(), add = TRUE)

# Max samples to run through iml::Shapley - SHAP via Monte Carlo sampling is
# expensive per sample; cap to keep runtime bounded on large cohorts.
MAX_SHAP_SAMPLES <- as.integer(Sys.getenv("SHAP_MAX_SAMPLES", unset = "50"))
SHAP_SAMPLE_SIZE <- as.integer(Sys.getenv("SHAP_SAMPLE_SIZE", unset = "50"))

if (!file.exists(rf_rds)) {
  log_status("shap_randomForest", "SKIPPED", "siamcat_randomForest.rds not found")
  write_status()
  quit(save = "no", status = 0)
}

sc <- tryCatch(readRDS(rf_rds), error = function(e) NULL)
if (is.null(sc)) {
  log_status("shap_randomForest", "SKIPPED", "Failed to read siamcat_randomForest.rds")
  write_status()
  quit(save = "no", status = 0)
}

tryCatch({
  ml <- SIAMCAT::model_list(sc)
  fold1 <- ml$models[[1]]
  learner <- fold1$model
  feat_names_model <- learner$state$train_task$feature_names

  norm_feat <- SIAMCAT::get.norm_feat.matrix(sc)
  newdata_full <- as.data.frame(t(norm_feat))
  # mlr3 sanitizes feature names on train (make.names()); align the same way
  # here or every prediction/SHAP lookup silently returns zero matches.
  colnames(newdata_full) <- make.names(colnames(newdata_full))
  missing_feats <- setdiff(feat_names_model, colnames(newdata_full))
  if (length(missing_feats)) {
    stop(sprintf("%d model features missing from norm_feat after name sanitization", length(missing_feats)))
  }
  newdata_full <- newdata_full[, feat_names_model, drop = FALSE]

  if (nrow(newdata_full) > MAX_SHAP_SAMPLES) {
    set.seed(42)
    sample_idx <- sample(seq_len(nrow(newdata_full)), MAX_SHAP_SAMPLES)
    newdata_shap <- newdata_full[sample_idx, , drop = FALSE]
    log_status("sample_capping", "OK",
               sprintf("Capped to %d/%d samples (SHAP_MAX_SAMPLES)", MAX_SHAP_SAMPLES, nrow(newdata_full)))
  } else {
    newdata_shap <- newdata_full
  }

  predict_fun <- function(model, newdata) {
    p <- model$predict_newdata(newdata)
    data.frame(prob.1 = p$prob[, "1"])
  }

  predictor <- iml::Predictor$new(model = learner, data = newdata_full,
                                   predict.fun = predict_fun, y = NULL)

  shap_rows <- vector("list", nrow(newdata_shap))
  t0 <- Sys.time()
  for (i in seq_len(nrow(newdata_shap))) {
    shap_i <- iml::Shapley$new(predictor, x.interest = newdata_shap[i, , drop = FALSE],
                                sample.size = SHAP_SAMPLE_SIZE)
    df_i <- shap_i$results
    df_i$sample_id <- rownames(newdata_shap)[i]
    shap_rows[[i]] <- df_i
  }
  elapsed <- as.numeric(Sys.time() - t0, units = "secs")
  log_status("shap_compute", "OK",
             sprintf("%d samples in %.1fs (%.2fs/sample)", nrow(newdata_shap), elapsed, elapsed / nrow(newdata_shap)))

  shap_df <- dplyr::bind_rows(shap_rows) %>%
    dplyr::select(sample_id, feature, phi, phi.var, feature.value) %>%
    dplyr::rename(shap_value = phi, shap_variance = phi.var)

  utils::write.table(shap_df, shap_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
  log_status("shap_values_tsv", "OK", basename(shap_tsv))

  # shapviz expects a numeric matrix of SHAP values (samples x features) plus
  # the corresponding feature-value matrix - reshape the long-format results.
  shap_wide <- shap_df %>%
    dplyr::select(sample_id, feature, shap_value) %>%
    tidyr::pivot_wider(names_from = feature, values_from = shap_value) %>%
    tibble::column_to_rownames("sample_id")
  feat_matrix <- as.matrix(newdata_shap[rownames(shap_wide), colnames(shap_wide), drop = FALSE])

  sv <- shapviz::shapviz(as.matrix(shap_wide), X = as.data.frame(feat_matrix))
  p <- shapviz::sv_importance(sv, kind = "beeswarm", max_display = 20) +
    ggplot2::labs(title = "SHAP feature attribution — randomForest")
  grDevices::pdf(shap_pdf, width = 10, height = 8)
  print(p)
  grDevices::dev.off()
  log_status("shap_summary_pdf", "OK", basename(shap_pdf))
  shap_png <- sub("\\.pdf$", ".png", shap_pdf)
  if (tolower(Sys.getenv("MGX_FIGURE_FORMATS", "")) %in% c("png", "pdf,png", "png,pdf") &&
      requireNamespace("ragg", quietly = TRUE)) {
    ragg::agg_png(shap_png, width = 10, height = 8, units = "in", res = 600)
    print(p)
    grDevices::dev.off()
    log_status("shap_summary_png", "OK", basename(shap_png))
  }

}, error = function(e) {
  log_status("shap_randomForest", "FAILED", conditionMessage(e))
})

write_status()
quit(save = "no", status = 0)
