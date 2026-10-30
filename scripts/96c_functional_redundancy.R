#!/usr/bin/env Rscript

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
      normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

suppressPackageStartupMessages({
  library(optparse)
  library(vegan)
  library(ggplot2)
})

# Optional PNG companion figures, only when MGX_FIGURE_FORMATS requests "png"
mgx_want_png <- function() {
  fmts <- tolower(trimws(strsplit(Sys.getenv("MGX_FIGURE_FORMATS", ""), ",")[[1]]))
  "png" %in% fmts && requireNamespace("ragg", quietly = TRUE)
}

option_list <- list(
  make_option(c("-f", "--functional-file"), dest="functional_file", type="character",
              help="Functional abundance TSV (features in rows, samples in columns)"),
  make_option(c("-t", "--taxonomy-file"), dest="taxonomy_file", type="character",
              help="Taxonomy abundance TSV (species in rows, samples in columns)"),
  make_option(c("-o", "--output-dir"), dest="output_dir", type="character",
              help="Output directory"),
  make_option(c("-d", "--dimension"), dest="dimension", type="character", default="bacteria",
              help="Dimension: bacteria, fungi, or virus [default %default]"),
  make_option(c("-y", "--type"), dest="functional_type", type="character", default="kegg_ko",
              help="Functional type, e.g. kegg_ko, arg, or vog [default %default]"),
  make_option(c("--ml-importance"), dest="ml_importance", type="character", default=NULL,
              help="Optional ML SHAP importance CSV")
)
opt <- parse_args(OptionParser(option_list=option_list))

required <- c("functional_file", "taxonomy_file", "output_dir")
missing <- required[vapply(opt[required], function(value) is.null(value) || !nzchar(value), logical(1))]
if(length(missing) > 0) stop("Missing required options: ", paste(missing, collapse=", "))
if(!file.exists(opt$functional_file)) stop("Functional file not found: ", opt$functional_file)
if(!file.exists(opt$taxonomy_file)) stop("Taxonomy file not found: ", opt$taxonomy_file)
opt$dimension <- tolower(opt$dimension)
if(!opt$dimension %in% c("bacteria", "fungi", "virus")) {
  stop("--dimension must be one of: bacteria, fungi, virus")
}
dir.create(opt$output_dir, recursive=TRUE, showWarnings=FALSE)

has_data_table <- requireNamespace("data.table", quietly=TRUE)
read_delimited <- function(path) {
  # Skip comment lines (starting with #)
  all_lines <- readLines(path, warn=FALSE)
  data_lines <- all_lines[!grepl("^#", all_lines)]
  if(length(data_lines) == 0) stop("File contains only comment lines: ", path)

  first_line <- data_lines[1]
  separator <- if(grepl("\t", first_line, fixed=TRUE)) "\t" else ","
  quote_character <- if(separator == ",") "\"" else ""

  # Write cleaned data to temp connection
  tmp <- textConnection(data_lines)
  on.exit(close(tmp), add=TRUE)

  if(has_data_table) {
    data.table::fread(text=paste(data_lines, collapse="\n"), sep=separator, header=TRUE,
                      data.table=FALSE, check.names=FALSE, quote=quote_character, fill=TRUE)
  } else {
    read.table(tmp, sep=separator, header=TRUE, check.names=FALSE, quote=quote_character,
               comment.char="", stringsAsFactors=FALSE, fill=TRUE)
  }
}

read_abundance <- function(path, label) {
  dat <- read_delimited(path)
  if(ncol(dat) < 3) stop(label, " table must contain an identifier and at least two samples: ", path)
  identifiers <- trimws(as.character(dat[[1]]))
  values <- as.data.frame(lapply(dat[-1], function(column) suppressWarnings(as.numeric(column))),
                          check.names=FALSE)
  rownames(values) <- make.unique(ifelse(nzchar(identifiers), identifiers, paste0(label, "_", seq_along(identifiers))))
  values <- as.matrix(values)
  storage.mode(values) <- "double"
  values[!is.finite(values)] <- NA_real_
  if(all(is.na(values))) stop(label, " table has no numeric abundance values: ", path)
  values[is.na(values)] <- 0
  duplicate_samples <- duplicated(colnames(values))
  if(any(duplicate_samples)) {
    warning(label, " table contains duplicate sample columns; keeping first occurrence")
    values <- values[, !duplicate_samples, drop=FALSE]
  }
  values
}

