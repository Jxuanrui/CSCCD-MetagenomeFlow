#!/usr/bin/env Rscript

# This script is a fast AutoML-style exploration step that uses single-level
# cross-validation to screen learners and hyperparameter ranges. Because the
# same CV results guide tuning and rank learners, the reported AUC values are
# not unbiased performance estimates. Use 04_nested_cv.R for careful model
# assessment with nested cross-validation.

suppressPackageStartupMessages({
  library(optparse)
  library(mlr3)
  library(mlr3learners)
  library(mlr3tuning)
  library(mlr3pipelines)
  library(paradox)
  library(future)
  library(ggplot2)
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
  make_option(c("--folds"), type="integer", default=5,
              help="Number of CV folds [default: 5]"),
  make_option(c("--n-evals-per-learner"), dest="n_evals_per_learner",
              type="integer", default=30,
              help="Random-search evaluations per learner [default: 30]"),
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

integer_options <- c("folds", "n_evals_per_learner", "threads")
for(option_name in integer_options) {
  option_value <- opt[[option_name]]
  if(is.null(option_value) || length(option_value) != 1 || is.na(option_value) ||
     !is.finite(option_value) || option_value < 1) {
    stop("--", gsub("_", "-", option_name), " must be a positive integer")
  }
}
if(opt$folds < 2) {
  stop("--folds must be at least 2")
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

cat(sprintf("[INFO] Starting AutoML-style learner exploration\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Input: %s\n", opt$input))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] CV folds: %d; evaluations per learner: %d\n",
            opt$folds, opt$n_evals_per_learner))
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
if(nrow(features) < opt$folds) {
  stop("Number of samples is smaller than --folds")
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
if(any(class_counts < opt$folds)) {
  stop("Each class must contain at least --folds samples; class balance: ",
       paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
             collapse=", "))
}

task_data <- as.data.frame(features, check.names=FALSE)
task_data$label <- label

