#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(Boruta)
})

# Parse arguments
option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character",
              help="Dimension: bacteria/virus/fungi"),
  make_option(c("-i", "--input"), type="character", default=NULL,
              help="Processed input RDS [default: workdir/result/stat/dimension/ml_mlr3/processed_dimension.rds]"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: workdir/result/stat/dimension/ml_mlr3]"),
  make_option(c("--max-runs"), dest="max_runs", type="integer", default=100,
              help="Maximum Boruta runs [default: 100]"),
  make_option(c("--p-value"), dest="p_value", type="double", default=0.01,
              help="Boruta p-value threshold [default: 0.01]"),
  make_option(c("-t", "--threads"), type="integer", default=1,
              help="Requested parallel workers; Boruta 9.0.0 runs serially [default: 1]"),
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
if(is.na(opt$max_runs) || opt$max_runs <= 10) {
  stop("--max-runs must be an integer greater than 10")
}
if(!is.finite(opt$p_value) || opt$p_value <= 0 || opt$p_value >= 1) {
  stop("--p-value must be greater than 0 and less than 1")
}
if(is.na(opt$threads) || opt$threads < 1) {
  stop("--threads must be a positive integer")
}
if(is.na(opt$seed)) {
  stop("--seed must be an integer")
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

cat(sprintf("[INFO] Starting Boruta feature selection\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Input: %s\n", opt$input))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Parameters: maxRuns=%d, pValue=%.6g, seed=%d\n",
            opt$max_runs, opt$p_value, opt$seed))
if(opt$threads > 1) {
  cat(sprintf(paste0(
    "[WARN] --threads=%d requested, but installed Boruta %s has no native ",
    "parallel argument; proceeding serially\n"
  ), opt$threads, as.character(utils::packageVersion("Boruta"))))
} else {
  cat(sprintf("[INFO] Boruta will run serially\n"))
}

start_time <- proc.time()[["elapsed"]]
processed <- readRDS(opt$input)
if(!is.list(processed) || !all(c("features", "label") %in% names(processed))) {
  stop("Input RDS must be a list containing features and label")
}

features <- processed$features
label <- processed$label
if(!is.matrix(features) || !is.numeric(features)) {
  stop("features must be a numeric matrix")
}
if(nrow(features) < 2 || ncol(features) < 1) {
  stop("features must contain at least 2 samples and 1 feature")
}
if(any(!is.finite(features))) {
  stop("features contains non-finite values")
}
if(is.null(colnames(features)) || anyNA(colnames(features)) || any(colnames(features) == "")) {
  stop("features must have non-empty column names")
}
if(anyDuplicated(colnames(features))) {
  stop("Feature names must be unique")
}
if(!is.factor(label)) {
  stop("label must be a factor")
}
if(length(label) != nrow(features)) {
  stop("label length must equal the number of feature matrix rows")
}
if(anyNA(label)) {
  stop("label contains missing values")
}
if(nlevels(label) != 2) {
  stop("label must have exactly 2 levels")
}

cat(sprintf("[INFO] Loaded %d samples x %d features\n",
            nrow(features), ncol(features)))
class_counts <- table(label)
cat(sprintf("[INFO] Class balance: %s\n",
            paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
                  collapse=", ")))

set.seed(opt$seed)
boruta_result <- Boruta::Boruta(
  x=features,
  y=label,
  maxRuns=opt$max_runs,
  pValue=opt$p_value,
  doTrace=2
)

initial_stats <- Boruta::attStats(boruta_result)
initial_counts <- table(factor(initial_stats$decision,
                               levels=c("Confirmed", "Tentative", "Rejected")))
cat(sprintf("[INFO] Main run decisions: Confirmed=%d, Tentative=%d, Rejected=%d\n",
            initial_counts[["Confirmed"]], initial_counts[["Tentative"]],
            initial_counts[["Rejected"]]))

if(initial_counts[["Tentative"]] > 0) {
  cat(sprintf("[INFO] Applying TentativeRoughFix to %d tentative features\n",
              initial_counts[["Tentative"]]))
  boruta_result <- Boruta::TentativeRoughFix(boruta_result)
}

attribute_stats <- Boruta::attStats(boruta_result)

# Boruta coerces x to a data.frame internally, which mangles column names
# (e.g. "|" becomes ".") via make.names(). Map mangled names in attStats
# back to the original feature names so downstream consumers of
# selected_features_*.txt can match them against colnames(features).
mangled_names <- make.names(colnames(features), unique=TRUE)
name_lookup <- setNames(colnames(features), mangled_names)
restored_features <- name_lookup[rownames(attribute_stats)]
if(anyNA(restored_features)) {
  stop("Failed to map Boruta's mangled feature names back to original names")
}

