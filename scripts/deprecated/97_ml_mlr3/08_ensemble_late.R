#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
})

option_list <- list(
  make_option(c("-w", "--workdir"), type="character",
              help="Project work directory"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: workdir/result/stat/ensemble/ml_mlr3]"),
  make_option(c("--dimensions"), type="character", default="bacteria,virus,fungi",
              help="Comma-separated dimensions [default: bacteria,virus,fungi]"),
  make_option(c("--base-learner"), dest="base_learner", type="character",
              default="best",
              help="Base learner ID or 'best' per dimension [default: best]"),
  make_option(c("--meta-learner"), dest="meta_learner", type="character",
              default="logreg",
              help="Meta learner: logreg/glmnet [default: logreg]"),
  make_option(c("--outer-folds"), dest="outer_folds", type="integer", default=5,
              help="Number of shared outer folds [default: 5]"),
  make_option(c("--seed"), type="integer", default=42,
              help="Random seed [default: 42]")
)

opt <- parse_args(OptionParser(option_list=option_list))

if(is.null(opt$workdir) || length(opt$workdir) != 1 || is.na(opt$workdir) ||
   opt$workdir == "") {
  stop("Missing required argument: workdir")
}
if(!dir.exists(opt$workdir)) {
  stop("Work directory not found: ", opt$workdir)
}
if(is.null(opt$outdir)) {
  opt$outdir <- file.path(
    opt$workdir, "result", "stat", "ensemble", "ml_mlr3"
  )
}

dimensions <- trimws(strsplit(opt$dimensions, ",", fixed=TRUE)[[1]])
dimensions <- dimensions[nzchar(dimensions)]
if(length(dimensions) == 0 || anyDuplicated(dimensions)) {
  stop("--dimensions must contain unique, non-empty comma-separated values")
}
valid_dimensions <- c("bacteria", "virus", "fungi")
invalid_dimensions <- setdiff(dimensions, valid_dimensions)
if(length(invalid_dimensions) > 0) {
  stop("Invalid dimension(s): ", paste(invalid_dimensions, collapse=", "),
       ". Expected values from: ", paste(valid_dimensions, collapse=", "))
}

valid_base_learners <- c(
  "lasso", "ridge", "elasticNet", "randomForest", "xgboost", "svm"
)
if(is.null(opt$base_learner) || length(opt$base_learner) != 1 ||
   is.na(opt$base_learner) || opt$base_learner == "") {
  stop("--base-learner must be 'best' or a supported learner ID")
}
if(opt$base_learner != "best" && !opt$base_learner %in% valid_base_learners) {
  stop("Invalid --base-learner: ", opt$base_learner,
       ". Expected 'best' or one of: ",
       paste(valid_base_learners, collapse=", "))
}
if(is.null(opt$meta_learner) || length(opt$meta_learner) != 1 ||
   is.na(opt$meta_learner) || !opt$meta_learner %in% c("logreg", "glmnet")) {
  stop("--meta-learner must be one of: logreg, glmnet")
}
if(is.null(opt$outer_folds) || length(opt$outer_folds) != 1 ||
   is.na(opt$outer_folds) || !is.finite(opt$outer_folds) || opt$outer_folds < 2) {
  stop("--outer-folds must be an integer of at least 2")
}
if(is.null(opt$seed) || length(opt$seed) != 1 || is.na(opt$seed) ||
   !is.finite(opt$seed)) {
  stop("--seed must be a finite integer")
}

required_packages <- c("mlr3", "mlr3learners", "pROC")
if(opt$meta_learner == "glmnet") {
  required_packages <- c(
    required_packages, "mlr3tuning", "paradox", "bbotk"
  )
}
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, quietly=TRUE, FUN.VALUE=logical(1))
]
if(length(missing_packages) > 0) {
  stop("Required package(s) not installed: ",
       paste(missing_packages, collapse=", "))
}

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)
start_time <- Sys.time()