clean_species <- function(value) {
  value <- sub("^.*\\|", "", value)
  value <- sub("^[sg]__", "", value, ignore.case=TRUE)
  value <- gsub("[._]", " ", value)
  trimws(value)
}

split_stratified_id <- function(identifier) {
  if(!grepl("\\|", identifier)) return(c(function_id=identifier, species=NA_character_))
  parts <- strsplit(identifier, "\\|", fixed=FALSE)[[1]]
  c(function_id=parts[1], species=clean_species(parts[length(parts)]))
}

shannon_effective <- function(values) {
  values <- values[is.finite(values) & values > 0]
  if(length(values) == 0 || sum(values) <= 0) return(NA_real_)
  exp(vegan::diversity(values / sum(values), index="shannon"))
}

shannon_diversity <- function(values) {
  values <- values[is.finite(values) & values > 0]
  if(length(values) == 0 || sum(values) <= 0) return(NA_real_)
  vegan::diversity(values / sum(values), index="shannon")
}

functional_raw <- read_abundance(opt$functional_file, "functional")
taxonomy <- read_abundance(opt$taxonomy_file, "taxonomy")
common_samples <- intersect(colnames(functional_raw), colnames(taxonomy))
if(length(common_samples) < 3) {
  stop("Functional and taxonomy tables need at least three matching sample columns; found ",
       length(common_samples))
}
functional_raw <- functional_raw[, common_samples, drop=FALSE]
taxonomy <- taxonomy[, common_samples, drop=FALSE]

parsed_ids <- t(vapply(rownames(functional_raw), split_stratified_id, character(2)))
has_stratified <- any(!is.na(parsed_ids[, "species"]) & nzchar(parsed_ids[, "species"]))
if(has_stratified) {
  unstratified_rows <- is.na(parsed_ids[, "species"]) | !nzchar(parsed_ids[, "species"])
  if(any(unstratified_rows)) {
    functional <- functional_raw[unstratified_rows, , drop=FALSE]
    rownames(functional) <- parsed_ids[unstratified_rows, "function_id"]
  } else {
    function_ids <- unique(parsed_ids[, "function_id"])
    functional <- t(vapply(function_ids, function(function_id) {
      colSums(functional_raw[parsed_ids[, "function_id"] == function_id, , drop=FALSE])
    }, numeric(ncol(functional_raw))))
    colnames(functional) <- colnames(functional_raw)
    rownames(functional) <- function_ids
  }
} else {
  functional <- functional_raw
}

aggregate_rows <- function(matrix_data) {
  if(!anyDuplicated(rownames(matrix_data))) return(matrix_data)
  rowsum(matrix_data, group=rownames(matrix_data), reorder=FALSE, na.rm=TRUE)
}
functional <- aggregate_rows(functional)
taxonomy <- aggregate_rows(taxonomy)
rownames(taxonomy) <- make.unique(vapply(rownames(taxonomy), clean_species, character(1)))
functional <- functional[rowSums(functional, na.rm=TRUE) > 0, , drop=FALSE]
taxonomy <- taxonomy[rowSums(taxonomy, na.rm=TRUE) > 0, , drop=FALSE]
if(nrow(functional) == 0) stop("No non-zero functional features remain after filtering")
if(nrow(taxonomy) == 0) stop("No non-zero taxonomy features remain after filtering")

# Vectorized Spearman correlation + p-value (avoids O(nrow(functional)*nrow(taxonomy)) cor.test calls).
# Spearman rho == Pearson correlation of rank-transformed rows; p-value uses the same
# t-distribution approximation stats::cor.test(..., exact=FALSE) uses internally.
n_samples <- ncol(functional)
function_ranks <- t(apply(functional, 1, rank, ties.method="average"))
taxonomy_ranks <- t(apply(taxonomy, 1, rank, ties.method="average"))
rownames(function_ranks) <- rownames(functional)
rownames(taxonomy_ranks) <- rownames(taxonomy)

correlation <- stats::cor(t(function_ranks), t(taxonomy_ranks))
dimnames(correlation) <- list(rownames(functional), rownames(taxonomy))

