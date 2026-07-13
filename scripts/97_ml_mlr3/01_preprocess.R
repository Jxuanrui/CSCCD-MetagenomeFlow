#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(compositions)
})

# Parse arguments
option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character", help="Dimension: bacteria/virus/fungi"),
  make_option(c("-m", "--metadata"), type="character", help="Metadata CSV path"),
  make_option(c("-g", "--group"), type="character", help="Group column name"),
  make_option(c("--min-prevalence"), dest="min_prevalence", type="double", default=0.05,
              help="Minimum feature prevalence [default: 0.05]"),
  make_option(c("--min-rel-abund"), dest="min_rel_abund", type="double", default=1e-4,
              help="Minimum mean relative abundance [default: 1e-4]"),
  make_option(c("--pseudocount"), type="double", default=1e-6,
              help="Pseudocount for CLR transform [default: 1e-6]"),
  make_option(c("--abundance-file"), dest="abundance_file", type="character", default=NULL,
              help="Abundance table path override [default: dimension-specific taxonomy table]"),
  make_option(c("--feature-label"), dest="feature_label", type="character", default=NULL,
              help="Output filename label [default: dimension]"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: workdir/result/stat/dimension/ml_mlr3]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate inputs
required <- c("workdir", "dimension", "metadata", "group")
missing <- required[!required %in% names(opt) | vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}

valid_dimensions <- c("bacteria", "virus", "fungi")
if(!opt$dimension %in% valid_dimensions) {
  stop("Invalid dimension: ", opt$dimension,
       ". Expected one of: ", paste(valid_dimensions, collapse=", "))
}
if(!is.finite(opt$min_prevalence) || opt$min_prevalence < 0 || opt$min_prevalence > 1) {
  stop("--min-prevalence must be between 0 and 1")
}
if(!is.finite(opt$min_rel_abund) || opt$min_rel_abund < 0) {
  stop("--min-rel-abund must be non-negative")
}
if(!is.finite(opt$pseudocount) || opt$pseudocount <= 0) {
  stop("--pseudocount must be greater than 0")
}
if(!file.exists(opt$metadata)) {
  stop("Metadata file not found: ", opt$metadata)
}

if(is.null(opt$outdir)) {
  opt$outdir <- file.path(opt$workdir, "result", "stat", opt$dimension, "ml_mlr3")
}

abundance_paths <- c(
  bacteria=file.path(opt$workdir, "result", "bacteria", "metaphlan4",
                     "merged_abundance_table.txt"),
  virus=file.path(opt$workdir, "result", "virus", "votu", "votu_table.tsv"),
  fungi=file.path(opt$workdir, "result", "fungi", "metaphlan4",
                  "merged_abundance_table.txt")
)
if(is.null(opt$abundance_file)) {
  abundance_file <- abundance_paths[[opt$dimension]]
} else {
  abundance_file <- opt$abundance_file
}
if(!file.exists(abundance_file)) {
  stop("Abundance table not found: ", abundance_file)
}

feature_label <- if(is.null(opt$feature_label)) opt$dimension else opt$feature_label

cat(sprintf("[INFO] Starting mlr3 preprocessing\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Abundance table: %s\n", abundance_file))
cat(sprintf("[INFO] Metadata: %s\n", opt$metadata))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))

# Load abundance table with features in rows and samples in columns
abundance_df <- readr::read_tsv(
  abundance_file,
  comment="#",
  show_col_types=FALSE,
  progress=FALSE,
  name_repair="minimal"
)
if(ncol(abundance_df) < 2) {
  stop("Abundance table must contain a feature column and at least one sample column")
}

feature_col <- names(abundance_df)[1]
feature_ids <- as.character(abundance_df[[feature_col]])
if(anyNA(feature_ids) || any(feature_ids == "")) {
  stop("Feature identifiers contain missing or empty values")
}
if(anyDuplicated(feature_ids)) {
  stop("Feature identifiers must be unique; duplicated identifiers found")
}

sample_ids <- names(abundance_df)[-1]
if(anyDuplicated(sample_ids)) {
  stop("Sample identifiers in abundance table must be unique")
}

abundance_numeric <- lapply(abundance_df[-1], function(values) {
  suppressWarnings(as.numeric(values))
})
invalid_numeric <- vapply(seq_along(abundance_numeric), function(index) {
  any(is.na(abundance_numeric[[index]]) & !is.na(abundance_df[-1][[index]]))
}, logical(1))
if(any(invalid_numeric)) {
  stop("Non-numeric abundance values found in sample columns: ",
       paste(sample_ids[invalid_numeric], collapse=", "))
}

abundance_matrix <- as.matrix(as.data.frame(abundance_numeric, check.names=FALSE))
storage.mode(abundance_matrix) <- "double"
rownames(abundance_matrix) <- feature_ids
colnames(abundance_matrix) <- sample_ids

if(any(!is.finite(abundance_matrix))) {
  stop("Abundance table contains non-finite values")
}
if(any(abundance_matrix < 0)) {
  stop("Abundance table contains negative values")
}

n_features_raw <- nrow(abundance_matrix)
cat(sprintf("[INFO] Loaded %d raw features across %d abundance samples\n",
            n_features_raw, ncol(abundance_matrix)))

