#!/usr/bin/env Rscript

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

# Optional PNG companion figures, only when MGX_FIGURE_FORMATS requests "png"
mgx_want_png <- function() {
  fmts <- tolower(trimws(strsplit(Sys.getenv("MGX_FIGURE_FORMATS", ""), ",")[[1]]))
  "png" %in% fmts && requireNamespace("ragg", quietly = TRUE)
}

suppressPackageStartupMessages({
  library(SIAMCAT); library(ggplot2); library(cowplot)
  library(dplyr);   library(tidyr)
})

theme_set(theme_bw())
npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488","#F39B7F",
              "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

workdir <- Sys.getenv("WORKDIR")
result_dir <- Sys.getenv("RESULT_DIR", unset = file.path(workdir, "result", "stat", "ml"))
viz_dir <- Sys.getenv("VIZ_ML_DIR", unset = file.path(workdir, "result", "stat", "ml"))
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

roc_pdf <- file.path(result_dir, "roc_multimodel_comparison.pdf")
feat_pdf <- file.path(result_dir, "feature_importance_with_sd.pdf")
sentinel <- file.path(result_dir, "siamcat_done.txt")
status_tsv <- file.path(result_dir, "ml_status.tsv")
status_log <- data.frame(step = character(), status = character(), message = character())
log_status <- function(step, status, message = "") {
  status_log[nrow(status_log) + 1, ] <<- list(step, status, message)
  cat(sprintf("[%s] %s: %s\n", status, step, message))
}

write_outputs <- function() {
  utils::write.table(status_log, status_tsv, sep = "\t", row.names = FALSE, quote = FALSE)
  if (!file.exists(sentinel)) writeLines(format(Sys.time()), sentinel)
}
on.exit(write_outputs(), add = TRUE)

extract_roc_df <- function(sc) {
  ev <- tryCatch(SIAMCAT::eval_data(sc), error = function(e) NULL)
  roc <- ev$roc %||% NULL
  if (inherits(roc, "roc") || (!is.null(roc$specificities) && !is.null(roc$sensitivities))) {
    df <- data.frame(fpr = 1 - as.numeric(roc$specificities), tpr = as.numeric(roc$sensitivities))
  } else if (!is.null(roc$x.values) && !is.null(roc$y.values)) {
    df <- data.frame(fpr = as.numeric(roc$x.values[[1]]), tpr = as.numeric(roc$y.values[[1]]))
  } else if (inherits(roc, "performance")) {
    df <- data.frame(fpr = as.numeric(roc@x.values[[1]]), tpr = as.numeric(roc@y.values[[1]]))
  } else {
    return(NULL)
  }
  auc <- ev$auroc %||% ev$auc %||% roc$auc %||% attr(roc, "auc") %||% NA_real_
  df |>
    filter(is.finite(fpr), is.finite(tpr)) |>
    mutate(fpr = pmin(pmax(fpr, 0), 1), tpr = pmin(pmax(tpr, 0), 1)) |>
    arrange(fpr, tpr) |>
    distinct(fpr, tpr, .keep_all = TRUE) |>
    mutate(auc = as.numeric(auc)[1])
}

coerce_fw <- function(fw) {
  if (is.matrix(fw)) return(fw)
  if (is.data.frame(fw)) return(as.matrix(fw))
  if (is.atomic(fw) && !is.null(dim(fw))) return(as.matrix(fw))
  if (is.atomic(fw)) {
    mat <- matrix(as.numeric(fw), ncol = 1, dimnames = list(names(fw), "Fold_1"))
    return(mat)
  }
  if (is.list(fw) && length(fw)) {
    ids <- unique(unlist(lapply(fw, names), use.names = FALSE))
    if (length(ids)) {
      mat <- vapply(fw, function(x) {
        v <- setNames(rep(0, length(ids)), ids); v[names(x)] <- as.numeric(x); v
      }, numeric(length(ids)))
      rownames(mat) <- ids
      return(mat)
    }
  }
  stop("Unsupported feature_weights structure")
}