importance_df <- data.frame(
  feature=unname(restored_features),
  meanImp=attribute_stats$meanImp,
  medianImp=attribute_stats$medianImp,
  decision=as.character(attribute_stats$decision),
  stringsAsFactors=FALSE,
  row.names=NULL
)
importance_df <- importance_df[order(importance_df$meanImp, decreasing=TRUE,
                                     na.last=TRUE), , drop=FALSE]
confirmed_features <- importance_df$feature[importance_df$decision == "Confirmed"]
final_counts <- table(factor(importance_df$decision,
                             levels=c("Confirmed", "Tentative", "Rejected")))

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)
rds_file <- file.path(opt$outdir, sprintf("boruta_%s.rds", opt$dimension))
selected_file <- file.path(opt$outdir,
                           sprintf("selected_features_%s.txt", opt$dimension))
importance_file <- file.path(opt$outdir,
                             sprintf("boruta_importance_%s.csv", opt$dimension))
importance_plot_file <- file.path(opt$outdir,
                                  sprintf("boruta_importance_%s.pdf", opt$dimension))
history_plot_file <- file.path(opt$outdir,
                               sprintf("boruta_history_%s.pdf", opt$dimension))

saveRDS(boruta_result, rds_file)
writeLines(confirmed_features, selected_file, useBytes=TRUE)
utils::write.csv(importance_df, importance_file, row.names=FALSE, quote=TRUE)

plot_result <- boruta_result
if(nrow(importance_df) > 40) {
  # plot_result retains Boruta's internal mangled names, so subset using
  # those rather than the restored original names in importance_df$feature.
  plot_features <- head(mangled_names[match(importance_df$feature, restored_features)], 30)
  shadow_features <- grep("^shadow", colnames(plot_result$ImpHistory), value=TRUE)
  plot_result$finalDecision <- plot_result$finalDecision[plot_features]
  plot_result$ImpHistory <- plot_result$ImpHistory[, c(plot_features, shadow_features),
                                                   drop=FALSE]
}

grDevices::pdf(importance_plot_file, width=12, height=8, onefile=TRUE)
tryCatch(
  plot(plot_result, las=2, cex.axis=0.5,
       main=sprintf("Boruta feature importance: %s", opt$dimension)),
  error=function(error) {
    graphics::plot.new()
    graphics::text(0.5, 0.5,
                   sprintf("Boruta importance plot unavailable: %s", error$message),
                   cex=0.8)
    cat(sprintf("[WARN] Built-in importance plot failed: %s\n", error$message))
  }
)
grDevices::dev.off()

grDevices::pdf(history_plot_file, width=12, height=8, onefile=TRUE)
tryCatch(
  Boruta::plotImpHistory(
    plot_result,
    main=sprintf("Boruta importance history: %s", opt$dimension)
  ),
  error=function(error) {
    graphics::plot.new()
    graphics::text(0.5, 0.5,
                   sprintf("Boruta history plot unavailable: %s", error$message),
                   cex=0.8)
    cat(sprintf("[WARN] Importance history plot failed: %s\n", error$message))
  }
)
grDevices::dev.off()

cat(sprintf("[INFO] Final decisions: Confirmed=%d, Tentative=%d, Rejected=%d\n",
            final_counts[["Confirmed"]], final_counts[["Tentative"]],
            final_counts[["Rejected"]]))
cat(sprintf("[INFO] Final confirmed feature count: %d\n", length(confirmed_features)))
if(length(confirmed_features) < 5) {
  cat(sprintf("[WARN] Fewer than 5 features were confirmed; downstream steps should handle this case\n"))
}
cat(sprintf("[INFO] Saved Boruta result: %s\n", rds_file))
cat(sprintf("[INFO] Saved confirmed features: %s\n", selected_file))
cat(sprintf("[INFO] Saved importance statistics: %s\n", importance_file))
cat(sprintf("[INFO] Saved importance plot: %s\n", importance_plot_file))
cat(sprintf("[INFO] Saved importance history: %s\n", history_plot_file))
runtime_seconds <- proc.time()[["elapsed"]] - start_time
cat(sprintf("[INFO] Runtime: %.2f seconds (%.2f minutes)\n",
            runtime_seconds, runtime_seconds / 60))
cat(sprintf("[INFO] Boruta feature selection completed successfully\n"))