# Filter features by prevalence and mean relative abundance
prevalence <- rowMeans(abundance_matrix > 0)
prevalence_keep <- prevalence >= opt$min_prevalence

sample_totals <- colSums(abundance_matrix)
if(any(sample_totals <= 0)) {
  zero_total_samples <- names(sample_totals)[sample_totals <= 0]
  stop("Samples with zero total abundance cannot be normalized: ",
       paste(zero_total_samples, collapse=", "))
}

relative_abundance <- sweep(abundance_matrix, 2, sample_totals, "/")
mean_relative_abundance <- rowMeans(relative_abundance)
abundance_keep <- mean_relative_abundance >= opt$min_rel_abund
feature_keep <- prevalence_keep & abundance_keep

filtered_matrix <- abundance_matrix[feature_keep, , drop=FALSE]
n_features_kept <- nrow(filtered_matrix)
n_features_dropped <- n_features_raw - n_features_kept

cat(sprintf("[INFO] Prevalence threshold %.6g retained %d features\n",
            opt$min_prevalence, sum(prevalence_keep)))
cat(sprintf("[INFO] Mean relative abundance threshold %.6g retained %d features\n",
            opt$min_rel_abund, sum(abundance_keep)))
cat(sprintf("[INFO] Combined filtering kept %d features and dropped %d features\n",
            n_features_kept, n_features_dropped))

if(n_features_kept < 2) {
  stop("CLR transform requires at least two features after filtering; retained: ",
       n_features_kept)
}

# Match and align metadata to abundance samples
metadata <- as.data.frame(
  readr::read_csv(opt$metadata, show_col_types=FALSE, progress=FALSE)
)
if(!"sample_id" %in% names(metadata)) {
  stop("Metadata must contain a sample_id column")
}
if(!opt$group %in% names(metadata)) {
  stop("Group column not found in metadata: ", opt$group)
}

metadata <- metadata %>%
  dplyr::mutate(sample_id=as.character(.data$sample_id))
if(anyDuplicated(metadata$sample_id)) {
  stop("Metadata sample_id values must be unique")
}

matched_samples <- sample_ids[sample_ids %in% metadata$sample_id]
if(length(matched_samples) == 0) {
  stop("No samples are shared between the abundance table and metadata")
}

meta_aligned <- metadata[match(matched_samples, metadata$sample_id), , drop=FALSE]
group_values <- meta_aligned[[opt$group]]
if(anyNA(group_values) || any(as.character(group_values) == "")) {
  stop("Matched samples contain missing or empty values in group column: ", opt$group)
}

# "case" is set as the positive class (2nd factor level) when present, so that
# downstream AUC direction and feature-effect signs consistently refer to the
# case/disease group rather than depending on alphabetical level ordering.
unique_groups <- unique(as.character(group_values))
if(length(unique_groups) != 2) {
  stop("Group column must have exactly 2 levels among matched samples; found: ",
       paste(unique_groups, collapse=", "))
}
if("case" %in% unique_groups) {
  neg_level <- setdiff(unique_groups, "case")
  label <- factor(group_values, levels=c(neg_level, "case"))
} else {
  label <- factor(group_values)
}
if(nlevels(label) != 2) {
  stop("Group column must have exactly 2 levels among matched samples; found: ",
       paste(levels(label), collapse=", "))
}

filtered_matrix <- filtered_matrix[, matched_samples, drop=FALSE]
rownames(meta_aligned) <- meta_aligned$sample_id
n_samples <- length(matched_samples)

cat(sprintf("[INFO] Matched %d samples between abundance and metadata\n", n_samples))
class_counts <- table(label)
cat(sprintf("[INFO] Class balance: %s\n",
            paste(sprintf("%s=%d", names(class_counts), as.integer(class_counts)),
                  collapse=", ")))

# CLR transform each sample composition; output samples as rows
sample_feature_matrix <- t(filtered_matrix)
clr_matrix <- as.matrix(compositions::clr(sample_feature_matrix + opt$pseudocount))
storage.mode(clr_matrix) <- "double"
rownames(clr_matrix) <- matched_samples
colnames(clr_matrix) <- rownames(filtered_matrix)

if(any(!is.finite(clr_matrix))) {
  stop("CLR transform produced non-finite values")
}

filter_stats <- list(
  n_features_raw=n_features_raw,
  n_features_kept=n_features_kept,
  n_samples=n_samples
)

processed <- list(
  features=clr_matrix,
  label=label,
  meta=as.data.frame(meta_aligned),
  dimension=opt$dimension,
  filter_stats=filter_stats
)

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)
rds_file <- file.path(opt$outdir, sprintf("processed_%s.rds", feature_label))
stats_file <- file.path(opt$outdir, sprintf("preprocess_stats_%s.csv", feature_label))

saveRDS(processed, rds_file)
readr::write_csv(tibble::as_tibble(filter_stats), stats_file)

cat(sprintf("[INFO] CLR matrix: %d samples x %d features; all values finite\n",
            nrow(clr_matrix), ncol(clr_matrix)))
cat(sprintf("[INFO] Saved processed data: %s\n", rds_file))
cat(sprintf("[INFO] Saved preprocessing statistics: %s\n", stats_file))
cat(sprintf("[INFO] Preprocessing completed successfully\n"))
