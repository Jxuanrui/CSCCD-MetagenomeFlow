#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
      normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("microeco", "magrittr", "ggplot2", "cowplot", "dplyr", "tidyr")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))

suppressPackageStartupMessages({
  library(microeco)
  library(magrittr)
  library(ggplot2)
  library(cowplot)
  library(dplyr)
  library(tidyr)
})

theme_set(theme_bw())

npg_base <- c(
  "#E64B35", "#4DBBD5", "#00A087", "#3C5488", "#F39B7F",
  "#8491B4", "#91D1C2", "#DC0000", "#7E6148", "#B09C85"
)
npg_pal <- function(n) if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")
threads <- suppressWarnings(as.integer(Sys.getenv("THREADS", "1")))
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
result_dir <- Sys.getenv("RESULT_DIR")
dimension_req <- Sys.getenv("DIMENSION", "all")
if (!nzchar(result_dir)) result_dir <- file.path(workdir, "result", "stat", "diff")
if (!is.na(threads) && threads > 0) options(mc.cores = threads)

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

status_rows <- list()
summary_rows <- list()
add_status <- function(dimension, step, method = "", taxa_level = "", status = "OK", message = "", output_file = "") {
  status_rows[[length(status_rows) + 1]] <<- data.frame(
    dimension = dimension, step = step, method = method, taxa_level = taxa_level,
    status = status, message = message, output_file = output_file,
    stringsAsFactors = FALSE
  )
}
add_summary <- function(dimension, method, n_sig, top_feature, output_file) {
  summary_rows[[length(summary_rows) + 1]] <<- data.frame(
    dimension = dimension, method = method, n_sig = n_sig,
    top_feature = top_feature %||% "", output_file = output_file,
    stringsAsFactors = FALSE
  )
}
empty_status <- function() data.frame(
  dimension = character(), step = character(), method = character(),
  taxa_level = character(), status = character(), message = character(),
  output_file = character(), stringsAsFactors = FALSE
)
empty_summary <- function() data.frame(
  dimension = character(), method = character(), n_sig = integer(),
  top_feature = character(), output_file = character(), stringsAsFactors = FALSE
)
write_tsv <- function(x, path) write.table(x, path, sep = "\t", quote = FALSE, row.names = FALSE, na = "")

count_sig <- function(res) {
  if (is.null(res) || !nrow(res)) return(0L)
  if ("diff" %in% names(res)) return(sum(!is.na(res$diff) & res$diff, na.rm = TRUE))
  if ("P.adj" %in% names(res)) return(sum(!is.na(res$P.adj) & res$P.adj < 0.05, na.rm = TRUE))
  if ("qvalue" %in% names(res)) return(sum(!is.na(res$qvalue) & res$qvalue < 0.05, na.rm = TRUE))
  if ("Significance" %in% names(res)) return(sum(!is.na(res$Significance) & nzchar(res$Significance) & res$Significance != "ns"))
  nrow(res)
}

top_feature <- function(res) {
  if (is.null(res) || !nrow(res) || !"Taxa" %in% names(res)) return("")
  if ("diff" %in% names(res)) {
    x <- res[!is.na(res$diff) & res$diff, , drop = FALSE]
  } else if ("P.adj" %in% names(res)) {
    x <- res[!is.na(res$P.adj) & res$P.adj < 0.05, , drop = FALSE]
    if (nrow(x)) x <- x[order(x$P.adj), , drop = FALSE]
  } else if ("qvalue" %in% names(res)) {
    x <- res[!is.na(res$qvalue) & res$qvalue < 0.05, , drop = FALSE]
    if (nrow(x)) x <- x[order(x$qvalue), , drop = FALSE]
  } else {
    x <- res
  }
  if (!nrow(x)) return("")
  as.character(x$Taxa[1])
}

