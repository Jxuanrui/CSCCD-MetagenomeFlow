#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(pROC)
  library(ggplot2)
})

# Parse arguments
option_list <- list(
  make_option(c("-w", "--workdir"), type="character",
              help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character",
              help="Dimension: bacteria/virus/fungi"),
  make_option(c("-i", "--indir"), type="character", default=NULL,
              help="Prediction input directory [default: workdir/result/stat/dimension/ml_mlr3]"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: same as indir]"),
  make_option(c("--positive-class"), dest="positive_class", type="character",
              default="case", help="Positive class label [default: case]"),
  make_option(c("--n-bootstrap"), dest="n_bootstrap", type="integer", default=1000,
              help="Bootstrap resamples for AUC confidence interval [default: 1000]"),
  make_option(c("--seed"), type="integer", default=42,
              help="Random seed [default: 42]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate inputs
required <- c("workdir", "dimension")
missing <- required[!required %in% names(opt) | vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}

valid_dimensions <- c("bacteria", "virus", "fungi")
if(!opt$dimension %in% valid_dimensions) {
  stop("Invalid dimension: ", opt$dimension,
       ". Expected one of: ", paste(valid_dimensions, collapse=", "))
}
if(is.null(opt$positive_class) || length(opt$positive_class) != 1 ||
   is.na(opt$positive_class) || opt$positive_class == "") {
  stop("--positive-class must be a non-empty label string")
}
if(is.null(opt$n_bootstrap) || length(opt$n_bootstrap) != 1 ||
   is.na(opt$n_bootstrap) || !is.finite(opt$n_bootstrap) || opt$n_bootstrap < 1) {
  stop("--n-bootstrap must be a positive integer")
}
if(is.null(opt$seed) || length(opt$seed) != 1 || is.na(opt$seed) || !is.finite(opt$seed)) {
  stop("--seed must be a finite integer")
}

if(is.null(opt$indir)) {
  opt$indir <- file.path(opt$workdir, "result", "stat", opt$dimension, "ml_mlr3")
}
if(is.null(opt$outdir)) {
  opt$outdir <- opt$indir
}
if(!dir.exists(opt$indir)) {
  stop("Input directory not found: ", opt$indir)
}
dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

start_time <- Sys.time()

cat(sprintf("[INFO] Starting pooled nested-CV evaluation\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Input directory: %s\n", opt$indir))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Positive class: %s\n", opt$positive_class))
cat(sprintf("[INFO] Bootstrap resamples: %d; seed: %d\n",
            opt$n_bootstrap, opt$seed))

prediction_pattern <- sprintf(
  "^predictions_(.+)_%s\\.csv$",
  opt$dimension
)
prediction_files <- list.files(
  opt$indir,
  pattern=prediction_pattern,
  full.names=TRUE
)
prediction_files <- sort(prediction_files)
if(length(prediction_files) == 0) {
  stop("No prediction files found in ", opt$indir,
       " matching predictions_*_", opt$dimension, ".csv")
}

prediction_basenames <- basename(prediction_files)
learner_ids <- sub(prediction_pattern, "\\1", prediction_basenames)
if(any(learner_ids == prediction_basenames) || any(learner_ids == "")) {
  stop("Failed to extract learner IDs from prediction filenames")
}
if(anyDuplicated(learner_ids)) {
  stop("Duplicate learner IDs discovered: ",
       paste(unique(learner_ids[duplicated(learner_ids)]), collapse=", "))
}

cat(sprintf("[INFO] Discovered %d learner prediction file(s): %s\n",
            length(learner_ids), paste(learner_ids, collapse=", ")))

trapezoid_auc <- function(x, y) {
  if(length(x) < 2) {
    return(0)
  }
  sum(diff(x) * (head(y, -1) + tail(y, -1)) / 2)
}

manual_pr_curve <- function(labels, probabilities) {
  positives <- sum(labels == 1)
  if(positives == 0) {
    stop("Cannot compute a precision-recall curve without positive samples")
  }

  ordering <- order(probabilities, decreasing=TRUE)
  sorted_labels <- labels[ordering]
  sorted_probabilities <- probabilities[ordering]
  true_positives <- cumsum(sorted_labels == 1)
  false_positives <- cumsum(sorted_labels == 0)
  threshold_ends <- which(!duplicated(sorted_probabilities, fromLast=TRUE))

  recall <- true_positives[threshold_ends] / positives
  precision <- true_positives[threshold_ends] /
    (true_positives[threshold_ends] + false_positives[threshold_ends])

  data.frame(
    recall=c(0, recall),
    precision=c(1, precision),
    stringsAsFactors=FALSE
  )
}

compute_pr <- function(labels, probabilities, use_prroc) {
  curve_data <- manual_pr_curve(labels, probabilities)
  if(use_prroc) {
    prroc_result <- PRROC::pr.curve(
      scores.class0=probabilities[labels == 1],
      scores.class1=probabilities[labels == 0],
      curve=FALSE
    )
    auc_pr <- as.numeric(prroc_result$auc.integral)
  } else {
    auc_pr <- trapezoid_auc(curve_data$recall, curve_data$precision)
  }

  list(auc=auc_pr, curve=curve_data)
}

bootstrap_auc_ci <- function(labels, probabilities, n_bootstrap) {
  auc_values <- numeric(n_bootstrap)
  valid_count <- 0L
  attempts <- 0L
  max_attempts <- max(100L, n_bootstrap * 20L)
  n_samples <- length(labels)

  while(valid_count < n_bootstrap && attempts < max_attempts) {
    attempts <- attempts + 1L
    bootstrap_indices <- sample.int(n_samples, n_samples, replace=TRUE)
    bootstrap_labels <- labels[bootstrap_indices]
    if(length(unique(bootstrap_labels)) < 2) {
      next
    }

    bootstrap_roc <- pROC::roc(
      response=bootstrap_labels,
      predictor=probabilities[bootstrap_indices],
      levels=c(0, 1),
      direction="<",
      quiet=TRUE
    )
    valid_count <- valid_count + 1L
    auc_values[valid_count] <- as.numeric(pROC::auc(bootstrap_roc))
  }

  if(valid_count < n_bootstrap) {
    stop("Unable to generate ", n_bootstrap,
         " valid bootstrap samples containing both classes")
  }

  quantile(auc_values, probs=c(0.025, 0.975), names=FALSE, type=7)
}

build_palette <- function(learner_names) {
  n_learners <- length(learner_names)
  if(requireNamespace("RColorBrewer", quietly=TRUE)) {
    palette_info <- RColorBrewer::brewer.pal.info
    max_colors <- palette_info["Dark2", "maxcolors"]
    base_colors <- RColorBrewer::brewer.pal(min(max(3, n_learners), max_colors), "Dark2")
    colors <- if(n_learners <= length(base_colors)) {
      base_colors[seq_len(n_learners)]
    } else {
      grDevices::colorRampPalette(base_colors)(n_learners)
    }
  } else {
    colors <- grDevices::hcl.colors(n_learners, palette="Dark 3")
  }
  setNames(colors, learner_names)
}

use_prroc <- requireNamespace("PRROC", quietly=TRUE)
if(use_prroc) {
  cat(sprintf("[INFO] PRROC available; using PRROC integral for AUC-PR\n"))
} else {
  cat(sprintf("[INFO] PRROC unavailable; using manual trapezoidal AUC-PR\n"))
}

set.seed(opt$seed)
summary_rows <- list()
bootstrap_rows <- list()
roc_curve_rows <- list()
pr_curve_rows <- list()
confusion_rows <- list()
calibration_rows <- list()

for(file_index in seq_along(prediction_files)) {
  prediction_file <- prediction_files[file_index]
  learner_id <- learner_ids[file_index]
  cat(sprintf("[INFO] Evaluating learner: %s\n", learner_id))
  cat(sprintf("[INFO] Reading predictions: %s\n", prediction_file))

  predictions <- read.csv(
    prediction_file,
    stringsAsFactors=FALSE,
    check.names=FALSE
  )
  required_columns <- c("sample_id", "truth", "prob_positive", "fold")
  missing_columns <- setdiff(required_columns, names(predictions))
  if(length(missing_columns) > 0) {
    stop("Prediction file for ", learner_id, " is missing columns: ",
         paste(missing_columns, collapse=", "))
  }
  if(nrow(predictions) == 0) {
    stop("Prediction file for ", learner_id, " contains no rows")
  }
  if(anyNA(predictions$sample_id) || any(predictions$sample_id == "") ||
     anyDuplicated(predictions$sample_id)) {
    stop("Prediction file for ", learner_id,
         " must contain unique, non-empty sample_id values")
  }
  if(anyNA(predictions$truth) || any(predictions$truth == "")) {
    stop("Prediction file for ", learner_id, " contains missing truth labels")
  }

  truth_levels <- unique(as.character(predictions$truth))
  if(length(truth_levels) != 2) {
    stop("Prediction file for ", learner_id,
         " must contain exactly two truth labels; found: ",
         paste(truth_levels, collapse=", "))
  }
  if(!opt$positive_class %in% truth_levels) {
    stop("Positive class '", opt$positive_class,
         "' is not present in truth for ", learner_id,
         "; available labels: ", paste(truth_levels, collapse=", "))
  }

  probabilities <- suppressWarnings(as.numeric(predictions$prob_positive))
  if(anyNA(probabilities) || any(!is.finite(probabilities)) ||
     any(probabilities < 0 | probabilities > 1)) {
    stop("Prediction probabilities for ", learner_id,
         " must be finite numeric values between 0 and 1")
  }
  labels <- as.integer(as.character(predictions$truth) == opt$positive_class)
  class_counts <- table(predictions$truth)

  roc_obj <- pROC::roc(
    response=labels,
    predictor=probabilities,
    levels=c(0, 1),
    direction="<",
    quiet=TRUE
  )
  auc_roc <- as.numeric(pROC::auc(roc_obj))
  best_coords <- pROC::coords(
    roc_obj,
    x="best",
    best.method="youden",
    ret=c("threshold", "sensitivity", "specificity"),
    transpose=FALSE
  )
  if(is.data.frame(best_coords) || is.matrix(best_coords)) {
    best_threshold <- as.numeric(best_coords[1, "threshold"])
  } else {
    best_threshold <- as.numeric(best_coords["threshold"])
  }
  if(length(best_threshold) != 1 || is.na(best_threshold)) {
    stop("Unable to determine a Youden-optimal threshold for ", learner_id)
  }

  predicted_labels <- as.integer(probabilities >= best_threshold)
  true_positive <- sum(predicted_labels == 1 & labels == 1)
  true_negative <- sum(predicted_labels == 0 & labels == 0)
  false_positive <- sum(predicted_labels == 1 & labels == 0)
  false_negative <- sum(predicted_labels == 0 & labels == 1)

  accuracy <- (true_positive + true_negative) / length(labels)
  sensitivity <- true_positive / (true_positive + false_negative)
  specificity <- true_negative / (true_negative + false_positive)
  precision <- if((true_positive + false_positive) == 0) {
    0
  } else {
    true_positive / (true_positive + false_positive)
  }
  f1_score <- if((precision + sensitivity) == 0) {
    0
  } else {
    2 * precision * sensitivity / (precision + sensitivity)
  }
  balanced_accuracy <- (sensitivity + specificity) / 2
  brier_score <- mean((probabilities - labels)^2)

  pr_result <- compute_pr(labels, probabilities, use_prroc)
  auc_pr <- pr_result$auc
  auc_ci <- bootstrap_auc_ci(labels, probabilities, opt$n_bootstrap)

  roc_curve_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    false_positive_rate=1 - as.numeric(roc_obj$specificities),
    true_positive_rate=as.numeric(roc_obj$sensitivities),
    stringsAsFactors=FALSE
  )
  pr_curve_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    recall=pr_result$curve$recall,
    precision=pr_result$curve$precision,
    stringsAsFactors=FALSE
  )

  negative_class <- setdiff(truth_levels, opt$positive_class)
  confusion_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    truth=factor(
      c(negative_class, negative_class, opt$positive_class, opt$positive_class),
      levels=c(negative_class, opt$positive_class)
    ),
    predicted=factor(
      c(negative_class, opt$positive_class, negative_class, opt$positive_class),
      levels=c(negative_class, opt$positive_class)
    ),
    count=c(true_negative, false_positive, false_negative, true_positive),
    stringsAsFactors=FALSE
  )

  calibration_data <- data.frame(
    probability=probabilities,
    label=labels,
    stringsAsFactors=FALSE
  )
  calibration_data$bin <- pmin(
    10L,
    ceiling(rank(calibration_data$probability, ties.method="first") /
              nrow(calibration_data) * 10)
  )
  calibration_summary <- aggregate(
    cbind(probability, label) ~ bin,
    data=calibration_data,
    FUN=mean
  )
  calibration_summary$n_samples <- as.integer(table(calibration_data$bin)[
    as.character(calibration_summary$bin)
  ])
  calibration_summary$learner <- learner_id
  names(calibration_summary)[names(calibration_summary) == "probability"] <-
    "mean_predicted_probability"
  names(calibration_summary)[names(calibration_summary) == "label"] <-
    "observed_frequency"
  calibration_rows[[learner_id]] <- calibration_summary

  summary_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    n_samples=length(labels),
    auc_roc=auc_roc,
    auc_roc_ci_low=auc_ci[1],
    auc_roc_ci_high=auc_ci[2],
    auc_pr=auc_pr,
    accuracy=accuracy,
    sensitivity=sensitivity,
    specificity=specificity,
    f1_score=f1_score,
    balanced_accuracy=balanced_accuracy,
    brier_score=brier_score,
    stringsAsFactors=FALSE
  )
  bootstrap_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    auc_roc=auc_roc,
    ci_low=auc_ci[1],
    ci_high=auc_ci[2],
    stringsAsFactors=FALSE
  )

  cat(sprintf("[INFO] %s samples: %d; class balance: %s\n",
              learner_id, length(labels),
              paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
                    collapse=", ")))
  cat(sprintf("[INFO] %s AUC-ROC: %.6f (95%% CI %.6f-%.6f); AUC-PR: %.6f\n",
              learner_id, auc_roc, auc_ci[1], auc_ci[2], auc_pr))
  cat(sprintf("[INFO] %s Youden threshold: %.6f; accuracy: %.6f; sensitivity: %.6f; specificity: %.6f; F1: %.6f; balanced accuracy: %.6f; Brier: %.6f\n",
              learner_id, best_threshold, accuracy, sensitivity, specificity,
              f1_score, balanced_accuracy, brier_score))
}