cat(sprintf("[INFO] Starting leakage-safe late-fusion stacking\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Dimensions: %s\n", paste(dimensions, collapse=", ")))
cat(sprintf("[INFO] Base learner selection: %s\n", opt$base_learner))
cat(sprintf("[INFO] Meta learner: %s\n", opt$meta_learner))
cat(sprintf("[INFO] Outer folds: %d; seed: %d\n", opt$outer_folds, opt$seed))

read_summary <- function(dimension) {
  input_dir <- file.path(
    opt$workdir, "result", "stat", dimension, "ml_mlr3"
  )
  summary_pattern <- sprintf("^nested_cv_summary_%s\\.csv$", dimension)
  summary_files <- list.files(
    input_dir, pattern=summary_pattern, full.names=TRUE
  )
  if(length(summary_files) != 1) {
    stop("Expected exactly one summary file in ", input_dir,
         " matching nested_cv_summary_", dimension, ".csv; found ",
         length(summary_files))
  }
  summary_data <- read.csv(
    summary_files[[1]], stringsAsFactors=FALSE, check.names=FALSE
  )
  required_columns <- c("learner", "mean_auc")
  missing_columns <- setdiff(required_columns, names(summary_data))
  if(length(missing_columns) > 0) {
    stop("Summary file for ", dimension, " is missing columns: ",
         paste(missing_columns, collapse=", "))
  }
  if(nrow(summary_data) == 0 || anyNA(summary_data$learner) ||
     any(summary_data$learner == "") || anyDuplicated(summary_data$learner)) {
    stop("Summary file for ", dimension,
         " must contain unique, non-empty learner IDs")
  }
  summary_data$mean_auc <- suppressWarnings(as.numeric(summary_data$mean_auc))
  if(anyNA(summary_data$mean_auc) || any(!is.finite(summary_data$mean_auc)) ||
     any(summary_data$mean_auc < 0 | summary_data$mean_auc > 1)) {
    stop("Summary file for ", dimension,
         " contains invalid mean_auc values")
  }
  list(data=summary_data, input_dir=input_dir, file=summary_files[[1]])
}

load_dimension <- function(dimension) {
  summary_info <- read_summary(dimension)
  summary_data <- summary_info$data
  if(opt$base_learner == "best") {
    learner_id <- summary_data$learner[which.max(summary_data$mean_auc)]
  } else {
    learner_id <- opt$base_learner
    if(!learner_id %in% summary_data$learner) {
      stop("Requested base learner '", learner_id,
           "' is absent from summary for ", dimension)
    }
  }
  summary_row <- summary_data[summary_data$learner == learner_id, , drop=FALSE]
  prediction_pattern <- sprintf(
    "^predictions_%s_%s\\.csv$", learner_id, dimension
  )
  prediction_files <- list.files(
    summary_info$input_dir, pattern=prediction_pattern, full.names=TRUE
  )
  if(length(prediction_files) != 1) {
    stop("Expected exactly one prediction file in ", summary_info$input_dir,
         " matching predictions_", learner_id, "_", dimension,
         ".csv; found ", length(prediction_files))
  }
  predictions <- read.csv(
    prediction_files[[1]], stringsAsFactors=FALSE, check.names=FALSE
  )
  required_columns <- c("sample_id", "truth", "prob_positive", "fold")
  missing_columns <- setdiff(required_columns, names(predictions))
  if(length(missing_columns) > 0) {
    stop("Prediction file for ", dimension, " is missing columns: ",
         paste(missing_columns, collapse=", "))
  }
  predictions <- predictions[, required_columns, drop=FALSE]
  if(nrow(predictions) == 0 || anyNA(predictions$sample_id) ||
     any(predictions$sample_id == "") || anyDuplicated(predictions$sample_id)) {
    stop("Prediction file for ", dimension,
         " must contain unique, non-empty sample_id values")
  }
  if(anyNA(predictions$truth) || any(predictions$truth == "")) {
    stop("Prediction file for ", dimension, " contains missing truth labels")
  }
  predictions$prob_positive <- suppressWarnings(
    as.numeric(predictions$prob_positive)
  )
  if(anyNA(predictions$prob_positive) ||
     any(!is.finite(predictions$prob_positive)) ||
     any(predictions$prob_positive < 0 | predictions$prob_positive > 1)) {
    stop("Prediction probabilities for ", dimension,
         " must be finite numeric values between 0 and 1")
  }
  predictions$fold <- suppressWarnings(as.integer(predictions$fold))
  if(anyNA(predictions$fold) || any(predictions$fold < 1) ||
     max(predictions$fold) != opt$outer_folds ||
     !setequal(unique(predictions$fold), seq_len(opt$outer_folds))) {
    stop("Fold assignment for ", dimension, " must contain exactly folds 1..",
         opt$outer_folds, "; observed: ",
         paste(sort(unique(predictions$fold)), collapse=", "))
  }
  if(length(unique(predictions$truth)) != 2) {
    stop("Prediction file for ", dimension,
         " must contain exactly two truth labels")
  }
  cat(sprintf("[INFO] %s: selected %s (mean fold AUC %.6f)\n",
              dimension, learner_id, summary_row$mean_auc[[1]]))
  cat(sprintf("[INFO] %s: reading predictions %s\n",
              dimension, prediction_files[[1]]))
  list(
    dimension=dimension,
    learner=learner_id,
    summary_auc=summary_row$mean_auc[[1]],
    summary_sd=if("sd_auc" %in% names(summary_row)) {
      suppressWarnings(as.numeric(summary_row$sd_auc[[1]]))
    } else {
      NA_real_
    },
    predictions=predictions
  )
}

