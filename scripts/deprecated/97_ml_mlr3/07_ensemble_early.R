#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(mlr3)
  library(mlr3learners)
  library(mlr3tuning)
  library(mlr3pipelines)
  library(paradox)
  library(future)
})

# Parse arguments
option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Project work directory"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: workdir/result/stat/ensemble/ml_mlr3]"),
  make_option(c("--dimensions"), type="character", default="bacteria,virus,fungi",
              help="Comma-separated dimensions [default: bacteria,virus,fungi]"),
  make_option(c("--use-selected-features"), dest="use_selected_features",
              action="store_true", default=TRUE,
              help="Restrict each dimension to Boruta-confirmed features [default]"),
  make_option(c("--no-feature-selection"), dest="no_feature_selection",
              action="store_true", default=FALSE,
              help="Disable Boruta feature restriction and use all processed features"),
  make_option(c("--outer-folds"), dest="outer_folds", type="integer", default=5,
              help="Number of outer CV folds [default: 5]"),
  make_option(c("--inner-folds"), dest="inner_folds", type="integer", default=5,
              help="Number of inner CV folds [default: 5]"),
  make_option(c("--inner-evals"), dest="inner_evals", type="integer", default=20,
              help="Random-search evaluations per inner tuning [default: 20]"),
  make_option(c("-t", "--threads"), type="integer", default=1,
              help="Parallel workers for mlr3 via future [default: 1]"),
  make_option(c("--seed"), type="integer", default=42,
              help="Random seed [default: 42]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate inputs
required <- c("workdir")
missing <- required[!required %in% names(opt) | vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}

dimensions <- trimws(strsplit(opt$dimensions, ",", fixed=TRUE)[[1]])
dimensions <- dimensions[nzchar(dimensions)]
if(length(dimensions) == 0) {
  stop("--dimensions must contain at least one dimension")
}
if(anyDuplicated(dimensions)) {
  stop("--dimensions contains duplicate dimensions: ",
       paste(unique(dimensions[duplicated(dimensions)]), collapse=", "))
}
valid_dimensions <- c("bacteria", "virus", "fungi")
invalid_dimensions <- setdiff(dimensions, valid_dimensions)
if(length(invalid_dimensions) > 0) {
  stop("Invalid dimensions: ", paste(invalid_dimensions, collapse=", "),
       ". Expected values from: ", paste(valid_dimensions, collapse=", "))
}

integer_options <- c("outer_folds", "inner_folds", "inner_evals", "threads", "seed")
for(option_name in integer_options) {
  option_value <- opt[[option_name]]
  if(is.null(option_value) || length(option_value) != 1 || is.na(option_value) ||
     !is.finite(option_value) || option_value < 1) {
    stop("--", gsub("_", "-", option_name), " must be a positive integer")
  }
}
if(opt$outer_folds < 2) {
  stop("--outer-folds must be at least 2")
}
if(opt$inner_folds < 2) {
  stop("--inner-folds must be at least 2")
}

if(is.null(opt$outdir)) {
  opt$outdir <- file.path(opt$workdir, "result", "stat", "ensemble", "ml_mlr3")
}
use_selected_features <- opt$use_selected_features && !opt$no_feature_selection

start_time <- Sys.time()

cat(sprintf("[INFO] Starting early-fusion nested cross-validation\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimensions: %s\n", paste(dimensions, collapse=", ")))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Feature selection: %s\n",
            if(use_selected_features) "Boruta-confirmed features" else "all features"))
cat(sprintf("[INFO] Outer folds: %d; inner folds: %d; inner evaluations: %d\n",
            opt$outer_folds, opt$inner_folds, opt$inner_evals))
cat(sprintf("[INFO] Parallel workers: %d; seed: %d\n", opt$threads, opt$seed))

fused_parts <- list()
manifest_rows <- list()
reference_sample_ids <- NULL
reference_label <- NULL

