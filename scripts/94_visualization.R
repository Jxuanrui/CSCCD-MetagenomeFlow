#!/usr/bin/env Rscript
# ==============================================================================
# Script: 94_visualization.R
# Purpose: Publication-ready genus composition barplot and ComplexHeatmap
# ==============================================================================

options(stringsAsFactors = FALSE, warn = 1)

conda_r_lib <- file.path(R.home("home"), "library")
project_r_lib <- Sys.getenv("R_LIBS_USER", unset = "")
lib_paths <- .libPaths()
if (nzchar(project_r_lib)) {
  lib_paths <- lib_paths[normalizePath(lib_paths, winslash = "/", mustWork = FALSE) !=
    normalizePath(project_r_lib, winslash = "/", mustWork = FALSE)]
}
if (dir.exists(conda_r_lib)) {
  .libPaths(unique(c(conda_r_lib, lib_paths)))
}

required_pkgs <- c("ComplexHeatmap", "circlize", "ggplot2", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(ComplexHeatmap)
  library(circlize)
  library(ggplot2)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL", unset = "group")
bact_table <- Sys.getenv("BACT_TABLE")
result_dir <- Sys.getenv("RESULT_DIR")
viz_dir <- Sys.getenv("VIZ_DIR")
force_flag <- identical(Sys.getenv("FORCE", unset = "0"), "1")
sentinel <- Sys.getenv("SENTINEL", unset = file.path(result_dir, "plots.done"))
barplot_pdf <- Sys.getenv("BARPLOT_PDF", unset = file.path(viz_dir, "barplot_composition_by_group.pdf"))
heatmap_pdf <- Sys.getenv("HEATMAP_PDF", unset = file.path(viz_dir, "heatmap_genus_complexheatmap.pdf"))

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Starting visualization analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Metadata:", ifelse(nzchar(metadata_csv), metadata_csv, "<none>"), "\n")
cat("  Group column:", group_col, "\n")
cat("  Bacteria table:", bact_table, "\n")
cat("  Visualization dir:", viz_dir, "\n")

status_log <- list()

log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- tibble(step = step, status = status, message = message)
}

run_step <- function(step, expr) {
  tryCatch(
    {
      force(expr)
      log_status(step, "OK", "")
      TRUE
    },
    error = function(e) {
      log_status(step, "FAILED", conditionMessage(e))
      message("[WARN] ", step, ": ", conditionMessage(e))
      FALSE
    }
  )
}

theme_publication <- function(base_size = 12) {
  theme_bw(base_size = base_size) +
    theme(
      panel.grid = element_blank(),
      panel.border = element_rect(color = "black", linewidth = 0.6),
      strip.background = element_rect(fill = "grey95", color = "grey80"),
      strip.text = element_text(face = "bold"),
      plot.title = element_text(face = "bold"),
      legend.key = element_blank()
    )
}

coerce_numeric_df <- function(df) {
  for (i in seq_along(df)) {
    df[[i]] <- suppressWarnings(as.numeric(df[[i]]))
  }
  df
}

read_metadata <- function(path, group_col) {
  if (!nzchar(path) || !file.exists(path)) {
    stop("Metadata CSV not found: ", path)
  }

  meta <- readr::read_csv(path, show_col_types = FALSE)
  if (nrow(meta) == 0) {
    stop("Metadata is empty")
  }

  sample_candidates <- c("sample", "sample_id", "SampleID", "Sample", "id")
  sample_col <- sample_candidates[sample_candidates %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)

  if (!group_col %in% names(meta)) {
    stop("Metadata group column not found: ", group_col)
  }

  meta <- meta %>%
    dplyr::mutate(
      sample_id = as.character(sample_id),
      group_value = as.character(.data[[group_col]])
    ) %>%
    dplyr::filter(!is.na(sample_id), sample_id != "", !is.na(group_value), group_value != "") %>%
    dplyr::distinct(sample_id, .keep_all = TRUE)

  if (nrow(meta) == 0) {
    stop("Metadata has no usable sample/group rows")
  }

  meta$group_value <- factor(meta$group_value, levels = unique(meta$group_value))
  meta
}

