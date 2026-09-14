#!/usr/bin/env Rscript

# Nested cross-validation in 04_nested_cv.R estimates unbiased generalization
# performance for each learner type. SHAP explanations instead require one
# deployable fitted model, so this script selects the learner type with the
# highest nested-CV mean AUC, repeats the same random-search tuning protocol on
# the full dataset, trains one final model on all samples, and explains that
# final model with model-agnostic Kernel SHAP via iml.

suppressPackageStartupMessages({
  library(optparse)
  library(mlr3)
  library(mlr3learners)
  library(mlr3tuning)
  library(paradox)
  library(future)
  library(iml)
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
  make_option(c("--n-tune-evals"), dest="n_tune_evals", type="integer", default=30,
              help="Random-search evaluations for final refit [default: 30]"),
  make_option(c("--n-shap-samples"), dest="n_shap_samples", type="integer", default=100,
              help="Maximum stratified samples to explain [default: 100]"),
  make_option(c("--n-top-features"), dest="n_top_features", type="integer", default=20,
              help="Top features shown in SHAP plots [default: 20]"),
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

integer_options <- c("n_tune_evals", "n_shap_samples", "n_top_features", "threads")
for(option_name in integer_options) {
  option_value <- opt[[option_name]]
  if(is.null(option_value) || length(option_value) != 1 || is.na(option_value) ||
     !is.finite(option_value) || option_value < 1) {
    stop("--", gsub("_", "-", option_name), " must be a positive integer")
  }
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
summary_file <- file.path(
  opt$outdir,
  sprintf("nested_cv_summary_%s.csv", opt$dimension)
)
if(!file.exists(opt$input)) {
  stop("Processed input file not found: ", opt$input)
}
if(!file.exists(summary_file)) {
  stop("Nested CV summary file not found: ", summary_file)
}
if(!requireNamespace("iml", quietly=TRUE)) {
  stop("Required package 'iml' is not installed")
}

start_time <- Sys.time()

cat(sprintf("[INFO] Starting final-model SHAP analysis\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Input: %s\n", opt$input))
cat(sprintf("[INFO] Nested CV summary: %s\n", summary_file))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Tuning evaluations: %d; maximum SHAP samples: %d\n",
            opt$n_tune_evals, opt$n_shap_samples))
cat(sprintf("[INFO] Top features: %d; parallel workers: %d; seed: %d\n",
            opt$n_top_features, opt$threads, opt$seed))

load_start <- Sys.time()
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
if(nrow(features) < 5) {
  stop("Number of samples is smaller than the required 5 tuning folds")
}
if(is.null(colnames(features)) || anyNA(colnames(features)) ||
   any(colnames(features) == "") || anyDuplicated(colnames(features))) {
  stop("Feature names must contain unique, non-empty values")
}

sample_ids <- rownames(features)
if(is.null(sample_ids) || anyNA(sample_ids) || any(sample_ids == "") ||
   anyDuplicated(sample_ids)) {
  stop("Feature row names must contain unique, non-empty sample IDs")
}

class_counts <- table(label)
if(any(class_counts < 5)) {
  stop("Each class must contain at least 5 samples for tuning CV; class balance: ",
       paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
             collapse=", "))
}

nested_cv_summary <- read.csv(summary_file, stringsAsFactors=FALSE, check.names=FALSE)
required_summary_columns <- c("learner", "mean_auc", "sd_auc", "min_auc", "max_auc")
missing_summary_columns <- setdiff(required_summary_columns, names(nested_cv_summary))
if(length(missing_summary_columns) > 0) {
  stop("Nested CV summary is missing columns: ",
       paste(missing_summary_columns, collapse=", "))
}
if(nrow(nested_cv_summary) == 0) {
  stop("Nested CV summary contains no successful learners")
}
nested_cv_summary$learner <- as.character(nested_cv_summary$learner)
nested_cv_summary$mean_auc <- suppressWarnings(as.numeric(nested_cv_summary$mean_auc))
if(anyNA(nested_cv_summary$learner) || any(nested_cv_summary$learner == "") ||
   any(!is.finite(nested_cv_summary$mean_auc))) {
  stop("Nested CV summary contains invalid learner names or mean AUC values")
}
valid_learner_ids <- c("lasso", "ridge", "elasticNet", "randomForest", "xgboost", "svm")
unknown_learners <- setdiff(nested_cv_summary$learner, valid_learner_ids)
if(length(unknown_learners) > 0) {
  stop("Nested CV summary contains unsupported learners: ",
       paste(unknown_learners, collapse=", "))
}

