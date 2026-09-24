#!/usr/bin/env Rscript
# ==============================================================================
# Script: 97_crosscohort.R
# Purpose: Cross-cohort validation with local multi-cohort support + 8 visualizations
# ==============================================================================

options(stringsAsFactors = FALSE, warn = 1)

options(device = function(...) grDevices::pdf(file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...))

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
ml_dir <- Sys.getenv("ML_DIR")
result_dir <- Sys.getenv("RESULT_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Starting cross-cohort analysis\n")
cat("  Source mode:", source_mode, "\n")
cat("  Cohorts:", cohorts_str, "\n")
cat("  Train cohort:", train_cohort, "\n")

# ============================================================================
# Helper Functions
# ============================================================================

load_local_cohort <- function(cohort_name, parent_dir) {
  cat("[INFO] Loading local cohort:", cohort_name, "\n")
  cohort_path <- file.path(parent_dir, cohort_name)

  # Load abundance table (bacteria from MetaPhlAn4)
  abund_file <- file.path(cohort_path, "result/metaphlan4/merged/taxonomy.tsv")
  if (!file.exists(abund_file)) {
    warning("Abundance file not found: ", abund_file)
    return(NULL)
  }

  abund <- read_tsv(abund_file, show_col_types = FALSE)
  # Assume first column is taxon, rest are samples
  taxa <- abund[[1]]
  abund_mat <- as.matrix(abund[, -1, drop = FALSE])
  rownames(abund_mat) <- taxa

  # Load metadata
  meta_file <- file.path(cohort_path, basename(metadata_csv))
  if (!file.exists(meta_file)) {
    meta_file <- metadata_csv  # fallback to global metadata
  }
  meta <- read_csv(meta_file, show_col_types = FALSE)

  # Filter samples present in both
  common_samples <- intersect(colnames(abund_mat), meta$sample_id)
  if (length(common_samples) == 0) {
    warning("No common samples between abundance and metadata for cohort ", cohort_name)
    return(NULL)
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
    stop("Package curatedMetagenomicData not available (requires network)")
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
    warning("Failed to load ", dataset_name, ": ", conditionMessage(e))
    NULL
  })
}

perform_batch_correction <- function(cohort_list) {
  cat("[INFO] Performing batch correction across cohorts\n")

  if (!requireNamespace("MMUPHin", quietly = TRUE)) {
    warning("MMUPHin not available, skipping batch correction")
    return(cohort_list)
  }

  # Merge all abundance matrices
  all_samples <- unlist(lapply(cohort_list, function(x) colnames(x$abundance)))
  all_taxa <- unique(unlist(lapply(cohort_list, function(x) rownames(x$abundance))))

  merged_mat <- matrix(0, nrow = length(all_taxa), ncol = length(all_samples),
                       dimnames = list(all_taxa, all_samples))

  for (cohort_data in cohort_list) {
    mat <- cohort_data$abundance
    merged_mat[rownames(mat), colnames(mat)] <- mat
  }

  # Create batch vector
  batch_vec <- unlist(lapply(cohort_list, function(x) {
    rep(x$cohort, ncol(x$abundance))
  }))
  names(batch_vec) <- all_samples

  # MMUPHin batch correction
  tryCatch({
    corrected <- MMUPHin::adjust_batch(
      feature_abd = merged_mat,
      batch = "batch",
      covariates = data.frame(batch = batch_vec, row.names = all_samples),
      control = list(verbose = FALSE)
    )
    corrected_mat <- corrected$feature_abd_adj %||% merged_mat

    # Split back to cohorts
    for (i in seq_along(cohort_list)) {
      samples <- colnames(cohort_list[[i]]$abundance)
      cohort_list[[i]]$abundance <- corrected_mat[, samples, drop = FALSE]
    }

    cat("[INFO] Batch correction completed\n")
  }, error = function(e) {
    warning("Batch correction failed: ", conditionMessage(e))
  })

  cohort_list
}

# ============================================================================
# Main Analysis
# ============================================================================

# Load SIAMCAT model from script 96
model_file <- file.path(ml_dir, "siamcat_lasso.rds")
if (!file.exists(model_file)) {
  stop("SIAMCAT model not found: ", model_file, "\nRun script 96 first")
}

siamcat_model <- readRDS(model_file)
cat("[INFO] Loaded SIAMCAT model from:", model_file, "\n")

# Load cohorts based on source mode
cohort_list <- list()