read_abundance_table <- function(path) {
  if (!nzchar(path) || !file.exists(path)) {
    stop("Missing input table: ", path)
  }

  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  if (nrow(raw) == 0) {
    stop("Bacteria table is empty")
  }

  feature_col <- names(raw)[1]
  candidate_numeric <- names(raw)[vapply(
    raw,
    function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0,
    logical(1)
  )]
  sample_cols <- setdiff(candidate_numeric, feature_col)
  if (length(sample_cols) == 0) {
    stop("No sample columns detected in ", path)
  }

  abund <- raw %>%
    dplyr::select(all_of(c(feature_col, sample_cols))) %>%
    dplyr::rename(feature = !!feature_col)

  abund[sample_cols] <- coerce_numeric_df(abund[sample_cols])
  abund <- abund %>%
    dplyr::filter(!is.na(feature), feature != "") %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(dplyr::across(all_of(sample_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")

  mat <- as.matrix(abund[, sample_cols, drop = FALSE])
  rownames(mat) <- abund$feature
  mat[is.na(mat)] <- 0
  mat[rowSums(mat) > 0, , drop = FALSE]
}

extract_genus_label <- function(feature) {
  parts <- strsplit(feature, "\\|", fixed = FALSE)[[1]]
  genus_candidates <- parts[grepl("^g__", parts)]
  genus_part <- if (length(genus_candidates) > 0) genus_candidates[1] else NA_character_
  genus_label <- sub("^g__", "", genus_part)
  genus_label <- trimws(genus_label)
  if (is.na(genus_label) || !nzchar(genus_label) || identical(genus_label, "NA")) {
    "Unclassified"
  } else {
    genus_label
  }
}

aggregate_genus_matrix <- function(mat) {
  genus_rows <- grepl("\\|g__", rownames(mat)) & !grepl("\\|s__", rownames(mat)) & !grepl("\\|t__", rownames(mat))
  genus_mat <- mat[genus_rows, , drop = FALSE]
  if (nrow(genus_mat) == 0) {
    stop("No genus-level rows found in MetaPhlAn table")
  }

  genus_labels <- vapply(rownames(genus_mat), extract_genus_label, character(1))
  genus_df <- as.data.frame(genus_mat, check.names = FALSE) %>%
    tibble::rownames_to_column("feature") %>%
    dplyr::mutate(genus = genus_labels) %>%
    dplyr::select(-feature) %>%
    dplyr::group_by(genus) %>%
    dplyr::summarise(dplyr::across(everything(), ~ sum(.x, na.rm = TRUE)), .groups = "drop")

  out <- as.matrix(genus_df[, -1, drop = FALSE])
  rownames(out) <- genus_df$genus
  out[is.na(out)] <- 0
  out[rowSums(out) > 0, , drop = FALSE]
}

prepare_inputs <- function() {
  if (!file.exists(bact_table)) {
    return(list(skip = TRUE, reason = paste("Bacteria table missing:", bact_table)))
  }

  if (!nzchar(metadata_csv) || !file.exists(metadata_csv)) {
    return(list(skip = TRUE, reason = "Metadata CSV missing; cannot group samples"))
  }

  metadata <- read_metadata(metadata_csv, group_col)
  bacteria <- read_abundance_table(bact_table)
  genus_mat <- aggregate_genus_matrix(bacteria)

  common_samples <- intersect(colnames(genus_mat), metadata$sample_id)
  if (length(common_samples) < 2) {
    return(list(skip = TRUE, reason = "Fewer than two overlapping samples between metadata and genus matrix"))
  }

  metadata <- metadata %>%
    dplyr::filter(sample_id %in% common_samples) %>%
    dplyr::arrange(group_value, sample_id)

  ordered_samples <- metadata$sample_id
  genus_mat <- genus_mat[, ordered_samples, drop = FALSE]

  totals <- colSums(genus_mat, na.rm = TRUE)
  keep_samples <- totals > 0
  if (!all(keep_samples)) {
    metadata <- metadata[keep_samples, , drop = FALSE]
    genus_mat <- genus_mat[, metadata$sample_id, drop = FALSE]
  }

  if (ncol(genus_mat) < 2 || nrow(genus_mat) == 0) {
    return(list(skip = TRUE, reason = "No usable genus abundance matrix after filtering"))
  }

  list(skip = FALSE, metadata = metadata, genus_mat = genus_mat)
}

make_group_palette <- function(groups) {
  uniq <- unique(as.character(groups))
  n <- length(uniq)
  hues <- seq(15, 375, length.out = n + 1)[seq_len(n)]
  cols <- grDevices::hcl(h = hues, c = 100, l = 65)
  stats::setNames(cols, uniq)
}

plot_stacked_bar <- function(genus_mat, metadata, output_file) {
  rel_mat <- sweep(genus_mat, 2, colSums(genus_mat), "/")
  rel_mat[is.na(rel_mat)] <- 0

  top_genera <- names(sort(rowMeans(rel_mat), decreasing = TRUE))[seq_len(min(15, nrow(rel_mat)))]
  plot_mat <- rel_mat
  other_idx <- setdiff(rownames(plot_mat), top_genera)
  if (length(other_idx) > 0) {
    other_row <- matrix(colSums(plot_mat[other_idx, , drop = FALSE]), nrow = 1)
    colnames(other_row) <- colnames(plot_mat)
    rownames(other_row) <- "Other"
    plot_mat <- rbind(plot_mat[top_genera, , drop = FALSE], other_row)
  } else {
    plot_mat <- plot_mat[top_genera, , drop = FALSE]
  }

  genus_levels <- c(top_genera, if ("Other" %in% rownames(plot_mat)) "Other")
  plot_df <- as.data.frame(plot_mat, check.names = FALSE) %>%
    tibble::rownames_to_column("genus") %>%
    tidyr::pivot_longer(-genus, names_to = "sample_id", values_to = "abundance") %>%
    dplyr::left_join(metadata[, c("sample_id", "group_value")], by = "sample_id") %>%
    dplyr::mutate(
      genus = factor(genus, levels = rev(genus_levels)),
      sample_id = factor(sample_id, levels = metadata$sample_id),
      group_value = factor(group_value, levels = levels(metadata$group_value)),
      abundance_pct = abundance * 100
    )

  palette_vals <- grDevices::hcl.colors(max(length(top_genera), 1), palette = "Dynamic")
  names(palette_vals) <- top_genera
  fill_values <- c(palette_vals, Other = "#BDBDBD")
  fill_values <- fill_values[unique(c(top_genera, if ("Other" %in% genus_levels) "Other"))]

  p <- ggplot(plot_df, aes(x = sample_id, y = abundance_pct, fill = genus)) +
    geom_col(width = 0.9, color = NA) +
    facet_grid(~group_value, scales = "free_x", space = "free_x") +
    scale_y_continuous(expand = c(0, 0), labels = function(x) sprintf("%.0f", x)) +
    scale_fill_manual(values = fill_values, drop = FALSE) +
    labs(
      title = "Genus-level composition by group",
      x = "Samples",
      y = "Relative abundance (%)",
      fill = "Genus"
    ) +
    theme_publication(base_size = 11) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      panel.spacing.x = grid::unit(0.5, "lines"),
      legend.position = "right",
      strip.text.x = element_text(face = "bold")
    )

  ggplot2::ggsave(output_file, plot = p, width = 12, height = 7, units = "in")
}

plot_complex_heatmap <- function(genus_mat, metadata, output_file) {
  rel_mat <- sweep(genus_mat, 2, colSums(genus_mat), "/")
  rel_mat[is.na(rel_mat)] <- 0

  variances <- apply(rel_mat, 1, stats::var, na.rm = TRUE)
  variances[is.na(variances)] <- 0
  top_n <- min(30, nrow(rel_mat))
  selected <- names(sort(variances, decreasing = TRUE))[seq_len(top_n)]
  heat_mat <- rel_mat[selected, , drop = FALSE]

  z_mat <- t(scale(t(heat_mat)))
  z_mat[is.na(z_mat)] <- 0
  rownames(z_mat) <- selected
  colnames(z_mat) <- metadata$sample_id

  row_dist <- function(m) {
    cor_mat <- stats::cor(t(m), method = "pearson", use = "pairwise.complete.obs")
    cor_mat[!is.finite(cor_mat)] <- 0
    diag(cor_mat) <- 1
    as.dist(1 - cor_mat)
  }
  group_colors <- make_group_palette(metadata$group_value)
  top_annot <- ComplexHeatmap::HeatmapAnnotation(
    Group = metadata$group_value,
    col = list(Group = group_colors),
    annotation_name_side = "left",
    show_annotation_name = TRUE
  )

  ht <- ComplexHeatmap::Heatmap(
    z_mat,
    name = "Z-score",
    top_annotation = top_annot,
    col = circlize::colorRamp2(c(-2, 0, 2), c("#2166AC", "#F7F7F7", "#B2182B")),
    cluster_rows = TRUE,
    cluster_columns = FALSE,
    clustering_distance_rows = row_dist,
    clustering_method_rows = "complete",
    show_column_names = FALSE,
    show_row_names = TRUE,
    row_names_gp = grid::gpar(fontsize = 8),
    column_split = metadata$group_value,
    column_title = NULL,
    border = TRUE,
    heatmap_legend_param = list(direction = "vertical")
  )

  grDevices::pdf(output_file, width = 14, height = 10)
  on.exit(grDevices::dev.off(), add = TRUE)
  ComplexHeatmap::draw(
    ht,
    merge_legends = TRUE,
    heatmap_legend_side = "right",
    annotation_legend_side = "right"
  )
}

inputs <- prepare_inputs()

if (isTRUE(inputs$skip)) {
  message("[WARN] Skipping visualization: ", inputs$reason)
  log_status("prepare_inputs", "SKIPPED", inputs$reason)
  readr::write_tsv(bind_rows(status_log), file.path(result_dir, "visualization_status.tsv"))
  writeLines("skipped", sentinel)
  quit(save = "no", status = 0)
}

genus_mat <- inputs$genus_mat
metadata <- inputs$metadata

barplot_ok <- TRUE
if (!force_flag && file.exists(barplot_pdf) && file.info(barplot_pdf)$size > 0) {
  log_status("stacked_barplot", "SKIPPED", "Output already exists")
} else {
  barplot_ok <- run_step("stacked_barplot", {
    plot_stacked_bar(genus_mat, metadata, barplot_pdf)
  })
}

heatmap_ok <- TRUE
if (!force_flag && file.exists(heatmap_pdf) && file.info(heatmap_pdf)$size > 0) {
  log_status("complex_heatmap", "SKIPPED", "Output already exists")
} else {
  heatmap_ok <- run_step("complex_heatmap", {
    plot_complex_heatmap(genus_mat, metadata, heatmap_pdf)
  })
}

readr::write_tsv(bind_rows(status_log), file.path(result_dir, "visualization_status.tsv"))
if (!barplot_ok || !heatmap_ok) {
  stop("One or more visualization steps failed; sentinel not written")
}
writeLines("done", sentinel)