performance_summary <- do.call(rbind, summary_rows)
bootstrap_summary <- do.call(rbind, bootstrap_rows)
roc_curve_data <- do.call(rbind, roc_curve_rows)
pr_curve_data <- do.call(rbind, pr_curve_rows)
confusion_data <- do.call(rbind, confusion_rows)
calibration_data <- do.call(rbind, calibration_rows)
rownames(performance_summary) <- NULL
rownames(bootstrap_summary) <- NULL
rownames(roc_curve_data) <- NULL
rownames(pr_curve_data) <- NULL
rownames(confusion_data) <- NULL
rownames(calibration_data) <- NULL

performance_summary_file <- file.path(
  opt$outdir, sprintf("performance_summary_%s.csv", opt$dimension)
)
bootstrap_summary_file <- file.path(
  opt$outdir, sprintf("bootstrap_ci_%s.csv", opt$dimension)
)
write.csv(performance_summary, performance_summary_file,
          row.names=FALSE, quote=TRUE)
write.csv(bootstrap_summary, bootstrap_summary_file,
          row.names=FALSE, quote=TRUE)

learner_order <- performance_summary$learner
learner_colors <- build_palette(learner_order)
roc_curve_data$learner <- factor(roc_curve_data$learner, levels=learner_order)
pr_curve_data$learner <- factor(pr_curve_data$learner, levels=learner_order)
confusion_data$learner <- factor(confusion_data$learner, levels=learner_order)
calibration_data$learner <- factor(calibration_data$learner, levels=learner_order)
performance_summary$learner <- factor(performance_summary$learner, levels=learner_order)

