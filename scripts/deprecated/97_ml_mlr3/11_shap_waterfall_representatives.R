#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(iml)
  library(ggplot2)
})

option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character", help="Dimension: bacteria/fungi/virus"),
  make_option(c("-i", "--input-dir"), dest="input_dir", type="character",
              help="Functional ML result directory"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: input-dir]")
)
opt <- parse_args(OptionParser(option_list=option_list))

required <- c("workdir", "dimension", "input_dir")
missing <- required[vapply(required, function(name) is.null(opt[[name]]) || !nzchar(opt[[name]]), logical(1))]
if(length(missing) > 0L) stop("Missing required arguments: ", paste(missing, collapse=", "))
if(!opt$dimension %in% c("bacteria", "fungi", "virus")) stop("Invalid dimension: ", opt$dimension)

resolve_path <- function(path) {
  if(grepl("^/", path)) path else file.path(opt$workdir, path)
}
opt$input_dir <- normalizePath(resolve_path(opt$input_dir), mustWork=TRUE)
if(is.null(opt$outdir)) opt$outdir <- opt$input_dir else opt$outdir <- resolve_path(opt$outdir)
dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)
opt$outdir <- normalizePath(opt$outdir, mustWork=TRUE)

type <- basename(opt$input_dir)
shap_file <- file.path(opt$input_dir, sprintf("shap_values_%s.rds", opt$dimension))
summary_file <- file.path(opt$input_dir, sprintf("nested_cv_summary_%s.csv", opt$dimension))
processed_file <- file.path(opt$input_dir, sprintf("processed_%s.rds", type))
for(path in c(shap_file, summary_file, processed_file)) if(!file.exists(path)) stop("Input file not found: ", path)

summary_data <- read.csv(summary_file, stringsAsFactors=FALSE, check.names=FALSE)
if(!all(c("learner", "mean_auc") %in% names(summary_data))) stop("Nested-CV summary lacks learner/mean_auc columns")
best_row <- which.max(summary_data$mean_auc)
best_learner <- summary_data$learner[best_row]
cv_file <- file.path(opt$input_dir, sprintf("nested_cv_%s_%s.rds", best_learner, opt$dimension))
if(!file.exists(cv_file)) stop("Best learner nested-CV RDS not found: ", cv_file)

processed <- readRDS(processed_file)
shap_data <- readRDS(shap_file)
if(!all(c("label", "meta") %in% names(processed)) || !"sample_id" %in% names(processed$meta)) {
  stop("Processed RDS lacks label or meta$sample_id")
}
if(!all(c("positive_class", "sample_ids", "shapley_objects") %in% names(shap_data))) {
  stop("SHAP RDS lacks positive_class, sample_ids, or shapley_objects")
}

sample_ids <- as.character(processed$meta$sample_id)
truth <- as.character(processed$label)
if(length(sample_ids) != length(truth) || anyDuplicated(sample_ids)) stop("Processed sample IDs are invalid")
positive_class <- as.character(shap_data$positive_class)
negative_class <- setdiff(unique(truth), positive_class)
if(length(negative_class) != 1L) stop("Could not identify the negative class")

cv_result <- readRDS(cv_file)
prediction <- cv_result$prediction()
row_ids <- as.integer(prediction$row_ids)
probabilities <- prediction$prob
if(length(row_ids) != nrow(probabilities) || anyDuplicated(row_ids) || any(!row_ids %in% seq_along(sample_ids))) {
  stop("Nested-CV outer-fold row IDs are invalid")
}
if(!positive_class %in% colnames(probabilities)) stop("Positive-class probability missing from nested-CV predictions")

prediction_data <- data.frame(
  sample_id=sample_ids[row_ids],
  true_label=truth[row_ids],
  predicted_label=as.character(prediction$response),
  positive_probability=as.numeric(probabilities[, positive_class]),
  stringsAsFactors=FALSE
)
prediction_data$predicted_probability <- ifelse(
  prediction_data$predicted_label == positive_class,
  prediction_data$positive_probability,
  1 - prediction_data$positive_probability
)
prediction_data$error_deviation <- ifelse(
  prediction_data$true_label == positive_class,
  1 - prediction_data$positive_probability,
  prediction_data$positive_probability
)

available_ids <- intersect(as.character(shap_data$sample_ids), names(shap_data$shapley_objects))
candidates <- prediction_data[prediction_data$sample_id %in% available_ids, , drop=FALSE]
if(nrow(candidates) == 0L) stop("No nested-CV predictions correspond to saved SHAP objects")

pick_first <- function(data, order_value, decreasing=TRUE) {
  if(nrow(data) == 0L) stop("No eligible representative sample")
  data[order(order_value, data$sample_id, decreasing=decreasing)[1L], , drop=FALSE]
}
case_row <- pick_first(candidates[candidates$predicted_label == positive_class, , drop=FALSE],
                       candidates$positive_probability[candidates$predicted_label == positive_class])
control_subset <- candidates[candidates$predicted_label == negative_class, , drop=FALSE]
control_row <- pick_first(control_subset, 1 - control_subset$positive_probability)
misclassified <- candidates[candidates$predicted_label != candidates$true_label, , drop=FALSE]
if(nrow(misclassified) > 0L) {
  failure_row <- pick_first(misclassified, misclassified$error_deviation)
  failure_type <- "misclassified"
} else {
  failure_row <- pick_first(candidates, -abs(candidates$positive_probability - 0.5))
  failure_type <- "uncertain_fallback"
}

representatives <- rbind(
  transform(case_row, representative_type="high_confidence_case"),
  transform(control_row, representative_type="high_confidence_control"),
  transform(failure_row, representative_type=failure_type)
)
representatives$learner <- best_learner
representatives <- representatives[, c("representative_type", "sample_id", "true_label", "predicted_label",
                                       "positive_probability", "predicted_probability", "error_deviation", "learner")]

plot_one <- function(row, suffix) {
  sample_id <- row$sample_id[[1L]]
  shapley <- shap_data$shapley_objects[[sample_id]]
  if(is.null(shapley)) stop("SHAP object missing for sample: ", sample_id)
  plot_object <- plot(shapley) +
    labs(
      title=sprintf("%s: %s", gsub("_", " ", row$representative_type[[1L]]), sample_id),
      subtitle=sprintf("truth=%s; predicted=%s; P(%s)=%.4f; learner=%s",
                       row$true_label[[1L]], row$predicted_label[[1L]], positive_class,
                       row$positive_probability[[1L]], best_learner)
    ) +
    theme_bw(base_size=10) +
    theme(plot.title=element_text(face="bold"))
  output_file <- file.path(opt$outdir, sprintf("shap_waterfall_%s_%s.pdf", suffix, opt$dimension))
  ggsave(output_file, plot=plot_object, width=10, height=7, units="in", device=cairo_pdf)
  output_file
}

outputs <- c(
  plot_one(representatives[1L, , drop=FALSE], "case"),
  plot_one(representatives[2L, , drop=FALSE], "control"),
  plot_one(representatives[3L, , drop=FALSE], "misclassified")
)
csv_file <- file.path(opt$outdir, sprintf("representative_samples_%s.csv", opt$dimension))
write.csv(representatives, csv_file, row.names=FALSE, quote=TRUE)
cat(sprintf("[INFO] %s/%s best learner: %s\n", opt$dimension, type, best_learner))
print(representatives, row.names=FALSE)
cat("[INFO] Wrote:\n", paste(c(outputs, csv_file), collapse="\n"), "\n")
