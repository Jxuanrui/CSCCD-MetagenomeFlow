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
  library(ggplot2)
})

# Optional PNG companion figures, only when MGX_FIGURE_FORMATS requests "png"
mgx_want_png <- function() {
  fmts <- tolower(trimws(strsplit(Sys.getenv("MGX_FIGURE_FORMATS", ""), ",")[[1]]))
  "png" %in% fmts && requireNamespace("ragg", quietly = TRUE)
}

option_list <- list(
  make_option(c("--humann3-dir"), dest="humann3_dir", type="character",
              help="HUMAnN3 output directory containing pathabundance/pathcoverage files"),
  make_option(c("-m", "--metadata-file"), dest="metadata_file", type="character",
              help="Metadata CSV/TSV containing sample identifiers"),
  make_option(c("-o", "--output-dir"), dest="output_dir", type="character",
              help="Output directory"),
  make_option(c("--min-coverage"), dest="min_coverage", type="double", default=0.5,
              help="Minimum coverage threshold separating medium and low completeness [default %default]"),
  make_option(c("--top-n-contributors"), dest="top_n_contributors", type="integer", default=5,
              help="Number of contributors retained per pathway [default %default]"),
  make_option(c("-d", "--dimension"), dest="dimension", type="character", default="bacteria",
              help="Data dimension; currently only bacteria is supported [default %default]")
)
opt <- parse_args(OptionParser(option_list=option_list))

required <- c("humann3_dir", "metadata_file", "output_dir")
missing <- required[vapply(opt[required], function(value) is.null(value) || !nzchar(value), logical(1))]
if(length(missing) > 0) stop("Missing required options: ", paste(missing, collapse=", "))
if(!dir.exists(opt$humann3_dir)) stop("HUMAnN3 directory not found: ", opt$humann3_dir)
if(!file.exists(opt$metadata_file)) stop("Metadata file not found: ", opt$metadata_file)
if(opt$dimension != "bacteria") stop("Pathway activity analysis currently supports only dimension=bacteria")
if(!is.finite(opt$min_coverage) || opt$min_coverage < 0 || opt$min_coverage > 1) {
  stop("--min-coverage must be between 0 and 1")
}
if(is.na(opt$top_n_contributors) || opt$top_n_contributors < 1) {
  stop("--top-n-contributors must be a positive integer")
}
dir.create(opt$output_dir, recursive=TRUE, showWarnings=FALSE)

has_data_table <- requireNamespace("data.table", quietly=TRUE)
read_table <- function(path) {
  if(has_data_table) {
    data.table::fread(path, sep="\t", header=TRUE, data.table=FALSE,
                      check.names=FALSE, quote="", comment.char="")
  } else {
    read.delim(path, sep="\t", header=TRUE, check.names=FALSE,
               quote="", comment.char="", stringsAsFactors=FALSE)
  }
}

read_metadata <- function(path) {
  first_line <- readLines(path, n=1, warn=FALSE)
  separator <- if(grepl("\t", first_line, fixed=TRUE)) "\t" else ","
  if(has_data_table) {
    data.table::fread(path, sep=separator, header=TRUE, data.table=FALSE, check.names=FALSE)
  } else {
    read.table(path, sep=separator, header=TRUE, check.names=FALSE,
               quote="\"", comment.char="", stringsAsFactors=FALSE)
  }
}

clean_sample_name <- function(path, value_column, suffix) {
  file_sample <- sub(paste0(suffix, "$"), "", basename(path))
  value_column <- sub("-RPKs$|-CPM$|-RELAB$", "", value_column, ignore.case=TRUE)
  value_column <- sub("_(Abundance|Coverage)$", "", value_column, ignore.case=TRUE)
  if(nzchar(file_sample)) return(file_sample)
  value_column
}