auc_labels <- setNames(
  sprintf("%s (AUC=%.3f)", learner_order, performance_summary$auc_roc),
  learner_order
)

roc_plot <- ggplot(
  roc_curve_data,
  aes(x=false_positive_rate, y=true_positive_rate, color=learner)
) +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="grey55") +
  geom_step(linewidth=0.9) +
  scale_color_manual(values=learner_colors, labels=auc_labels) +
  coord_equal() +
  labs(
    title=sprintf("Pooled ROC Curves - %s", opt$dimension),
    x="False Positive Rate",
    y="True Positive Rate",
    color="Learner"
  ) +
  theme_bw() +
  theme(legend.position="right")

ggsave(
  file.path(opt$outdir, sprintf("roc_curves_%s.pdf", opt$dimension)),
  plot=roc_plot, width=7.5, height=6, device="pdf"
)

pr_plot <- ggplot(
  pr_curve_data,
  aes(x=recall, y=precision, color=learner)
) +
  geom_step(linewidth=0.9) +
  scale_color_manual(values=learner_colors) +
  coord_cartesian(xlim=c(0, 1), ylim=c(0, 1)) +
  labs(
    title=sprintf("Pooled Precision-Recall Curves - %s", opt$dimension),
    x="Recall",
    y="Precision",
    color="Learner"
  ) +
  theme_bw() +
  theme(legend.position="right")

