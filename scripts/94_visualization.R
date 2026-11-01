#!/usr/bin/env Rscript
# 94_visualization.R — composition plots per dimension (bacteria / virus / fungi)
# Outputs: result/stat/{dim}/composition/barplot_composition_by_group.{svg,pdf,tiff}
#                                            barplot_genus_groupmean.{svg,pdf,tiff}
#                                            heatmap_genus.{svg,pdf,tiff}
#                                            {dim}_viz_status.tsv

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(x)) y else x

workdir      <- Sys.getenv("WORKDIR")
repo         <- Sys.getenv("REPO")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col    <- Sys.getenv("GROUP_COL") %||% "group"
stat_root    <- Sys.getenv("STAT_ROOT") %||% file.path(workdir, "result", "stat")
sentinel     <- Sys.getenv("SENTINEL") %||% file.path(stat_root, "composition_done.txt")

dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("microeco", "magrittr", "ggplot2", "cowplot", "dplyr", "RColorBrewer", "svglite", "ragg",
                    "MicrobiotaProcess", "phyloseq", "patchwork", "rlang")
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
  library(MicrobiotaProcess)
  library(phyloseq)
  library(patchwork)
})

grDevices::pdf(file = NULL)

# Shared publication theme/export helpers (scripts/R/pub_theme.R), resolved
# from this script's own location so any cwd works.
local({
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  script_dir <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else
    file.path(Sys.getenv("REPO"), "scripts")
  source(file.path(script_dir, "R", "pub_theme.R"))
})

theme_set(theme_pub())

rank_has_values <- function(mt, rank) {
  if (!rank %in% colnames(mt$tax_table)) return(FALSE)
  vals <- as.character(mt$tax_table[[rank]])
  vals <- vals[!is.na(vals) & nzchar(vals) & vals != "NA"]
  length(unique(vals)) > 1
}

choose_taxrank <- function(mt, preferred, fallbacks = c("Species", "Genus", "Family", "Phylum", "vOTU")) {
  if (rank_has_values(mt, preferred)) return(preferred)
  for (rank in unique(c(fallbacks, colnames(mt$tax_table)))) {
    if (rank_has_values(mt, rank)) return(rank)
  }
  stop("No usable taxonomy rank found for plotting")
}

rank_subtitle <- function(preferred, selected) {
  if (identical(preferred, selected)) NULL else paste0("Displayed at ", selected, " level; ", preferred, " unavailable or uninformative")
}

# Re-colors a mp_plot_abundance() ggplot with the project's ggsci-derived NPG palette,
# extended via npg_pal() beyond its native 10-color limit, and forces "Others" to the
# last factor level/legend entry (mp_plot_abundance() sorts fill levels alphabetically,
# which would otherwise put "Others" first).
recolor_mpse_plot <- function(p, others_color = "grey70") {
  fill_var <- rlang::as_name(p$mapping$fill)
  lv_all <- levels(factor(p$data[[fill_var]]))
  has_others <- "Others" %in% lv_all
  lv <- setdiff(lv_all, "Others")
  cols <- npg_pal(length(lv))
  names(cols) <- lv
  if (has_others) cols <- c(cols, Others = others_color)
  p$data[[fill_var]] <- factor(p$data[[fill_var]], levels = c(lv, if (has_others) "Others"))
  p + ggplot2::scale_fill_manual(values = cols, breaks = c(lv, if (has_others) "Others")) +
    theme_pub(base_size = 7)
}

style_mpse_sample_axis <- function(p, n_samples) {
  if (n_samples > 40) {
    p + ggplot2::theme(axis.text.x = ggplot2::element_blank(), axis.ticks.x = ggplot2::element_blank())
  } else {
    p + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 5))
  }
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
cat("  Stat root:", stat_root, "\n")