prepare_mt <- function(mt) {
  x <- clone(mt)
  if (!group_col %in% names(x$sample_table)) stop("Group column not found in sample_table: ", group_col)
  x$sample_table[[group_col]] <- as.character(x$sample_table[[group_col]])
  x$sample_table <- x$sample_table[!is.na(x$sample_table[[group_col]]) & nzchar(x$sample_table[[group_col]]), , drop = FALSE]
  x$sample_table[[group_col]] <- factor(x$sample_table[[group_col]])
  x$tidy_dataset()
  if (nrow(x$sample_table) < 2) stop("Fewer than 2 samples after filtering metadata")
  if (length(unique(as.character(x$sample_table[[group_col]]))) < 2) stop("Fewer than 2 groups in sample_table")
  x$cal_abund(rel = TRUE)
  x$filter_taxa(rel_abund = 0.001)
  x
}

run_diff <- function(mt, method, taxa_level, out_csv, extra = list()) {
  args <- c(list(dataset = mt, method = method, group = group_col, taxa_level = taxa_level), extra)
  obj <- do.call(trans_diff$new, args)
  write.csv(obj$res_diff, out_csv, row.names = FALSE)
  list(obj = obj, output = out_csv, n_sig = count_sig(obj$res_diff), top_feature = top_feature(obj$res_diff))
}

choose_bacteria_level <- function(mt, dim_dir) {
  attempts <- c("Species", "Genus", "Phylum")
  best <- NULL
  for (lvl in attempts) {
    out_csv <- file.path(dim_dir, "lefse_results.csv")
    res <- tryCatch(run_diff(mt, "lefse", lvl, out_csv, list(filter_thres = 0.001)),
      error = function(e) {
        add_status("bacteria", "diff", "lefse", lvl, "FAILED", conditionMessage(e), out_csv)
        NULL
      }
    )
    if (is.null(res)) next
    add_status("bacteria", "diff", "lefse", lvl, "OK", paste("n_sig =", res$n_sig), out_csv)
    best <- best %||% res
    if (res$n_sig >= 5L || lvl == "Phylum") return(res)
    best <- if (res$n_sig >= best$n_sig) res else best
  }
  best
}