constant_function <- apply(function_ranks, 1, stats::sd) == 0
constant_species <- apply(taxonomy_ranks, 1, stats::sd) == 0
correlation[constant_function, ] <- NA_real_
correlation[, constant_species] <- NA_real_

df <- n_samples - 2
t_stat <- correlation * sqrt(df / (1 - correlation^2))
pvalue <- matrix(2 * stats::pt(-abs(t_stat), df=df), nrow=nrow(correlation), ncol=ncol(correlation),
                 dimnames=dimnames(correlation))
pvalue[!is.finite(t_stat) & is.finite(correlation)] <- 0
max_abs_correlation <- apply(abs(correlation), 1, function(values) {
  if(all(!is.finite(values))) NA_real_ else max(values, na.rm=TRUE)
})

contribution <- matrix(0, nrow=nrow(functional), ncol=nrow(taxonomy),
                       dimnames=list(rownames(functional), rownames(taxonomy)))
method <- "correlation_inference"
if(has_stratified) {
  method <- "stratified_abundance"
  stratified_rows <- !is.na(parsed_ids[, "species"]) & nzchar(parsed_ids[, "species"])
  stratified <- functional_raw[stratified_rows, , drop=FALSE]
  stratified_functions <- parsed_ids[stratified_rows, "function_id"]
  stratified_species <- parsed_ids[stratified_rows, "species"]
  mean_abundance <- rowMeans(stratified, na.rm=TRUE)
  for(row_index in seq_along(mean_abundance)) {
    function_id <- stratified_functions[row_index]
    species_id <- stratified_species[row_index]
    if(!function_id %in% rownames(contribution)) next
    if(!species_id %in% colnames(contribution)) {
      contribution <- cbind(contribution, setNames(rep(0, nrow(contribution)), species_id))
    }
    contribution[function_id, species_id] <- contribution[function_id, species_id] + mean_abundance[row_index]
  }
} else {
  species_mean <- rowMeans(taxonomy, na.rm=TRUE)
  significant_positive <- is.finite(correlation) & is.finite(pvalue) & correlation > 0.3 & pvalue < 0.05
  contribution[significant_positive] <- correlation[significant_positive] *
    rep(species_mean, each=nrow(functional))[significant_positive]
}

contribution_proportion <- contribution
for(function_index in seq_len(nrow(contribution))) {
  total <- sum(contribution[function_index, ], na.rm=TRUE)
  if(is.finite(total) && total > 0) contribution_proportion[function_index, ] <- contribution[function_index, ] / total
}

valid_contribution_functions <- rowSums(contribution, na.rm=TRUE) > 0
fallback_used <- !any(valid_contribution_functions)
if(fallback_used) {
  method <- "cv_proxy"
  function_mean <- rowMeans(functional, na.rm=TRUE)
  function_sd <- apply(functional, 1, stats::sd, na.rm=TRUE)
  cv <- ifelse(function_mean > 0, function_sd / function_mean, NA_real_)
  inverse_cv <- 1 / (1 + cv)
  finite_inverse <- inverse_cv[is.finite(inverse_cv)]
  if(length(finite_inverse) > 1 && diff(range(finite_inverse)) > 0) {
    scaled <- (inverse_cv - min(finite_inverse)) / diff(range(finite_inverse))
  } else {
    scaled <- ifelse(is.finite(inverse_cv), 0.5, NA_real_)
  }
  proxy_upper <- max(2, min(nrow(taxonomy), 20))
  fdi_values <- 1 + scaled * (proxy_upper - 1)
} else {
  fdi_values <- apply(contribution, 1, shannon_effective)
}

fdi_rows <- lapply(seq_len(nrow(functional)), function(function_index) {
  weights <- contribution_proportion[function_index, ]
  contributors <- which(is.finite(weights) & weights > 0)
  if(length(contributors) > 0) {
    top_index <- contributors[which.max(weights[contributors])]
    top_species <- colnames(contribution_proportion)[top_index]
    top_percentage <- 100 * weights[top_index]
  } else {
    top_species <- NA_character_
    top_percentage <- NA_real_
  }
  data.frame("function"=rownames(functional)[function_index], fdi=fdi_values[function_index],
             n_contributors=if(fallback_used) NA_integer_ else length(contributors),
             top_contributor_species=top_species,
             top_contributor_percentage=top_percentage, stringsAsFactors=FALSE,
             check.names=FALSE)
})
fdi_table <- do.call(rbind, fdi_rows)
fdi_table <- fdi_table[is.finite(fdi_table$fdi), , drop=FALSE]
fdi_table <- fdi_table[order(fdi_table$fdi, fdi_table[["function"]]), , drop=FALSE]
write.csv(fdi_table, file.path(opt$output_dir, "function_dispersion_index.csv"), row.names=FALSE, na="")