if (source_mode == "local") {
  cohort_names <- strsplit(cohorts_str, ",")[[1]]
  parent_dir <- dirname(workdir)

  for (cohort_name in cohort_names) {
    cohort_data <- load_local_cohort(cohort_name, parent_dir)
    if (!is.null(cohort_data)) {
      cohort_list[[cohort_name]] <- cohort_data
    }
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
    cohort_data <- load_curated_cohort(ds)
    if (!is.null(cohort_data)) {
      cohort_list[[ds]] <- cohort_data
    }
  }
}

if (length(cohort_list) == 0) {
  stop("No cohorts loaded successfully")
}

cat("[INFO] Loaded", length(cohort_list), "cohorts:\n")
for (name in names(cohort_list)) {
  n_samples <- ncol(cohort_list[[name]]$abundance)
  cat("  -", name, ":", n_samples, "samples\n")
}

# Batch correction
cohort_list <- perform_batch_correction(cohort_list)

# ============================================================================
# Model Transfer & Prediction
# ============================================================================

cat("[INFO] Performing model transfer and prediction\n")

cohort_results <- list()
cohort_predictions <- list()
cohort_labels <- list()

for (cohort_name in names(cohort_list)) {
  cat("[INFO] Predicting on cohort:", cohort_name, "\n")

  cohort_data <- cohort_list[[cohort_name]]
  abund <- cohort_data$abundance
  meta <- cohort_data$metadata

  tryCatch({
    # Make predictions
    pred_obj <- SIAMCAT::make.predictions(siamcat_model, newdata = abund)

    # Get true labels
    true_labels <- meta[[group_col]]
    names(true_labels) <- meta$sample_id

    # Evaluate if labels available
    if (!all(is.na(true_labels))) {
      # Create label object for evaluation
      label_obj <- SIAMCAT::create.label(
        label = true_labels,
        case = unique(true_labels)[1]  # assume first level is case
      )

      # Evaluate predictions
      pred_matrix <- SIAMCAT::pred_matrix(pred_obj)
      pred_vector <- rowMeans(pred_matrix, na.rm = TRUE)

      # Calculate AUC
      roc_obj <- pROC::roc(true_labels, pred_vector, quiet = TRUE)
      auc_val <- as.numeric(pROC::auc(roc_obj))
      ci_val <- pROC::ci.auc(roc_obj, quiet = TRUE)

      # Store results
      cohort_results[[cohort_name]] <- tibble(
        cohort = cohort_name,
        auc = auc_val,
        auc_ci_low = ci_val[1],
        auc_ci_high = ci_val[3],
        n_samples = ncol(abund)
      )

      cohort_predictions[[cohort_name]] <- pred_vector
      cohort_labels[[cohort_name]] <- true_labels

      # Save individual ROC plot
      pdf(file.path(result_dir, paste0(gsub("[^A-Za-z0-9]+", "_", cohort_name), "_roc.pdf")),
          width = 6, height = 6)
      plot(roc_obj, main = paste("ROC Curve:", cohort_name),
           col = "#d73027", lwd = 2)
      text(0.6, 0.2, sprintf("AUC = %.3f", auc_val), cex = 1.2)
      dev.off()

      cat("    AUC =", round(auc_val, 3), "\n")
    }
  }, error = function(e) {
    warning("Prediction failed for ", cohort_name, ": ", conditionMessage(e))
  })
}

# Combine results
results_df <- bind_rows(cohort_results)
write_tsv(results_df, file.path(result_dir, "auc_summary.tsv"))

cat("[INFO] Cross-cohort AUC summary:\n")
print(results_df)

# ============================================================================
# Visualization 1: Forest Plot (AUC)
# ============================================================================

cat("[INFO] Generating forest plot for AUC\n")

if (nrow(results_df) > 0) {
  pdf(file.path(result_dir, "forest_plot_auc.pdf"), width = 10, height = max(6, nrow(results_df) * 0.8))

  forest_data <- results_df %>%
    mutate(
      mean = auc,
      lower = auc_ci_low,
      upper = auc_ci_high,
      cohort_label = paste0(cohort, " (n=", n_samples, ")")
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
    xticks = seq(0.5, 1.0, 0.1),
    clip = c(0.5, 1.0),
    grid = TRUE
  )

  dev.off()
}

# ============================================================================
# Visualization 2: Waterfall Plot (AUC)
# ============================================================================

