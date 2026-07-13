#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(ggplot2)
})

# Parse arguments
option_list <- list(
  make_option(c("-i", "--input"), type="character",
              help="Functional table TSV (rows=features, columns=samples)"),
  make_option(c("-m", "--metadata"), type="character",
              help="Metadata CSV path"),
  make_option(c("-g", "--group"), type="character",
              help="Binary metadata group column"),
  make_option(c("-l", "--label"), type="character",
              help="Output filename and plot-title label"),
  make_option(c("-o", "--outdir"), type="character",
              help="Output directory"),
  make_option(c("--n-top"), dest="n_top", type="integer", default=30,
              help="Maximum features shown in the plot [default: 30]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate inputs
required <- c("input", "metadata", "group", "label", "outdir")
missing <- required[!required %in% names(opt) |
                      vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}
if(!file.exists(opt$input)) {
  stop("Input file not found: ", opt$input)
}
if(!file.exists(opt$metadata)) {
  stop("Metadata file not found: ", opt$metadata)
}
if(length(opt$n_top) != 1 || is.na(opt$n_top) || !is.finite(opt$n_top) ||
   opt$n_top < 1 || opt$n_top != as.integer(opt$n_top)) {
  stop("--n-top must be a positive integer")
}

shorten_feature_label <- function(feature_strings) {
  shortened <- vapply(feature_strings, function(feature_string) {
    if(is.na(feature_string)) {
      return("NA")
    }
    feature_string <- as.character(feature_string)
    if(nchar(feature_string) > 60) {
      return(paste0(substr(feature_string, 1, 57), "..."))
    }
    feature_string
  }, character(1))
  make.unique(shortened, sep=" #")
}

start_time <- proc.time()[["elapsed"]]

cat(sprintf("[INFO] Starting two-group CLR effect-size analysis\n"))
cat(sprintf("[INFO] Functional table: %s\n", opt$input))
cat(sprintf("[INFO] Metadata: %s\n", opt$metadata))
cat(sprintf("[INFO] Group column: %s\n", opt$group))
cat(sprintf("[INFO] Label: %s\n", opt$label))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Maximum plotted features: %d\n", opt$n_top))

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

# Load functional table with features in rows and samples in columns
functional_df <- readr::read_tsv(
  opt$input,
  comment="#",
  show_col_types=FALSE,
  progress=FALSE,
  name_repair="minimal"
)
if(ncol(functional_df) < 2) {
  stop("Functional table must contain a feature column and at least one sample column")
}
if(nrow(functional_df) == 0) {
  stop("Functional table contains 0 features")
}

feature_col <- names(functional_df)[1]
feature_ids <- as.character(functional_df[[feature_col]])
if(anyNA(feature_ids) || any(feature_ids == "")) {
  stop("Feature identifiers contain missing or empty values")
}
if(anyDuplicated(feature_ids)) {
  stop("Feature identifiers must be unique; duplicated identifiers found")
}

sample_ids <- names(functional_df)[-1]
if(anyDuplicated(sample_ids)) {
  stop("Sample identifiers in functional table must be unique")
}

functional_numeric <- lapply(functional_df[-1], function(values) {
  suppressWarnings(as.numeric(values))
})
invalid_numeric <- vapply(seq_along(functional_numeric), function(index) {
  any(is.na(functional_numeric[[index]]) & !is.na(functional_df[-1][[index]]))
}, logical(1))
if(any(invalid_numeric)) {
  stop("Non-numeric abundance values found in sample columns: ",
       paste(sample_ids[invalid_numeric], collapse=", "))
}

otu_mat <- as.matrix(as.data.frame(functional_numeric, check.names=FALSE))
storage.mode(otu_mat) <- "double"
rownames(otu_mat) <- feature_ids
colnames(otu_mat) <- sample_ids
if(any(!is.finite(otu_mat))) {
  stop("Functional table contains non-finite values")
}
if(any(otu_mat < 0)) {
  stop("Functional table contains negative values")
}

cat(sprintf("[INFO] Loaded %d features across %d table samples\n",
            nrow(otu_mat), ncol(otu_mat)))

# Match metadata using sample_id when available, otherwise the first column
metadata <- as.data.frame(
  readr::read_csv(opt$metadata, show_col_types=FALSE, progress=FALSE),
  check.names=FALSE
)
if(!opt$group %in% names(metadata)) {
  stop("Group column not found in metadata: ", opt$group)
}

sample_id_col <- if("sample_id" %in% names(metadata)) "sample_id" else names(metadata)[1]
metadata[[sample_id_col]] <- as.character(metadata[[sample_id_col]])
if(anyNA(metadata[[sample_id_col]]) || any(metadata[[sample_id_col]] == "")) {
  stop("Metadata sample identifiers contain missing or empty values")
}
if(anyDuplicated(metadata[[sample_id_col]])) {
  stop("Metadata sample identifiers must be unique")
}

metadata_groups <- as.character(metadata[[opt$group]])
group_levels_all <- sort(unique(metadata_groups[!is.na(metadata_groups) &
                                                  metadata_groups != ""]))
if(length(group_levels_all) != 2) {
  stop("Group column must have exactly 2 unique non-NA levels; found: ",
       paste(group_levels_all, collapse=", "))
}

matched_samples <- sample_ids[sample_ids %in% metadata[[sample_id_col]]]
if(length(matched_samples) == 0) {
  stop("No samples are shared between the functional table and metadata")
}

meta_aligned <- metadata[
  match(matched_samples, metadata[[sample_id_col]]), , drop=FALSE
]
group_values <- as.character(meta_aligned[[opt$group]])
valid_group <- !is.na(group_values) & group_values != "" &
  group_values %in% group_levels_all
if(any(!valid_group)) {
  cat(sprintf("[WARN] Excluding %d matched samples with missing group values\n",
              sum(!valid_group)))
}

matched_samples <- matched_samples[valid_group]
group_values <- group_values[valid_group]
otu_mat <- otu_mat[, matched_samples, drop=FALSE]

group_levels <- sort(unique(group_values))
if(length(group_levels) != 2) {
  stop("Group column must have exactly 2 levels among matched samples; found: ",
       paste(group_levels, collapse=", "))
}
group_counts <- table(factor(group_values, levels=group_levels))
if(any(group_counts < 3)) {
  stop("At least 3 matched samples per group are required; found: ",
       paste(sprintf("%s=%d", names(group_counts), as.integer(group_counts)),
             collapse=", "))
}

cat(sprintf("[INFO] Metadata sample-ID column: %s\n", sample_id_col))
cat(sprintf("[INFO] Matched %d samples between table and metadata\n",
            length(matched_samples)))
cat(sprintf("[INFO] Group order: %s (group1), %s (group2)\n",
            group_levels[1], group_levels[2]))
cat(sprintf("[INFO] Class balance: %s\n",
            paste(sprintf("%s=%d", names(group_counts), as.integer(group_counts)),
                  collapse=", ")))

# Apply the same per-sample CLR fallback used by differential abundance.
clr_mat <- apply(otu_mat + 1, 2, function(x) log(x) - mean(log(x)))
if(is.null(dim(clr_mat))) {
  clr_mat <- matrix(clr_mat, nrow=nrow(otu_mat),
                    dimnames=list(rownames(otu_mat), colnames(otu_mat)))
} else {
  rownames(clr_mat) <- rownames(otu_mat)
  colnames(clr_mat) <- colnames(otu_mat)
}
if(any(!is.finite(clr_mat))) {
  stop("CLR transform produced non-finite values")
}
if(nrow(clr_mat) == 0) {
  stop("No valid features remain after CLR transformation and sample matching")
}

group1_samples <- group_values == group_levels[1]
group2_samples <- group_values == group_levels[2]

p_values <- apply(clr_mat, 1, function(values) {
  tryCatch(
    stats::wilcox.test(values[group1_samples], values[group2_samples],
                       exact=FALSE)$p.value,
    error=function(error) NA_real_
  )
})

# Direction is group2 minus group1, where group2 is the second alphabetic level.
mean_diff <- apply(clr_mat, 1, function(values) {
  mean(values[group2_samples]) - mean(values[group1_samples])
})

results <- data.frame(
  feature=rownames(clr_mat),
  mean_diff=as.numeric(mean_diff),
  p_value=as.numeric(p_values),
  direction=ifelse(mean_diff >= 0, "up", "down"),
  stringsAsFactors=FALSE
)
valid_results <- is.finite(results$mean_diff) & is.finite(results$p_value) &
  !is.na(results$feature) & results$feature != ""
if(any(!valid_results)) {
  cat(sprintf("[WARN] Excluding %d features with invalid effect-size results\n",
              sum(!valid_results)))
}
results <- results[valid_results, , drop=FALSE]
if(nrow(results) == 0) {
  stop("No valid features remain after CLR effect-size calculation")
}
results <- results[order(abs(results$mean_diff), decreasing=TRUE), , drop=FALSE]
rownames(results) <- NULL

results_file <- file.path(opt$outdir, sprintf("effect_size_%s.csv", opt$label))
readr::write_csv(results, results_file)
cat(sprintf("[INFO] Saved effect-size results: %s\n", results_file))

n_plotted <- min(opt$n_top, nrow(results))
plot_data <- results[seq_len(n_plotted), , drop=FALSE]
plot_data$short_label <- shorten_feature_label(plot_data$feature)

effect_plot <- ggplot(
  plot_data,
  aes(
    x=mean_diff,
    y=stats::reorder(short_label, mean_diff),
    fill=mean_diff
  )
) +
  geom_col(width=0.78) +
  scale_fill_gradient2(
    low="#2C6DB2", mid="grey90", high="#C6295C", midpoint=0
  ) +
  labs(
    title=sprintf("Top %d features by effect size: %s", n_plotted, opt$label),
    x=sprintf("Mean CLR difference (%s - %s)", group_levels[2], group_levels[1]),
    y=NULL
  ) +
  theme_classic(base_size=11) +
  theme(
    legend.position="none",
    axis.ticks.y=element_blank(),
    plot.title=element_text(face="bold", hjust=0.5),
    plot.margin=margin(8, 12, 8, 8)
  )

plot_file <- file.path(opt$outdir, sprintf("effect_size_%s.pdf", opt$label))
ggsave(
  plot_file, effect_plot, width=8,
  height=max(4, 0.28 * n_plotted + 1.5), units="in"
)
cat(sprintf("[INFO] Saved effect-size plot: %s\n", plot_file))

elapsed <- proc.time()[["elapsed"]] - start_time
cat(sprintf("[INFO] Effect-size analysis completed in %.2f seconds\n", elapsed))
