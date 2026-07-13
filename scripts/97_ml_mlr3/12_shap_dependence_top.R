#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
})

option_list <- list(
  make_option(c("-w", "--workdir"), type="character",
              help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character",
              help="Dimension used in SHAP filenames: bacteria/virus/fungi"),
  make_option(c("-i", "--input-dir"), dest="input_dir", type="character", default=NULL,
              help="Directory containing processed_*.rds and SHAP outputs"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: input-dir]"),
  make_option(c("--n-top"), dest="n_top", type="integer", default=5,
              help="Number of top features to plot [default: 5]")
)

opt <- parse_args(OptionParser(option_list=option_list))

required <- c("workdir", "dimension", "input_dir")
missing <- required[!required %in% names(opt) |
                    vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}
if(!opt$dimension %in% c("bacteria", "virus", "fungi")) {
  stop("Invalid dimension: ", opt$dimension,
       ". Expected bacteria, virus, or fungi")
}
if(length(opt$n_top) != 1 || is.na(opt$n_top) || opt$n_top < 1) {
  stop("--n-top must be a positive integer")
}

input_dir <- normalizePath(opt$input_dir, mustWork=TRUE)
if(is.null(opt$outdir)) {
  opt$outdir <- input_dir
}
dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

importance_file <- file.path(
  input_dir, sprintf("shap_importance_%s.csv", opt$dimension)
)
shap_file <- file.path(
  input_dir, sprintf("shap_values_%s.rds", opt$dimension)
)
processed_candidates <- list.files(
  input_dir, pattern="^processed_.+\\.rds$", full.names=TRUE
)

if(!file.exists(importance_file)) {
  stop("SHAP importance file not found: ", importance_file)
}
if(!file.exists(shap_file)) {
  stop("SHAP values file not found: ", shap_file)
}
if(length(processed_candidates) != 1) {
  stop("Expected exactly one processed_*.rds in ", input_dir,
       "; found ", length(processed_candidates))
}

importance <- read.csv(
  importance_file, stringsAsFactors=FALSE, check.names=FALSE
)
if(!all(c("feature", "mean_abs_shap") %in% names(importance))) {
  stop("SHAP importance CSV must contain feature and mean_abs_shap columns")
}
importance <- importance[
  is.finite(importance$mean_abs_shap) & !is.na(importance$feature) &
    nzchar(importance$feature), , drop=FALSE
]
importance <- importance[
  order(importance$mean_abs_shap, decreasing=TRUE), , drop=FALSE
]
importance <- importance[!duplicated(importance$feature), , drop=FALSE]
if(nrow(importance) == 0) {
  stop("No valid features found in: ", importance_file)
}

processed <- readRDS(processed_candidates[[1]])
if(is.null(processed$features)) {
  stop("Processed RDS is missing the features element")
}
features <- as.matrix(processed$features)
if(is.null(colnames(features))) {
  stop("Processed feature matrix has no column names")
}
if(is.null(rownames(features))) {
  if(!is.null(processed$meta$sample_id) &&
     length(processed$meta$sample_id) == nrow(features)) {
    rownames(features) <- as.character(processed$meta$sample_id)
  } else {
    stop("Cannot determine sample IDs for processed feature matrix")
  }
}

shap_result <- readRDS(shap_file)
shap_long <- shap_result$shap_values
if(is.null(shap_long) ||
   !all(c("sample_id", "feature", "shap_value") %in% names(shap_long))) {
  stop("SHAP RDS must contain shap_values with sample_id, feature, and shap_value")
}
shap_long$sample_id <- as.character(shap_long$sample_id)
shap_long$feature <- as.character(shap_long$feature)

available_features <- intersect(importance$feature, colnames(features))
available_features <- intersect(available_features, unique(shap_long$feature))
if(length(available_features) == 0) {
  stop("No ranked SHAP features are shared by processed and SHAP data")
}
top_features <- head(available_features, opt$n_top)

