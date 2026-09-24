#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
  library(MASS)
})

# Optional PNG companion figures, only when MGX_FIGURE_FORMATS requests "png"
mgx_want_png <- function() {
  fmts <- tolower(trimws(strsplit(Sys.getenv("MGX_FIGURE_FORMATS", ""), ",")[[1]]))
  "png" %in% fmts && requireNamespace("ragg", quietly = TRUE)
}

option_list <- list(
  make_option(c("-i", "--abundance-file"), dest="abundance_file", type="character",
              help="Feature-by-sample TSV"),
  make_option(c("-m", "--metadata-file"), dest="metadata_file", type="character",
              help="Metadata CSV containing sample_id and group"),
  make_option(c("-o", "--output-dir"), dest="output_dir", type="character",
              help="Output directory"),
  make_option(c("--lda-threshold"), dest="lda_threshold", type="double", default=2.0),
  make_option(c("--wilcoxon-alpha"), dest="wilcoxon_alpha", type="double", default=0.05),
  make_option(c("--min-prevalence"), dest="min_prevalence", type="double", default=0.1),
  make_option(c("-d", "--dimension"), dest="dimension", type="character"),
  make_option(c("-y", "--type"), dest="type", type="character")
)
opt <- parse_args(OptionParser(option_list=option_list))

required <- c("abundance_file", "metadata_file", "output_dir", "dimension", "type")
missing <- required[vapply(opt[required], function(value) is.null(value) || !nzchar(value), logical(1))]
if(length(missing) > 0) stop("Missing required arguments: ", paste(missing, collapse=", "))
if(opt$lda_threshold < 0) stop("--lda-threshold must be non-negative")
if(opt$wilcoxon_alpha <= 0 || opt$wilcoxon_alpha > 1) stop("--wilcoxon-alpha must be in (0, 1]")
if(opt$min_prevalence < 0 || opt$min_prevalence > 1) stop("--min-prevalence must be in [0, 1]")

dir.create(opt$output_dir, recursive=TRUE, showWarnings=FALSE)

read_abundance <- function(path) {
  table <- read.delim(path, header=TRUE, sep="\t", check.names=FALSE,
                      stringsAsFactors=FALSE, comment.char="#", quote="")
  if(ncol(table) < 3) stop("Abundance table must contain one feature column and at least two samples")
  features <- as.character(table[[1]])
  if(anyNA(features) || any(!nzchar(features))) stop("Abundance table contains empty feature names")
  if(anyDuplicated(features)) {
    warning("Duplicate feature names detected; summing duplicate rows")
  }
  values <- as.data.frame(lapply(table[-1], function(column) suppressWarnings(as.numeric(column))),
                          check.names=FALSE)
  if(any(!is.finite(as.matrix(values)))) stop("Abundance table contains non-numeric or non-finite values")
  if(any(as.matrix(values) < 0)) stop("Abundance table contains negative values")
  rowsum(as.matrix(values), group=features, reorder=FALSE)
}

read_metadata <- function(path) {
  metadata <- read.csv(path, header=TRUE, check.names=FALSE, stringsAsFactors=FALSE)
  required_columns <- c("sample_id", "group")
  missing_columns <- setdiff(required_columns, colnames(metadata))
  if(length(missing_columns) > 0) stop("Metadata missing columns: ", paste(missing_columns, collapse=", "))
  metadata$sample_id <- as.character(metadata$sample_id)
  metadata$group <- as.character(metadata$group)
  metadata <- metadata[nzchar(metadata$sample_id) & nzchar(metadata$group), , drop=FALSE]
  if(anyDuplicated(metadata$sample_id)) stop("Metadata contains duplicate sample_id values")
  metadata
}

abundance <- read_abundance(opt$abundance_file)
metadata <- read_metadata(opt$metadata_file)
common_samples <- intersect(colnames(abundance), metadata$sample_id)
if(length(common_samples) < 4) stop("At least four common samples are required")
metadata <- metadata[match(common_samples, metadata$sample_id), , drop=FALSE]
abundance <- abundance[, common_samples, drop=FALSE]
group <- factor(metadata$group)
if(nlevels(group) < 2) stop("Metadata group must contain at least two levels")
if(any(table(group) < 2)) stop("Each group must contain at least two samples")

prevalence <- rowMeans(abundance > 0)
abundance <- abundance[prevalence >= opt$min_prevalence, , drop=FALSE]
if(nrow(abundance) == 0) stop("No features remain after prevalence filtering")