for(dimension in dimensions) {
  input_file <- file.path(
    opt$workdir, "result", "stat", dimension, "ml_mlr3",
    sprintf("processed_%s.rds", dimension)
  )
  if(!file.exists(input_file)) {
    stop("Processed input file not found for ", dimension, ": ", input_file)
  }

  cat(sprintf("[INFO] Loading %s processed data: %s\n", dimension, input_file))
  processed <- readRDS(input_file)
  required_elements <- c("features", "label", "meta", "dimension")
  missing_elements <- setdiff(required_elements, names(processed))
  if(length(missing_elements) > 0) {
    stop("Processed input for ", dimension, " is missing elements: ",
         paste(missing_elements, collapse=", "))
  }
  if(!identical(as.character(processed$dimension), dimension)) {
    stop("Processed input dimension mismatch for ", dimension,
         "; found: ", paste(as.character(processed$dimension), collapse=", "))
  }

  dimension_features <- as.matrix(processed$features)
  dimension_label <- processed$label
  if(!is.numeric(dimension_features)) {
    stop("Processed features for ", dimension, " must be numeric")
  }
  if(any(!is.finite(dimension_features))) {
    stop("Processed features for ", dimension, " contain non-finite values")
  }
  if(!is.factor(dimension_label)) {
    dimension_label <- factor(dimension_label)
  }
  if(nlevels(dimension_label) != 2) {
    stop("Classification label for ", dimension,
         " must have exactly 2 levels; found: ",
         paste(levels(dimension_label), collapse=", "))
  }
  if(nrow(dimension_features) != length(dimension_label)) {
    stop("Feature rows and label length are not aligned for ", dimension)
  }
  if(ncol(dimension_features) == 0) {
    stop("Processed features contain no columns for ", dimension)
  }
  if(is.null(colnames(dimension_features)) || anyNA(colnames(dimension_features)) ||
     any(colnames(dimension_features) == "") || anyDuplicated(colnames(dimension_features))) {
    stop("Feature names must be unique and non-empty for ", dimension)
  }

  dimension_sample_ids <- rownames(dimension_features)
  if(is.null(dimension_sample_ids) || anyNA(dimension_sample_ids) ||
     any(dimension_sample_ids == "") || anyDuplicated(dimension_sample_ids)) {
    stop("Feature row names must contain unique, non-empty sample IDs for ", dimension)
  }
  if(!"sample_id" %in% names(processed$meta)) {
    stop("Processed metadata for ", dimension, " is missing sample_id")
  }
  metadata_sample_ids <- as.character(processed$meta$sample_id)
  if(length(metadata_sample_ids) != length(dimension_sample_ids) ||
     !identical(metadata_sample_ids, dimension_sample_ids)) {
    stop("Metadata sample_id values are not aligned with feature row names for ", dimension)
  }

  if(is.null(reference_sample_ids)) {
    reference_sample_ids <- dimension_sample_ids
    reference_label <- dimension_label
  } else {
    if(!setequal(dimension_sample_ids, reference_sample_ids)) {
      missing_samples <- setdiff(reference_sample_ids, dimension_sample_ids)
      extra_samples <- setdiff(dimension_sample_ids, reference_sample_ids)
      stop("Sample set mismatch for ", dimension,
           "; missing relative to ", dimensions[[1]], ": ",
           if(length(missing_samples) > 0) paste(missing_samples, collapse=", ") else "none",
           "; extra: ",
           if(length(extra_samples) > 0) paste(extra_samples, collapse=", ") else "none")
    }
    sample_order <- match(reference_sample_ids, dimension_sample_ids)
    aligned_labels <- as.character(dimension_label[sample_order])
    reference_labels <- as.character(reference_label)
    mismatched_labels <- reference_sample_ids[aligned_labels != reference_labels]
    if(length(mismatched_labels) > 0) {
      stop("Label mismatch for ", dimension, " versus ", dimensions[[1]],
           " for sample_id(s): ", paste(mismatched_labels, collapse=", "))
    }
    if(!identical(levels(dimension_label), levels(reference_label))) {
      stop("Label factor levels differ for ", dimension, " versus ", dimensions[[1]],
           ": ", paste(levels(dimension_label), collapse=", "), " versus ",
           paste(levels(reference_label), collapse=", "))
    }
    dimension_features <- dimension_features[sample_order, , drop=FALSE]
  }

  total_features_available <- ncol(dimension_features)
  if(use_selected_features) {
    selected_features_file <- file.path(
      opt$workdir, "result", "stat", dimension, "ml_mlr3",
      sprintf("selected_features_%s.txt", dimension)
    )
    if(!file.exists(selected_features_file)) {
      stop("Selected feature file not found for ", dimension, ": ",
           selected_features_file)
    }
    selected_features <- trimws(readLines(selected_features_file, warn=FALSE))
    selected_features <- unique(selected_features[nzchar(selected_features)])
    if(length(selected_features) == 0) {
      stop("Selected feature file contains no feature names for ", dimension,
           ": ", selected_features_file)
    }
    missing_selected <- setdiff(selected_features, colnames(dimension_features))
    if(length(missing_selected) > 0) {
      cat(sprintf("[INFO] Ignoring %d selected %s features absent from processed data\n",
                  length(missing_selected), dimension))
    }
    selected_features <- intersect(selected_features, colnames(dimension_features))
    if(length(selected_features) == 0) {
      stop("None of the selected features for ", dimension,
           " are present in processed data")
    }
    dimension_features <- dimension_features[, selected_features, drop=FALSE]
  }

  selected_feature_count <- ncol(dimension_features)
  colnames(dimension_features) <- paste0(dimension, "__", colnames(dimension_features))
  fused_parts[[dimension]] <- dimension_features
  manifest_rows[[dimension]] <- data.frame(
    dimension=dimension,
    n_features_selected=selected_feature_count,
    n_features_total_available=total_features_available,
    stringsAsFactors=FALSE
  )
  cat(sprintf("[INFO] %s features: %d used of %d available\n",
              dimension, selected_feature_count, total_features_available))
}

