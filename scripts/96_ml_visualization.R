#!/usr/bin/env Rscript
# ==============================================================================
# Script: 96_ml_visualization.R
# Purpose: SIAMCAT multi-model ROC and feature-importance visualizations
# ==============================================================================

options(stringsAsFactors = FALSE, warn = 1)

required_pkgs <- c("SIAMCAT", "ggplot2", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(SIAMCAT)
  library(ggplot2)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

workdir <- Sys.getenv("WORKDIR")
result_dir <- Sys.getenv("RESULT_DIR", unset = file.path(workdir, "result", "stat", "ml"))
viz_dir <- Sys.getenv("VIZ_ML_DIR", unset = file.path(workdir, "result", "viz_ml"))
force_run <- identical(Sys.getenv("FORCE", "0"), "1")

dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Starting ML visualization\n")
cat("  Result dir:", result_dir, "\n")
cat("  Visualization dir:", viz_dir, "\n")
cat("  Force:", force_run, "\n")

status_log <- list()

log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- tibble(step = step, status = status, message = message)
}

run_step <- function(step, expr) {
  tryCatch(
    {
      base::force(expr)
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

theme_publication <- function(base_size = 12) {
  theme_bw(base_size = base_size) +
    theme(
      panel.grid = element_blank(),
      panel.border = element_rect(color = "black", linewidth = 0.6),
      strip.background = element_rect(fill = "grey95", color = "grey80"),
      strip.text = element_text(face = "bold"),
      plot.title = element_text(face = "bold"),
      legend.key = element_blank()
    )
}

write_status_log <- function() {
  out <- if (length(status_log) == 0) {
    tibble(step = character(), status = character(), message = character())
  } else {
    bind_rows(status_log)
  }
  readr::write_tsv(out, file.path(viz_dir, "ml_visualization_status.tsv"))
}

on.exit(write_status_log(), add = TRUE)

should_skip_output <- function(path, force_flag = FALSE) {
  !force_flag && file.exists(path) && isTRUE(file.info(path)$size > 0)
}

safe_eval_data <- function(siamcat_obj) {
  out <- tryCatch(SIAMCAT::eval_data(siamcat_obj), error = function(e) NULL)
  if (!is.null(out)) {
    return(out)
  }
  if (methods::isS4(siamcat_obj) && methods::slotExists(siamcat_obj, "eval_data")) {
    return(siamcat_obj@eval_data)
  }
  if (is.list(siamcat_obj) && !is.null(siamcat_obj$eval_data)) {
    return(siamcat_obj$eval_data)
  }
  NULL
}

safe_feature_weights <- function(siamcat_obj) {
  if (methods::isS4(siamcat_obj) && methods::slotExists(siamcat_obj, "feature_weights")) {
    return(siamcat_obj@feature_weights)
  }
  if (is.list(siamcat_obj) && !is.null(siamcat_obj$feature_weights)) {
    return(siamcat_obj$feature_weights)
  }
  tryCatch(slot(siamcat_obj, "feature_weights"), error = function(e) NULL)
}

extract_auc_value <- function(eval_obj, roc_obj = NULL) {
  auc_val <- eval_obj$auroc %||% eval_obj$auc %||% NULL
  if (!is.null(auc_val)) {
    return(as.numeric(auc_val)[1])
  }
  if (inherits(roc_obj, "roc")) {
    roc_auc <- roc_obj$auc %||% attr(roc_obj, "auc") %||% NULL
    if (!is.null(roc_auc)) {
      return(as.numeric(roc_auc)[1])
    }
  }
  NA_real_
}

extract_roc_df <- function(roc_obj) {
  if (is.null(roc_obj)) {
    return(NULL)
  }

  if (inherits(roc_obj, "roc") || (!is.null(roc_obj$specificities) && !is.null(roc_obj$sensitivities))) {
    df <- tibble(
      fpr = 1 - as.numeric(roc_obj$specificities),
      tpr = as.numeric(roc_obj$sensitivities)
    )
  } else if (inherits(roc_obj, "performance")) {
    df <- tibble(
      fpr = as.numeric(roc_obj@x.values[[1]]),
      tpr = as.numeric(roc_obj@y.values[[1]])
    )
  } else if (inherits(roc_obj, "prediction")) {
    if (!requireNamespace("ROCR", quietly = TRUE)) {
      stop("ROCR namespace unavailable for prediction-class ROC object")
    }
    perf <- ROCR::performance(roc_obj, "tpr", "fpr")
    df <- tibble(
      fpr = as.numeric(perf@x.values[[1]]),
      tpr = as.numeric(perf@y.values[[1]])
    )
  } else if (!is.null(roc_obj$x.values) && !is.null(roc_obj$y.values)) {
    df <- tibble(
      fpr = as.numeric(roc_obj$x.values[[1]]),
      tpr = as.numeric(roc_obj$y.values[[1]])
    )
  } else {
    return(NULL)
  }

  df %>%
    dplyr::filter(is.finite(fpr), is.finite(tpr)) %>%
    dplyr::mutate(
      fpr = pmin(pmax(fpr, 0), 1),
      tpr = pmin(pmax(tpr, 0), 1)
    ) %>%
    dplyr::arrange(fpr, tpr) %>%
    dplyr::distinct(fpr, tpr, .keep_all = TRUE)
}

as_named_numeric_vector <- function(x) {
  if (is.matrix(x) || is.data.frame(x)) {
    x <- as.matrix(x)
    if (ncol(x) == 1) {
      vals <- as.numeric(x[, 1])
      names(vals) <- rownames(x)
      return(vals)
    }
    stop("List-based feature weights contain multi-column matrix entries")
  }

  vals <- as.numeric(x)
  nm <- names(x)
  if (!is.null(nm) && length(nm) == length(vals)) {
    names(vals) <- nm
  }
  vals
}

coerce_weight_matrix <- function(weights) {
  if (is.null(weights)) {
    stop("Feature weights slot is empty")
  }

  if (is.matrix(weights)) {
    mat <- weights
  } else if (is.data.frame(weights)) {
    mat <- as.matrix(weights)
  } else if (is.atomic(weights) && !is.null(dim(weights))) {
    mat <- as.matrix(weights)
  } else if (is.atomic(weights)) {
    mat <- matrix(as.numeric(weights), ncol = 1)
    rownames(mat) <- names(weights) %||% paste0("Feature_", seq_len(nrow(mat)))
  } else if (is.list(weights)) {
    if (length(weights) == 0) {
      stop("Feature weights list is empty")
    }

    weight_vectors <- lapply(weights, as_named_numeric_vector)
    feature_ids <- unique(unlist(lapply(weight_vectors, names), use.names = FALSE))
    feature_ids <- feature_ids[!is.na(feature_ids) & feature_ids != ""]

    if (length(feature_ids) > 0) {
      mat <- vapply(
        weight_vectors,
        function(x) {
          vec <- setNames(rep(0, length(feature_ids)), feature_ids)
          if (length(x) > 0) {
            vec[names(x)] <- as.numeric(x)
          }
          vec
        },
        numeric(length(feature_ids))
      )
      rownames(mat) <- feature_ids
    } else {
      fold_lengths <- lengths(weight_vectors)
      if (length(unique(fold_lengths)) != 1) {
        stop("Cannot align unnamed feature-weight vectors with unequal lengths")
      }
      mat <- do.call(cbind, lapply(weight_vectors, as.numeric))
      rownames(mat) <- paste0("Feature_", seq_len(nrow(mat)))
    }
  } else {
    stop("Unsupported feature_weights structure: ", paste(class(weights), collapse = ", "))
  }

  storage.mode(mat) <- "numeric"
  if (is.null(colnames(mat))) {
    colnames(mat) <- paste0("Fold_", seq_len(ncol(mat)))
  }
  if (is.null(rownames(mat))) {
    rownames(mat) <- paste0("Feature_", seq_len(nrow(mat)))
  }
  mat[is.na(mat)] <- 0
  mat
}

locate_model_file <- function(candidates) {
  paths <- file.path(result_dir, candidates)
  found <- paths[file.exists(paths)]
  if (length(found) == 0) {
    return(NULL)
  }
  found[[1]]
}

model_specs <- tribble(
  ~model_id, ~model_label, ~filenames,
  "lasso", "Lasso", list(c("siamcat_lasso.rds")),
  "ridge", "Ridge", list(c("siamcat_ridge.rds")),
  "enet", "Elastic Net", list(c("siamcat_enet.rds")),
  "rf", "Random Forest", list(c("siamcat_rf.rds", "siamcat_randomForest.rds"))
)

roc_pdf <- file.path(viz_dir, "roc_multimodel_comparison.pdf")
importance_pdf <- file.path(viz_dir, "feature_importance_with_sd.pdf")

if (should_skip_output(roc_pdf, force_run)) {
  log_status("roc_multimodel_comparison", "SKIPPED", paste("Output exists:", roc_pdf))
} else {
  run_step("roc_multimodel_comparison", {
    roc_curves <- list()
    legend_levels <- character()

    for (i in seq_len(nrow(model_specs))) {
      spec <- model_specs[i, ]
      model_path <- locate_model_file(spec$filenames[[1]])
      if (is.null(model_path)) {
        log_status(
          paste0("roc_input_", spec$model_id),
          "SKIPPED",
          paste("Missing model file:", paste(spec$filenames[[1]], collapse = ", "))
        )
        next
      }

      siamcat_obj <- readRDS(model_path)
      eval_obj <- safe_eval_data(siamcat_obj)
      if (is.null(eval_obj)) {
        log_status(paste0("roc_input_", spec$model_id), "SKIPPED", paste("No eval_data in", basename(model_path)))
        next
      }

      roc_obj <- eval_obj$roc %||% NULL
      roc_df <- extract_roc_df(roc_obj)
      if (is.null(roc_df) || nrow(roc_df) == 0) {
        log_status(paste0("roc_input_", spec$model_id), "SKIPPED", paste("No ROC curve extracted from", basename(model_path)))
        next
      }

      auc_val <- extract_auc_value(eval_obj, roc_obj)
      legend_label <- if (is.na(auc_val)) {
        sprintf("%s (AUC=NA)", spec$model_label)
      } else {
        sprintf("%s (AUC=%.2f)", spec$model_label, auc_val)
      }

      roc_curves[[length(roc_curves) + 1]] <- roc_df %>%
        dplyr::mutate(model = spec$model_label, legend_label = legend_label)
      legend_levels <- c(legend_levels, legend_label)
    }

    if (length(roc_curves) == 0) {
      log_status("roc_multimodel_comparison", "SKIPPED", "No readable SIAMCAT ROC models found")
      invisible(NULL)
    } else {
      roc_plot_df <- bind_rows(roc_curves) %>%
        dplyr::mutate(legend_label = factor(legend_label, levels = unique(legend_levels)))

      palette_vals <- c(
        "#1b9e77", "#d95f02", "#7570b3", "#e7298a"
      )
      color_map <- setNames(palette_vals[seq_len(nlevels(roc_plot_df$legend_label))], levels(roc_plot_df$legend_label))

      p <- ggplot(roc_plot_df, aes(x = fpr, y = tpr, color = legend_label)) +
        geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "grey65", linewidth = 0.5) +
        geom_path(linewidth = 1) +
        scale_color_manual(values = color_map, name = NULL) +
        coord_equal() +
        labs(
          title = "Multi-model ROC comparison",
          x = "False Positive Rate",
          y = "True Positive Rate"
        ) +
        theme_publication(base_size = 12) +
        theme(
          legend.position = "bottom",
          legend.text = element_text(size = 10)
        )

      pdf(roc_pdf, width = 8, height = 6)
      print(p)
      dev.off()
    }
  })
}

if (should_skip_output(importance_pdf, force_run)) {
  log_status("feature_importance_with_sd", "SKIPPED", paste("Output exists:", importance_pdf))
} else {
  run_step("feature_importance_with_sd", {
    lasso_path <- locate_model_file(c("siamcat_lasso.rds"))
    if (is.null(lasso_path)) {
      log_status("feature_importance_with_sd", "SKIPPED", "Missing lasso model file: siamcat_lasso.rds")
      invisible(NULL)
    } else {
      siamcat_obj <- readRDS(lasso_path)
      weight_mat <- coerce_weight_matrix(safe_feature_weights(siamcat_obj))

      feature_df <- tibble(
        feature = rownames(weight_mat),
        mean_weight = rowMeans(weight_mat, na.rm = TRUE),
        sd_weight = apply(weight_mat, 1, sd, na.rm = TRUE)
      ) %>%
        dplyr::filter(is.finite(mean_weight), is.finite(sd_weight)) %>%
        dplyr::mutate(abs_mean = abs(mean_weight)) %>%
        dplyr::arrange(dplyr::desc(abs_mean), dplyr::desc(mean_weight)) %>%
        dplyr::slice_head(n = 30) %>%
        dplyr::mutate(
          direction = if_else(mean_weight >= 0, "Positive", "Negative"),
          feature = forcats::fct_reorder(feature, mean_weight)
        )

      if (nrow(feature_df) == 0) {
        log_status("feature_importance_with_sd", "SKIPPED", "No feature weights available for plotting")
        invisible(NULL)
      } else {
        p <- ggplot(feature_df, aes(x = feature, y = mean_weight, fill = direction)) +
          geom_col(width = 0.75) +
          geom_errorbar(
            aes(ymin = mean_weight - sd_weight, ymax = mean_weight + sd_weight),
            width = 0.2,
            linewidth = 0.4
          ) +
          coord_flip() +
          scale_fill_manual(values = c(Positive = "#1b9e77", Negative = "#d95f02"), name = NULL) +
          labs(
            title = "Lasso feature importance across CV folds",
            x = NULL,
            y = "Mean coefficient +/- SD"
          ) +
          theme_publication(base_size = 11) +
          theme(
            legend.position = "top",
            axis.text.y = element_text(size = 8)
          )

        pdf(importance_pdf, width = 10, height = 8)
        print(p)
        dev.off()
      }
    }
  })
}

cat("[INFO] ML visualization completed\n")
cat("  ROC PDF:", roc_pdf, "\n")
cat("  Feature importance PDF:", importance_pdf, "\n")