for (dim in dims) {
  cat(sprintf("\n[INFO] === Dimension: %s ===\n", dim))
  rds_path      <- file.path(stat_root, dim, paste0(dim, "_microtable.rds"))
  phyloseq_path <- file.path(stat_root, dim, "phyloseq", paste0(dim, "_phyloseq.rds"))
  out_dir    <- file.path(stat_root, dim, "composition")
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
  n_samples <- nrow(mt_clone$sample_table)
  phylum_rank <- choose_taxrank(mt_clone, "Phylum", fallbacks = c("Phylum", "Species", "vOTU"))
  genus_rank <- choose_taxrank(mt_clone, "Genus", fallbacks = c("Genus", "Species", "Family", "Phylum", "vOTU"))

  mpse <- NULL
  if (file.exists(phyloseq_path)) {
    run_step("load_mpse", status_log, {
      ps <- readRDS(phyloseq_path)
      mpse <<- MicrobiotaProcess::as.MPSE(ps)
    })
  } else {
    msg <- paste("phyloseq RDS not found:", phyloseq_path)
    cat("[WARN]", msg, "\n")
    status_log[[length(status_log) + 1]] <- data.frame(step = "load_mpse", status = "SKIPPED",
                                                         message = msg, stringsAsFactors = FALSE)
  }

  if (!is.null(mpse)) {
    run_step(paste0(dim, "_barplot_phylum_genus"), status_log, {
      grp_sym <- if (!is.null(grp)) rlang::sym(grp) else NULL
      phylum_sym <- rlang::sym(phylum_rank)
      genus_sym <- rlang::sym(genus_rank)

      p_phylum <- mpse %>%
        MicrobiotaProcess::mp_plot_abundance(
          .abundance = Abundance, .group = !!grp_sym, taxa.class = !!phylum_sym,
          topn = 10, relative = TRUE, force = TRUE, geom = "bar"
        ) %>%
        recolor_mpse_plot() %>%
        style_mpse_sample_axis(n_samples)
      p_phylum <- p_phylum + ggplot2::labs(subtitle = rank_subtitle("Phylum", phylum_rank))

      p_genus <- mpse %>%
        MicrobiotaProcess::mp_plot_abundance(
          .abundance = Abundance, .group = !!grp_sym, taxa.class = !!genus_sym,
          topn = 15, relative = TRUE, force = TRUE, geom = "bar"
        ) %>%
        recolor_mpse_plot() %>%
        style_mpse_sample_axis(n_samples)
      p_genus <- p_genus + ggplot2::labs(subtitle = rank_subtitle("Genus", genus_rank))

      p <- p_phylum / p_genus +
        patchwork::plot_layout(guides = "collect") +
        patchwork::plot_annotation(tag_levels = "a")
      export_pub_figure(p, file.path(out_dir, "barplot_composition_by_group"),
                        width_mm = 260, height_mm = 170)
    })

    run_step(paste0(dim, "_barplot_groupmean"), status_log, {
      if (is.null(grp)) stop("group column missing in sample_table")
      grp_sym <- rlang::sym(grp)
      genus_sym <- rlang::sym(genus_rank)

      p_group <- mpse %>%
        MicrobiotaProcess::mp_plot_abundance(
          .abundance = Abundance, .group = !!grp_sym, taxa.class = !!genus_sym,
          topn = 15, relative = TRUE, force = TRUE, geom = "bar", plot.group = TRUE
        ) %>%
        recolor_mpse_plot()
      p_group <- p_group +
        ggplot2::labs(subtitle = rank_subtitle("Genus", genus_rank)) +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1, size = 7),
                        legend.text = ggplot2::element_text(size = 7))
      export_pub_figure(p_group, file.path(out_dir, "barplot_genus_groupmean"),
                        width_mm = 183, height_mm = 90)
    })
  } else {
    status_log[[length(status_log) + 1]] <- data.frame(
      step = paste0(dim, "_barplot_phylum_genus"), status = "SKIPPED",
      message = "MPSE unavailable", stringsAsFactors = FALSE)
    status_log[[length(status_log) + 1]] <- data.frame(
      step = paste0(dim, "_barplot_groupmean"), status = "SKIPPED",
      message = "MPSE unavailable", stringsAsFactors = FALSE)
  }

  run_step(paste0(dim, "_heatmap_genus"), status_log, {
    tmp <- trans_abund$new(dataset = mt_clone, taxrank = genus_rank, ntaxa = 30)
    g4  <- tmp$plot_heatmap(
      facet = grp, xtext_keep = n_samples <= 40, xtext_angle = 45, xtext_size = 6,
      withmargin = FALSE,
      color_values = rev(RColorBrewer::brewer.pal(11, "RdYlBu")),
      plot_colorscale = "identity"
    ) +
      theme_pub(base_size = 7) +
      ggplot2::labs(fill = "Relative abundance", subtitle = paste(c(
        rank_subtitle("Genus", genus_rank),
        if (n_samples > 40) paste0("n = ", n_samples, " samples; x-axis sample labels omitted for readability")
      ), collapse = " | "))
    if (n_samples <= 40) {
      g4 <- g4 + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 6))
    } else {
      # theme_pub() overrides plot_heatmap's xtext_keep=FALSE, so re-blank explicitly
      g4 <- g4 + ggplot2::theme(axis.text.x = ggplot2::element_blank(),
                                 axis.ticks.x = ggplot2::element_blank())
    }
    export_pub_figure(g4, file.path(out_dir, "heatmap_genus"),
                      width_mm = 183, height_mm = 130)
  })

  write_status(status_log, status_tsv)
  ok_n <- sum(vapply(status_log, function(x) x$status == "OK", logical(1)))
  if (ok_n > 0) completed <- completed + 1L
  cat(sprintf("  [%s] %d/%d steps OK\n", dim, ok_n, length(status_log)))
}

cat(sprintf("\n[INFO] Completed %d/%d dimensions\n", completed, length(dims)))
writeLines(format(Sys.time()), sentinel)
cat("[INFO] Visualization finished\n")