cat("[INFO] Generating waterfall plot for AUC\n")

if (nrow(results_df) > 0) {
  ggplot(results_df %>% arrange(desc(auc)),
         aes(x = reorder(cohort, auc), y = auc)) +
    geom_col(fill = "#4575b4", width = 0.7) +
    geom_errorbar(aes(ymin = auc_ci_low, ymax = auc_ci_high), width = 0.3) +
    geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey50") +
    coord_flip() +
    ylim(0, 1) +
    theme_bw(base_size = 12) +
    labs(x = NULL, y = "AUC", title = "Cross-Cohort AUC Waterfall") +
    theme(panel.grid.major.y = element_blank())

  ggsave(file.path(result_dir, "waterfall_auc.pdf"), width = 8, height = max(4, nrow(results_df) * 0.5), units = "in", dpi = 300)
}

# ============================================================================
# Visualization 3: ROC Overlay (All Cohorts)
# ============================================================================

cat("[INFO] Generating ROC overlay plot\n")

if (length(cohort_predictions) > 0) {
  roc_list <- list()

  for (cohort_name in names(cohort_predictions)) {
    pred <- cohort_predictions[[cohort_name]]
    label <- cohort_labels[[cohort_name]]

    roc_obj <- pROC::roc(label, pred, quiet = TRUE)
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

  colors <- RColorBrewer::brewer.pal(min(9, length(roc_list)), "Set1")

  for (i in seq_along(roc_list)) {
    lines(1 - roc_list[[i]]$roc$specificities, roc_list[[i]]$roc$sensitivities,
          col = colors[i], lwd = 2)
  }

  legend("bottomright",
         legend = sapply(roc_list, function(x) sprintf("%s (AUC=%.3f)", x$cohort, x$auc)),
         col = colors[seq_along(roc_list)],
         lwd = 2, cex = 0.9)

  dev.off()
}

# ============================================================================
# Write sentinel
# ============================================================================

writeLines(c(
  "Cross-Cohort Validation Completed",
  paste("Timestamp:", Sys.time()),
  paste("Cohorts analyzed:", length(cohort_list)),
  "",
  "AUC Summary:",
  capture.output(print(results_df))
), file.path(result_dir, "crosscohort_done.txt"))

cat("[SUCCESS] Cross-cohort analysis completed\n")
cat("Results saved to:", result_dir, "\n")

# ============================================================================
# Visualization 4: UpSet - Shared Significant Features
# ============================================================================

cat("[INFO] Generating UpSet plot for shared features\n")

# Extract significant features per cohort (requires differential abundance results)
# For now, use top 50 features from model weights as proxy

tryCatch({
  feature_weights <- SIAMCAT::feature_weights(siamcat_model)
  top_features <- names(sort(abs(feature_weights), decreasing = TRUE)[1:50])
  
  # Create binary matrix: cohort × feature (1 if present, 0 if absent)
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
}, error = function(e) {
  warning("UpSet plot failed: ", conditionMessage(e))
})

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
  col_fun <- colorRamp2(c(0, 1), c("white", "#4575b4"))
  
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
}, error = function(e) {
  warning("Feature stability heatmap failed: ", conditionMessage(e))
})

# ============================================================================
# Visualization 6: PCoA with Batch Effect (Cohort Coloring)
# ============================================================================

cat("[INFO] Generating PCoA with cohort coloring\n")

