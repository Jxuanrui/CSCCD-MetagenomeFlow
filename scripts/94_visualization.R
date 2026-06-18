#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(x)) y else x

workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL") %||% "group"
out_dir <- Sys.getenv("VIZ_DIR") %||% file.path(workdir, "result", "stat", "composition")
sentinel <- Sys.getenv("SENTINEL") %||% file.path(workdir, "result", "stat", "visualization", "plots.done")
barplot_pdf <- Sys.getenv("BARPLOT_PDF") %||% file.path(out_dir, "barplot_composition_by_group.pdf")
heatmap_pdf <- Sys.getenv("HEATMAP_PDF") %||% file.path(out_dir, "heatmap_genus_complexheatmap.pdf")
status_tsv <- file.path(out_dir, "viz_status.tsv")
groupmean_pdf <- file.path(out_dir, "barplot_genus_groupmean.pdf")
microtable_rds <- file.path(workdir, "result", "stat", "diversity", "bacteria", "bacteria_microtable.rds")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

status_log <- list()
log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- data.frame(
    step = step, status = status, message = as.character(message),
    stringsAsFactors = FALSE
  )
}
write_status <- function() {
  status_df <- if (length(status_log)) do.call(rbind, status_log) else data.frame(
    step = character(), status = character(), message = character(),
    stringsAsFactors = FALSE
  )
  utils::write.table(status_df, status_tsv, sep = "\t", quote = FALSE,
                     row.names = FALSE, col.names = TRUE)
}
write_sentinel <- function() writeLines(format(Sys.time()), sentinel)

required_pkgs <- c("microeco", "magrittr", "ggplot2", "cowplot", "dplyr", "RColorBrewer")
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  log_status("packages", "FAILED", paste("Missing packages:", paste(miss, collapse = ", ")))
  write_status()
  write_sentinel()
  quit(save = "no", status = 0)
}

suppressPackageStartupMessages({
  library(microeco)
  library(magrittr)
  library(ggplot2)
  library(cowplot)
  library(dplyr)
})

theme_set(theme_bw())

npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488","#F39B7F",
              "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) {
  if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
}

run_step <- function(step, expr) {
  tryCatch({
    force(expr)
    log_status(step, "OK", "")
    TRUE
  }, error = function(e) {
    log_status(step, "FAILED", conditionMessage(e))
    message("[WARN] ", step, ": ", conditionMessage(e))
    FALSE
  })
}

cat("[INFO] Starting visualization analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Repo:", repo, "\n")
cat("  Metadata:", if (nzchar(metadata_csv)) metadata_csv else "<none>", "\n")
cat("  Group column:", group_col, "\n")
cat("  Microtable:", microtable_rds, "\n")

mt <- NULL
if (!file.exists(microtable_rds)) {
  log_status("load_microtable", "SKIPPED", paste("Missing microtable:", microtable_rds))
  write_status()
  write_sentinel()
  quit(save = "no", status = 0)
}

run_step("load_microtable", {
  mt <<- readRDS(microtable_rds)
  if (is.null(mt$sample_table) || nrow(mt$sample_table) == 0) stop("sample_table is empty")
})

mt_clone <- NULL
run_step("prepare_relative_abundance", {
  mt_clone <<- clone(mt)
  mt_clone$cal_abund(rel = TRUE)
})

group_facet <- if (!is.null(mt_clone) && group_col %in% colnames(mt_clone$sample_table)) group_col else NULL
if (is.null(group_facet)) log_status("group_column", "SKIPPED", paste("Missing group column:", group_col))

run_step("barplot_composition_by_group", {
  tmp <- trans_abund$new(dataset = mt_clone, taxrank = "Phylum")
  g1 <- tmp$plot_bar(color_values = npg_pal(30), others_color = "grey70",
                     xtext_keep = TRUE, barwidth = 0.6)
  tmp <- trans_abund$new(dataset = mt_clone, taxrank = "Genus")
  g2 <- tmp$plot_bar(color_values = npg_pal(30), others_color = "grey70",
                     xtext_keep = TRUE, barwidth = 0.6)
  p <- cowplot::plot_grid(g1, g2, ncol = 1, align = "hv", labels = c("A", "B"))
  cowplot::save_plot(barplot_pdf, p, base_aspect_ratio = 1.1, base_height = 10, dpi = 300)
})

run_step("barplot_genus_groupmean", {
  if (is.null(group_facet)) stop("Cannot merge samples; group column missing in sample_table")
  mt_group <- mt_clone$merge_samples(group_col)
  mt_group$cal_abund(rel = TRUE)
  tmp <- trans_abund$new(dataset = mt_group, taxrank = "Genus")
  g3 <- tmp$plot_bar(color_values = npg_pal(30), others_color = "grey70", bar_full = FALSE,
                     xtext_size = 13, xtext_angle = 30, barwidth = 0.618) +
    theme(legend.text = element_text(size = 10))
  cowplot::save_plot(groupmean_pdf, g3, base_aspect_ratio = 1.1, base_height = 5.5, dpi = 300)
})

run_step("heatmap_genus_complexheatmap", {
  tmp <- trans_abund$new(dataset = mt_clone, taxrank = "Genus", ntaxa = 30)
  g4 <- tmp$plot_heatmap(
    facet = group_facet, xtext_keep = TRUE, withmargin = FALSE,
    color_values = rev(RColorBrewer::brewer.pal(11, "RdYlBu")),
    plot_colorscale = "identity"
  )
  cowplot::save_plot(heatmap_pdf, g4, base_aspect_ratio = 1.3, base_height = 8, dpi = 300)
})

write_status()
write_sentinel()
cat("[INFO] Visualization finished\n")