ggsave(
  file.path(opt$outdir, sprintf("pr_curves_%s.pdf", opt$dimension)),
  plot=pr_plot, width=7.5, height=6, device="pdf"
)

confusion_plot <- ggplot(
  confusion_data,
  aes(x=predicted, y=truth, fill=count)
) +
  geom_tile(color="white") +
  geom_text(aes(label=count), size=4) +
  facet_wrap(~ learner) +
  scale_fill_gradient(low="white", high="#2166AC") +
  coord_equal() +
  labs(
    title=sprintf("Confusion Matrices at Youden Threshold - %s", opt$dimension),
    x="Predicted Class",
    y="True Class",
    fill="Count"
  ) +
  theme_bw() +
  theme(panel.grid=element_blank())

ggsave(
  file.path(opt$outdir, sprintf("confusion_matrices_%s.pdf", opt$dimension)),
  plot=confusion_plot,
  width=max(7.5, 3.8 * min(length(learner_order), 3)),
  height=max(5, 4.0 * ceiling(length(learner_order) / 3)),
  device="pdf"
)

calibration_plot <- ggplot(
  calibration_data,
  aes(
    x=mean_predicted_probability,
    y=observed_frequency,
    color=learner,
    group=learner
  )
) +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="grey55") +
  geom_line(linewidth=0.9) +
  geom_point(aes(size=n_samples), alpha=0.85) +
  scale_color_manual(values=learner_colors) +
  scale_size_continuous(range=c(2, 5)) +
  coord_equal(xlim=c(0, 1), ylim=c(0, 1)) +
  labs(
    title=sprintf("Calibration Plots - %s", opt$dimension),
    x="Mean Predicted Probability",
    y="Observed Positive Frequency",
    color="Learner",
    size="Bin Samples"
  ) +
  theme_bw() +
  theme(legend.position="right")