sample_ids <- unique(shap_long$sample_id)
missing_samples <- setdiff(sample_ids, rownames(features))
if(length(missing_samples) > 0) {
  stop("SHAP sample IDs missing from processed features: ",
       paste(head(missing_samples, 10), collapse=", "))
}

wrap_feature <- function(feature, width=48) {
  pieces <- strwrap(feature, width=width, simplify=FALSE)
  if(length(pieces) == 0) feature else paste(pieces, collapse="\n")
}

is_low_variance <- function(values) {
  finite_values <- values[is.finite(values)]
  if(length(finite_values) < 2 || length(unique(finite_values)) < 2) {
    return(TRUE)
  }
  value_scale <- max(1, max(abs(finite_values)))
  stats::sd(finite_values) <= 1e-8 * value_scale ||
    diff(range(finite_values)) <= 1e-8 * value_scale
}

make_plot <- function(feature) {
  feature_shap <- shap_long[shap_long$feature == feature,
                            c("sample_id", "shap_value"), drop=FALSE]
  if(anyDuplicated(feature_shap$sample_id)) {
    feature_shap <- aggregate(
      shap_value ~ sample_id, data=feature_shap, FUN=mean
    )
  }
  feature_shap$feature_value <- features[feature_shap$sample_id, feature]

  interaction_feature <- if(length(available_features) < 2) {
    NA_character_
  } else if(feature == available_features[[2]]) {
    available_features[[1]]
  } else {
    available_features[[2]]
  }

  plot_data <- feature_shap
  if(!is.na(interaction_feature)) {
    plot_data$interaction_value <- features[
      plot_data$sample_id, interaction_feature
    ]
  }

  title <- paste0("SHAP dependence: ", wrap_feature(feature))
  subtitle <- if(is.na(interaction_feature)) {
    sprintf("%s; no second feature available for interaction coloring",
            opt$dimension)
  } else {
    sprintf("%s; color shows CLR of %s", opt$dimension,
            wrap_feature(interaction_feature, width=60))
  }

  plot <- ggplot(plot_data, aes(x=feature_value, y=shap_value)) +
    geom_hline(yintercept=0, color="grey75", linewidth=0.45) +
    labs(
      title=title,
      subtitle=subtitle,
      x=sprintf("CLR value of %s", wrap_feature(feature, width=55)),
      y="SHAP value"
    ) +
    theme_classic(base_size=12) +
    theme(
      plot.title=element_text(face="bold", size=13),
      plot.subtitle=element_text(color="grey35", size=10),
      legend.position="right"
    )

  if(is.na(interaction_feature)) {
    plot <- plot + geom_point(color="#2C7FB8", alpha=0.78, size=2.1)
  } else {
    plot <- plot +
      geom_point(aes(color=interaction_value), alpha=0.8, size=2.1) +
      scale_color_gradient(
        low="#2166AC", high="#B2182B",
        name=paste0("CLR: ", wrap_feature(interaction_feature, width=24))
      )
  }

  if(is_low_variance(plot_data$feature_value)) {
    plot <- plot + annotate(
      "label", x=Inf, y=Inf, label="Low variance feature",
      hjust=1.08, vjust=1.4, color="#B2182B", fill="white",
      label.size=0.25, size=3.7
    )
  }
  plot
}

output_file <- file.path(
  opt$outdir,
  sprintf("shap_dependence_top%d_%s.pdf", length(top_features), opt$dimension)
)
grDevices::pdf(output_file, width=9, height=6.5, onefile=TRUE)
for(feature in top_features) {
  print(make_plot(feature))
}
grDevices::dev.off()

cat(sprintf("[INFO] Input directory: %s\n", input_dir))
cat(sprintf("[INFO] Processed input: %s\n", processed_candidates[[1]]))
cat(sprintf("[INFO] Wrote %d-page PDF: %s\n",
            length(top_features), output_file))
cat(sprintf("[TOP_FEATURES] %s\n", paste(top_features, collapse=" | ")))
