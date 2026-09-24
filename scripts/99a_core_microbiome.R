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
  make_option(c("-i", "--abundance-file"), dest="abundance_file", type="character",
              help="Feature-by-sample abundance TSV"),
  make_option(c("-m", "--metadata-file"), dest="metadata_file", type="character",
              help="Metadata CSV containing sample_id and optionally group"),
  make_option(c("-o", "--output-dir"), dest="output_dir", type="character",
              help="Output directory"),
  make_option(c("--prevalence-threshold"), dest="prevalence_threshold", type="double",
              default=0.5, help="Core prevalence threshold [default %default]"),
  make_option(c("--min-abundance"), dest="min_abundance", type="double",
              default=0.0001, help="Values below this abundance become zero [default %default]"),
  make_option(c("-d", "--dimension"), dest="dimension", type="character",
              help="Data dimension: bacteria, fungi, or virus")
)
opt <- parse_args(OptionParser(option_list=option_list))

required <- c("abundance_file", "metadata_file", "output_dir", "dimension")
missing <- required[vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) stop("Missing required arguments: ", paste(missing, collapse=", "))
if(!file.exists(opt$abundance_file)) stop("Abundance file not found: ", opt$abundance_file)
if(!file.exists(opt$metadata_file)) stop("Metadata file not found: ", opt$metadata_file)
if(!opt$dimension %in% c("bacteria", "fungi", "virus")) {
  stop("Dimension must be bacteria, fungi, or virus: ", opt$dimension)
}
if(!is.finite(opt$prevalence_threshold) || opt$prevalence_threshold <= 0 ||
   opt$prevalence_threshold > 1) {
  stop("prevalence-threshold must be in (0, 1]")
}
if(!is.finite(opt$min_abundance) || opt$min_abundance < 0) {
  stop("min-abundance must be a non-negative number")
}

dir.create(opt$output_dir, recursive=TRUE, showWarnings=FALSE)

read_abundance <- function(path) {
  table <- read.delim(path, header=TRUE, check.names=FALSE, comment.char="#",
                      quote="", stringsAsFactors=FALSE)
  if(ncol(table) < 2) stop("Abundance table must contain a feature column and sample columns")
  features <- as.character(table[[1]])
  if(anyNA(features) || any(features == "")) stop("Abundance table contains empty feature names")
  if(anyDuplicated(features)) {
    warning("Duplicate feature names detected; summing duplicate rows")
  }
  values <- table[-1]
  numeric_values <- lapply(values, function(column) suppressWarnings(as.numeric(column)))
  abundance <- as.matrix(as.data.frame(numeric_values, check.names=FALSE))
  rownames(abundance) <- features
  if(any(!is.finite(abundance))) stop("Abundance table contains non-numeric or non-finite values")
  if(any(abundance < 0)) stop("Abundance table contains negative values")
  if(anyDuplicated(rownames(abundance))) {
    abundance <- rowsum(abundance, group=rownames(abundance), reorder=FALSE)
  }
  abundance
}

empty_core_table <- function() {
  data.frame(feature=character(), prevalence=double(), mean_abundance=double(),
             median_abundance=double(), stringsAsFactors=FALSE)
}

core_statistics <- function(abundance, threshold) {
  if(ncol(abundance) == 0) return(empty_core_table())
  prevalence <- rowMeans(abundance > 0)
  result <- data.frame(
    feature=rownames(abundance),
    prevalence=as.numeric(prevalence),
    mean_abundance=rowMeans(abundance),
    median_abundance=apply(abundance, 1, median),
    stringsAsFactors=FALSE
  )
  result <- result[result$prevalence >= threshold, , drop=FALSE]
  result[order(-result$prevalence, -result$mean_abundance, result$feature), , drop=FALSE]
}

find_effective_threshold <- function(abundance, requested_threshold) {
  threshold <- requested_threshold
  result <- core_statistics(abundance, threshold)
  while(nrow(result) == 0 && threshold > 0.1) {
    threshold <- max(0.1, round(threshold - 0.1, 10))
    result <- core_statistics(abundance, threshold)
  }
  if(threshold < requested_threshold) {
    warning(sprintf(
      "No global core features at prevalence %.2f; lowered threshold to %.2f",
      requested_threshold, threshold
    ))
  }
  list(threshold=threshold, result=result)
}