ggsave(
  file.path(opt$outdir, sprintf("calibration_plots_%s.pdf", opt$dimension)),
  plot=calibration_plot, width=7.5, height=6, device="pdf"
)

performance_plot <- ggplot(
  performance_summary,
  aes(x=learner, y=auc_roc, fill=learner)
) +
  geom_col(width=0.7, show.legend=FALSE) +
  geom_errorbar(
    aes(ymin=auc_roc_ci_low, ymax=auc_roc_ci_high),
    width=0.18,
    linewidth=0.7
  ) +
  scale_fill_manual(values=learner_colors) +
  coord_cartesian(ylim=c(0, 1)) +
  labs(
    title=sprintf("Pooled AUC-ROC with Bootstrap 95%% CI - %s", opt$dimension),
    x="Learner",
    y="AUC-ROC"
  ) +
  theme_bw() +
  theme(axis.text.x=element_text(angle=30, hjust=1))

ggsave(
  file.path(opt$outdir, sprintf("performance_barplot_%s.pdf", opt$dimension)),
  plot=performance_plot, width=7.5, height=5.5, device="pdf"
)

cat(sprintf("[INFO] Saved performance summary: %s\n", performance_summary_file))
cat(sprintf("[INFO] Saved bootstrap confidence intervals: %s\n", bootstrap_summary_file))
cat(sprintf("[INFO] Saved ROC curves: %s\n",
            file.path(opt$outdir, sprintf("roc_curves_%s.pdf", opt$dimension))))
cat(sprintf("[INFO] Saved precision-recall curves: %s\n",
            file.path(opt$outdir, sprintf("pr_curves_%s.pdf", opt$dimension))))
cat(sprintf("[INFO] Saved confusion matrices: %s\n",
            file.path(opt$outdir, sprintf("confusion_matrices_%s.pdf", opt$dimension))))
cat(sprintf("[INFO] Saved calibration plots: %s\n",
            file.path(opt$outdir, sprintf("calibration_plots_%s.pdf", opt$dimension))))
cat(sprintf("[INFO] Saved performance bar plot: %s\n",
            file.path(opt$outdir, sprintf("performance_barplot_%s.pdf", opt$dimension))))

total_runtime <- as.numeric(difftime(Sys.time(), start_time, units="secs"))
cat(sprintf("[INFO] Total runtime: %.1f seconds (%.2f minutes)\n",
            total_runtime, total_runtime / 60))
cat(sprintf("[INFO] Pooled nested-CV evaluation completed successfully\n"))