dimension_data <- lapply(dimensions, load_dimension)
names(dimension_data) <- dimensions

reference <- dimension_data[[1]]$predictions
reference_ids <- reference$sample_id
for(dimension in dimensions[-1]) {
  current <- dimension_data[[dimension]]$predictions
  if(!setequal(reference_ids, current$sample_id)) {
    missing_ids <- setdiff(reference_ids, current$sample_id)
    extra_ids <- setdiff(current$sample_id, reference_ids)
    stop("sample_id mismatch between ", dimensions[[1]], " and ", dimension,
         "; missing: ", paste(head(missing_ids, 10), collapse=", "),
         "; extra: ", paste(head(extra_ids, 10), collapse=", "))
  }
  current <- current[match(reference_ids, current$sample_id), , drop=FALSE]
  if(!identical(as.character(reference$truth), as.character(current$truth))) {
    mismatch <- reference_ids[
      as.character(reference$truth) != as.character(current$truth)
    ]
    stop("Truth-label mismatch between ", dimensions[[1]], " and ", dimension,
         " for sample_id(s): ", paste(head(mismatch, 10), collapse=", "))
  }
  if(!identical(as.integer(reference$fold), as.integer(current$fold))) {
    mismatch <- reference_ids[reference$fold != current$fold]
    stop("Outer-fold assignment mismatch between ", dimensions[[1]],
         " and ", dimension, " for sample_id(s): ",
         paste(head(mismatch, 10), collapse=", "),
         ". Shared folds are required for leakage-safe stacking")
  }
  dimension_data[[dimension]]$predictions <- current
}

truth_levels <- unique(as.character(reference$truth))
if("case" %in% truth_levels) {
  positive_class <- "case"
} else {
  positive_class <- truth_levels[[2]]
}
negative_class <- setdiff(truth_levels, positive_class)
if(length(negative_class) != 1) {
  stop("Unable to resolve binary negative and positive truth labels")
}
cat(sprintf("[INFO] Truth levels: negative=%s; positive=%s\n",
            negative_class, positive_class))

meta_data <- data.frame(
  sample_id=reference_ids,
  truth=as.character(reference$truth),
  fold=as.integer(reference$fold),
  stringsAsFactors=FALSE,
  check.names=FALSE
)
feature_names <- paste0(dimensions, "_prob")
for(index in seq_along(dimensions)) {
  meta_data[[feature_names[[index]]]] <-
    dimension_data[[dimensions[[index]]]]$predictions$prob_positive
}