write_core_csv <- function(result, filename) {
  write.csv(result, file.path(opt$output_dir, filename), row.names=FALSE, quote=TRUE)
}

abundance <- read_abundance(opt$abundance_file)
metadata <- read.csv(opt$metadata_file, header=TRUE, check.names=FALSE,
                     stringsAsFactors=FALSE)
if(!"sample_id" %in% colnames(metadata)) stop("Metadata must contain a sample_id column")
if(anyDuplicated(metadata$sample_id)) stop("Metadata sample_id values must be unique")

common_samples <- intersect(colnames(abundance), metadata$sample_id)
if(length(common_samples) == 0) stop("No common samples between abundance table and metadata")
if(length(common_samples) < ncol(abundance)) {
  warning(sprintf("Using %d of %d abundance samples present in metadata",
                  length(common_samples), ncol(abundance)))
}
abundance <- abundance[, common_samples, drop=FALSE]
metadata <- metadata[match(common_samples, metadata$sample_id), , drop=FALSE]
abundance[abundance < opt$min_abundance] <- 0

global_fit <- find_effective_threshold(abundance, opt$prevalence_threshold)
effective_threshold <- global_fit$threshold
global_core <- global_fit$result
global_features <- global_core$feature

cat(sprintf("[INFO] %s: %d features x %d samples\n",
            opt$dimension, nrow(abundance), ncol(abundance)))
cat(sprintf("[INFO] Effective prevalence threshold: %.2f\n", effective_threshold))
cat(sprintf("[INFO] Global core features: %d\n", nrow(global_core)))

group_available <- "group" %in% colnames(metadata)
case_samples <- character()
control_samples <- character()
case_core <- empty_core_table()
control_core <- empty_core_table()

if(!group_available) {
  warning("Metadata has no group column; skipping grouped core analysis")
} else {
  group_values <- tolower(trimws(as.character(metadata$group)))
  nonempty_groups <- unique(group_values[!is.na(group_values) & group_values != ""])
  if(length(nonempty_groups) < 2) {
    warning("Metadata contains only one non-empty group; grouped comparisons may be incomplete")
  }
  case_samples <- metadata$sample_id[group_values == "case"]
  control_samples <- metadata$sample_id[group_values == "control"]
  if(length(case_samples) == 0) warning("No samples labeled 'case'; case core table will be empty")
  if(length(control_samples) == 0) warning("No samples labeled 'control'; control core table will be empty")
  if(length(case_samples) > 0) {
    case_core <- core_statistics(abundance[, case_samples, drop=FALSE], effective_threshold)
  }
  if(length(control_samples) > 0) {
    control_core <- core_statistics(abundance[, control_samples, drop=FALSE], effective_threshold)
  }
}

write_core_csv(global_core, "core_microbiome_global.csv")
write_core_csv(case_core, "core_microbiome_case.csv")
write_core_csv(control_core, "core_microbiome_control.csv")

case_features <- case_core$feature
control_features <- control_core$feature
shared_features <- intersect(case_features, control_features)
case_specific <- setdiff(case_features, control_features)
control_specific <- setdiff(control_features, case_features)

total_abundance <- sum(abundance)
global_core_abundance <- if(length(global_features) > 0) sum(abundance[global_features, , drop=FALSE]) else 0
global_core_fraction <- if(total_abundance > 0) global_core_abundance / total_abundance else 0