features <- do.call(cbind, fused_parts)
label <- reference_label
sample_ids <- reference_sample_ids
feature_manifest <- do.call(rbind, manifest_rows)
rownames(feature_manifest) <- NULL

if(anyDuplicated(colnames(features))) {
  stop("Fused feature names must be globally unique")
}
if(nrow(features) < opt$outer_folds) {
  stop("Number of samples is smaller than --outer-folds")
}
class_counts <- table(label)
if(any(class_counts < opt$outer_folds)) {
  stop("Each class must contain at least --outer-folds samples; class balance: ",
       paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
             collapse=", "))
}

cat(sprintf("[INFO] Total fused feature count: %d\n", ncol(features)))

task_data <- as.data.frame(features, check.names=FALSE)
task_data$label <- label

# The second factor level is intentionally treated as the positive class.
positive_class <- levels(label)[2]
task <- TaskClassif$new(
  id=sprintf("ensemble_early_nested_cv"),
  backend=task_data,
  target="label",
  positive=positive_class
)

cat(sprintf("[INFO] Created classification task: %d samples x %d features\n",
            task$nrow, length(task$feature_names)))
cat(sprintf("[INFO] Class balance: %s; positive class: %s\n",
            paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
                  collapse=", "), positive_class))

glmnet_params <- lrn("classif.glmnet")$param_set$ids()
if(!"s" %in% glmnet_params) {
  stop("Installed classif.glmnet learner does not expose the expected 's' parameter")
}
if(!"alpha" %in% glmnet_params) {
  stop("Installed classif.glmnet learner does not expose the expected 'alpha' parameter")
}
ranger_params <- lrn("classif.ranger")$param_set$ids()
if("mtry.ratio" %in% ranger_params) {
  ranger_mtry_param <- "mtry.ratio"
} else if("mtry" %in% ranger_params) {
  ranger_mtry_param <- "mtry"
} else {
  stop("Installed classif.ranger learner exposes neither 'mtry.ratio' nor 'mtry'")
}
if(!"min.node.size" %in% ranger_params) {
  stop("Installed classif.ranger learner does not expose 'min.node.size'")
}

