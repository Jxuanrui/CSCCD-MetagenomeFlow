# Deprecated 2026-07-16: superseded by 96_functional_integrated.R due to directory-convention duplication.
#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
})

option_list <- list(
  make_option(c("-w", "--workdir"), type = "character",
              help = "Project working directory"),
  make_option(c("-d", "--dimension"), type = "character",
              help = "Dimension: bacteria/fungi/virus"),
  make_option(c("-t", "--type"), type = "character",
              help = "Functional table type, e.g. arg or kegg_ko")
)
opt <- parse_args(OptionParser(option_list = option_list))

required <- c("workdir", "dimension", "type")
missing <- required[vapply(opt[required], is.null, logical(1))]
if (length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse = ", "))
}

plot_library <- file.path("scripts", "R", "plot_differential.R")
if (!file.exists(plot_library)) {
  stop("Run this script from the repository root; plotting library not found: ",
       plot_library)
}
source(plot_library)

output_dir <- file.path(
  opt$workdir, "result", "stat", opt$dimension,
  "functional_differential", opt$type
)
if (!dir.exists(output_dir)) {
  stop("Functional differential directory not found: ", output_dir)
}

method_specs <- list(
  deseq2 = list(
    label = "DESeq2",
    path = file.path(output_dir, "deseq2_results.tsv"),
    effect = c("log2FoldChange"),
    adjusted_p = c("padj")
  ),
  maaslin2 = list(
    label = "MaAsLin2",
    path = file.path(output_dir, "maaslin2_results", "results.tsv"),
    effect = c("coef", "log2FoldChange"),
    adjusted_p = c("qval", "padj")
  ),
  wilcoxon = list(
    label = "Wilcoxon",
    path = file.path(output_dir, "wilcoxon_results.tsv"),
    effect = c("mean_diff", "log2FoldChange"),
    adjusted_p = c("padj")
  )
)

first_column <- function(data, candidates, description) {
  column <- candidates[candidates %in% colnames(data)][1]
  if (is.na(column)) {
    stop("Missing ", description, " column; expected one of: ",
         paste(candidates, collapse = ", "))
  }
  column
}

standardize_result <- function(path, effect_candidates, adjusted_p_candidates) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    stop("Result file missing or empty: ", path)
  }

  data <- read.delim(
    path, check.names = FALSE, stringsAsFactors = FALSE,
    quote = "", comment.char = ""
  )
  if (nrow(data) == 0) {
    stop("Result table has no rows: ", path)
  }

  feature_column <- first_column(
    data, c("feature", "name", "taxon", "id"), "feature"
  )
  effect_column <- first_column(data, effect_candidates, "effect size")
  adjusted_p_column <- first_column(
    data, adjusted_p_candidates, "adjusted p-value"
  )

  standardized <- data.frame(
    feature = as.character(data[[feature_column]]),
    log2FoldChange = suppressWarnings(as.numeric(data[[effect_column]])),
    padj = suppressWarnings(as.numeric(data[[adjusted_p_column]])),
    stringsAsFactors = FALSE
  )
  standardized <- standardized[
    !is.na(standardized$feature) & standardized$feature != "" &
      is.finite(standardized$log2FoldChange) &
      is.finite(standardized$padj),
    , drop = FALSE
  ]
  if (nrow(standardized) == 0) {
    stop("No finite plottable rows in: ", path)
  }

  standardized$padj <- pmin(pmax(standardized$padj, .Machine$double.xmin), 1)
  standardized$sig <- standardized$padj < 0.05 &
    abs(standardized$log2FoldChange) > 1
  standardized
}

save_plot <- function(plot, path, width, height) {
  ggsave(
    filename = path, plot = plot, device = "pdf",
    width = width, height = height, units = "in", limitsize = FALSE
  )
  if (!file.exists(path) || file.info(path)$size == 0) {
    stop("Plot was not created successfully: ", path)
  }
}

cat(sprintf("[INFO] Visualizing %s/%s\n", opt$dimension, opt$type))
for (method_key in names(method_specs)) {
  spec <- method_specs[[method_key]]
  cat(sprintf("[INFO] Reading %s: %s\n", spec$label, spec$path))
  result <- standardize_result(spec$path, spec$effect, spec$adjusted_p)

  title <- sprintf("%s %s %s", spec$label, opt$dimension, opt$type)
  volcano <- plot_volcano_nature(
    result, method = title, fdr = 0.05, lfc = 1, top_n = 10
  )
  barplot <- plot_barplot_enhanced(result, method = title, top_n = 20)

  volcano_path <- file.path(
    output_dir,
    sprintf("volcano_%s_%s_%s.pdf", method_key, opt$dimension, opt$type)
  )
  barplot_path <- file.path(
    output_dir,
    sprintf("barplot_%s_%s_%s.pdf", method_key, opt$dimension, opt$type)
  )

  save_plot(volcano, volcano_path, width = 8, height = 6)
  save_plot(barplot, barplot_path, width = 8, height = 7)
  cat(sprintf("[INFO] Created %s plots (%d rows, %d significant)\n",
              spec$label, nrow(result), sum(result$sig)))
}

cat(sprintf("[INFO] Completed visualization for %s/%s\n",
            opt$dimension, opt$type))