make_task <- function(data, task_id) {
  task_data <- data[, feature_names, drop=FALSE]
  task_data$truth <- factor(
    data$truth, levels=c(negative_class, positive_class)
  )
  mlr3::TaskClassif$new(
    id=task_id,
    backend=task_data,
    target="truth",
    positive=positive_class
  )
}

extract_logreg_coefficients <- function(learner, fold_index) {
  coefficients <- stats::coef(learner$model)
  values <- rep(NA_real_, length(feature_names))
  names(values) <- feature_names
  common <- intersect(feature_names, names(coefficients))
  values[common] <- as.numeric(coefficients[common])
  data.frame(
    fold=fold_index,
    meta_learner="logreg",
    dimension=dimensions,
    feature=feature_names,
    coefficient=as.numeric(values),
    stringsAsFactors=FALSE
  )
}

extract_glmnet_coefficients <- function(learner, fold_index) {
  tuned_value_rows <- learner$tuning_result$learner_param_vals
  if(length(tuned_value_rows) != 1 || !is.list(tuned_value_rows[[1]])) {
    stop("Unable to extract tuned glmnet parameters for fold ", fold_index)
  }
  tuned_values <- tuned_value_rows[[1]]
  if(is.null(tuned_values) || !"s" %in% names(tuned_values)) {
    stop("Unable to extract tuned glmnet 's' value for fold ", fold_index)
  }
  glmnet_model <- learner$learner$model
  coefficient_matrix <- stats::coef(glmnet_model, s=tuned_values$s)
  coefficient_names <- rownames(coefficient_matrix)
  coefficient_values <- as.numeric(coefficient_matrix)
  names(coefficient_values) <- coefficient_names
  values <- rep(NA_real_, length(feature_names))
  names(values) <- feature_names
  common <- intersect(feature_names, coefficient_names)
  values[common] <- coefficient_values[common]
  data.frame(
    fold=fold_index,
    meta_learner="glmnet",
    dimension=dimensions,
    feature=feature_names,
    coefficient=as.numeric(values),
    stringsAsFactors=FALSE
  )
}

stacked_prob <- rep(NA_real_, nrow(meta_data))
coefficient_rows <- vector("list", opt$outer_folds)
per_fold_rows <- vector("list", opt$outer_folds)