sfd_rows <- lapply(seq_len(ncol(contribution)), function(species_index) {
  weights <- contribution[, species_index]
  functions <- which(is.finite(weights) & weights > 0)
  top_function <- if(length(functions) > 0) rownames(contribution)[functions[which.max(weights[functions])]] else NA_character_
  data.frame(species=colnames(contribution)[species_index],
             sfd=if(length(functions) > 0) shannon_diversity(weights[functions]) else NA_real_,
             n_functions_contributed=length(functions), top_function=top_function,
             stringsAsFactors=FALSE)
})
sfd_table <- do.call(rbind, sfd_rows)
sfd_table <- sfd_table[order(-sfd_table$sfd, -sfd_table$n_functions_contributed, sfd_table$species,
                             na.last=TRUE), , drop=FALSE]
write.csv(sfd_table, file.path(opt$output_dir, "species_functional_diversity.csv"), row.names=FALSE, na="")

scatter_data <- merge(fdi_table[, c("function", "fdi")],
                      data.frame("function"=names(max_abs_correlation),
                                 max_abs_correlation=as.numeric(max_abs_correlation),
                                 stringsAsFactors=FALSE, check.names=FALSE), by="function")
scatter_data <- scatter_data[is.finite(scatter_data$fdi) & is.finite(scatter_data$max_abs_correlation), , drop=FALSE]
relationship <- NULL
if(nrow(scatter_data) >= 3 && length(unique(scatter_data$fdi)) > 1 &&
   length(unique(scatter_data$max_abs_correlation)) > 1) {
  relationship <- suppressWarnings(stats::cor.test(scatter_data$fdi,
                                                     scatter_data$max_abs_correlation,
                                                     method="spearman", exact=FALSE))
}
relationship_label <- if(is.null(relationship)) {
  "Spearman rho = NA"
} else {
  sprintf("Spearman rho = %.3f, p = %.3g", unname(relationship$estimate), relationship$p.value)
}
scatter_file <- file.path(opt$output_dir, "redundancy_correlation_scatter.pdf")
if(nrow(scatter_data) > 0) {
  plot <- ggplot(scatter_data, aes(x=fdi, y=max_abs_correlation)) +
    geom_point(alpha=0.65, color="#2C7FB8", size=1.8) +
    geom_smooth(method="lm", formula=y ~ x, se=TRUE, color="#D7301F", linewidth=0.8) +
    annotate("text", x=Inf, y=Inf, label=relationship_label, hjust=1.05, vjust=1.5, size=3.7) +
    labs(title="Functional Redundancy vs. Species-Function Correlation",
         subtitle=paste(opt$dimension, opt$functional_type, sep=" / "),
         x="Function Dispersion Index (effective contributor species)",
         y="Maximum absolute species-function Spearman correlation") +
    theme_bw(base_size=11)
  ggsave(scatter_file, plot, width=8, height=6)
  if(mgx_want_png()) ggsave(sub("\\.pdf$", ".png", scatter_file), plot,
         width=8, height=6, device=ragg::agg_png, dpi=600)
} else {
  grDevices::pdf(scatter_file, width=8, height=6)
  plot.new(); text(0.5, 0.5, "Insufficient data for redundancy-correlation scatter plot")
  grDevices::dev.off()
}