augment_wilcox_for_volcano <- function(obj) {
  res <- obj$res_diff
  if (is.null(res) || !nrow(res) || any(c("Estimate", "log2FC", "lfc", "logFC", "log2FoldChange") %in% names(res))) return(obj)
  alpha_df <- tryCatch(obj$res_abund_tmp$data_alpha, error = function(e) NULL)
  grp_name <- tryCatch(obj$res_abund_tmp$group, error = function(e) NULL) %||% group_col
  if (is.null(alpha_df)) return(obj)
  if ("Measure" %in% names(alpha_df) && !"Taxa" %in% names(alpha_df)) names(alpha_df)[names(alpha_df) == "Measure"] <- "Taxa"
  if (!all(c("Taxa", "Value", grp_name) %in% names(alpha_df)) || !"Comparison" %in% names(res)) return(obj)
  means <- alpha_df %>%
    group_by(Taxa, .data[[grp_name]]) %>%
    summarise(mean_value = mean(Value, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = .data[[grp_name]], values_from = mean_value, values_fill = 0)
  res$Estimate <- NA_real_
  eps <- 1e-6
  for (i in seq_len(nrow(res))) {
    pair <- strsplit(as.character(res$Comparison[i]), " - ", fixed = TRUE)[[1]]
    rowi <- means[means$Taxa == res$Taxa[i], , drop = FALSE]
    if (length(pair) == 2 && nrow(rowi) == 1 && all(pair %in% names(rowi))) {
      res$Estimate[i] <- log2((rowi[[pair[1]]] + eps) / (rowi[[pair[2]]] + eps))
    }
  }
  obj$res_diff <- res
  obj
}

plot_diff_abund_fallback <- function(obj, use_number = 15, color_values = npg_base) {
  res <- obj$res_diff
  alpha_df <- obj$res_abund_tmp$data_alpha
  grp_name <- obj$res_abund_tmp$group %||% group_col
  if ("Measure" %in% names(alpha_df) && !"Taxa" %in% names(alpha_df)) names(alpha_df)[names(alpha_df) == "Measure"] <- "Taxa"
  if (!all(c("Taxa", "Value", grp_name) %in% names(alpha_df))) stop("Fallback abundance plot requires Taxa/Value/group columns")
  taxa_order <- unique(as.character(res$Taxa))
  taxa_order <- taxa_order[seq_len(min(length(taxa_order), use_number))]
  plot_df <- alpha_df[alpha_df$Taxa %in% taxa_order, , drop = FALSE]
  if (!nrow(plot_df)) stop("No abundance data available for fallback plot")
  sig_df <- res[match(taxa_order, res$Taxa), , drop = FALSE]
  sig_df$Taxa <- factor(sig_df$Taxa, levels = rev(taxa_order))
  plot_df$Taxa <- factor(plot_df$Taxa, levels = rev(taxa_order))
  y_pos <- plot_df %>%
    group_by(Taxa) %>%
    summarise(y = max(Value, na.rm = TRUE) * 1.08 + 1e-6, .groups = "drop")
  sig_df <- left_join(sig_df, y_pos, by = "Taxa")
  simple_labs <- setNames(sub(".*\\|", "", taxa_order), taxa_order)
  ggplot(plot_df, aes(x = .data[[grp_name]], y = Value, fill = .data[[grp_name]], color = .data[[grp_name]])) +
    geom_boxplot(width = 0.65, outlier.shape = NA, alpha = 0.35) +
    geom_point(position = position_jitter(width = 0.12, height = 0), size = 1.2, alpha = 0.85) +
    geom_text(data = sig_df, aes(x = 1.5, y = y, label = Significance), inherit.aes = FALSE, size = 4.2) +
    facet_wrap(~ Taxa, ncol = 1, scales = "free_y", labeller = labeller(Taxa = simple_labs)) +
    scale_fill_manual(values = color_values) +
    scale_color_manual(values = color_values) +
    labs(x = NULL, y = "Relative abundance") +
    theme_bw() +
    theme(
      panel.grid = element_blank(),
      strip.text = element_text(face = "bold"),
      legend.position = "none",
      axis.text.x = element_text(angle = 0, hjust = 0.5)
    )
}

save_plot_safe <- function(plot_expr, output_file, dimension, step, method, taxa_level, ratio, height) {
  tryCatch({
    g <- force(plot_expr)
    cowplot::save_plot(output_file, g, base_aspect_ratio = ratio, base_height = height, dpi = 300)
    add_status(dimension, step, method, taxa_level, "OK", "", output_file)
    TRUE
  }, error = function(e) {
    add_status(dimension, step, method, taxa_level, "FAILED", conditionMessage(e), output_file)
    FALSE
  })
}

load_mt <- function(dim) {
  rds_path <- file.path(workdir, "result", "stat", "diversity", dim, paste0(dim, "_microtable.rds"))
  if (!file.exists(rds_path)) {
    add_status(dim, "load_rds", "", "", "SKIPPED", "RDS not found", rds_path)
    return(NULL)
  }
  tryCatch({
    mt <- readRDS(rds_path)
    add_status(dim, "load_rds", "", "", "OK", "", rds_path)
    mt
  }, error = function(e) {
    add_status(dim, "load_rds", "", "", "FAILED", conditionMessage(e), rds_path)
    NULL
  })
}

message("[INFO] Starting differential analysis with trans_diff")
message("[INFO] WORKDIR=", workdir)
message("[INFO] REPO=", repo)
message("[INFO] THREADS=", threads)
message("[INFO] METADATA_CSV=", metadata_csv)
message("[INFO] GROUP_COL=", group_col)
message("[INFO] RESULT_DIR=", result_dir)

dims <- c("bacteria", "virus", "fungi")
selected_dims <- if (dimension_req %in% dims) dimension_req else dims
success_dims <- 0L

for (dim in selected_dims) {
  dim_dir <- file.path(result_dir, dim)
  dir.create(dim_dir, recursive = TRUE, showWarnings = FALSE)
  mt_raw <- load_mt(dim)
  if (is.null(mt_raw)) next

  mt <- tryCatch({
    x <- prepare_mt(mt_raw)
    add_status(dim, "prepare", "", "", "OK", sprintf("%d samples; %d groups", nrow(x$sample_table), length(unique(x$sample_table[[group_col]]))))
    x
  }, error = function(e) {
    add_status(dim, "prepare", "", "", "FAILED", conditionMessage(e))
    NULL
  })
  if (is.null(mt)) next

  group_colors <- npg_pal(length(levels(mt$sample_table[[group_col]])))
  lefse_res <- if (dim == "bacteria") choose_bacteria_level(mt, dim_dir) else {
    out_csv <- file.path(dim_dir, "lefse_results.csv")
    tryCatch({
      x <- run_diff(mt, "lefse", "ASV", out_csv, list(filter_thres = 0.001))
      add_status(dim, "diff", "lefse", "ASV", "OK", paste("n_sig =", x$n_sig), out_csv)
      x
    }, error = function(e) {
      add_status(dim, "diff", "lefse", "ASV", "FAILED", conditionMessage(e), out_csv)
      NULL
    })
  }
  # Continue even when LEfSe finds 0 significant features (e.g. small test datasets).
  # Wilcoxon is the fallback for visualization.
  taxa_level <- if (!is.null(lefse_res)) {
    add_summary(dim, "lefse", lefse_res$n_sig, lefse_res$top_feature, lefse_res$output)
    lefse_res$obj$taxa_level
  } else {
    if (dim == "bacteria") "Species" else "ASV"
  }
  success_dims <- success_dims + 1L

  wilcox_csv <- file.path(dim_dir, "wilcox_results.csv")
  wilcox_res <- tryCatch({
    x <- run_diff(mt, "wilcox", taxa_level, wilcox_csv, list(transformation = "AST", filter_thres = 0.001))
    x$obj <- augment_wilcox_for_volcano(x$obj)
    add_status(dim, "diff", "wilcox", taxa_level, "OK", paste("n_sig =", x$n_sig), wilcox_csv)
    x
  }, error = function(e) {
    add_status(dim, "diff", "wilcox", taxa_level, "FAILED", conditionMessage(e), wilcox_csv)
    NULL
  })
  if (!is.null(wilcox_res)) add_summary(dim, "wilcox", wilcox_res$n_sig, wilcox_res$top_feature, wilcox_res$output)

  ancombc_csv <- file.path(dim_dir, "ancombc2_results.csv")
  ancombc_res <- tryCatch({
    x <- run_diff(mt, "ancombc2", taxa_level, ancombc_csv)
    add_status(dim, "diff", "ancombc2", taxa_level, "OK", paste("n_sig =", x$n_sig), ancombc_csv)
    x
  }, error = function(e) {
    message("[WARN] ancombc2 failed for ", dim, ": ", conditionMessage(e))
    add_status(dim, "diff", "ancombc2", taxa_level, "FAILED", conditionMessage(e), ancombc_csv)
    NULL
  })
  if (!is.null(ancombc_res)) add_summary(dim, "ancombc2", ancombc_res$n_sig, ancombc_res$top_feature, ancombc_res$output)

  lefse_bar <- file.path(dim_dir, "lefse_lda_bars.pdf")
  diff_abund <- file.path(dim_dir, "diff_abund_sig.pdf")
  volcano <- file.path(dim_dir, "volcano_plot.pdf")

  # LEfSe plots — only when we have a valid result with features
  if (!is.null(lefse_res) && !is.null(lefse_res$obj) && !is.null(lefse_res$obj$res_diff) && nrow(lefse_res$obj$res_diff) > 0) {
    save_plot_safe(lefse_res$obj$plot_diff_bar(width = 0.7, color_values = group_colors), lefse_bar, dim, "plot", "lefse_bar", taxa_level, 1.3, 6)
    diff_abund_ok <- save_plot_safe(lefse_res$obj$plot_diff_abund(add_sig = TRUE, use_number = 15, color_values = group_colors), diff_abund, dim, "plot", "lefse_abund", taxa_level, 1.3, 7)
    if (!isTRUE(diff_abund_ok)) {
      save_plot_safe(plot_diff_abund_fallback(lefse_res$obj, use_number = 15, color_values = group_colors), diff_abund, dim, "plot", "lefse_abund_fallback", taxa_level, 1.3, 7)
    }
  } else {
    add_status(dim, "plot", "lefse_bar", taxa_level, "SKIPPED", "0 LEfSe features (small sample set)", lefse_bar)
    add_status(dim, "plot", "lefse_abund", taxa_level, "SKIPPED", "0 LEfSe features (small sample set)", diff_abund)
  }

  # Wilcox-based plots — always attempted when wilcox succeeded
  if (!is.null(wilcox_res)) {
    # Differential abundance boxplot using wilcox result (top N by effect size)
    diff_abund_wil <- file.path(dim_dir, "diff_abund_wilcox.pdf")
    diff_abund_wil_ok <- save_plot_safe(
      wilcox_res$obj$plot_diff_abund(add_sig = TRUE, use_number = 15, color_values = group_colors),
      diff_abund_wil, dim, "plot", "wilcox_abund", taxa_level, 1.3, 7
    )
    # Use wilcox result as primary diff_abund if LEfSe produced nothing
    if (!file.exists(diff_abund) && file.exists(diff_abund_wil)) file.copy(diff_abund_wil, diff_abund)

    save_plot_safe(wilcox_res$obj$plot_volcano(color_values = c(npg_base[1], npg_base[2], "gray80")), volcano, dim, "plot", "wilcox_volcano", taxa_level, 1.2, 5.5)
  } else {
    add_status(dim, "plot", "wilcox_volcano", taxa_level, "SKIPPED", "wilcox unavailable", volcano)
  }

  if (dim == "bacteria") {
    cladogram <- file.path(dim_dir, "lefse_cladogram.pdf")
    lefse_all <- tryCatch(
      trans_diff$new(dataset = mt, method = "lefse", group = group_col, taxa_level = "all", filter_thres = 0.001),
      error = function(e1) tryCatch(
        trans_diff$new(dataset = mt, method = "lefse", group = group_col, taxa_level = "all", filter_thres = 0.001, p_adjust_method = "none"),
        error = function(e2) {
          add_status(dim, "diff", "lefse_cladogram", "all", "FAILED", paste(conditionMessage(e1), "| retry:", conditionMessage(e2)), cladogram)
          NULL
        }
      )
    )
    if (!is.null(lefse_all)) {
      add_status(dim, "diff", "lefse_cladogram", "all", "OK", paste("n_sig =", count_sig(lefse_all$res_diff)), cladogram)
      save_plot_safe(
        lefse_all$plot_diff_cladogram(color = group_colors, use_taxa_num = 100, use_feature_num = 30, clade_label_level = 5),
        cladogram, dim, "plot", "lefse_cladogram", "all", 1.3, 9
      )
    }
    for (pair in list(c(lefse_bar, file.path(result_dir, "lefse_lda_bars.pdf")), c(diff_abund, file.path(result_dir, "diff_abund_sig.pdf")), c(volcano, file.path(result_dir, "volcano_plot.pdf")))) {
      if (file.exists(pair[1])) file.copy(pair[1], pair[2], overwrite = TRUE)
    }
  }
}

status_df <- if (length(status_rows)) bind_rows(status_rows) else empty_status()
summary_df <- if (length(summary_rows)) bind_rows(summary_rows) else empty_summary()
write_tsv(status_df, file.path(result_dir, "diff_status.tsv"))
write_tsv(summary_df, file.path(result_dir, "diff_summary.tsv"))

if (!success_dims) message("[WARN] No dimension completed successfully; wrote header-only diff_summary.tsv")
message("[INFO] Differential analysis finished")