for(fold_index in seq_len(opt$outer_folds)) {
  train_indices <- which(meta_data$fold != fold_index)
  test_indices <- which(meta_data$fold == fold_index)
  if(length(train_indices) == 0 || length(test_indices) == 0) {
    stop("Fold ", fold_index, " has an empty training or test partition")
  }
  train_class_counts <- table(meta_data$truth[train_indices])
  test_class_counts <- table(meta_data$truth[test_indices])
  if(length(train_class_counts) != 2 || length(test_class_counts) != 2) {
    stop("Fold ", fold_index,
         " must contain both classes in training and test partitions")
  }
  train_task <- make_task(
    meta_data[train_indices, , drop=FALSE],
    sprintf("ensemble_meta_train_fold_%d", fold_index)
  )
  test_task <- make_task(
    meta_data[test_indices, , drop=FALSE],
    sprintf("ensemble_meta_test_fold_%d", fold_index)
  )

  set.seed(opt$seed + fold_index - 1L)
  if(opt$meta_learner == "logreg") {
    learner <- mlr3::lrn("classif.log_reg", predict_type="prob")
    learner$train(train_task)
    coefficient_rows[[fold_index]] <- extract_logreg_coefficients(
      learner, fold_index
    )
  } else {
    glmnet_learner <- mlr3::lrn(
      "classif.glmnet", id="elasticNet", predict_type="prob"
    )
    glmnet_params <- glmnet_learner$param_set$ids()
    missing_glmnet_params <- setdiff(c("alpha", "s"), glmnet_params)
    if(length(missing_glmnet_params) > 0) {
      stop("Installed classif.glmnet learner does not expose expected parameters: ",
           paste(missing_glmnet_params, collapse=", "))
    }
    if(min(train_class_counts) < 5) {
      stop("Fold ", fold_index,
           " has fewer than five training samples in a class; ",
           "glmnet meta-tuning requires five-fold inner CV")
    }
    learner <- mlr3tuning::auto_tuner(
      tuner=mlr3tuning::tnr("random_search"),
      learner=glmnet_learner,
      resampling=mlr3::rsmp("cv", folds=5),
      measure=mlr3::msr("classif.auc"),
      terminator=bbotk::trm("evals", n_evals=50),
      search_space=paradox::ps(
        alpha=paradox::p_dbl(lower=0, upper=1),
        s=paradox::p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
      ),
      store_tuning_instance=TRUE
    )
    learner$train(train_task)
    coefficient_rows[[fold_index]] <- extract_glmnet_coefficients(
      learner, fold_index
    )
  }

  prediction <- learner$predict(test_task)
  fold_probabilities <- as.numeric(prediction$prob[, positive_class])
  if(length(fold_probabilities) != length(test_indices) ||
     anyNA(fold_probabilities) || any(!is.finite(fold_probabilities)) ||
     any(fold_probabilities < 0 | fold_probabilities > 1)) {
    stop("Invalid stacked probabilities produced for fold ", fold_index)
  }
  stacked_prob[test_indices] <- fold_probabilities
  fold_labels <- as.integer(meta_data$truth[test_indices] == positive_class)
  fold_roc <- pROC::roc(
    response=fold_labels,
    predictor=fold_probabilities,
    levels=c(0, 1),
    direction="<",
    quiet=TRUE
  )
  fold_auc <- as.numeric(pROC::auc(fold_roc))
  if(!is.finite(fold_auc) || fold_auc < 0 || fold_auc > 1) {
    stop("Invalid AUC produced for fold ", fold_index)
  }
  per_fold_rows[[fold_index]] <- data.frame(
    fold=fold_index,
    auc_roc=fold_auc,
    stringsAsFactors=FALSE
  )
  cat(sprintf("[INFO] Meta fold %d AUC: %.6f\n", fold_index, fold_auc))
}

if(anyNA(stacked_prob) || any(!is.finite(stacked_prob)) ||
   any(stacked_prob < 0 | stacked_prob > 1)) {
  stop("Final stacked probabilities must be finite values between 0 and 1")
}
if(!setequal(meta_data$sample_id, reference_ids) ||
   length(stacked_prob) != length(reference_ids)) {
  stop("Final stacked prediction sample_id coverage is incomplete")
}

labels <- as.integer(meta_data$truth == positive_class)
stacked_roc <- pROC::roc(
  response=labels,
  predictor=stacked_prob,
  levels=c(0, 1),
  direction="<",
  quiet=TRUE
)
stacked_auc <- as.numeric(pROC::auc(stacked_roc))
if(!is.finite(stacked_auc) || stacked_auc < 0 || stacked_auc > 1) {
  stop("Invalid pooled stacked AUC produced")
}

per_fold_performance <- do.call(rbind, per_fold_rows)
stacked_sd <- stats::sd(per_fold_performance$auc_roc)
comparison_rows <- lapply(dimensions, function(dimension) {
  item <- dimension_data[[dimension]]
  data.frame(
    source=dimension,
    learner_used=item$learner,
    auc_roc=item$summary_auc,
    sd_or_ci=item$summary_sd,
    stringsAsFactors=FALSE
  )
})
comparison_rows[[length(comparison_rows) + 1L]] <- data.frame(
  source="stacked_ensemble",
  learner_used=opt$meta_learner,
  auc_roc=stacked_auc,
  sd_or_ci=stacked_sd,
  stringsAsFactors=FALSE
)
performance_data <- do.call(rbind, comparison_rows)
if(anyNA(performance_data$auc_roc) ||
   any(!is.finite(performance_data$auc_roc)) ||
   any(performance_data$auc_roc < 0 | performance_data$auc_roc > 1)) {
  stop("Performance table contains invalid AUC values")
}