tryCatch({
  # Merge all cohorts
  all_samples <- unlist(lapply(cohort_list, function(x) colnames(x$abundance)))
  all_taxa <- unique(unlist(lapply(cohort_list, function(x) rownames(x$abundance))))
  
  merged_mat <- matrix(0, nrow = length(all_taxa), ncol = length(all_samples),
                       dimnames = list(all_taxa, all_samples))
  
  cohort_labels <- c()
  for (cohort_data in cohort_list) {
    mat <- cohort_data$abundance
    merged_mat[rownames(mat), colnames(mat)] <- mat
    cohort_labels <- c(cohort_labels, rep(cohort_data$cohort, ncol(mat)))
  }
  names(cohort_labels) <- all_samples
  
  # Calculate Bray-Curtis distance
  library(vegan)
  dist_mat <- vegdist(t(merged_mat + 1e-6), method = "bray")
  
  # PCoA
  pcoa_obj <- cmdscale(dist_mat, k = 2, eig = TRUE)
  var_exp <- round(100 * pcoa_obj$eig[1:2] / sum(pcoa_obj$eig), 1)
  
  pcoa_df <- data.frame(
    Axis1 = pcoa_obj$points[, 1],
    Axis2 = pcoa_obj$points[, 2],
    Cohort = cohort_labels[rownames(pcoa_obj$points)]
  )
  
  ggplot(pcoa_df, aes(x = Axis1, y = Axis2, color = Cohort)) +
    geom_point(size = 3, alpha = 0.7) +
    stat_ellipse(aes(fill = Cohort), geom = "polygon", alpha = 0.1, level = 0.95) +
    theme_bw(base_size = 12) +
    labs(x = paste0("Axis 1 (", var_exp[1], "%)"),
         y = paste0("Axis 2 (", var_exp[2], "%)"),
         title = "PCoA - Batch Effect Assessment (Colored by Cohort)") +
    theme(legend.position = "right")
  
  ggsave(file.path(result_dir, "pcoa_batch_effect.pdf"), width = 8, height = 6, dpi = 300)
}, error = function(e) {
  warning("PCoA batch effect plot failed: ", conditionMessage(e))
})

# ============================================================================
# Visualization 7: Calibration Curves per Cohort
# ============================================================================

cat("[INFO] Generating calibration curves\n")

if (length(cohort_predictions) > 0) {
  calib_plots <- list()
  
  for (cohort_name in names(cohort_predictions)) {
    pred <- cohort_predictions[[cohort_name]]
    label <- cohort_labels[[cohort_name]]
    
    # Bin predictions
    pred_bins <- cut(pred, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
    calib_df <- data.frame(
      pred = pred,
      label = as.numeric(label == levels(factor(label))[1]),
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
    }
  }
  
  if (length(calib_plots) > 0) {
    combined <- wrap_plots(calib_plots, ncol = 2)
    ggsave(file.path(result_dir, "calibration_per_cohort.pdf"),
           combined, width = 10, height = ceiling(length(calib_plots) / 2) * 4, dpi = 300)
  }
}

# ============================================================================
# Visualization 8: Effect Correlation Matrix (Cohort vs Cohort)
# ============================================================================

cat("[INFO] Generating effect correlation matrix\n")

# This requires differential abundance results per cohort
# For now, use feature mean abundances as proxy

tryCatch({
  # Calculate mean abundance per cohort for top features
  feature_weights <- SIAMCAT::feature_weights(siamcat_model)
  top_features <- names(sort(abs(feature_weights), decreasing = TRUE)[1:30])
  
  effect_mat <- matrix(NA, nrow = length(top_features), ncol = length(cohort_list),
                       dimnames = list(top_features, names(cohort_list)))
  
  for (i in seq_along(cohort_list)) {
    cohort_name <- names(cohort_list)[i]
    abund <- cohort_list[[cohort_name]]$abundance
    present_features <- intersect(top_features, rownames(abund))
    effect_mat[present_features, cohort_name] <- log10(rowMeans(abund[present_features, , drop = FALSE]) + 1e-6)
  }
  
  # Only plot if we have at least 2 cohorts
  if (ncol(effect_mat) >= 2) {
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
  }
}, error = function(e) {
  warning("Effect correlation matrix failed: ", conditionMessage(e))
})

# ============================================================================
# Meta-Analysis (Optional)
# ============================================================================

if (meta_analysis && nrow(results_df) >= 3) {
  cat("[INFO] Performing meta-analysis\n")
  
  tryCatch({
    # Random-effects meta-analysis of AUC
    # Transform AUC to logit for meta-analysis
    results_df <- results_df %>%
      mutate(
        logit_auc = log(auc / (1 - auc)),
        se_logit = (auc_ci_high - auc_ci_low) / (2 * 1.96)  # approximate SE
      )
    
    ma_model <- metafor::rma(yi = logit_auc, sei = se_logit, data = results_df, method = "REML")
    
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
    
    cat("[INFO] Meta-analysis summary:\n")
    cat("  Pooled AUC:", round(ma_summary$pooled_auc, 3), "\n")
    cat("  I²:", round(ma_summary$I2, 1), "%\n")
    cat("  Heterogeneity Q p-value:", format.pval(ma_summary$Q_pvalue, digits = 3), "\n")
    
  }, error = function(e) {
    warning("Meta-analysis failed: ", conditionMessage(e))
  })
}

cat("[SUCCESS] All visualizations completed\n")