summary_lines <- c(
  "Core Microbiome Identification Summary",
  "======================================",
  sprintf("Dimension: %s", opt$dimension),
  sprintf("Features analyzed: %d", nrow(abundance)),
  sprintf("Samples analyzed: %d", ncol(abundance)),
  sprintf("Requested prevalence threshold: %.4f", opt$prevalence_threshold),
  sprintf("Effective prevalence threshold: %.4f", effective_threshold),
  sprintf("Minimum abundance: %.8g", opt$min_abundance),
  "",
  sprintf("Global core features: %d", length(global_features)),
  sprintf("Global core total relative abundance fraction: %.6f", global_core_fraction),
  sprintf("Global core total relative abundance percent: %.2f%%", 100 * global_core_fraction),
  "",
  sprintf("Grouped analysis available: %s", if(group_available) "yes" else "no"),
  sprintf("Case samples: %d", length(case_samples)),
  sprintf("Case core features: %d", length(case_features)),
  sprintf("Case-specific core features: %d", length(case_specific)),
  sprintf("Control samples: %d", length(control_samples)),
  sprintf("Control core features: %d", length(control_features)),
  sprintf("Control-specific core features: %d", length(control_specific)),
  sprintf("Shared case/control core features: %d", length(shared_features)),
  sprintf("Venn partition check: %d + %d + %d = %d unique grouped core features",
          length(case_specific), length(shared_features), length(control_specific),
          length(union(case_features, control_features)))
)
writeLines(summary_lines, file.path(opt$output_dir, "core_microbiome_summary.txt"))

thresholds <- seq(0.1, 0.9, by=0.1)
curve_rows <- list(data.frame(
  threshold=thresholds,
  core_count=vapply(thresholds, function(value) sum(rowMeans(abundance > 0) >= value), integer(1)),
  scope="Global"
))
if(length(case_samples) > 0) {
  case_abundance <- abundance[, case_samples, drop=FALSE]
  curve_rows[[length(curve_rows) + 1]] <- data.frame(
    threshold=thresholds,
    core_count=vapply(thresholds, function(value) sum(rowMeans(case_abundance > 0) >= value), integer(1)),
    scope="Case"
  )
}
if(length(control_samples) > 0) {
  control_abundance <- abundance[, control_samples, drop=FALSE]
  curve_rows[[length(curve_rows) + 1]] <- data.frame(
    threshold=thresholds,
    core_count=vapply(thresholds, function(value) sum(rowMeans(control_abundance > 0) >= value), integer(1)),
    scope="Control"
  )
}
curve_data <- do.call(rbind, curve_rows)
curve_data$scope <- factor(curve_data$scope, levels=c("Global", "Case", "Control"))
curve_plot <- ggplot(curve_data, aes(x=threshold, y=core_count, color=scope)) +
  geom_line(linewidth=1) +
  geom_point(size=2) +
  scale_x_continuous(breaks=thresholds, limits=c(0.1, 0.9)) +
  scale_color_manual(values=c(Global="#2C7BB6", Case="#D7191C", Control="#1A9641"), drop=FALSE) +
  labs(title=paste("Core Microbiome Prevalence Curve -", tools::toTitleCase(opt$dimension)),
       x="Prevalence threshold", y="Number of core features", color=NULL) +
  theme_bw(base_size=11) +
  theme(legend.position="top", panel.grid.minor=element_blank())
ggsave(file.path(opt$output_dir, "prevalence_curve.pdf"), curve_plot,
       width=7.5, height=5.5, device="pdf")
if(mgx_want_png()) ggsave(file.path(opt$output_dir, "prevalence_curve.png"), curve_plot,
       width=7.5, height=5.5, device=ragg::agg_png, dpi=600)

venn_data <- data.frame(
  x=c(-0.72, 0, 0.72), y=c(0, 0, 0),
  label=c(length(case_specific), length(shared_features), length(control_specific))
)
circle_points <- function(center_x, color, set_name) {
  angle <- seq(0, 2 * pi, length.out=361)
  data.frame(x=center_x + cos(angle), y=sin(angle), color=color, set=set_name)
}
circles <- rbind(circle_points(-0.45, "Case", "Case"),
                 circle_points(0.45, "Control", "Control"))