xgboost_params <- lrn("classif.xgboost")$param_set$ids()
required_xgboost_params <- c(
  "eta", "max_depth", "nrounds", "subsample", "colsample_bytree", "nthread"
)
missing_xgboost_params <- setdiff(required_xgboost_params, xgboost_params)
if(length(missing_xgboost_params) > 0) {
  stop("Installed classif.xgboost learner does not expose expected parameters: ",
       paste(missing_xgboost_params, collapse=", "))
}

lasso_learner <- lrn(
  "classif.glmnet",
  id="lasso",
  predict_type="prob",
  alpha=1
)
lasso_search_space <- ps(
  s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
)

ridge_learner <- lrn(
  "classif.glmnet",
  id="ridge",
  predict_type="prob",
  alpha=0
)
ridge_search_space <- ps(
  s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
)

elastic_net_learner <- lrn(
  "classif.glmnet",
  id="elasticNet",
  predict_type="prob"
)
elastic_net_search_space <- ps(
  alpha=p_dbl(lower=0, upper=1),
  s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
)

random_forest_learner <- lrn(
  "classif.ranger",
  id="randomForest",
  predict_type="prob",
  num.trees=500
)
if(ranger_mtry_param == "mtry.ratio") {
  random_forest_search_space <- ps(
    mtry.ratio=p_dbl(lower=0.1, upper=0.9),
    min.node.size=p_int(lower=1, upper=20)
  )
} else {
  mtry_lower <- max(1L, as.integer(floor(0.1 * length(task$feature_names))))
  mtry_upper <- max(mtry_lower, as.integer(ceiling(0.9 * length(task$feature_names))))
  random_forest_search_space <- ps(
    mtry=p_int(lower=mtry_lower, upper=mtry_upper),
    min.node.size=p_int(lower=1, upper=20)
  )
}

xgboost_learner <- lrn(
  "classif.xgboost",
  id="xgboost",
  predict_type="prob",
  nthread=1
)
xgboost_search_space <- ps(
  eta=p_dbl(lower=0.01, upper=0.3, logscale=TRUE),
  max_depth=p_int(lower=3, upper=10),
  nrounds=p_int(lower=50, upper=300),
  subsample=p_dbl(lower=0.5, upper=1.0),
  colsample_bytree=p_dbl(lower=0.5, upper=1.0)
)

learner_specs <- list(
  lasso=list(learner=lasso_learner, search_space=lasso_search_space),
  randomForest=list(
    learner=random_forest_learner,
    search_space=random_forest_search_space
  ),
  ridge=list(learner=ridge_learner, search_space=ridge_search_space),
  elasticNet=list(learner=elastic_net_learner, search_space=elastic_net_search_space),
  xgboost=list(learner=xgboost_learner, search_space=xgboost_search_space)
)

svm_setup <- tryCatch({
  svm_learner <- lrn(
    "classif.svm",
    id="svm",
    predict_type="prob",
    kernel="radial",
    type="C-classification"
  )
  svm_params <- svm_learner$param_set$ids()
  missing_svm_params <- setdiff(c("cost", "gamma", "kernel", "type"), svm_params)
  if(length(missing_svm_params) > 0) {
    stop("Installed classif.svm learner does not expose expected parameters: ",
         paste(missing_svm_params, collapse=", "))
  }
  list(
    learner=svm_learner,
    search_space=ps(
      cost=p_dbl(lower=1e-2, upper=1e2, logscale=TRUE),
      gamma=p_dbl(lower=1e-4, upper=1e0, logscale=TRUE)
    )
  )
}, error=function(error) {
  cat(sprintf("[WARN] Skipping SVM during setup: %s\n", conditionMessage(error)))
  NULL
})
if(!is.null(svm_setup)) {
  learner_specs$svm <- svm_setup
}

learner_setup_descriptions <- c(
  "LASSO tunes 's'",
  sprintf("Random Forest tunes '%s' and 'min.node.size'", ranger_mtry_param),
  "Ridge tunes 's'",
  "Elastic Net tunes 'alpha' and 's'",
  paste0(
    "XGBoost tunes 'eta', 'max_depth', 'nrounds', 'subsample', ",
    "and 'colsample_bytree'"
  )
)
if(!is.null(svm_setup)) {
  learner_setup_descriptions <- c(
    learner_setup_descriptions,
    "SVM tunes 'cost' and 'gamma'"
  )
}
cat(sprintf("[INFO] Learner setup complete: %s\n",
            paste(learner_setup_descriptions, collapse="; ")))