read_humann_file <- function(path, suffix) {
  dat <- read_table(path)
  if(ncol(dat) < 2) {
    warning("Skipping malformed HUMAnN file with fewer than two columns: ", path)
    return(NULL)
  }
  if(ncol(dat) > 2) {
    warning("HUMAnN file has multiple value columns; using the first: ", path)
  }
  feature <- trimws(as.character(dat[[1]]))
  value <- suppressWarnings(as.numeric(dat[[2]]))
  sample <- clean_sample_name(path, names(dat)[2], suffix)
  valid <- nzchar(feature) & !is.na(value) & !grepl("^UNMAPPED$|^UNINTEGRATED$", feature)
  data.frame(feature=feature[valid], sample=sample, value=value[valid],
             stringsAsFactors=FALSE)
}

bind_files <- function(files, suffix, label) {
  parsed <- lapply(files, function(path) {
    tryCatch(read_humann_file(path, suffix), error=function(error) {
      warning("Skipping unreadable ", label, " file ", path, ": ", conditionMessage(error))
      NULL
    })
  })
  parsed <- Filter(Negate(is.null), parsed)
  if(length(parsed) == 0) stop("No readable ", label, " files found in: ", opt$humann3_dir)
  do.call(rbind, parsed)
}

abundance_files <- list.files(opt$humann3_dir, pattern="_pathabundance(?:_relab)?\\.tsv$",
                              recursive=TRUE, full.names=TRUE)
abundance_files <- abundance_files[!grepl("[/\\\\](unstratified|stratified)[/\\\\]", abundance_files)]
raw_files <- abundance_files[!grepl("_pathabundance_relab\\.tsv$", abundance_files)]
if(length(raw_files) > 0) abundance_files <- raw_files
coverage_files <- list.files(opt$humann3_dir, pattern="_pathcoverage\\.tsv$",
                             recursive=TRUE, full.names=TRUE)
coverage_files <- coverage_files[!grepl("[/\\\\](unstratified|stratified)[/\\\\]", coverage_files)]
if(length(abundance_files) == 0) stop("No *_pathabundance.tsv files found in: ", opt$humann3_dir)
if(length(coverage_files) == 0) stop("No *_pathcoverage.tsv files found in: ", opt$humann3_dir)

metadata <- read_metadata(opt$metadata_file)
if(nrow(metadata) == 0 || ncol(metadata) == 0) stop("Metadata file is empty: ", opt$metadata_file)
sample_candidates <- c("sample_id", "SampleID", "sample", "Sample", "id", "ID")
sample_column <- sample_candidates[sample_candidates %in% names(metadata)][1]
if(is.na(sample_column)) sample_column <- names(metadata)[1]
metadata_samples <- unique(as.character(metadata[[sample_column]]))

cat(sprintf("[INFO] Reading %d pathabundance and %d pathcoverage files\n",
            length(abundance_files), length(coverage_files)))
abundance_long <- bind_files(abundance_files, "_pathabundance(?:_relab)?\\.tsv", "pathabundance")
coverage_long <- bind_files(coverage_files, "_pathcoverage\\.tsv", "pathcoverage")
analysis_samples <- intersect(unique(abundance_long$sample), unique(coverage_long$sample))
if(length(analysis_samples) == 0) stop("No samples have both pathabundance and pathcoverage data")
missing_metadata <- setdiff(analysis_samples, metadata_samples)
if(length(missing_metadata) > 0) {
  warning("Samples absent from metadata remain included in the unsupervised analysis: ",
          paste(missing_metadata, collapse=", "))
}
missing_abundance <- setdiff(unique(coverage_long$sample), unique(abundance_long$sample))
missing_coverage <- setdiff(unique(abundance_long$sample), unique(coverage_long$sample))
if(length(missing_abundance) > 0) warning("Skipping samples missing pathabundance: ", paste(missing_abundance, collapse=", "))
if(length(missing_coverage) > 0) warning("Skipping samples missing pathcoverage: ", paste(missing_coverage, collapse=", "))
abundance_long <- abundance_long[abundance_long$sample %in% analysis_samples, , drop=FALSE]
coverage_long <- coverage_long[coverage_long$sample %in% analysis_samples, , drop=FALSE]

unstratified_abundance <- abundance_long[!grepl("\\|", abundance_long$feature), , drop=FALSE]
unstratified_coverage <- coverage_long[!grepl("\\|", coverage_long$feature), , drop=FALSE]
if(nrow(unstratified_abundance) == 0) stop("No unstratified pathway abundance rows found")
if(nrow(unstratified_coverage) == 0) stop("No unstratified pathway coverage rows found")
names(unstratified_abundance)[names(unstratified_abundance) == "feature"] <- "pathway"
names(unstratified_coverage)[names(unstratified_coverage) == "feature"] <- "pathway"

