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
  make_option(c("-d", "--dimension"), type="character",
              help="Dimension: bacteria/virus/fungi"),
  make_option(c("-i", "--input"), type="character", default=NULL,
              help="Processed RDS input [default: workdir/result/stat/dimension/ml_mlr3/processed_dimension.rds]"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: workdir/result/stat/dimension/ml_mlr3]"),
  make_option(c("--use-selected-features"), dest="use_selected_features",
              action="store_true", default=FALSE,
              help="Restrict analysis to selected_features_dimension.txt when available"),
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

integer_options <- c("outer_folds", "inner_folds", "inner_evals", "threads")
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
if(is.null(opt$seed) || length(opt$seed) != 1 || is.na(opt$seed) || !is.finite(opt$seed)) {
  stop("--seed must be a finite integer")
}

if(is.null(opt$input)) {
  opt$input <- file.path(
    opt$workdir, "result", "stat", opt$dimension, "ml_mlr3",
    sprintf("processed_%s.rds", opt$dimension)
  )
}
if(is.null(opt$outdir)) {
  opt$outdir <- file.path(opt$workdir, "result", "stat", opt$dimension, "ml_mlr3")
}
if(!file.exists(opt$input)) {
  stop("Processed input file not found: ", opt$input)
}

start_time <- Sys.time()

cat(sprintf("[INFO] Starting nested cross-validation\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Input: %s\n", opt$input))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Outer folds: %d; inner folds: %d; inner evaluations: %d\n",
            opt$outer_folds, opt$inner_folds, opt$inner_evals))
cat(sprintf("[INFO] Parallel workers: %d; seed: %d\n", opt$threads, opt$seed))

processed <- readRDS(opt$input)
required_elements <- c("features", "label", "meta", "dimension")
missing_elements <- setdiff(required_elements, names(processed))
if(length(missing_elements) > 0) {
  stop("Processed input is missing elements: ", paste(missing_elements, collapse=", "))
}

features <- as.matrix(processed$features)
label <- processed$label
if(!is.numeric(features)) {
  stop("Processed features must be numeric")
}
if(any(!is.finite(features))) {
  stop("Processed features contain non-finite values")
}
if(!is.factor(label)) {
  label <- factor(label)
}
if(nlevels(label) != 2) {
  stop("Classification label must have exactly 2 levels; found: ",
       paste(levels(label), collapse=", "))
}
if(nrow(features) != length(label)) {
  stop("Feature rows and label length are not aligned")
}
if(nrow(features) < opt$outer_folds) {
  stop("Number of samples is smaller than --outer-folds")
}
if(anyDuplicated(colnames(features))) {
  stop("Feature names must be unique")
}

sample_ids <- rownames(features)
if(is.null(sample_ids) || anyNA(sample_ids) || any(sample_ids == "") ||
   anyDuplicated(sample_ids)) {
  stop("Feature row names must contain unique, non-empty sample IDs")
}

selected_features_file <- file.path(
  opt$workdir, "result", "stat", opt$dimension, "ml_mlr3",
  sprintf("selected_features_%s.txt", opt$dimension)
)
if(opt$use_selected_features) {
  if(file.exists(selected_features_file)) {
    selected_features <- trimws(readLines(selected_features_file, warn=FALSE))
    selected_features <- unique(selected_features[nzchar(selected_features)])
    if(length(selected_features) == 0) {
      stop("Selected feature file contains no feature names: ", selected_features_file)
    }
    missing_selected <- setdiff(selected_features, colnames(features))
    if(length(missing_selected) > 0) {
      cat(sprintf("[INFO] Ignoring %d selected features absent from processed data\n",
                  length(missing_selected)))
    }
    selected_features <- intersect(selected_features, colnames(features))
    if(length(selected_features) == 0) {
      stop("None of the selected features are present in processed data")
    }
    features <- features[, selected_features, drop=FALSE]
    cat(sprintf("[INFO] Restricted to %d selected features from: %s\n",
                ncol(features), selected_features_file))
  } else {
    cat(sprintf("[INFO] Selected feature file not found; using all features: %s\n",
                selected_features_file))
  }
} else {
  cat(sprintf("[INFO] Selected feature restriction disabled; using all features\n"))
}