# The second factor level is intentionally treated as the positive class.
positive_class <- levels(label)[2]
task <- TaskClassif$new(
  id=sprintf("%s_automl", opt$dimension),
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
if(!"num.trees" %in% ranger_params) {
  stop("Installed classif.ranger learner does not expose 'num.trees'")
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
  id="LASSO",
  predict_type="prob",
  alpha=1
)
lasso_search_space <- ps(
  s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
)

ridge_learner <- lrn(
  "classif.glmnet",
  id="Ridge",
  predict_type="prob",
  alpha=0
)
ridge_search_space <- ps(
  s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
)

elastic_net_learner <- lrn(
  "classif.glmnet",
  id="ElasticNet",
  predict_type="prob"
)
elastic_net_search_space <- ps(
  alpha=p_dbl(lower=0, upper=1),
  s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
)

random_forest_learner <- lrn(
  "classif.ranger",
  id="RandomForest",
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
  id="XGBoost",
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
  LASSO=list(learner=lasso_learner, search_space=lasso_search_space),
  Ridge=list(learner=ridge_learner, search_space=ridge_search_space),
  ElasticNet=list(learner=elastic_net_learner, search_space=elastic_net_search_space),
  RandomForest=list(
    learner=random_forest_learner,
    search_space=random_forest_search_space
  ),
  XGBoost=list(learner=xgboost_learner, search_space=xgboost_search_space)
)

svm_setup <- tryCatch({
  svm_learner <- lrn(
    "classif.svm",
    id="SVM",
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
  learner_specs$SVM <- svm_setup
}

cat(sprintf("[INFO] Learner setup complete: %d learners; Random Forest tunes '%s' and 'min.node.size'\n",
            length(learner_specs), ranger_mtry_param))

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

future::plan(future::multisession, workers=opt$threads)
on.exit(future::plan(future::sequential), add=TRUE)

format_hyperparameters <- function(values) {
  if(is.null(values) || length(values) == 0) {
    return("")
  }
  values <- as.list(values)
  paste(names(values), vapply(values, function(value) {
    if(length(value) == 0 || is.null(value)) {
      return(NA_character_)
    }
    paste(as.character(value), collapse=",")
  }, character(1)), sep="=", collapse="; ")
}

leaderboard_rows <- list()
trace_rows <- list()
skipped_learners <- character()
if(is.null(svm_setup)) {
  skipped_learners <- c(skipped_learners, "SVM (setup failure)")
}

for(learner_index in seq_along(learner_specs)) {
  learner_id <- names(learner_specs)[learner_index]
  learner_spec <- learner_specs[[learner_index]]

  set.seed(opt$seed + learner_index - 1L)
  learner_start <- Sys.time()
  cat(sprintf("[INFO] Starting tuning for %s\n", learner_id))

  tuning_result <- tryCatch({
    tune(
      tuner=tnr("random_search"),
      task=task,
      learner=learner_spec$learner,
      resampling=rsmp("cv", folds=opt$folds),
      measures=msr("classif.auc"),
      term_evals=opt$n_evals_per_learner,
      search_space=learner_spec$search_space
    )
  }, error=function(error) {
    cat(sprintf("[WARN] Skipping %s after tuning failure: %s\n",
                learner_id, conditionMessage(error)))
    skipped_learners <<- c(
      skipped_learners,
      sprintf("%s (%s)", learner_id, conditionMessage(error))
    )
    NULL
  })

  learner_runtime <- as.numeric(difftime(Sys.time(), learner_start, units="secs"))
  if(is.null(tuning_result)) {
    next
  }

  archive_data <- as.data.frame(tuning_result$archive$data)
  if(nrow(archive_data) == 0 || !"classif.auc" %in% names(archive_data)) {
    cat(sprintf("[WARN] Skipping %s because its tuning archive contains no AUC results\n",
                learner_id))
    skipped_learners <- c(skipped_learners, sprintf("%s (no archived AUC results)", learner_id))
    next
  }

  best_cv_auc <- as.numeric(tuning_result$result$classif.auc[[1]])
  if(!is.finite(best_cv_auc)) {
    cat(sprintf("[WARN] Skipping %s because its best CV AUC is not finite\n", learner_id))
    skipped_learners <- c(skipped_learners, sprintf("%s (non-finite best CV AUC)", learner_id))
    next
  }

  best_hyperparameters <- tuning_result$result_learner_param_vals
  if(is.null(best_hyperparameters) || length(best_hyperparameters) == 0) {
    best_hyperparameters <- tuning_result$result_x_domain
  }
  best_hyperparameters <- as.list(best_hyperparameters)
  fixed_parameter_names <- setdiff(
    names(best_hyperparameters),
    learner_spec$search_space$ids()
  )
  if(length(fixed_parameter_names) > 0) {
    best_hyperparameters <- best_hyperparameters[
      c(fixed_parameter_names, learner_spec$search_space$ids())
    ]
  }

  leaderboard_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    best_cv_auc=best_cv_auc,
    best_hyperparams=format_hyperparameters(best_hyperparameters),
    n_evals_completed=nrow(archive_data),
    runtime_seconds=learner_runtime,
    stringsAsFactors=FALSE
  )

  archive_auc <- as.numeric(archive_data$classif.auc)
  running_best_auc <- rep(NA_real_, length(archive_auc))
  finite_auc <- is.finite(archive_auc)
  if(any(finite_auc)) {
    running_best_auc[finite_auc] <- cummax(archive_auc[finite_auc])
  }
  trace_rows[[learner_id]] <- data.frame(
    learner=learner_id,
    evaluation_index=seq_len(nrow(archive_data)),
    running_best_auc=running_best_auc,
    stringsAsFactors=FALSE
  )

  cat(sprintf("[INFO] %s best CV AUC: %.6f after %d evaluations\n",
              learner_id, best_cv_auc, nrow(archive_data)))
  cat(sprintf("[INFO] Completed tuning for %s in %.1f seconds\n",
              learner_id, learner_runtime))
}

if(length(leaderboard_rows) == 0) {
  stop("All learners failed during AutoML-style exploration")
}

leaderboard <- do.call(rbind, leaderboard_rows)
leaderboard <- leaderboard[order(leaderboard$best_cv_auc, decreasing=TRUE), , drop=FALSE]
rownames(leaderboard) <- NULL

leaderboard_file <- file.path(
  opt$outdir, sprintf("automl_leaderboard_%s.csv", opt$dimension)
)
write.csv(leaderboard, leaderboard_file, row.names=FALSE, quote=TRUE)
cat(sprintf("[INFO] Saved AutoML leaderboard: %s\n", leaderboard_file))

best_config <- leaderboard[1, , drop=FALSE]
best_config_json_file <- file.path(
  opt$outdir, sprintf("automl_best_config_%s.json", opt$dimension)
)
best_config_csv_file <- file.path(
  opt$outdir, sprintf("automl_best_config_%s.csv", opt$dimension)
)
if(requireNamespace("jsonlite", quietly=TRUE)) {
  best_config_json <- jsonlite::toJSON(
    best_config,
    pretty=TRUE,
    auto_unbox=TRUE,
    null="null",
    digits=NA
  )
  writeLines(best_config_json, best_config_json_file, useBytes=TRUE)
  cat(sprintf("[INFO] Saved best overall configuration: %s\n", best_config_json_file))
} else {
  write.csv(best_config, best_config_csv_file, row.names=FALSE, quote=TRUE)
  cat(sprintf("[INFO] jsonlite unavailable; saved best overall configuration as CSV: %s\n",
              best_config_csv_file))
}

trace_data <- do.call(rbind, trace_rows)
trace_data$learner <- factor(trace_data$learner, levels=leaderboard$learner)
trace_plot <- ggplot(
  trace_data,
  aes(x=evaluation_index, y=running_best_auc, group=learner)
) +
  geom_line(linewidth=0.6, colour="#2C7FB8", na.rm=TRUE) +
  geom_point(size=0.8, colour="#2C7FB8", na.rm=TRUE) +
  facet_wrap(~learner, scales="free_x") +
  labs(
    title=sprintf("AutoML tuning trace: %s", opt$dimension),
    x="Evaluation index",
    y="Running best classif.auc"
  ) +
  theme_bw(base_size=10)

trace_file <- file.path(
  opt$outdir, sprintf("automl_tuning_trace_%s.pdf", opt$dimension)
)
ggsave(trace_file, trace_plot, width=10, height=7, units="in")
cat(sprintf("[INFO] Saved tuning trace plot: %s\n", trace_file))

if(length(skipped_learners) > 0) {
  cat(sprintf("[WARN] Skipped learners: %s\n",
              paste(unique(skipped_learners), collapse="; ")))
} else {
  cat(sprintf("[INFO] All configured learners completed successfully\n"))
}

total_runtime <- as.numeric(difftime(Sys.time(), start_time, units="secs"))
cat(sprintf("[INFO] Best overall learner: %s (CV AUC %.6f)\n",
            best_config$learner, best_config$best_cv_auc))
cat(sprintf("[INFO] AutoML-style exploration completed in %.1f seconds\n",
            total_runtime))