read_ml_importance <- function(path) {
  dat <- read_delimited(path)
  lowered <- tolower(names(dat))
  function_candidates <- c("function", "feature", "feature_name", "variable", "ko", "ko_id", "vog", "id")
  function_column <- which(lowered %in% function_candidates)[1]
  if(is.na(function_column)) function_column <- 1
  rank_candidates <- c("ml_rank", "rank", "importance_rank", "shap_rank")
  rank_column <- which(lowered %in% rank_candidates)[1]
  importance_candidates <- c("importance", "mean_abs_shap", "mean_absolute_shap", "shap_importance", "mean_shap")
  importance_column <- which(lowered %in% importance_candidates)[1]
  result <- data.frame("function"=as.character(dat[[function_column]]), stringsAsFactors=FALSE,
                       check.names=FALSE)
  if(!is.na(rank_column)) {
    result$ml_rank <- suppressWarnings(as.numeric(dat[[rank_column]]))
  } else if(!is.na(importance_column)) {
    importance <- suppressWarnings(as.numeric(dat[[importance_column]]))
    result$ml_rank <- rank(-importance, ties.method="min", na.last="keep")
  } else {
    numeric_columns <- which(vapply(dat, is.numeric, logical(1)))
    numeric_columns <- setdiff(numeric_columns, function_column)
    if(length(numeric_columns) == 0) stop("ML importance file has no rank or numeric importance column")
    importance <- suppressWarnings(as.numeric(dat[[numeric_columns[1]]]))
    result$ml_rank <- rank(-importance, ties.method="min", na.last="keep")
  }
  result[!duplicated(result[["function"]]), , drop=FALSE]
}

keystone <- data.frame("function"=character(), fdi=numeric(), ml_rank=numeric(),
                       key_species=character(), species_contribution_percentage=numeric(),
                       stringsAsFactors=FALSE, check.names=FALSE)
ml_status <- "not provided"
if(!is.null(opt$ml_importance) && nzchar(opt$ml_importance)) {
  if(file.exists(opt$ml_importance)) {
    ml_status <- "loaded"
    ml <- read_ml_importance(opt$ml_importance)
    candidates <- merge(fdi_table[fdi_table$fdi < 2, ], ml, by="function")
    message("ML importance matched ", nrow(candidates), " low-redundancy functions")
    candidates <- candidates[is.finite(candidates$ml_rank) & candidates$ml_rank < 50, , drop=FALSE]
    if(nrow(candidates) > 0) {
      keystone <- data.frame("function"=candidates[["function"]], fdi=candidates$fdi,
                             ml_rank=candidates$ml_rank,
                             key_species=candidates$top_contributor_species,
                             species_contribution_percentage=candidates$top_contributor_percentage,
                             stringsAsFactors=FALSE, check.names=FALSE)
      keystone <- keystone[order(keystone$ml_rank, keystone$fdi), , drop=FALSE]
    }
  } else {
    ml_status <- paste("missing:", opt$ml_importance)
    warning("ML importance file not found; keystone identification skipped: ", opt$ml_importance)
  }
}
write.csv(keystone, file.path(opt$output_dir, "keystone_functions.csv"), row.names=FALSE, na="")

heatmap_file <- file.path(opt$output_dir, "redundancy_heatmap.pdf")
heatmap_functions <- head(fdi_table[["function"]], 30)
heatmap_matrix <- 100 * contribution_proportion[intersect(heatmap_functions, rownames(contribution_proportion)), , drop=FALSE]
heatmap_matrix <- heatmap_matrix[rowSums(heatmap_matrix, na.rm=TRUE) > 0, , drop=FALSE]
if(nrow(heatmap_matrix) > 0) {
  species_order <- order(colSums(heatmap_matrix, na.rm=TRUE), decreasing=TRUE)
  heatmap_matrix <- heatmap_matrix[, species_order, drop=FALSE]
  heatmap_matrix <- heatmap_matrix[, colSums(heatmap_matrix, na.rm=TRUE) > 0, drop=FALSE]
  row_annotation <- data.frame(FDI=fdi_table$fdi[match(rownames(heatmap_matrix), fdi_table[["function"]])])
  rownames(row_annotation) <- rownames(heatmap_matrix)
  palette <- grDevices::colorRampPalette(c("#FFFFCC", "#FED976", "#FD8D3C", "#E31A1C", "#800026"))(100)
  draw_heatmap <- function() {
    if(requireNamespace("pheatmap", quietly=TRUE)) {
      pheatmap::pheatmap(heatmap_matrix, color=palette, cluster_rows=FALSE,
                         cluster_cols=FALSE, border_color=NA, angle_col=45,
                         annotation_row=row_annotation, fontsize_row=8, fontsize_col=7,
                         main="Function-Species Contribution (%)")
    } else {
      graphics::heatmap(heatmap_matrix, Rowv=NA, Colv=NA, scale="none", col=palette,
                        margins=c(10, 12), main="Function-Species Contribution (%)")
    }
  }
  heatmap_w <- max(9, 0.25 * ncol(heatmap_matrix) + 5)
  heatmap_h <- max(7, 0.25 * nrow(heatmap_matrix) + 3)
  grDevices::pdf(heatmap_file, width=heatmap_w, height=heatmap_h)
  draw_heatmap()
  grDevices::dev.off()
  if (mgx_want_png()) {
    ragg::agg_png(sub("\\.pdf$", ".png", heatmap_file), width=heatmap_w, height=heatmap_h, units="in", res=600)
    draw_heatmap()
    grDevices::dev.off()
  }
} else {
  grDevices::pdf(heatmap_file, width=9, height=7)
  plot.new(); text(0.5, 0.5, "No contributor matrix available (CV proxy mode)")
  grDevices::dev.off()
  if (mgx_want_png()) {
    ragg::agg_png(sub("\\.pdf$", ".png", heatmap_file), width=9, height=7, units="in", res=600)
    plot.new(); text(0.5, 0.5, "No contributor matrix available (CV proxy mode)")
    grDevices::dev.off()
  }
}

