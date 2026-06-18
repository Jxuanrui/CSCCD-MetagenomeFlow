#!/usr/bin/env Rscript
# 94_visualization.R — composition plots per dimension (bacteria / virus / fungi)
# Outputs: result/stat/composition/{dim}/barplot_composition_by_group.pdf
#                                        barplot_genus_groupmean.pdf
#                                        heatmap_genus.pdf
#                                        {dim}_viz_status.tsv

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(x)) y else x

workdir      <- Sys.getenv("WORKDIR")
repo         <- Sys.getenv("REPO")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col    <- Sys.getenv("GROUP_COL") %||% "group"
sentinel     <- Sys.getenv("SENTINEL") %||% file.path(workdir, "result", "stat", "visualization", "plots.done")
comp_root    <- file.path(workdir, "result", "stat", "composition")
div_root     <- file.path(workdir, "result", "stat", "diversity")

dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("microeco", "magrittr", "ggplot2", "cowplot", "dplyr", "RColorBrewer")
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  writeLines(format(Sys.time()), sentinel)
  stop("Missing packages: ", paste(miss, collapse = ", "))
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

write_status <- function(status_log, path) {
  df <- if (length(status_log)) do.call(rbind, status_log) else
    data.frame(step = character(), status = character(), message = character(),
               stringsAsFactors = FALSE)
  utils::write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE)
}

run_step <- function(step, status_log, expr) {
  tryCatch({
    force(expr)
    status_log[[length(status_log) + 1]] <<- data.frame(
      step = step, status = "OK", message = "", stringsAsFactors = FALSE
    )
    TRUE
  }, error = function(e) {
    msg <- conditionMessage(e)
    status_log[[length(status_log) + 1]] <<- data.frame(
      step = step, status = "FAILED", message = as.character(msg), stringsAsFactors = FALSE
    )
    message("[WARN] ", step, ": ", msg)
    FALSE
  })
}

dims <- c("bacteria", "virus", "fungi")
completed <- 0L

cat("[INFO] Starting composition visualization\n")
cat("  Workdir:", workdir, "\n")
cat("  Group column:", group_col, "\n")
cat("  Output root:", comp_root, "\n")

for (dim in dims) {
  cat(sprintf("\n[INFO] === Dimension: %s ===\n", dim))
  rds_path   <- file.path(div_root, dim, paste0(dim, "_microtable.rds"))
  out_dir    <- file.path(comp_root, dim)
  status_tsv <- file.path(out_dir, paste0(dim, "_viz_status.tsv"))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  status_log <- list()

  if (!file.exists(rds_path)) {
    msg <- paste("microtable RDS not found:", rds_path)
    cat("[SKIP]", msg, "\n")
    status_log[[1]] <- data.frame(step = "load_microtable", status = "SKIPPED",
                                   message = msg, stringsAsFactors = FALSE)
    write_status(status_log, status_tsv)
    next
  }

  mt <- tryCatch(readRDS(rds_path), error = function(e) NULL)
  if (is.null(mt)) {
    status_log[[1]] <- data.frame(step = "load_microtable", status = "FAILED",
                                   message = "readRDS returned NULL", stringsAsFactors = FALSE)
    write_status(status_log, status_tsv)
    next
  }
  status_log[[1]] <- data.frame(step = "load_microtable", status = "OK",
                                 message = "", stringsAsFactors = FALSE)
  cat(sprintf("  Loaded microtable: %d samples, %d taxa\n",
              nrow(mt$sample_table), nrow(mt$otu_table)))

  mt_clone <- NULL
  run_step("prepare_abund", status_log, {
    mt_clone <<- clone(mt)
    mt_clone$cal_abund(rel = TRUE)
  })
  if (is.null(mt_clone)) { write_status(status_log, status_tsv); next }

  grp <- if (group_col %in% colnames(mt_clone$sample_table)) group_col else NULL

  run_step(paste0(dim, "_barplot_phylum_genus"), status_log, {
    tmp_p <- trans_abund$new(dataset = mt_clone, taxrank = "Phylum")
    g1 <- tmp_p$plot_bar(color_values = npg_pal(30), others_color = "grey70",
                          xtext_keep = TRUE, barwidth = 0.6)
    tmp_g <- trans_abund$new(dataset = mt_clone, taxrank = "Genus")
    g2 <- tmp_g$plot_bar(color_values = npg_pal(30), others_color = "grey70",
                          xtext_keep = TRUE, barwidth = 0.6)
    p  <- cowplot::plot_grid(g1, g2, ncol = 1, align = "hv", labels = c("A", "B"))
    cowplot::save_plot(file.path(out_dir, "barplot_composition_by_group.pdf"),
                       p, base_aspect_ratio = 1.1, base_height = 10, dpi = 300)
  })

  run_step(paste0(dim, "_barplot_groupmean"), status_log, {
    if (is.null(grp)) stop("group column missing in sample_table")
    mt_g <- mt_clone$merge_samples(grp)
    mt_g$cal_abund(rel = TRUE)
    tmp  <- trans_abund$new(dataset = mt_g, taxrank = "Genus")
    g3   <- tmp$plot_bar(color_values = npg_pal(30), others_color = "grey70",
                          bar_full = FALSE, xtext_size = 13, xtext_angle = 30,
                          barwidth = 0.618) +
      theme(legend.text = element_text(size = 10))
    cowplot::save_plot(file.path(out_dir, "barplot_genus_groupmean.pdf"),
                       g3, base_aspect_ratio = 1.1, base_height = 5.5, dpi = 300)
  })

  run_step(paste0(dim, "_heatmap_genus"), status_log, {
    tmp <- trans_abund$new(dataset = mt_clone, taxrank = "Genus", ntaxa = 30)
    g4  <- tmp$plot_heatmap(
      facet = grp, xtext_keep = TRUE, withmargin = FALSE,
      color_values = rev(RColorBrewer::brewer.pal(11, "RdYlBu")),
      plot_colorscale = "identity"
    )
    cowplot::save_plot(file.path(out_dir, "heatmap_genus.pdf"),
                       g4, base_aspect_ratio = 1.3, base_height = 8, dpi = 300)
  })

  write_status(status_log, status_tsv)
  ok_n <- sum(vapply(status_log, function(x) x$status == "OK", logical(1)))
  if (ok_n > 0) completed <- completed + 1L
  cat(sprintf("  [%s] %d/%d steps OK\n", dim, ok_n, length(status_log)))
}

cat(sprintf("\n[INFO] Completed %d/%d dimensions\n", completed, length(dims)))
writeLines(format(Sys.time()), sentinel)
cat("[INFO] Visualization finished\n")