column_sums <- colSums(abundance)
if(any(column_sums <= 0)) stop("At least one sample has zero total abundance after filtering")
relative_abundance <- sweep(abundance, 2, column_sums, "/")

cat(sprintf("[INFO] %d features x %d samples across %d groups\n",
            nrow(relative_abundance), ncol(relative_abundance), nlevels(group)))

safe_kruskal <- function(values) {
  if(length(unique(values)) < 2) return(1)
  tryCatch(kruskal.test(values ~ group)$p.value, error=function(error) 1)
}

safe_wilcoxon <- function(values) {
  if(nlevels(group) != 2 || length(unique(values)) < 2) return(NA_real_)
  tryCatch(wilcox.test(values ~ group, exact=FALSE)$p.value, error=function(error) NA_real_)
}

lda_effect <- function(values) {
  data <- data.frame(abundance=as.numeric(values), group=group)
  fit <- tryCatch(MASS::lda(group ~ abundance, data=data), error=function(error) NULL)
  if(!is.null(fit) && length(fit$scaling) > 0 && is.finite(fit$scaling[1])) {
    group_means <- tapply(values, group, mean)
    separation <- diff(range(group_means * fit$scaling[1]))
    score <- log10(max(abs(separation) * 1e4, 1))
    if(is.finite(score)) return(c(score=score, fallback=0))
  }
  group_means <- tapply(values, group, mean)
  positive <- relative_abundance[relative_abundance > 0]
  pseudocount <- if(length(positive) > 0) min(positive) / 2 else 1e-12
  fold_change <- max(group_means + pseudocount) / min(group_means + pseudocount)
  c(score=log10(max(fold_change, 1)), fallback=1)
}

kw_pvalue <- apply(relative_abundance, 1, safe_kruskal)
wilcoxon_pvalue <- apply(relative_abundance, 1, safe_wilcoxon)
effects <- t(apply(relative_abundance, 1, lda_effect))
group_means <- vapply(seq_len(nrow(relative_abundance)), function(index) {
  means <- tapply(relative_abundance[index, ], group, mean)
  names(means)[which.max(means)]
}, character(1))

levels_group <- levels(group)
case_group <- if("case" %in% levels_group) "case" else levels_group[min(2, length(levels_group))]
control_group <- if("control" %in% levels_group) "control" else levels_group[1]
mean_for_group <- function(group_name) {
  if(!group_name %in% levels_group) return(rep(NA_real_, nrow(relative_abundance)))
  rowMeans(relative_abundance[, group == group_name, drop=FALSE])
}

all_results <- data.frame(
  feature=rownames(relative_abundance),
  lda_score=as.numeric(effects[, "score"]),
  pvalue=as.numeric(kw_pvalue),
  enriched_group=group_means,
  mean_abundance_case=mean_for_group(case_group),
  mean_abundance_control=mean_for_group(control_group),
  wilcoxon_pvalue=as.numeric(wilcoxon_pvalue),
  wilcoxon_validated=if(nlevels(group) == 2) !is.na(wilcoxon_pvalue) & wilcoxon_pvalue < opt$wilcoxon_alpha else NA,
  lda_fallback=as.logical(effects[, "fallback"]),
  dimension=opt$dimension,
  type=opt$type,
  stringsAsFactors=FALSE
)

results <- all_results[all_results$pvalue < 0.05 & all_results$lda_score >= opt$lda_threshold, , drop=FALSE]
results <- results[order(results$lda_score, decreasing=TRUE), , drop=FALSE]
write.table(results, file.path(opt$output_dir, "lefse_results.tsv"), sep="\t", quote=FALSE,
            row.names=FALSE, na="NA")

short_feature <- function(feature) {
  parts <- strsplit(feature, "\\|", fixed=FALSE)[[1]]
  label <- tail(parts, 1)
  label <- sub("^[a-z]__", "", label)
  label <- gsub("_", " ", label, fixed=TRUE)
  if(nchar(label) > 55) paste0(substr(label, 1, 52), "...") else label
}

plot_data <- head(results, 20)
if(nrow(plot_data) == 0) {
  plot_data <- head(all_results[order(all_results$lda_score, decreasing=TRUE), , drop=FALSE], 20)
  plot_subtitle <- "No features passed both Kruskal-Wallis P < 0.05 and the LDA threshold"
} else {
  plot_subtitle <- sprintf("Kruskal-Wallis P < 0.05; LDA score >= %.2f", opt$lda_threshold)
}
plot_data$feature_label <- vapply(plot_data$feature, short_feature, character(1))
plot_data$feature_label <- factor(plot_data$feature_label, levels=rev(unique(plot_data$feature_label)))
group_palette <- setNames(rep(c("#C6295C", "#2C6DB2", "#E69F00", "#009E73", "#7A5195"),
                              length.out=nlevels(group)), levels(group))