winner_index <- which.max(nested_cv_summary$mean_auc)
winning_learner_id <- nested_cv_summary$learner[winner_index]
winning_mean_auc <- nested_cv_summary$mean_auc[winner_index]
cat(sprintf("[INFO] Winning learner: %s (mean_auc=%.6f)\n",
            winning_learner_id, winning_mean_auc))

feature_data <- as.data.frame(features, check.names=FALSE)
original_feature_names <- colnames(feature_data)
task_data <- feature_data
task_data$label <- label

# The second factor level is intentionally treated as the positive class.
positive_class <- levels(label)[2]
task <- TaskClassif$new(
  id=sprintf("%s_shap_refit", opt$dimension),
  backend=task_data,
  target="label",
  positive=positive_class
)

cat(sprintf("[INFO] Created classification task: %d samples x %d features\n",
            task$nrow, length(task$feature_names)))
cat(sprintf("[INFO] Class balance: %s; positive class: %s\n",
            paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
                  collapse=", "), positive_class))
cat(sprintf("[INFO] Loaded inputs in %.1f seconds\n",
            as.numeric(difftime(Sys.time(), load_start, units="secs"))))

build_winning_learner <- function(learner_id) {
  if(learner_id %in% c("lasso", "ridge", "elasticNet")) {
    glmnet_params <- lrn("classif.glmnet")$param_set$ids()
    if(!"s" %in% glmnet_params) {
      stop("Installed classif.glmnet learner does not expose the expected 's' parameter")
    }
    if(!"alpha" %in% glmnet_params) {
      stop("Installed classif.glmnet learner does not expose the expected 'alpha' parameter")
    }
  }

  if(learner_id == "lasso") {
    lasso_learner <- lrn(
      "classif.glmnet",
      id="lasso",
      predict_type="prob",
      alpha=1
    )
    lasso_search_space <- ps(
      s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
    )
    return(list(learner=lasso_learner, search_space=lasso_search_space))
  }

  if(learner_id == "ridge") {
    ridge_learner <- lrn(
      "classif.glmnet",
      id="ridge",
      predict_type="prob",
      alpha=0
    )
    ridge_search_space <- ps(
      s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
    )
    return(list(learner=ridge_learner, search_space=ridge_search_space))
  }

  if(learner_id == "elasticNet") {
    elastic_net_learner <- lrn(
      "classif.glmnet",
      id="elasticNet",
      predict_type="prob"
    )
    elastic_net_search_space <- ps(
      alpha=p_dbl(lower=0, upper=1),
      s=p_dbl(lower=1e-4, upper=1e2, logscale=TRUE)
    )
    return(list(learner=elastic_net_learner, search_space=elastic_net_search_space))
  }

  if(learner_id == "randomForest") {
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
    return(list(
      learner=random_forest_learner,
      search_space=random_forest_search_space
    ))
  }

  if(learner_id == "xgboost") {
    xgboost_params <- lrn("classif.xgboost")$param_set$ids()
    required_xgboost_params <- c(
      "eta", "max_depth", "nrounds", "subsample", "colsample_bytree", "nthread"
    )
    missing_xgboost_params <- setdiff(required_xgboost_params, xgboost_params)
    if(length(missing_xgboost_params) > 0) {
      stop("Installed classif.xgboost learner does not expose expected parameters: ",
           paste(missing_xgboost_params, collapse=", "))
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
    return(list(learner=xgboost_learner, search_space=xgboost_search_space))
  }

  if(learner_id == "svm") {
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
    return(list(
      learner=svm_learner,
      search_space=ps(
        cost=p_dbl(lower=1e-2, upper=1e2, logscale=TRUE),
        gamma=p_dbl(lower=1e-4, upper=1e0, logscale=TRUE)
      )
    ))
  }

  stop("Unsupported winning learner: ", learner_id)
}

stratified_sample_indices <- function(labels, sample_size, seed) {
  total_size <- length(labels)
  if(sample_size >= total_size) {
    return(seq_len(total_size))
  }

  counts <- table(labels)
  proportions <- as.numeric(counts) / total_size
  allocations <- floor(proportions * sample_size)
  if(sample_size >= length(counts)) {
    allocations <- pmax(allocations, 1L)
  }
  allocations <- pmin(allocations, as.integer(counts))

  while(sum(allocations) < sample_size) {
    remaining_capacity <- as.integer(counts) - allocations
    candidates <- which(remaining_capacity > 0)
    priorities <- proportions[candidates] * sample_size - allocations[candidates]
    selected <- candidates[which.max(priorities)]
    allocations[selected] <- allocations[selected] + 1L
  }
  while(sum(allocations) > sample_size) {
    candidates <- which(allocations > 0)
    if(sample_size >= length(counts)) {
      candidates <- candidates[allocations[candidates] > 1]
    }
    priorities <- allocations[candidates] - proportions[candidates] * sample_size
    selected <- candidates[which.max(priorities)]
    allocations[selected] <- allocations[selected] - 1L
  }

  set.seed(seed)
  selected_indices <- unlist(lapply(seq_along(counts), function(class_index) {
    class_rows <- which(labels == names(counts)[class_index])
    sample(class_rows, allocations[class_index], replace=FALSE)
  }), use.names=FALSE)
  sort(selected_indices)
}

scale_within_feature <- function(values) {
  value_range <- range(values, na.rm=TRUE)
  if(!all(is.finite(value_range)) || value_range[1] == value_range[2]) {
    return(rep(0.5, length(values)))
  }
  (values - value_range[1]) / (value_range[2] - value_range[1])
}

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

if(opt$threads > 1) {
  future::plan(future::multisession, workers=opt$threads)
} else {
  future::plan(future::sequential)
}
on.exit(future::plan(future::sequential), add=TRUE)

learner_spec <- build_winning_learner(winning_learner_id)
cat(sprintf("[INFO] Reconstructed winning learner and nested-CV search space\n"))

set.seed(opt$seed)
tuning_start <- Sys.time()
cat(sprintf("[INFO] Starting full-data tuning for %s\n", winning_learner_id))
tuning_result <- tune(
  tuner=tnr("random_search"),
  task=task,
  learner=learner_spec$learner,
  resampling=rsmp("cv", folds=5),
  measures=msr("classif.auc"),
  terminator=trm("evals", n_evals=opt$n_tune_evals),
  search_space=learner_spec$search_space
)

archive_data <- as.data.frame(tuning_result$archive$data)
if(nrow(archive_data) == 0 || !"classif.auc" %in% names(archive_data)) {
  stop("Final refit tuning archive contains no AUC results")
}
best_cv_auc <- as.numeric(tuning_result$result$classif.auc[[1]])
if(!is.finite(best_cv_auc)) {
  stop("Final refit tuning produced a non-finite best CV AUC")
}
best_hyperparameters <- tuning_result$result_x_domain
if(is.null(best_hyperparameters) || length(best_hyperparameters) == 0) {
  best_hyperparameters <- tuning_result$result_learner_param_vals
}
best_hyperparameters <- as.list(best_hyperparameters)
if(length(best_hyperparameters) == 0) {
  stop("Unable to extract best hyperparameters from final refit tuning")
}
cat(sprintf("[INFO] Refit tuning best CV AUC: %.6f after %d evaluations\n",
            best_cv_auc, nrow(archive_data)))
cat(sprintf("[INFO] Completed full-data tuning in %.1f seconds\n",
            as.numeric(difftime(Sys.time(), tuning_start, units="secs"))))

training_start <- Sys.time()
final_learner <- learner_spec$learner$clone(deep=TRUE)
final_learner$param_set$set_values(.values=best_hyperparameters)
final_learner$train(task)
full_predictions <- as.numeric(
  final_learner$predict_newdata(feature_data)$prob[, positive_class]
)
if(length(full_predictions) != nrow(feature_data) || any(!is.finite(full_predictions)) ||
   any(full_predictions < 0 | full_predictions > 1)) {
  stop("Final learner produced invalid full-data probabilities")
}
baseline_prediction <- mean(full_predictions)
cat(sprintf("[INFO] Trained final learner on all samples in %.1f seconds\n",
            as.numeric(difftime(Sys.time(), training_start, units="secs"))))

iml_feature_names <- sprintf("feature_%0*d", nchar(ncol(feature_data)),
                             seq_len(ncol(feature_data)))
iml_feature_data <- feature_data
colnames(iml_feature_data) <- iml_feature_names

predict_positive_probability <- function(model, newdata) {
  if(ncol(newdata) != length(original_feature_names)) {
    stop("iml prediction data has an unexpected number of features: expected ",
         length(original_feature_names), ", found ", ncol(newdata))
  }
  colnames(newdata) <- original_feature_names
  newdata <- as.data.frame(newdata, check.names=FALSE)
  probabilities <- model$predict_newdata(newdata)$prob[, positive_class]
  data.frame(prob_positive=as.numeric(probabilities), check.names=FALSE)
}

predictor <- iml::Predictor$new(
  model=final_learner,
  data=iml_feature_data,
  y=label,
  predict.function=predict_positive_probability
)

predictor_test <- predictor$predict(
  iml_feature_data[seq_len(min(3L, nrow(iml_feature_data))), , drop=FALSE]
)
predictor_test_values <- as.numeric(predictor_test[[1]])
expected_test_values <- full_predictions[seq_len(length(predictor_test_values))]
if(length(predictor_test_values) != length(expected_test_values) ||
   any(!is.finite(predictor_test_values)) ||
   !isTRUE(all.equal(predictor_test_values, expected_test_values, tolerance=1e-12))) {
  stop("iml Predictor probability interface validation failed")
}
cat(sprintf("[INFO] Validated iml Predictor positive-class probability interface\n"))

selected_indices <- stratified_sample_indices(label, opt$n_shap_samples, opt$seed)
selected_sample_ids <- sample_ids[selected_indices]
selected_counts <- table(label[selected_indices])
cat(sprintf("[INFO] Selected %d samples for SHAP using stratified sampling: %s\n",
            length(selected_indices),
            paste(sprintf("%s=%d", names(selected_counts), as.integer(selected_counts)),
                  collapse=", ")))

shap_start <- Sys.time()
shapley_objects <- vector("list", length(selected_indices))
shap_rows <- vector("list", length(selected_indices))
for(shap_index in seq_along(selected_indices)) {
  row_index <- selected_indices[shap_index]
  sample_id <- sample_ids[row_index]
  sample_start <- Sys.time()
  set.seed(opt$seed + shap_index - 1L)
  shapley <- iml::Shapley$new(
    predictor,
    x.interest=iml_feature_data[row_index, , drop=FALSE]
  )
  result <- as.data.frame(shapley$results, stringsAsFactors=FALSE)
  if(!all(c("feature", "phi") %in% names(result))) {
    stop("Unexpected iml Shapley result columns for sample: ", sample_id)
  }
  feature_positions <- match(result$feature, iml_feature_names)
  if(anyNA(feature_positions)) {
    stop("Shapley results contain unknown features for sample: ", sample_id)
  }
  result$feature <- original_feature_names[feature_positions]
  shapley_objects[[shap_index]] <- shapley
  shap_rows[[shap_index]] <- data.frame(
    sample_id=sample_id,
    feature=result$feature,
    shap_value=as.numeric(result$phi),
    feature_value=as.numeric(features[row_index, feature_positions]),
    stringsAsFactors=FALSE
  )
  cat(sprintf("[INFO] SHAP sample %d/%d (%s) completed in %.1f seconds\n",
              shap_index, length(selected_indices), sample_id,
              as.numeric(difftime(Sys.time(), sample_start, units="secs"))))
}
names(shapley_objects) <- selected_sample_ids
shap_long <- do.call(rbind, shap_rows)
rownames(shap_long) <- NULL
if(any(!is.finite(shap_long$shap_value)) || any(!is.finite(shap_long$feature_value))) {
  stop("SHAP results contain non-finite values")
}
cat(sprintf("[INFO] Completed SHAP computation in %.1f seconds (%.2f minutes)\n",
            as.numeric(difftime(Sys.time(), shap_start, units="secs")),
            as.numeric(difftime(Sys.time(), shap_start, units="mins"))))

shap_rds_file <- file.path(
  opt$outdir, sprintf("shap_values_%s.rds", opt$dimension)
)
saveRDS(
  list(
    learner_id=winning_learner_id,
    nested_cv_mean_auc=winning_mean_auc,
    refit_cv_auc=best_cv_auc,
    best_hyperparameters=best_hyperparameters,
    positive_class=positive_class,
    baseline_prediction=baseline_prediction,
    sample_ids=selected_sample_ids,
    sample_indices=selected_indices,
    predictions=setNames(full_predictions[selected_indices], selected_sample_ids),
    shapley_objects=shapley_objects,
    shap_values=shap_long
  ),
  shap_rds_file
)

importance_split <- split(abs(shap_long$shap_value), shap_long$feature)
shap_importance <- data.frame(
  feature=names(importance_split),
  mean_abs_shap=vapply(importance_split, mean, numeric(1)),
  stringsAsFactors=FALSE
)
shap_importance <- shap_importance[
  order(shap_importance$mean_abs_shap, decreasing=TRUE), , drop=FALSE
]
rownames(shap_importance) <- NULL
importance_file <- file.path(
  opt$outdir, sprintf("shap_importance_%s.csv", opt$dimension)
)
write.csv(shap_importance, importance_file, row.names=FALSE, quote=TRUE)

top_feature_count <- min(opt$n_top_features, nrow(shap_importance))
top_features <- shap_importance$feature[seq_len(top_feature_count)]
summary_data <- shap_long[shap_long$feature %in% top_features, , drop=FALSE]
summary_data$feature_scaled <- ave(
  summary_data$feature_value,
  summary_data$feature,
  FUN=scale_within_feature
)
summary_data$feature <- factor(summary_data$feature, levels=rev(top_features))

summary_plot <- ggplot(summary_data, aes(x=shap_value, y=feature, color=feature_scaled)) +
  geom_vline(xintercept=0, color="grey75", linewidth=0.4) +
  geom_point(position=position_jitter(height=0.18, width=0),
             alpha=0.75, size=1.6) +
  scale_color_gradient(low="#2166AC", high="#B2182B",
                       limits=c(0, 1), name="Feature value\n(scaled)") +
  labs(
    title=sprintf("SHAP summary: %s", opt$dimension),
    subtitle=sprintf("Final tuned %s model; positive class: %s",
                     winning_learner_id, positive_class),
    x="SHAP value",
    y=NULL
  ) +
  theme_bw(base_size=11) +
  theme(panel.grid.major.y=element_blank(), panel.grid.minor=element_blank())
summary_plot_file <- file.path(
  opt$outdir, sprintf("shap_summary_%s.pdf", opt$dimension)
)
ggsave(summary_plot_file, summary_plot, width=9, height=max(5, 0.32 * top_feature_count + 2),
       units="in")

dependence_features <- shap_importance$feature[
  seq_len(min(5L, nrow(shap_importance)))
]
dependence_data <- shap_long[shap_long$feature %in% dependence_features, , drop=FALSE]
dependence_data$feature <- factor(dependence_data$feature, levels=dependence_features)
dependence_plot <- ggplot(dependence_data, aes(x=feature_value, y=shap_value)) +
  geom_hline(yintercept=0, color="grey75", linewidth=0.4) +
  geom_point(color="#2C7FB8", alpha=0.75, size=1.8) +
  facet_wrap(~ feature, scales="free_x") +
  labs(
    title=sprintf("SHAP dependence: %s", opt$dimension),
    x="Feature value",
    y="SHAP value"
  ) +
  theme_bw(base_size=11) +
  theme(panel.grid.minor=element_blank())
dependence_plot_file <- file.path(
  opt$outdir, sprintf("shap_dependence_%s.pdf", opt$dimension)
)
ggsave(dependence_plot_file, dependence_plot, width=10, height=6, units="in")

selected_predictions <- full_predictions[selected_indices]
selected_labels <- label[selected_indices]
case_positions <- which(selected_labels == positive_class)
control_positions <- which(selected_labels != positive_class)
high_case_positions <- if(length(case_positions) > 0) {
  head(case_positions[order(selected_predictions[case_positions], decreasing=TRUE)], 2L)
} else {
  integer()
}
high_control_positions <- if(length(control_positions) > 0) {
  head(control_positions[order(selected_predictions[control_positions])], 2L)
} else {
  integer()
}
uncertain_position <- which.min(abs(selected_predictions - 0.5))
representative_positions <- unique(c(
  high_case_positions,
  high_control_positions,
  uncertain_position
))
if(length(representative_positions) < min(5L, length(selected_indices))) {
  additional_positions <- order(abs(selected_predictions - 0.5))
  representative_positions <- unique(c(representative_positions, additional_positions))
}
representative_positions <- head(representative_positions, min(5L, length(selected_indices)))
representative_ids <- selected_sample_ids[representative_positions]

force_rows <- lapply(seq_along(representative_ids), function(representative_index) {
  sample_id <- representative_ids[representative_index]
  sample_data <- shap_long[shap_long$sample_id == sample_id, , drop=FALSE]
  sample_data <- sample_data[order(abs(sample_data$shap_value), decreasing=TRUE), , drop=FALSE]
  sample_data <- head(sample_data, 10L)
  sample_data$feature_label <- sprintf("%s = %.3g", sample_data$feature,
                                       sample_data$feature_value)
  sample_data$feature_label <- factor(
    sample_data$feature_label,
    levels=rev(sample_data$feature_label)
  )
  position <- match(sample_id, selected_sample_ids)
  sample_data$sample_panel <- sprintf(
    "%s | truth=%s | p(%s)=%.3f",
    sample_id, as.character(selected_labels[position]), positive_class,
    selected_predictions[position]
  )
  sample_data
})
force_data <- do.call(rbind, force_rows)
force_plot <- ggplot(force_data, aes(x=shap_value, y=feature_label, fill=shap_value > 0)) +
  geom_vline(xintercept=0, color="grey50", linewidth=0.4) +
  geom_col(width=0.72) +
  facet_wrap(~ sample_panel, scales="free_y", ncol=1) +
  scale_fill_manual(values=c(`TRUE`="#D73027", `FALSE`="#4575B4"),
                    labels=c(`TRUE`="Increases case probability",
                             `FALSE`="Decreases case probability"),
                    name=NULL) +
  labs(
    title=sprintf("Representative SHAP force plots: %s", opt$dimension),
    x="SHAP contribution",
    y=NULL
  ) +
  theme_bw(base_size=10) +
  theme(
    panel.grid.major.y=element_blank(),
    panel.grid.minor=element_blank(),
    legend.position="bottom",
    strip.text=element_text(size=9)
  )
force_plot_file <- file.path(
  opt$outdir, sprintf("shap_force_plots_%s.pdf", opt$dimension)
)
ggsave(force_plot_file, force_plot, width=10,
       height=max(7, 2.8 * length(representative_ids)), units="in")

uncertain_id <- selected_sample_ids[uncertain_position]
uncertain_data <- shap_long[shap_long$sample_id == uncertain_id, , drop=FALSE]
uncertain_data <- uncertain_data[
  order(abs(uncertain_data$shap_value), decreasing=TRUE), , drop=FALSE
]
top_waterfall <- head(uncertain_data, 10L)
uncertain_prediction <- selected_predictions[uncertain_position]
remaining_contribution <- uncertain_prediction - baseline_prediction -
  sum(top_waterfall$shap_value)
waterfall_contributions <- c(
  top_waterfall$shap_value,
  if(abs(remaining_contribution) > .Machine$double.eps) remaining_contribution else numeric()
)
waterfall_labels <- c(
  sprintf("%s = %.3g", top_waterfall$feature, top_waterfall$feature_value),
  if(abs(remaining_contribution) > .Machine$double.eps) {
    "Other features / SHAP residual"
  } else {
    character()
  }
)
waterfall_start <- baseline_prediction + c(0, head(cumsum(waterfall_contributions), -1L))
waterfall_end <- baseline_prediction + cumsum(waterfall_contributions)
waterfall_data <- data.frame(
  step=seq_along(waterfall_contributions),
  feature=waterfall_labels,
  contribution=waterfall_contributions,
  start=waterfall_start,
  end=waterfall_end,
  stringsAsFactors=FALSE
)
waterfall_data$lower <- pmin(waterfall_data$start, waterfall_data$end)
waterfall_data$upper <- pmax(waterfall_data$start, waterfall_data$end)
waterfall_data$direction <- waterfall_data$contribution > 0
waterfall_data$feature <- factor(waterfall_data$feature, levels=waterfall_labels)
waterfall_plot <- ggplot(waterfall_data, aes(x=feature)) +
  geom_rect(
    aes(xmin=step - 0.38, xmax=step + 0.38, ymin=lower, ymax=upper,
        fill=direction),
    inherit.aes=FALSE
  ) +
  geom_segment(
    data=waterfall_data[-nrow(waterfall_data), , drop=FALSE],
    aes(x=step + 0.38, xend=step + 1 - 0.38, y=end, yend=end),
    inherit.aes=FALSE,
    color="grey50",
    linewidth=0.4
  ) +
  geom_hline(yintercept=baseline_prediction, linetype="dashed",
             color="grey35", linewidth=0.5) +
  geom_hline(yintercept=uncertain_prediction, linetype="dotted",
             color="black", linewidth=0.6) +
  scale_fill_manual(values=c(`TRUE`="#D73027", `FALSE`="#4575B4"),
                    labels=c(`TRUE`="Increase", `FALSE`="Decrease"), name=NULL) +
  scale_x_discrete(drop=FALSE) +
  coord_cartesian(ylim=range(c(0, 1, waterfall_data$lower, waterfall_data$upper))) +
  labs(
    title=sprintf("SHAP waterfall: %s", uncertain_id),
    subtitle=sprintf("Baseline=%.3f; predicted p(%s)=%.3f; truth=%s",
                     baseline_prediction, positive_class, uncertain_prediction,
                     as.character(selected_labels[uncertain_position])),
    x=NULL,
    y=sprintf("Cumulative p(%s) approximation", positive_class)
  ) +
  theme_bw(base_size=10) +
  theme(
    axis.text.x=element_text(angle=50, hjust=1),
    panel.grid.minor=element_blank(),
    legend.position="bottom"
  )
waterfall_plot_file <- file.path(
  opt$outdir, sprintf("shap_waterfall_%s.pdf", opt$dimension)
)
ggsave(waterfall_plot_file, waterfall_plot, width=11, height=6.5, units="in")

plot_runtime <- as.numeric(difftime(Sys.time(), shap_start, units="secs"))
total_runtime <- as.numeric(difftime(Sys.time(), start_time, units="secs"))
cat(sprintf("[INFO] Saved raw SHAP results: %s\n", shap_rds_file))
cat(sprintf("[INFO] Saved SHAP importance: %s\n", importance_file))
cat(sprintf("[INFO] Saved SHAP summary plot: %s\n", summary_plot_file))
cat(sprintf("[INFO] Saved SHAP dependence plot: %s\n", dependence_plot_file))
cat(sprintf("[INFO] Saved SHAP force plots: %s\n", force_plot_file))
cat(sprintf("[INFO] Saved SHAP waterfall plot: %s\n", waterfall_plot_file))
cat(sprintf("[INFO] SHAP computation and output generation took %.1f seconds\n", plot_runtime))
cat(sprintf("[INFO] Total runtime: %.1f seconds (%.2f minutes)\n",
            total_runtime, total_runtime / 60))
cat(sprintf("[INFO] Final-model SHAP analysis completed successfully\n"))