class_counts <- table(label)
if(any(class_counts < opt$outer_folds)) {
  stop("Each class must contain at least --outer-folds samples; class balance: ",
       paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
             collapse=", "))
}

task_data <- as.data.frame(features, check.names=FALSE)
task_data$label <- label

# The second factor level is intentionally treated as the positive class.
positive_class <- levels(label)[2]
task <- TaskClassif$new(
  id=sprintf("%s_nested_cv", opt$dimension),
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

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

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

hyperparameters_to_table <- function(per_fold) {
  parameter_names <- unique(unlist(lapply(per_fold, names), use.names=FALSE))
  parameter_names <- c("fold", setdiff(parameter_names, "fold"))
  rows <- lapply(per_fold, function(values) {
    row <- setNames(vector("list", length(parameter_names)), parameter_names)
    for(parameter_name in parameter_names) {
      value <- values[[parameter_name]]
      if(is.null(value)) {
        row[[parameter_name]] <- NA
      } else if(length(value) == 1 && (is.atomic(value) || is.factor(value))) {
        row[[parameter_name]] <- as.character(value)
      } else {
        row[[parameter_name]] <- paste(as.character(value), collapse=";")
      }
    }
    as.data.frame(row, stringsAsFactors=FALSE, check.names=FALSE)
  })
  do.call(rbind, rows)
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
  hyperparameters_table <- hyperparameters_to_table(best_hyperparameters)

  resample_file <- file.path(
    opt$outdir, sprintf("nested_cv_%s_%s.rds", learner_id, opt$dimension)
  )
  predictions_file <- file.path(
    opt$outdir, sprintf("predictions_%s_%s.csv", learner_id, opt$dimension)
  )
  performance_file <- file.path(
    opt$outdir, sprintf("cv_performance_%s_%s.csv", learner_id, opt$dimension)
  )
  hyperparameters_json_file <- file.path(
    opt$outdir, sprintf("best_hyperparams_%s_%s.json", learner_id, opt$dimension)
  )
  hyperparameters_csv_file <- file.path(
    opt$outdir, sprintf("best_hyperparams_%s_%s.csv", learner_id, opt$dimension)
  )

  saveRDS(resample_result, resample_file)
  write.csv(predictions, predictions_file, row.names=FALSE, quote=TRUE)
  write.csv(performance, performance_file, row.names=FALSE, quote=TRUE)
  if(requireNamespace("jsonlite", quietly=TRUE)) {
    jsonlite::write_json(
      best_hyperparameters,
      hyperparameters_json_file,
      pretty=TRUE,
      auto_unbox=TRUE,
      null="null",
      digits=NA
    )
    cat(sprintf("[INFO] Saved best hyperparameters: %s\n", hyperparameters_json_file))
  } else {
    write.csv(hyperparameters_table, hyperparameters_csv_file,
              row.names=FALSE, quote=TRUE)
    cat(sprintf("[INFO] jsonlite unavailable; saved best hyperparameters as CSV: %s\n",
                hyperparameters_csv_file))
  }

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
summary_file <- file.path(
  opt$outdir, sprintf("nested_cv_summary_%s.csv", opt$dimension)
)
write.csv(summary_data, summary_file, row.names=FALSE, quote=TRUE)

total_runtime <- as.numeric(difftime(Sys.time(), start_time, units="secs"))
cat(sprintf("[INFO] Saved nested CV summary: %s\n", summary_file))
for(summary_index in seq_len(nrow(summary_data))) {
  cat(sprintf("[INFO] Final mean AUC - %s: %.6f\n",
              summary_data$learner[summary_index], summary_data$mean_auc[summary_index]))
}
cat(sprintf("[INFO] Total runtime: %.1f seconds (%.2f minutes)\n",
            total_runtime, total_runtime / 60))
cat(sprintf("[INFO] Nested cross-validation completed successfully\n"))