output_predictions <- meta_data[, c("sample_id", "truth", "fold"), drop=FALSE]
for(feature_name in feature_names) {
  output_predictions[[feature_name]] <- meta_data[[feature_name]]
}
output_predictions$stacked_prob <- stacked_prob
coefficients_data <- do.call(rbind, coefficient_rows)

predictions_file <- file.path(opt$outdir, "ensemble_late_predictions.csv")
performance_file <- file.path(opt$outdir, "ensemble_late_performance.csv")
coefficients_file <- file.path(
  opt$outdir, "ensemble_late_meta_coefficients.csv"
)
roc_file <- file.path(opt$outdir, "ensemble_late_roc_comparison.pdf")

write.csv(output_predictions, predictions_file, row.names=FALSE, quote=TRUE)
write.csv(performance_data, performance_file, row.names=FALSE, quote=TRUE)
write.csv(coefficients_data, coefficients_file, row.names=FALSE, quote=TRUE)

roc_objects <- list()
roc_labels <- character()
roc_colors <- grDevices::hcl.colors(length(dimensions) + 1L, "Dark 3")
for(index in seq_along(dimensions)) {
  dimension <- dimensions[[index]]
  probabilities <- meta_data[[feature_names[[index]]]]
  roc_objects[[dimension]] <- pROC::roc(
    response=labels,
    predictor=probabilities,
    levels=c(0, 1),
    direction="<",
    quiet=TRUE
  )
  dimension_auc <- as.numeric(pROC::auc(roc_objects[[dimension]]))
  if(!is.finite(dimension_auc) || dimension_auc < 0 || dimension_auc > 1) {
    stop("Invalid pooled ROC AUC for dimension ", dimension)
  }
  roc_labels[[index]] <- sprintf(
    "%s: %s (AUC=%.3f)",
    dimension, dimension_data[[dimension]]$learner, dimension_auc
  )
}
roc_objects$stacked_ensemble <- stacked_roc
roc_labels[[length(dimensions) + 1L]] <- sprintf(
  "stacked ensemble: %s (AUC=%.3f)", opt$meta_learner, stacked_auc
)

grDevices::pdf(roc_file, width=7.5, height=6)
first_roc <- roc_objects[[1]]
plot(
  first_roc,
  col=roc_colors[[1]],
  lwd=2,
  legacy.axes=TRUE,
  main="Late-Fusion ROC Comparison"
)
if(length(roc_objects) > 1) {
  for(index in 2:length(roc_objects)) {
    plot(
      roc_objects[[index]],
      col=roc_colors[[index]],
      lwd=2,
      add=TRUE,
      legacy.axes=TRUE
    )
  }
}
abline(a=0, b=1, lty=2, col="grey55")
legend(
  "bottomright",
  legend=roc_labels,
  col=roc_colors,
  lwd=2,
  bty="n",
  cex=0.85
)
grDevices::dev.off()

best_single_auc <- max(vapply(
  dimension_data, function(item) item$summary_auc, numeric(1)
))
cat(sprintf("[INFO] Stacked pooled AUC: %.6f\n", stacked_auc))
cat(sprintf("[INFO] Best single-dimension mean fold AUC: %.6f\n",
            best_single_auc))
cat(sprintf("[INFO] Fusion AUC difference: %+.6f\n",
            stacked_auc - best_single_auc))
cat(sprintf("[INFO] Per-fold stacked AUCs: %s\n",
            paste(sprintf("fold%d=%.6f", per_fold_performance$fold,
                          per_fold_performance$auc_roc), collapse=", ")))
cat(sprintf("[INFO] Saved predictions: %s\n", predictions_file))
cat(sprintf("[INFO] Saved performance comparison: %s\n", performance_file))
cat(sprintf("[INFO] Saved meta coefficients: %s\n", coefficients_file))
cat(sprintf("[INFO] Saved ROC comparison: %s\n", roc_file))
total_runtime <- as.numeric(difftime(Sys.time(), start_time, units="secs"))
cat(sprintf("[INFO] Total runtime: %.1f seconds (%.2f minutes)\n",
            total_runtime, total_runtime / 60))
cat(sprintf("[INFO] Late-fusion stacking completed successfully\n"))