if(!requireNamespace("jsonlite", quietly=TRUE)) {
  stop("jsonlite is required to write best hyperparameters JSON outputs")
}

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)
manifest_file <- file.path(opt$outdir, "fused_feature_manifest.csv")
write.csv(feature_manifest, manifest_file, row.names=FALSE, quote=TRUE)
cat(sprintf("[INFO] Saved fused feature manifest: %s\n", manifest_file))

if(opt$threads > 1) {
  future::plan(future::multisession, workers=opt$threads)
} else {
  future::plan(future::sequential)
}
on.exit(future::plan(future::sequential), add=TRUE)

extract_best_hyperparameters <- function(trained_learners) {
  per_fold <- vector("list", length(trained_learners))
  for(fold_index in seq_along(trained_learners)) {
    tuning_result <- trained_learners[[fold_index]]$tuning_result
    if(is.null(tuning_result) || nrow(tuning_result) == 0) {
      stop("Missing tuning result for outer fold ", fold_index)
    }

    if("x_domain" %in% names(tuning_result)) {
      hyperparameters <- tuning_result$x_domain[[1]]
    } else if("learner_param_vals" %in% names(tuning_result)) {
      hyperparameters <- tuning_result$learner_param_vals[[1]]
    } else {
      stop("Unable to extract best hyperparameters for outer fold ", fold_index)
    }

    hyperparameters <- as.list(hyperparameters)
    hyperparameters$fold <- fold_index
    if("classif.auc" %in% names(tuning_result)) {
      hyperparameters$inner_auc <- as.numeric(tuning_result$classif.auc[[1]])
    }
    per_fold[[fold_index]] <- hyperparameters
  }
  per_fold
}

summary_rows <- list()