mean_abundance <- aggregate(value ~ pathway, unstratified_abundance, mean, na.rm=TRUE)
names(mean_abundance)[2] <- "mean_abundance"
mean_coverage <- aggregate(value ~ pathway, unstratified_coverage, mean, na.rm=TRUE)
names(mean_coverage)[2] <- "mean_coverage"
completeness <- merge(mean_coverage, mean_abundance, by="pathway", all.x=TRUE)
completeness$mean_abundance[is.na(completeness$mean_abundance)] <- 0
completeness$category <- ifelse(completeness$mean_coverage >= 0.8, "high",
                                ifelse(completeness$mean_coverage >= opt$min_coverage, "medium", "low"))
completeness <- completeness[order(-completeness$mean_abundance, completeness$pathway),
                             c("pathway", "mean_coverage", "category", "mean_abundance")]

workdir <- normalizePath(file.path(opt$humann3_dir, "..", ".."), mustWork=FALSE)
diff_candidates <- unique(c(
  file.path(workdir, "temp", "04_differential", "bacteria", "pathway", "deseq2_results.tsv"),
  file.path(dirname(opt$humann3_dir), "04_differential", "bacteria", "pathway", "deseq2_results.tsv")
))
diff_file <- diff_candidates[file.exists(diff_candidates)][1]
if(!is.na(diff_file)) {
  diff_results <- tryCatch(read_table(diff_file), error=function(error) NULL)
  if(!is.null(diff_results) && nrow(diff_results) > 0) {
    feature_column <- intersect(c("pathway", "feature", "Feature", "ID"), names(diff_results))[1]
    padj_column <- intersect(c("padj", "qvalue", "FDR", "adj.P.Val"), names(diff_results))[1]
    if(!is.na(feature_column) && !is.na(padj_column)) {
      significant <- diff_results[!is.na(diff_results[[padj_column]]) & diff_results[[padj_column]] < 0.05, , drop=FALSE]
      completeness$significant_differential <- completeness$pathway %in% as.character(significant[[feature_column]])
      completeness$differential_padj <- diff_results[[padj_column]][match(completeness$pathway, diff_results[[feature_column]])]
      cat(sprintf("[INFO] Integrated %d significant differential pathways\n", nrow(significant)))
    } else {
      warning("Differential result lacks recognizable feature/padj columns; integration skipped")
    }
  }
} else {
  cat("[INFO] Differential pathway result not found; integration skipped\n")
}
write.csv(completeness, file.path(opt$output_dir, "pathway_completeness_summary.csv"), row.names=FALSE)

stratified <- abundance_long[grepl("\\|", abundance_long$feature), , drop=FALSE]
contributors <- data.frame(pathway=character(), species=character(), contribution_percentage=numeric(),
                           species_abundance=numeric(), stringsAsFactors=FALSE)
contributor_sample <- data.frame(pathway=character(), species=character(), sample=character(),
                                 species_abundance=numeric(), stringsAsFactors=FALSE)