barplot <- ggplot(plot_data, aes(x=lda_score, y=feature_label, fill=enriched_group)) +
  geom_col(width=0.72, alpha=0.9) +
  geom_vline(xintercept=opt$lda_threshold, linetype="dashed", color="grey40", linewidth=0.45) +
  scale_fill_manual(values=group_palette, drop=FALSE) +
  labs(title=sprintf("LEfSe Biomarkers: %s %s", opt$dimension, opt$type),
       subtitle=plot_subtitle, x="LDA score (log10)", y=NULL, fill="Enriched group") +
  theme_classic(base_size=11) +
  theme(plot.title=element_text(face="bold", size=13, hjust=0.5),
        plot.subtitle=element_text(size=9, color="grey30", hjust=0.5),
        axis.text=element_text(color="black"), axis.text.y=element_text(size=8.5),
        axis.title.x=element_text(face="bold"), legend.position="right",
        legend.title=element_text(face="bold"), plot.margin=margin(8, 12, 8, 8))
ggsave(file.path(opt$output_dir, "lefse_barplot.pdf"), barplot, width=9, height=7,
       device=cairo_pdf, limitsize=FALSE)
if(mgx_want_png()) {
  ggsave(file.path(opt$output_dir, "lefse_barplot.png"), barplot, width=9, height=7,
         device=ragg::agg_png, dpi=600, limitsize=FALSE)
}

if(tolower(opt$type) == "taxonomy" && any(grepl("\\|", all_results$feature))) {
  taxonomy_results <- results
  if(nrow(taxonomy_results) == 0) taxonomy_results <- head(all_results[order(all_results$lda_score, decreasing=TRUE), ], 20)
  extract_rank <- function(feature, prefix) {
    parts <- strsplit(feature, "\\|", fixed=FALSE)[[1]]
    hit <- parts[startsWith(parts, prefix)]
    if(length(hit) == 0) "Unclassified" else gsub("_", " ", sub(paste0("^", prefix), "", hit[1]), fixed=TRUE)
  }
  taxonomy_results$phylum <- vapply(taxonomy_results$feature, extract_rank, character(1), prefix="p__")
  taxonomy_results$class <- vapply(taxonomy_results$feature, extract_rank, character(1), prefix="c__")
  taxonomy_results$order <- vapply(taxonomy_results$feature, extract_rank, character(1), prefix="o__")
  taxonomy_results$label <- paste(taxonomy_results$phylum, taxonomy_results$class,
                                  taxonomy_results$order, sep=" | ")
  taxonomy_results <- head(taxonomy_results[order(taxonomy_results$lda_score, decreasing=TRUE), ], 25)
  taxonomy_results$label <- factor(taxonomy_results$label, levels=rev(unique(taxonomy_results$label)))
  cladogram <- ggplot(taxonomy_results, aes(x=lda_score, y=label, color=enriched_group,
                                            size=lda_score)) +
    geom_segment(aes(x=0, xend=lda_score, y=label, yend=label), inherit.aes=FALSE,
                 color="grey82", linewidth=0.7) +
    geom_point(alpha=0.9) +
    scale_color_manual(values=group_palette, drop=FALSE) +
    scale_size_continuous(range=c(2.5, 7)) +
    labs(title="Simplified Taxonomic Cladogram", subtitle="Phylum | Class | Order hierarchy",
         x="LDA score (log10)", y=NULL, color="Enriched group", size="LDA score") +
    theme_classic(base_size=10) +
    theme(plot.title=element_text(face="bold", hjust=0.5),
          plot.subtitle=element_text(hjust=0.5, color="grey35"),
          axis.text.y=element_text(size=7.5, color="black"), legend.position="right")
  ggsave(file.path(opt$output_dir, "cladogram.pdf"), cladogram, width=10, height=8,
         device=cairo_pdf, limitsize=FALSE)
  if(mgx_want_png()) {
    ggsave(file.path(opt$output_dir, "cladogram.png"), cladogram, width=10, height=8,
           device=ragg::agg_png, dpi=600, limitsize=FALSE)
  }
}

cat(sprintf("[INFO] %d biomarkers passed KW P < 0.05 and LDA >= %.2f\n",
            nrow(results), opt$lda_threshold))
cat(sprintf("[INFO] Results written to %s\n", opt$output_dir))