for(learner_index in seq_along(learner_specs)) {
  learner_id <- names(learner_specs)[learner_index]
  learner_spec <- learner_specs[[learner_index]]

  learner_completed <- tryCatch({
  set.seed(opt$seed + learner_index - 1L)
  inner_resampling <- rsmp("cv", folds=opt$inner_folds)
  outer_resampling <- rsmp("cv", folds=opt$outer_folds)
  auto_tuned_learner <- auto_tuner(
    tuner=tnr("random_search"),
    learner=learner_spec$learner,
    resampling=inner_resampling,
    measure=msr("classif.auc"),
    terminator=trm("evals", n_evals=opt$inner_evals),
    search_space=learner_spec$search_space,
    store_tuning_instance=TRUE
  )

  learner_start <- Sys.time()
  cat(sprintf("[INFO] Starting outer resampling for %s\n", learner_id))
  resample_result <- resample(
    task,
    auto_tuned_learner,
    outer_resampling,
    store_models=TRUE
  )
  learner_runtime <- as.numeric(difftime(Sys.time(), learner_start, units="secs"))
  cat(sprintf("[INFO] Completed outer resampling for %s in %.1f seconds\n",
              learner_id, learner_runtime))

  score_data <- as.data.frame(resample_result$score(msr("classif.auc")))
  performance <- data.frame(
    fold=score_data$iteration,
    auc=score_data$classif.auc,
    stringsAsFactors=FALSE
  )
  if(nrow(performance) != opt$outer_folds || any(!is.finite(performance$auc)) ||
     any(performance$auc < 0 | performance$auc > 1)) {
    stop("Invalid outer-fold AUC values produced for ", learner_id)
  }

  fold_predictions <- resample_result$predictions()
  if(length(fold_predictions) != opt$outer_folds) {
    stop("Unexpected number of outer-fold prediction objects for ", learner_id)
  }
  prediction_rows <- lapply(seq_along(fold_predictions), function(fold_index) {
    prediction <- fold_predictions[[fold_index]]
    probability <- prediction$prob[, positive_class]
    data.frame(
      sample_id=sample_ids[prediction$row_ids],
      truth=as.character(prediction$truth),
      prob_positive=as.numeric(probability),
      fold=fold_index,
      stringsAsFactors=FALSE
    )
  })
  predictions <- do.call(rbind, prediction_rows)
  task_order <- match(predictions$sample_id, sample_ids)
  predictions <- predictions[order(task_order), , drop=FALSE]
  rownames(predictions) <- NULL
  if(nrow(predictions) != task$nrow || anyDuplicated(predictions$sample_id) ||
     !setequal(predictions$sample_id, sample_ids) ||
     any(!is.finite(predictions$prob_positive)) ||
     any(predictions$prob_positive < 0 | predictions$prob_positive > 1)) {
    stop("Invalid out-of-sample predictions produced for ", learner_id)
  }

  best_hyperparameters <- extract_best_hyperparameters(resample_result$learners)

  resample_file <- file.path(
    opt$outdir, sprintf("nested_cv_ensemble_early_%s.rds", learner_id)
  )
  predictions_file <- file.path(
    opt$outdir, sprintf("predictions_ensemble_early_%s.csv", learner_id)
  )
  performance_file <- file.path(
    opt$outdir, sprintf("cv_performance_ensemble_early_%s.csv", learner_id)
  )
  hyperparameters_json_file <- file.path(
    opt$outdir, sprintf("best_hyperparams_ensemble_early_%s.json", learner_id)
  )

  saveRDS(resample_result, resample_file)
  write.csv(predictions, predictions_file, row.names=FALSE, quote=TRUE)
  write.csv(performance, performance_file, row.names=FALSE, quote=TRUE)
  jsonlite::write_json(
    best_hyperparameters,
    hyperparameters_json_file,
    pretty=TRUE,
    auto_unbox=TRUE,
    null="null",
    digits=NA
  )
  cat(sprintf("[INFO] Saved best hyperparameters: %s\n", hyperparameters_json_file))

  aggregated_auc <- as.numeric(resample_result$aggregate(msr("classif.auc")))
  summary_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    mean_auc=mean(performance$auc),
    sd_auc=sd(performance$auc),
    min_auc=min(performance$auc),
    max_auc=max(performance$auc),
    stringsAsFactors=FALSE
  )

  cat(sprintf("[INFO] %s outer-fold AUCs: %s\n", learner_id,
              paste(sprintf("fold%d=%.6f", performance$fold, performance$auc),
                    collapse=", ")))
  cat(sprintf("[INFO] %s aggregated AUC: %.6f; mean fold AUC: %.6f\n",
              learner_id, aggregated_auc, mean(performance$auc)))
  cat(sprintf("[INFO] Saved resampling result: %s\n", resample_file))
  cat(sprintf("[INFO] Saved predictions: %s\n", predictions_file))
  cat(sprintf("[INFO] Saved CV performance: %s\n", performance_file))
  TRUE
  }, error=function(error) {
    cat(sprintf("[WARN] Skipping %s after nested CV failure: %s\n",
                learner_id, conditionMessage(error)))
    FALSE
  })

  if(!learner_completed) {
    next
  }
}

if(length(summary_rows) == 0) {
  stop("All learners failed during nested cross-validation")
}

summary_data <- do.call(rbind, summary_rows)
rownames(summary_data) <- NULL
summary_file <- file.path(opt$outdir, "nested_cv_summary_ensemble_early.csv")
write.csv(summary_data, summary_file, row.names=FALSE, quote=TRUE)

total_runtime <- as.numeric(difftime(Sys.time(), start_time, units="secs"))
cat(sprintf("[INFO] Saved nested CV summary: %s\n", summary_file))
for(summary_index in seq_len(nrow(summary_data))) {
  cat(sprintf("[INFO] Final mean AUC - %s: %.6f\n",
              summary_data$learner[summary_index], summary_data$mean_auc[summary_index]))
}
cat(sprintf("[INFO] Total runtime: %.1f seconds (%.2f minutes)\n",
            total_runtime, total_runtime / 60))
cat(sprintf("[INFO] Early-fusion nested cross-validation completed successfully\n"))