if(nrow(stratified) > 0) {
  separator <- regexpr("\\|", stratified$feature)
  stratified$pathway <- substr(stratified$feature, 1, separator - 1)
  stratified$species <- substr(stratified$feature, separator + 1, nchar(stratified$feature))
  stratified$species <- sub("^g__", "", stratified$species)
  stratified$species <- gsub("_", " ", stratified$species, fixed=TRUE)
  stratified <- stratified[nzchar(stratified$pathway) & nzchar(stratified$species), , drop=FALSE]
  contributor_sample <- aggregate(value ~ pathway + species + sample, stratified, sum, na.rm=TRUE)
  names(contributor_sample)[4] <- "species_abundance"
  contributor_means <- aggregate(species_abundance ~ pathway + species, contributor_sample, mean, na.rm=TRUE)
  totals <- aggregate(value ~ pathway, unstratified_abundance, mean, na.rm=TRUE)
  names(totals)[2] <- "pathway_abundance"
  contributors <- merge(contributor_means, totals, by="pathway", all.x=TRUE)
  contributors$contribution_percentage <- ifelse(contributors$pathway_abundance > 0,
                                                  100 * contributors$species_abundance / contributors$pathway_abundance, NA_real_)
  contributors$contribution_percentage <- pmax(0, contributors$contribution_percentage)
  contributors <- contributors[order(contributors$pathway, -contributors$contribution_percentage,
                                     contributors$species), , drop=FALSE]
  contributors$rank <- ave(contributors$contribution_percentage, contributors$pathway,
                           FUN=function(values) seq_along(values))
  contributors <- contributors[contributors$rank <= opt$top_n_contributors,
                               c("pathway", "species", "contribution_percentage", "species_abundance")]
} else {
  warning("No stratified pathway|species rows found; contributor analysis will be empty")
}
write.csv(contributors, file.path(opt$output_dir, "pathway_contributors_top5.csv"), row.names=FALSE)

plot_message <- function(path, message, width=8, height=5) {
  grDevices::pdf(path, width=width, height=height)
  plot.new()
  text(0.5, 0.5, message, cex=1.1)
  grDevices::dev.off()
}

top20_pathways <- head(completeness$pathway[order(-completeness$mean_abundance)], 20)
heatmap_file <- file.path(opt$output_dir, "heatmap_pathway_species_contribution.pdf")
heatmap_data <- contributors[contributors$pathway %in% top20_pathways, , drop=FALSE]
if(nrow(heatmap_data) > 0) {
  heatmap_species <- unique(heatmap_data$species)
  heatmap_matrix <- matrix(0, nrow=length(top20_pathways), ncol=length(heatmap_species),
                           dimnames=list(top20_pathways, heatmap_species))
  for(row_index in seq_len(nrow(heatmap_data))) {
    heatmap_matrix[heatmap_data$pathway[row_index], heatmap_data$species[row_index]] <-
      heatmap_data$contribution_percentage[row_index]
  }
  heatmap_matrix <- heatmap_matrix[rowSums(heatmap_matrix) > 0, , drop=FALSE]
  heatmap_matrix <- heatmap_matrix[, colSums(heatmap_matrix) > 0, drop=FALSE]
  palette <- grDevices::colorRampPalette(c("#313695", "#74ADD1", "#FFFFBF", "#FDAE61", "#A50026"))(100)
  grDevices::pdf(heatmap_file, width=max(8, 0.32 * ncol(heatmap_matrix) + 4),
                 height=max(7, 0.28 * nrow(heatmap_matrix) + 3))
  if(requireNamespace("ComplexHeatmap", quietly=TRUE) && requireNamespace("circlize", quietly=TRUE)) {
    color_function <- circlize::colorRamp2(c(0, max(heatmap_matrix) / 2, max(heatmap_matrix)),
                                           c("#313695", "#FFFFBF", "#A50026"))
    ComplexHeatmap::draw(ComplexHeatmap::Heatmap(heatmap_matrix,
      name="Contribution (%)", col=color_function, cluster_rows=FALSE,
      row_names_gp=grid::gpar(fontsize=8), column_names_gp=grid::gpar(fontsize=7),
      column_names_rot=45, column_title="Contributing species", row_title="Pathway"))
  } else if(requireNamespace("pheatmap", quietly=TRUE)) {
    pheatmap::pheatmap(heatmap_matrix, color=palette, cluster_rows=FALSE,
                       border_color=NA, angle_col=45, fontsize_row=8, fontsize_col=7,
                       main="Pathway-Species Contribution (%)")
  } else {
    stats::heatmap(heatmap_matrix, Rowv=NA, Colv=NA, scale="none", col=palette,
                   margins=c(10, 12))
  }
  grDevices::dev.off()
} else {
  plot_message(heatmap_file, "No stratified pathway contributors available")
}

correlation_results <- data.frame(pathway=character(), main_contributor_species=character(),
                                  correlation=numeric(), pvalue=numeric(), stringsAsFactors=FALSE)