venn_plot <- ggplot() +
  geom_polygon(data=circles, aes(x=x, y=y, group=set, fill=color, color=color),
               alpha=0.25, linewidth=1) +
  geom_text(data=venn_data, aes(x=x, y=y, label=label), size=6, fontface="bold") +
  annotate("text", x=-0.75, y=1.18, label="Case", size=5, fontface="bold") +
  annotate("text", x=0.75, y=1.18, label="Control", size=5, fontface="bold") +
  annotate("text", x=0, y=-1.28,
           label=sprintf("Unique grouped core features: %d", length(union(case_features, control_features))),
           size=3.5) +
  scale_fill_manual(values=c(Case="#E64B35", Control="#4DBBD5"), guide="none") +
  scale_color_manual(values=c(Case="#E64B35", Control="#4DBBD5"), guide="none") +
  coord_fixed(xlim=c(-1.7, 1.7), ylim=c(-1.5, 1.5), clip="off") +
  labs(title=paste("Case vs Control Core Microbiome -", tools::toTitleCase(opt$dimension))) +
  theme_void(base_size=11) +
  theme(plot.title=element_text(hjust=0.5, face="bold"))
ggsave(file.path(opt$output_dir, "venn_diagram.pdf"), venn_plot,
       width=7, height=5.5, device="pdf")
if(mgx_want_png()) ggsave(file.path(opt$output_dir, "venn_diagram.png"), venn_plot,
       width=7, height=5.5, device=ragg::agg_png, dpi=600)

sample_totals <- colSums(abundance)
core_totals <- if(length(global_features) > 0) {
  colSums(abundance[global_features, , drop=FALSE])
} else {
  setNames(rep(0, ncol(abundance)), colnames(abundance))
}
sample_core_fraction <- ifelse(sample_totals > 0, core_totals / sample_totals, 0)
group_values <- if(group_available) tolower(trimws(as.character(metadata$group))) else rep("all", nrow(metadata))
display_groups <- ifelse(group_values %in% c("case", "control"), tools::toTitleCase(group_values), "All")
bar_sample_data <- data.frame(
  group=display_groups,
  core=sample_core_fraction,
  non_core=1 - sample_core_fraction,
  stringsAsFactors=FALSE
)
bar_groups <- unique(bar_sample_data$group)
bar_rows <- do.call(rbind, lapply(bar_groups, function(group_name) {
  subset <- bar_sample_data[bar_sample_data$group == group_name, , drop=FALSE]
  data.frame(group=group_name, component=c("Global core", "Non-core"),
             fraction=c(mean(subset$core), mean(subset$non_core)))
}))
bar_rows$group <- factor(bar_rows$group, levels=c("Case", "Control", "All"))
bar_plot <- ggplot(bar_rows, aes(x=component, y=fraction, fill=component)) +
  geom_col(width=0.7) +
  geom_text(aes(label=sprintf("%.1f%%", 100 * fraction)), vjust=-0.35, size=3.5) +
  facet_wrap(~ group) +
  scale_y_continuous(labels=function(values) paste0(round(100 * values), "%"),
                     limits=c(0, max(1.05, max(bar_rows$fraction) * 1.12))) +
  scale_fill_manual(values=c("Global core"="#3C5488", "Non-core"="#BDBDBD"), guide="none") +
  labs(title=paste("Global Core Abundance Contribution -", tools::toTitleCase(opt$dimension)),
       x=NULL, y="Mean relative abundance fraction") +
  theme_bw(base_size=11) +
  theme(axis.text.x=element_text(angle=20, hjust=1), panel.grid.minor=element_blank(),
        strip.background=element_rect(fill="#F0F0F0"))
ggsave(file.path(opt$output_dir, "core_abundance_barplot.pdf"), bar_plot,
       width=7.5, height=5.5, device="pdf")
if(mgx_want_png()) ggsave(file.path(opt$output_dir, "core_abundance_barplot.png"), bar_plot,
       width=7.5, height=5.5, device=ragg::agg_png, dpi=600)

cat(sprintf("[INFO] Case/control cores: %d/%d; shared: %d; case/control specific: %d/%d\n",
            length(case_features), length(control_features), length(shared_features),
            length(case_specific), length(control_specific)))
cat(sprintf("[INFO] Global core abundance fraction: %.2f%%\n", 100 * global_core_fraction))
cat("[INFO] Core microbiome analysis completed\n")