plot_roc <- function(models_found) {
  roc_list <- list()
  for (m in names(models_found)) {
    df <- tryCatch(extract_roc_df(models_found[[m]]), error = function(e) NULL)
    if (is.null(df) || !nrow(df)) {
      log_status(paste0("roc_", m), "SKIPPED", "No ROC data extracted")
      next
    }
    label <- sprintf("%s (AUC=%.2f)", toupper(m), unique(df$auc)[1])
    roc_list[[m]] <- mutate(df, model = label)
  }
  if (!length(roc_list)) {
    log_status("roc_multimodel_comparison", "SKIPPED", "No readable ROC curves")
    return()
  }
  roc_df <- bind_rows(roc_list)
  p <- ggplot(roc_df, aes(fpr, tpr, color = model)) +
    geom_line(linewidth = 1) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
    scale_color_manual(values = setNames(npg_pal(dplyr::n_distinct(roc_df$model)), unique(roc_df$model))) +
    coord_equal() +
    labs(x = "False Positive Rate", y = "True Positive Rate",
         title = "Multi-model ROC comparison", color = "Model (AUC)") +
    theme(legend.position = "inside", legend.position.inside = c(0.75, 0.25),
          panel.grid = element_blank(), legend.background = element_blank())
  cowplot::save_plot(roc_pdf, p, base_aspect_ratio = 1.1, base_height = 5.5, dpi = 300)
  if (mgx_want_png()) cowplot::save_plot(sub("\\.pdf$", ".png", roc_pdf), p,
    base_aspect_ratio = 1.1, base_height = 5.5, dpi = 600, device = ragg::agg_png)
  log_status("roc_multimodel_comparison", "OK", basename(roc_pdf))
}

plot_features <- function() {
  lasso_rds <- file.path(result_dir, "siamcat_lasso.rds")
  if (!file.exists(lasso_rds)) {
    log_status("feature_importance_with_sd", "SKIPPED", "Missing siamcat_lasso.rds")
    return()
  }
  sc <- tryCatch(readRDS(lasso_rds), error = function(e) NULL)
  if (is.null(sc)) {
    log_status("feature_importance_with_sd", "SKIPPED", "Failed to read siamcat_lasso.rds")
    return()
  }
  fw <- tryCatch(coerce_fw(SIAMCAT::feature_weights(sc)), error = function(e) NULL)
  if (is.null(fw) || !nrow(fw)) {
    log_status("feature_importance_with_sd", "SKIPPED", "No feature weights available")
    return()
  }
  afw <- abs(fw)
  feat_df <- data.frame(
    feature = rownames(afw),
    mean_weight = rowMeans(afw),
    sd_weight = apply(afw, 1, stats::sd)
  ) |>
    arrange(desc(mean_weight)) |>
    slice_head(n = 20) |>
    mutate(feature = factor(feature, levels = rev(feature)),
           pos = mean_weight > 0)
  p <- ggplot(feat_df, aes(feature, mean_weight, fill = pos)) +
    geom_col() +
    geom_errorbar(aes(ymin = pmax(mean_weight - sd_weight, 0), ymax = mean_weight + sd_weight), width = 0.3) +
    coord_flip() +
    scale_fill_manual(values = c("TRUE" = npg_base[1], "FALSE" = npg_base[2]), guide = "none") +
    labs(x = NULL, y = "Mean |weight|", title = "Top-20 LASSO features") +
    theme(panel.grid.major.y = element_blank())
  cowplot::save_plot(feat_pdf, p, base_aspect_ratio = 1.2, base_height = 7, dpi = 300)
  if (mgx_want_png()) cowplot::save_plot(sub("\\.pdf$", ".png", feat_pdf), p,
    base_aspect_ratio = 1.2, base_height = 7, dpi = 600, device = ragg::agg_png)
  log_status("feature_importance_with_sd", "OK", basename(feat_pdf))
}

tryCatch({
  models_found <- list()
  for (m in c("lasso", "ridge", "enet", "rf")) {
    rds <- file.path(result_dir, paste0("siamcat_", m, ".rds"))
    if (file.exists(rds)) {
      sc <- tryCatch(readRDS(rds), error = function(e) NULL)
      if (!is.null(sc)) models_found[[m]] <- sc else log_status(paste0("read_", m), "FAILED", basename(rds))
    }
  }
  if (!length(models_found)) {
    log_status("model_discovery", "SKIPPED", "No SIAMCAT RDS found")
  } else {
    tryCatch(plot_roc(models_found), error = function(e) log_status("roc_multimodel_comparison", "FAILED", conditionMessage(e)))
    tryCatch(plot_features(), error = function(e) log_status("feature_importance_with_sd", "FAILED", conditionMessage(e)))
  }
  writeLines(format(Sys.time()), sentinel)
}, error = function(e) {
  log_status("script", "FAILED", conditionMessage(e))
  writeLines(format(Sys.time()), sentinel)
})

write_outputs()
quit(save = "no", status = 0)