scatter_data <- data.frame()
if(nrow(contributors) > 0 && nrow(contributor_sample) > 0) {
  classified_contributors <- contributors[tolower(contributors$species) != "unclassified", , drop=FALSE]
  main_contributors <- classified_contributors[!duplicated(classified_contributors$pathway), c("pathway", "species")]
  pathways_without_classified <- setdiff(unique(contributors$pathway), main_contributors$pathway)
  if(length(pathways_without_classified) > 0) {
    fallback <- contributors[contributors$pathway %in% pathways_without_classified, , drop=FALSE]
    fallback <- fallback[!duplicated(fallback$pathway), c("pathway", "species")]
    main_contributors <- rbind(main_contributors, fallback)
  }
  main_contributors <- main_contributors[main_contributors$pathway %in% top20_pathways, , drop=FALSE]
  names(main_contributors)[2] <- "main_contributor_species"
  pathway_samples <- aggregate(value ~ pathway + sample, unstratified_abundance, sum, na.rm=TRUE)
  names(pathway_samples)[3] <- "pathway_abundance"
  correlation_rows <- vector("list", nrow(main_contributors))
  scatter_rows <- vector("list", nrow(main_contributors))
  for(row_index in seq_len(nrow(main_contributors))) {
    pathway_name <- main_contributors$pathway[row_index]
    species_name <- main_contributors$main_contributor_species[row_index]
    pathway_values <- pathway_samples[pathway_samples$pathway == pathway_name, c("sample", "pathway_abundance")]
    species_values <- contributor_sample[contributor_sample$pathway == pathway_name &
                                           contributor_sample$species == species_name,
                                         c("sample", "species_abundance")]
    joined <- merge(data.frame(sample=analysis_samples), pathway_values, by="sample", all.x=TRUE)
    joined <- merge(joined, species_values, by="sample", all.x=TRUE)
    joined$pathway_abundance[is.na(joined$pathway_abundance)] <- 0
    joined$species_abundance[is.na(joined$species_abundance)] <- 0
    valid_variation <- nrow(joined) >= 3 && length(unique(joined$pathway_abundance)) > 1 &&
      length(unique(joined$species_abundance)) > 1
    correlation_test <- if(valid_variation) {
      suppressWarnings(cor.test(joined$pathway_abundance, joined$species_abundance,
                                method="spearman", exact=FALSE))
    } else NULL
    correlation_value <- if(is.null(correlation_test)) NA_real_ else unname(correlation_test$estimate)
    pvalue <- if(is.null(correlation_test)) NA_real_ else correlation_test$p.value
    correlation_rows[[row_index]] <- data.frame(pathway=pathway_name,
      main_contributor_species=species_name, correlation=correlation_value, pvalue=pvalue)
    joined$pathway <- pathway_name
    joined$main_contributor_species <- species_name
    joined$correlation <- correlation_value
    scatter_rows[[row_index]] <- joined
  }
  correlation_results <- do.call(rbind, correlation_rows)
  scatter_data <- do.call(rbind, scatter_rows)
  pathway_order <- top20_pathways[top20_pathways %in% correlation_results$pathway]
  correlation_results <- correlation_results[match(pathway_order, correlation_results$pathway), , drop=FALSE]
}
write.csv(correlation_results,
          file.path(opt$output_dir, "pathway_activity_composition_correlation.csv"), row.names=FALSE)