mean_fdi <- if(nrow(fdi_table) > 0) mean(fdi_table$fdi, na.rm=TRUE) else NA_real_
low_redundancy <- sum(fdi_table$fdi < 2, na.rm=TRUE)
high_redundancy <- sum(fdi_table$fdi >= 3, na.rm=TRUE)
rho <- if(is.null(relationship)) NA_real_ else unname(relationship$estimate)
rho_p <- if(is.null(relationship)) NA_real_ else relationship$p.value
hypothesis <- if(is.finite(rho) && rho < 0 && is.finite(rho_p) && rho_p < 0.05) {
  "Supported: FDI is significantly negatively associated with maximum species-function correlation."
} else if(is.finite(rho) && rho < 0) {
  "Directionally supported, but the negative association is not statistically significant."
} else {
  "Not supported by this dataset; no negative redundancy-correlation association was detected."
}
summary_lines <- c(
  "Functional Redundancy Analysis Summary",
  "======================================",
  paste("Dimension:", opt$dimension),
  paste("Functional type:", opt$functional_type),
  paste("Functional file:", normalizePath(opt$functional_file, mustWork=FALSE)),
  paste("Taxonomy file:", normalizePath(opt$taxonomy_file, mustWork=FALSE)),
  paste("Common samples:", length(common_samples)),
  paste("Functions analyzed:", nrow(fdi_table)),
  paste("Species analyzed:", nrow(taxonomy)),
  paste("Contribution method:", method),
  paste("Mean FDI:", ifelse(is.finite(mean_fdi), sprintf("%.4f", mean_fdi), "NA")),
  paste("Low-redundancy functions (FDI < 2):", low_redundancy),
  paste("High-redundancy functions (FDI >= 3):", high_redundancy),
  paste("Keystone functions (FDI < 2 and ML rank < 50):", nrow(keystone)),
  paste("ML importance status:", ml_status),
  paste("FDI vs max|correlation| Spearman rho:", ifelse(is.finite(rho), sprintf("%.4f", rho), "NA")),
  paste("FDI vs max|correlation| p-value:", ifelse(is.finite(rho_p), format(rho_p, digits=5), "NA")),
  paste("Network-zero-edge hypothesis:", hypothesis),
  if(fallback_used) "Caution: No significant positive contributors were found; FDI uses an inverse-CV proxy and contributor/SFD fields are unavailable." else
    "Interpretation: FDI is the exponential Shannon diversity of inferred or stratified contributor proportions."
)
writeLines(summary_lines, file.path(opt$output_dir, "functional_redundancy_summary.txt"))
message("Functional redundancy analysis completed: ", opt$output_dir)
message("Mean FDI: ", ifelse(is.finite(mean_fdi), sprintf("%.4f", mean_fdi), "NA"),
        "; rho: ", ifelse(is.finite(rho), sprintf("%.4f", rho), "NA"),
        "; keystone functions: ", nrow(keystone))
