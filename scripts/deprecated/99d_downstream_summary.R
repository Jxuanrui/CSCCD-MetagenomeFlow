# Deprecated 2026-07-16: superseded by the Snakemake downstream_summary aggregation rule.
#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
  library(gridExtra)
})

main <- function() {
option_list <- list(
  make_option(c("-w", "--workdir"), dest="workdir", type="character",
              help="Project WORKDIR containing result/stat"),
  make_option(c("-o", "--output-dir"), dest="output_dir", type="character", default=NULL,
              help="Output directory [default: {workdir}/result/stat/downstream_summary]"),
  make_option(c("-d", "--dimensions"), dest="dimensions", type="character",
              default="bacteria,fungi,virus",
              help="Comma-separated dimensions to include if present [default %default]")
)
opt <- parse_args(OptionParser(option_list=option_list))

if(is.null(opt$workdir) || !nzchar(opt$workdir)) stop("Missing required option: --workdir")
if(!dir.exists(opt$workdir)) stop("Workdir not found: ", opt$workdir)

dimensions <- unique(tolower(trimws(strsplit(opt$dimensions, ",", fixed=TRUE)[[1]])))
dimensions <- dimensions[nzchar(dimensions)]
if(length(dimensions) == 0) stop("--dimensions must contain at least one dimension")
invalid_dimensions <- setdiff(dimensions, c("bacteria", "fungi", "virus"))
if(length(invalid_dimensions) > 0) {
  stop("Unsupported dimensions: ", paste(invalid_dimensions, collapse=", "),
       ". Expected bacteria, fungi, or virus")
}

if(is.null(opt$output_dir) || !nzchar(opt$output_dir)) {
  opt$output_dir <- file.path(opt$workdir, "result", "stat", "downstream_summary")
}
dir.create(opt$output_dir, recursive=TRUE, showWarnings=FALSE)

read_summary_lines <- function(path) {
  readLines(path, warn=FALSE, encoding="UTF-8")
}

extract_summary_value <- function(lines, label) {
  escaped_label <- gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", label)
  pattern <- paste0("^\\s*", escaped_label, "\\s*:\\s*(.*?)\\s*$")
  matching_lines <- grep(pattern, lines, value=TRUE, perl=TRUE)
  if(length(matching_lines) == 0) return(NA_character_)
  sub(pattern, "\\1", matching_lines[1], perl=TRUE)
}

parse_number <- function(value) {
  if(length(value) == 0 || is.na(value) || !nzchar(value)) return(NA_real_)
  suppressWarnings(as.numeric(sub("%$", "", trimws(value))))
}

summary_rows <- list()

add_summary_row <- function(dimension, module, metric_1, value_1, metric_2, value_2) {
  summary_rows[[length(summary_rows) + 1]] <<- data.frame(
    dimension=dimension,
    module=module,
    key_metric_1=metric_1,
    key_metric_1_value=as.character(value_1),
    key_metric_2=metric_2,
    key_metric_2_value=as.character(value_2),
    stringsAsFactors=FALSE
  )
}

core_metrics <- list()
redundancy_metrics <- list()

for(dimension in dimensions) {
  dimension_stat_dir <- file.path(opt$workdir, "result", "stat", dimension)

  core_file <- file.path(dimension_stat_dir, "core_microbiome", "core_microbiome_summary.txt")
  if(file.exists(core_file)) {
    core_lines <- read_summary_lines(core_file)
    core_features <- parse_number(extract_summary_value(core_lines, "Global core features"))
    core_fraction <- parse_number(extract_summary_value(
      core_lines, "Global core total relative abundance percent"))
    add_summary_row(
      dimension, "Core Microbiome",
      "Global core features", ifelse(is.finite(core_features), format(core_features, scientific=FALSE), "NA"),
      "Global core abundance fraction (%)",
      ifelse(is.finite(core_fraction), sprintf("%.2f", core_fraction), "NA")
    )
    core_metrics[[dimension]] <- core_fraction
    cat(sprintf("[INFO] %s/core_microbiome found: %s\n", dimension, core_file))
  } else {
    cat(sprintf("[INFO] %s/core_microbiome skipped: summary file not found\n", dimension))
  }

  lefse_dir <- file.path(dimension_stat_dir, "lefse")
  lefse_files <- if(dir.exists(lefse_dir)) {
    sort(Sys.glob(file.path(lefse_dir, "*", "lefse_results.tsv")))
  } else {
    character()
  }
  if(length(lefse_files) > 0) {
    type_counts <- vapply(lefse_files, function(path) {
      results <- tryCatch(
        read.delim(path, header=TRUE, sep="\t", check.names=FALSE,
                   stringsAsFactors=FALSE, comment.char="", quote=""),
        error=function(error) {
          warning("Unable to read LEfSe results: ", path, " (", conditionMessage(error), ")")
          NULL
        }
      )
      if(is.null(results)) return(NA_integer_)
      if(!"feature" %in% colnames(results)) {
        warning("LEfSe results missing feature column: ", path)
      }
      nrow(results)
    }, integer(1))
    type_names <- basename(dirname(lefse_files))
    valid_counts <- type_counts[!is.na(type_counts)]
    total_biomarkers <- if(length(valid_counts) > 0) sum(valid_counts) else NA_integer_
    type_listing <- paste(sprintf("%s=%s", type_names,
                                  ifelse(is.na(type_counts), "NA", type_counts)), collapse="; ")
    add_summary_row(
      dimension, "LEfSe",
      "Total biomarkers", ifelse(is.na(total_biomarkers), "NA", total_biomarkers),
      "Biomarkers by type", type_listing
    )
    for(index in seq_along(lefse_files)) {
      cat(sprintf("[INFO] %s/lefse found: %s (%s biomarkers)\n",
                  dimension, lefse_files[index],
                  ifelse(is.na(type_counts[index]), "NA", type_counts[index])))
    }
  } else {
    cat(sprintf("[INFO] %s/lefse skipped: no lefse_results.tsv files found\n", dimension))
  }

  redundancy_file <- file.path(
    dimension_stat_dir, "functional_redundancy", "functional_redundancy_summary.txt")
  if(file.exists(redundancy_file)) {
    redundancy_lines <- read_summary_lines(redundancy_file)
    mean_fdi <- parse_number(extract_summary_value(redundancy_lines, "Mean FDI"))
    keystone_functions <- parse_number(extract_summary_value(
      redundancy_lines, "Keystone functions (FDI < 2 and ML rank < 50)"))
    add_summary_row(
      dimension, "Functional Redundancy",
      "Mean FDI", ifelse(is.finite(mean_fdi), sprintf("%.4f", mean_fdi), "NA"),
      "Keystone functions",
      ifelse(is.finite(keystone_functions), format(keystone_functions, scientific=FALSE), "NA")
    )
    redundancy_metrics[[dimension]] <- mean_fdi
    cat(sprintf("[INFO] %s/functional_redundancy found: %s\n", dimension, redundancy_file))
  } else {
    cat(sprintf("[INFO] %s/functional_redundancy skipped: summary file not found\n", dimension))
  }

  if(dimension == "bacteria") {
    pathway_file <- file.path(
      dimension_stat_dir, "pathway_activity", "pathway_activity_summary.txt")
    if(file.exists(pathway_file)) {
      pathway_lines <- read_summary_lines(pathway_file)
      pathways_analyzed <- parse_number(extract_summary_value(pathway_lines, "Pathways analyzed"))
      mean_coverage <- parse_number(extract_summary_value(pathway_lines, "Mean pathway coverage"))
      high_completeness <- parse_number(extract_summary_value(
        pathway_lines, "High-completeness pathways (coverage >= 0.8)"))
      add_summary_row(
        dimension, "Pathway Activity",
        "Pathways analyzed / high completeness",
        sprintf("%s / %s",
                ifelse(is.finite(pathways_analyzed), format(pathways_analyzed, scientific=FALSE), "NA"),
                ifelse(is.finite(high_completeness), format(high_completeness, scientific=FALSE), "NA")),
        "Mean pathway coverage",
        ifelse(is.finite(mean_coverage), sprintf("%.4f", mean_coverage), "NA")
      )
      cat(sprintf("[INFO] %s/pathway_activity found: %s\n", dimension, pathway_file))
    } else {
      cat(sprintf("[INFO] %s/pathway_activity skipped: summary file not found\n", dimension))
    }
  } else {
    cat(sprintf("[INFO] %s/pathway_activity skipped: bacteria-only module\n", dimension))
  }
}

summary_table <- if(length(summary_rows) > 0) {
  do.call(rbind, summary_rows)
} else {
  data.frame(
    dimension=character(), module=character(), key_metric_1=character(),
    key_metric_1_value=character(), key_metric_2=character(),
    key_metric_2_value=character(), stringsAsFactors=FALSE
  )
}

summary_csv <- file.path(opt$output_dir, "downstream_summary_table.csv")
write.csv(summary_table, summary_csv, row.names=FALSE, na="")
cat(sprintf("[INFO] Summary table written: %s (%d rows)\n", summary_csv, nrow(summary_table)))

common_dimensions <- intersect(names(core_metrics), names(redundancy_metrics))
if(length(common_dimensions) > 0) {
  comparison_data <- data.frame(
    dimension=common_dimensions,
    core_abundance_fraction=vapply(core_metrics[common_dimensions], identity, numeric(1)),
    mean_fdi=vapply(redundancy_metrics[common_dimensions], identity, numeric(1)),
    stringsAsFactors=FALSE
  )
  comparison_data <- comparison_data[
    is.finite(comparison_data$core_abundance_fraction) & is.finite(comparison_data$mean_fdi),
    , drop=FALSE]
} else {
  comparison_data <- data.frame(
    dimension=character(), core_abundance_fraction=numeric(), mean_fdi=numeric(),
    stringsAsFactors=FALSE)
}

if(nrow(comparison_data) >= 2) {
  comparison_plot <- ggplot(
    comparison_data, aes(x=core_abundance_fraction, y=mean_fdi, label=dimension)) +
    geom_point(size=3.6, color="#2C7BB6") +
    geom_text(vjust=-0.8, size=3.5, color="#333333") +
    scale_x_continuous(labels=function(values) paste0(values, "%"),
                       expand=expansion(mult=c(0.08, 0.12))) +
    scale_y_continuous(expand=expansion(mult=c(0.08, 0.16))) +
    labs(title="Cross-Module Comparison",
         x="Global core abundance fraction", y="Mean FDI") +
    theme_bw(base_size=11) +
    theme(plot.title=element_text(face="bold", hjust=0.5),
          panel.grid.minor=element_blank())
} else {
  comparison_plot <- ggplot() +
    annotate("text", x=0.5, y=0.5,
             label="Insufficient data for cross-module comparison", size=4.2) +
    xlim(0, 1) + ylim(0, 1) +
    labs(title="Cross-Module Comparison") +
    theme_void(base_size=11) +
    theme(plot.title=element_text(face="bold", hjust=0.5),
          panel.border=element_rect(color="#BDBDBD", fill=NA, linewidth=0.5))
}

if(nrow(summary_table) > 0) {
  display_table <- summary_table
  colnames(display_table) <- c("Dimension", "Module", "Metric 1", "Value 1", "Metric 2", "Value 2")
  table_theme <- gridExtra::ttheme_minimal(
    base_size=7.5,
    core=list(fg_params=list(hjust=0, x=0.03),
              bg_params=list(fill=rep(c("#FFFFFF", "#F2F6FA"), length.out=nrow(display_table)))),
    colhead=list(fg_params=list(fontface="bold", col="white"),
                 bg_params=list(fill="#3C5488"))
  )
  table_panel <- gridExtra::tableGrob(display_table, rows=NULL, theme=table_theme)
} else {
  table_panel <- gridExtra::arrangeGrob(
    grid::textGrob("No downstream module outputs were found",
                   gp=grid::gpar(fontsize=12, col="#555555")))
}

report_grob <- gridExtra::arrangeGrob(
  table_panel, comparison_plot,
  ncol=1, heights=c(2.2, 1),
  top=grid::textGrob("Downstream Analysis Summary",
                     gp=grid::gpar(fontsize=16, fontface="bold", col="#333333"))
)
report_pdf <- file.path(opt$output_dir, "downstream_analysis_summary.pdf")
grDevices::pdf(report_pdf, width=11, height=8.5, onefile=TRUE)
grid::grid.newpage()
grid::grid.draw(report_grob)
grDevices::dev.off()
cat(sprintf("[INFO] Summary PDF written: %s\n", report_pdf))
cat(sprintf("[INFO] Downstream summary report completed: %s\n", opt$output_dir))
}

if(sys.nframe() == 0) main()