scatter_file <- file.path(opt$output_dir, "scatter_activity_composition.pdf")
if(nrow(scatter_data) > 0) {
  label_data <- correlation_results
  label_data$label <- ifelse(is.na(label_data$correlation), "rho = NA",
                             sprintf("rho = %.2f", label_data$correlation))
  scatter_plot <- ggplot(scatter_data, aes(x=species_abundance, y=pathway_abundance)) +
    geom_point(color="#2C7BB6", alpha=0.72, size=1.8) +
    geom_smooth(method="lm", se=FALSE, color="#D7191C", linewidth=0.55) +
    facet_wrap(~ pathway, scales="free", ncol=4) +
    geom_text(data=label_data, aes(x=-Inf, y=Inf, label=label),
              inherit.aes=FALSE, hjust=-0.08, vjust=1.2, size=3) +
    labs(title="Pathway Activity vs Main Species Contribution",
         subtitle="Each point represents one sample; Spearman correlation shown per pathway",
         x="Main contributor stratified abundance", y="Total pathway abundance") +
    theme_bw(base_size=10) +
    theme(strip.text=element_text(size=8), panel.grid.minor=element_blank())
  ggsave(scatter_file, scatter_plot, width=13, height=max(7, 2.5 * ceiling(length(unique(scatter_data$pathway)) / 4)),
         device="pdf", limitsize=FALSE)
  if(mgx_want_png()) ggsave(sub("\\.pdf$", ".png", scatter_file), scatter_plot,
         width=13, height=max(7, 2.5 * ceiling(length(unique(scatter_data$pathway)) / 4)),
         device=ragg::agg_png, dpi=600, limitsize=FALSE)
} else {
  plot_message(scatter_file, "Insufficient stratified data for activity-composition correlations")
}

coverage_plot_data <- unstratified_coverage
coverage_plot_data$value <- pmin(1, pmax(0, coverage_plot_data$value))
coverage_plot <- ggplot(coverage_plot_data, aes(x=value)) +
  geom_histogram(breaks=seq(0, 1, by=0.1), boundary=0, closed="left",
                 fill="#4DBBD5", color="white", linewidth=0.35) +
  scale_x_continuous(breaks=seq(0, 1, by=0.1), limits=c(0, 1), expand=c(0, 0)) +
  labs(title="Distribution of HUMAnN3 Pathway Coverage", x="Pathway coverage", y="Pathway count") +
  theme_bw(base_size=11) + theme(panel.grid.minor=element_blank())
ggsave(file.path(opt$output_dir, "completeness_distribution.pdf"), coverage_plot,
       width=8, height=5.5, device="pdf")
if(mgx_want_png()) ggsave(file.path(opt$output_dir, "completeness_distribution.png"), coverage_plot,
       width=8, height=5.5, device=ragg::agg_png, dpi=600)

category_counts <- table(factor(completeness$category, levels=c("high", "medium", "low")))
anomaly_count <- sum(!is.na(correlation_results$correlation) & correlation_results$correlation < 0.3)
cat(sprintf("[INFO] Samples analyzed: %d\n", length(analysis_samples)))
cat(sprintf("[INFO] Pathways: %d; completeness high/medium/low: %d/%d/%d\n",
            nrow(completeness), category_counts[["high"]], category_counts[["medium"]], category_counts[["low"]]))
cat(sprintf("[INFO] Contributor rows retained: %d (top %d per pathway)\n",
            nrow(contributors), opt$top_n_contributors))
cat(sprintf("[INFO] Low-correlation pathways (rho < 0.3): %d\n", anomaly_count))

mean_completeness <- if(nrow(completeness) > 0) mean(completeness$mean_coverage, na.rm=TRUE) else NA_real_
summary_lines <- c(
  "Pathway Activity Analysis Summary",
  "==================================",
  paste("Dimension:", opt$dimension),
  paste("HUMAnN3 directory:", normalizePath(opt$humann3_dir, mustWork=FALSE)),
  paste("Metadata file:", normalizePath(opt$metadata_file, mustWork=FALSE)),
  paste("Samples analyzed:", length(analysis_samples)),
  paste("Pathways analyzed:", nrow(completeness)),
  paste("Mean pathway coverage:", ifelse(is.finite(mean_completeness), sprintf("%.4f", mean_completeness), "NA")),
  paste("High-completeness pathways (coverage >= 0.8):", category_counts[["high"]]),
  paste("Medium-completeness pathways:", category_counts[["medium"]]),
  paste("Low-completeness pathways (coverage <", opt$min_coverage, "):", category_counts[["low"]]),
  paste("Contributor rows retained (top", opt$top_n_contributors, "per pathway):", nrow(contributors)),
  paste("Low-correlation pathways (rho < 0.3):", anomaly_count),
  "Interpretation: high completeness pathways with low activity-composition correlation may indicate functional redundancy across species."
)
writeLines(summary_lines, file.path(opt$output_dir, "pathway_activity_summary.txt"))

cat("[INFO] Pathway activity analysis completed\n")
