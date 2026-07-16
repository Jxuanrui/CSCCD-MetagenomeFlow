# Deprecated 2026-07-16: superseded by 91_diversity.R due to directory-convention duplication.
#!/usr/bin/env Rscript
# 02_alpha_diversity.R - Alpha diversity analysis for bacteria, fungi, and virus
# Outputs: result/stat/{dimension}/diversity/
#   - alpha_diversity_indices.tsv
#   - alpha_comparison_stats.tsv
#   - alpha_boxplot_comparison.{pdf,svg,tiff}
#   - {dimension}_alpha_diversity_status.tsv

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(as.character(x)[1])) y else x
}

show_help <- function() {
  cat(
    "Usage: Rscript 02_alpha_diversity.R [-w WORKDIR] [-r REPO] [-m METADATA_TSV] [-d DIMENSION]\n",
    "\n",
    "Optional:\n",
    "  -w, --workdir      Project work directory (default: WORKDIR env or current directory)\n",
    "  -r, --repo         Repository root (default: REPO env)\n",
    "  -m, --metadata     Metadata TSV/CSV (default: METADATA_CSV env or result/stat/metadata.tsv)\n",
    "  -d, --dimension    bacteria|fungi|virus (default: DIMENSION env or bacteria)\n",
    "  -g, --group-col    Metadata group column (default: GROUP_COL env or group)\n",
    "  --force            Accepted for wrapper compatibility\n",
    "  -h, --help         Show this help message\n",
    sep = ""
  )
}

parse_cli_args <- function(args) {
  opts <- list()
  i <- 1
  next_value <- function(flag) {
    if (i >= length(args)) stop("Missing value for argument: ", flag)
    args[[i + 1]]
  }

  while (i <= length(args)) {
    flag <- args[[i]]
    if (flag %in% c("-h", "--help")) {
      show_help()
      quit(status = 0)
    } else if (flag %in% c("-w", "--workdir")) {
      opts$workdir <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-r", "--repo")) {
      opts$repo <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-m", "--metadata")) {
      opts$metadata_csv <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-d", "--dimension")) {
      opts$dimension <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-g", "--group-col")) {
      opts$group_col <- next_value(flag); i <- i + 2
    } else if (identical(flag, "--force")) {
      i <- i + 1
    } else {
      stop("Unknown argument: ", flag)
    }
  }
  opts
}

cli_opts <- parse_cli_args(commandArgs(trailingOnly = TRUE))

workdir <- cli_opts$workdir %||% Sys.getenv("WORKDIR") %||% getwd()
repo <- cli_opts$repo %||% Sys.getenv("REPO")
metadata_csv <- cli_opts$metadata_csv %||% Sys.getenv("METADATA_CSV")
group_col <- cli_opts$group_col %||% Sys.getenv("GROUP_COL") %||% "group"
dimension <- tolower(cli_opts$dimension %||% Sys.getenv("DIMENSION") %||% "bacteria")
stat_root <- Sys.getenv("STAT_ROOT") %||% file.path(workdir, "result", "stat")
out_dir <- Sys.getenv("OUT_DIR") %||% file.path(stat_root, dimension, "diversity")
sentinel <- Sys.getenv("SENTINEL") %||% file.path(out_dir, paste0(dimension, "_alpha_diversity_done.txt"))

if (!dimension %in% c("bacteria", "fungi", "virus")) {
  stop("Invalid dimension: ", dimension)
}
if (!nzchar(metadata_csv)) {
  metadata_csv <- file.path(workdir, "result", "stat", "metadata.tsv")
}

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

required_pkgs <- c("vegan", "ggplot2", "dplyr", "tidyr", "rstatix", "ggpubr", "patchwork", "svglite", "ragg")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {
  stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(vegan)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(rstatix)
  library(ggpubr)
  library(patchwork)
})

grDevices::pdf(file = NULL)

mm2in <- function(x) x / 25.4
sci_linewidth <- 0.35 / 0.353
sci_text_size <- 7 / ggplot2::.pt
width_2col <- 183

theme_pub <- function(base_size = 7, base_family = "Arial") {
  ggplot2::theme_bw(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      line = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.line = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.title = ggplot2::element_text(size = base_size + 1),
      axis.text = ggplot2::element_text(size = base_size, colour = "black"),
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = base_size),
      legend.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(size = base_size + 1, face = "bold"),
      plot.title = ggplot2::element_text(size = base_size + 2, face = "bold"),
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.border = ggplot2::element_rect(linewidth = sci_linewidth, colour = "black", fill = NA),
      panel.grid = ggplot2::element_blank()
    )
}

export_pub_figure <- function(plot, path_noext, width_mm, height_mm, dpi = 600) {
  w <- mm2in(width_mm)
  h <- mm2in(height_mm)

  write_device <- function(open_device) {
    open_device()
    dev_id <- grDevices::dev.cur()
    on.exit({
      if (grDevices::dev.cur() == dev_id) {
        try(grDevices::dev.off(), silent = TRUE)
      }
    }, add = TRUE)
    print(plot)
    grDevices::dev.off()
    invisible(TRUE)
  }

  write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h))
  write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"))
  write_device(function() ragg::agg_tiff(
    paste0(path_noext, ".tiff"),
    width = w,
    height = h,
    units = "in",
    res = dpi,
    compression = "lzw"
  ))
  invisible(paste0(path_noext, ".svg"))
}

theme_set(theme_pub())

status_tsv <- file.path(out_dir, paste0(dimension, "_alpha_diversity_status.tsv"))
status_log <- list()

write_status <- function() {
  df <- if (length(status_log)) {
    do.call(rbind, status_log)
  } else {
    data.frame(step = character(), status = character(), message = character(),
               stringsAsFactors = FALSE)
  }
  utils::write.table(df, status_tsv, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
}

append_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- data.frame(
    step = step,
    status = status,
    message = as.character(message),
    stringsAsFactors = FALSE
  )
}

run_step <- function(step, expr) {
  t0 <- proc.time()[["elapsed"]]
  tryCatch({
    value <- force(expr)
    elapsed <- round(proc.time()[["elapsed"]] - t0, 2)
    append_status(step, "OK", paste0("elapsed_sec=", elapsed))
    value
  }, error = function(e) {
    append_status(step, "FAILED", conditionMessage(e))
    write_status()
    stop("Step failed [", step, "]: ", conditionMessage(e), call. = FALSE)
  })
}

on.exit(write_status(), add = TRUE)

write_tsv <- function(x, path) {
  utils::write.table(x, path, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
}

read_feature_matrix <- function(path, skip = 0, feature_label = "feature") {
  if (!file.exists(path)) {
    stop("Input table not found: ", path)
  }

  raw <- utils::read.delim(
    path,
    skip = skip,
    header = TRUE,
    row.names = 1,
    check.names = FALSE,
    comment.char = "",
    quote = "",
    stringsAsFactors = FALSE
  )
  if (!nrow(raw) || !ncol(raw)) {
    stop("Input table is empty: ", path)
  }

  raw[] <- lapply(raw, function(x) suppressWarnings(as.numeric(x)))
  mat <- as.matrix(raw)
  storage.mode(mat) <- "numeric"
  if (anyNA(mat)) {
    stop("Non-numeric abundance values detected in: ", path)
  }
  mat[!is.finite(mat)] <- 0
  mat[mat < 0] <- 0
  rownames(mat) <- make.unique(rownames(mat))
  colnames(mat) <- trimws(colnames(mat))
  mat <- mat[rowSums(mat, na.rm = TRUE) > 0, , drop = FALSE]
  if (!nrow(mat)) {
    stop("No non-zero ", feature_label, " rows in: ", path)
  }
  mat
}

load_metaphlan_species <- function(path, dimension_label) {
  mat <- read_feature_matrix(path, skip = 1, feature_label = paste0(dimension_label, " species"))
  species_rows <- grepl("(^|\\|)s__", rownames(mat)) & !grepl("(^|\\|)t__", rownames(mat))
  mat <- mat[species_rows, , drop = FALSE]
  mat <- mat[rowSums(mat, na.rm = TRUE) > 0, , drop = FALSE]
  if (nrow(mat) < 2) {
    stop("Fewer than 2 non-zero species rows after MetaPhlAn4 species filtering: ", path)
  }
  mat
}

load_bacteria_species <- function(workdir) {
  path <- Sys.getenv("BACTERIA_TABLE") %||%
    file.path(workdir, "result", "bacteria", "metaphlan4", "merged_abundance_table.txt")
  load_metaphlan_species(path, "bacteria")
}

load_fungi_species <- function(workdir) {
  path <- Sys.getenv("FUNGI_TABLE") %||%
    file.path(workdir, "result", "fungi", "metaphlan4", "merged_abundance_table.txt")
  load_metaphlan_species(path, "fungi")
}

load_virus_votu <- function(workdir) {
  path <- Sys.getenv("VIRUS_TABLE") %||%
    file.path(workdir, "result", "virus", "votu", "votu_table.tsv")
  read_feature_matrix(path, skip = 0, feature_label = "virus vOTU")
}

load_abundance_by_dimension <- function(workdir, dimension) {
  switch(
    dimension,
    bacteria = load_bacteria_species(workdir),
    fungi = load_fungi_species(workdir),
    virus = load_virus_votu(workdir),
    stop("Unsupported dimension: ", dimension)
  )
}

load_metadata <- function(path, group_col) {
  if (!file.exists(path)) {
    stop("Metadata file not found: ", path)
  }

  sep <- if (grepl("\\.csv$", path, ignore.case = TRUE)) "," else "\t"
  meta <- utils::read.table(
    path,
    header = TRUE,
    sep = sep,
    check.names = FALSE,
    quote = "",
    comment.char = "",
    stringsAsFactors = FALSE
  )
  if (!nrow(meta)) stop("Metadata file is empty: ", path)

  first_name <- names(meta)[1]
  sample_id_cols <- intersect(c("sample_id", "SampleID", "sample", "Sample", "id", "ID"), names(meta))
  if (length(sample_id_cols)) {
    names(meta)[match(sample_id_cols[1], names(meta))] <- "sample_id"
  } else if (!nzchar(first_name) || identical(first_name, "X") || !group_col %in% names(meta[, -1, drop = FALSE])) {
    names(meta)[1] <- "sample_id"
  } else {
    meta$sample_id <- rownames(meta)
  }

  if (!"sample_id" %in% names(meta)) {
    stop("Cannot identify sample_id column in metadata: ", path)
  }
  if (!group_col %in% names(meta)) {
    stop("Group column not found in metadata: ", group_col)
  }

  meta <- meta %>%
    dplyr::mutate(
      sample_id = as.character(.data$sample_id),
      !!group_col := as.character(.data[[group_col]])
    ) %>%
    dplyr::filter(!is.na(.data$sample_id), nzchar(.data$sample_id),
                  !is.na(.data[[group_col]]), nzchar(.data[[group_col]])) %>%
    dplyr::distinct(.data$sample_id, .keep_all = TRUE) %>%
    as.data.frame(stringsAsFactors = FALSE)

  if (!nrow(meta)) {
    stop("No metadata rows with non-empty sample_id and group: ", path)
  }
  rownames(meta) <- meta$sample_id
  meta
}

make_chao_counts <- function(abundance_t, pseudo_depth = 10000L) {
  x <- abundance_t
  x[!is.finite(x) | is.na(x) | x < 0] <- 0
  nonzero <- x[x > 0]
  integerish <- !length(nonzero) || all(abs(nonzero - round(nonzero)) < 1e-8)
  if (integerish) {
    return(round(x))
  }

  row_totals <- rowSums(x, na.rm = TRUE)
  counts <- matrix(0, nrow = nrow(x), ncol = ncol(x), dimnames = dimnames(x))
  valid <- row_totals > 0
  if (any(valid)) {
    props <- sweep(x[valid, , drop = FALSE], 1, row_totals[valid], "/")
    counts_valid <- round(props * pseudo_depth)
    counts_valid[x[valid, , drop = FALSE] > 0 & counts_valid < 1] <- 1
    counts[valid, ] <- counts_valid
  }
  storage.mode(counts) <- "numeric"
  counts
}

calculate_chao1 <- function(abundance_t, observed) {
  chao_counts <- make_chao_counts(abundance_t)
  estimate <- tryCatch(
    vegan::estimateR(chao_counts),
    error = function(e) NULL
  )

  if (is.null(estimate) || !"S.chao1" %in% rownames(estimate)) {
    chao1 <- vapply(seq_len(nrow(chao_counts)), function(i) {
      est_i <- tryCatch(vegan::estimateR(chao_counts[i, ]), error = function(e) NULL)
      if (is.null(est_i) || !"S.chao1" %in% names(est_i)) return(NA_real_)
      as.numeric(est_i[["S.chao1"]])
    }, numeric(1))
    names(chao1) <- rownames(chao_counts)
  } else {
    chao1 <- as.numeric(estimate["S.chao1", ])
    names(chao1) <- colnames(estimate)
  }

  chao1 <- chao1[rownames(abundance_t)]
  bad <- is.na(chao1) | !is.finite(chao1)
  chao1[bad] <- observed[bad]
  chao1 <- pmax(chao1, observed, na.rm = TRUE)
  chao1
}

calculate_alpha_diversity <- function(abundance_matrix) {
  abundance_t <- t(abundance_matrix)
  abundance_t[!is.finite(abundance_t) | is.na(abundance_t) | abundance_t < 0] <- 0

  shannon <- vegan::diversity(abundance_t, index = "shannon")
  simpson <- vegan::diversity(abundance_t, index = "simpson")
  observed <- rowSums(abundance_t > 0)
  chao1 <- calculate_chao1(abundance_t, observed)

  data.frame(
    sample_id = rownames(abundance_t),
    shannon = as.numeric(shannon),
    simpson = as.numeric(simpson),
    observed = as.integer(observed),
    chao1 = as.numeric(chao1),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

prepare_grouped_alpha <- function(alpha_df, metadata, group_col) {
  keep_meta <- metadata[, c("sample_id", group_col), drop = FALSE]
  alpha_grouped <- dplyr::inner_join(alpha_df, keep_meta, by = "sample_id")
  if (!nrow(alpha_grouped)) {
    stop("No overlapping samples between alpha diversity table and metadata")
  }

  groups <- unique(alpha_grouped[[group_col]])
  if (all(c("case", "control") %in% groups)) {
    alpha_grouped[[group_col]] <- factor(alpha_grouped[[group_col]], levels = c("case", "control"))
  } else {
    alpha_grouped[[group_col]] <- factor(alpha_grouped[[group_col]], levels = sort(groups))
  }
  alpha_grouped
}

compare_alpha_diversity <- function(alpha_grouped, group_col = "group") {
  groups <- levels(droplevels(alpha_grouped[[group_col]]))
  if (length(groups) != 2) {
    stop("Wilcoxon comparison requires exactly 2 groups; found: ", paste(groups, collapse = ", "))
  }

  indices <- c("shannon", "simpson", "observed", "chao1")
  results <- lapply(indices, function(idx) {
    df_idx <- alpha_grouped[!is.na(alpha_grouped[[idx]]) & !is.na(alpha_grouped[[group_col]]), , drop = FALSE]
    test <- suppressWarnings(stats::wilcox.test(df_idx[[idx]] ~ df_idx[[group_col]], exact = FALSE))
    vals_g1 <- df_idx[df_idx[[group_col]] == groups[1], idx, drop = TRUE]
    vals_g2 <- df_idx[df_idx[[group_col]] == groups[2], idx, drop = TRUE]

    data.frame(
      index = idx,
      statistic = unname(as.numeric(test$statistic)),
      p_value = test$p.value,
      group1 = groups[1],
      group2 = groups[2],
      n_group1 = length(vals_g1),
      n_group2 = length(vals_g2),
      median_group1 = stats::median(vals_g1, na.rm = TRUE),
      median_group2 = stats::median(vals_g2, na.rm = TRUE),
      median_case = if ("case" %in% groups) {
        stats::median(df_idx[df_idx[[group_col]] == "case", idx, drop = TRUE], na.rm = TRUE)
      } else {
        NA_real_
      },
      median_control = if ("control" %in% groups) {
        stats::median(df_idx[df_idx[[group_col]] == "control", idx, drop = TRUE], na.rm = TRUE)
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, results)
  out$p_adjust_fdr <- stats::p.adjust(out$p_value, method = "BH")
  out
}

generate_alpha_boxplot_grid <- function(alpha_df, dimension, out_dir) {
  indices <- c("shannon", "simpson", "observed", "chao1")
  index_labels <- c(
    shannon = "Shannon Index",
    simpson = "Simpson Index",
    observed = "Observed Richness",
    chao1 = "Chao1 Index"
  )

  required_cols <- c("sample_id", "group", indices)
  missing_cols <- setdiff(required_cols, names(alpha_df))
  if (length(missing_cols)) {
    stop("Alpha boxplot input is missing columns: ", paste(missing_cols, collapse = ", "))
  }

  alpha_df <- as.data.frame(alpha_df, stringsAsFactors = FALSE)
  alpha_df$group <- droplevels(factor(alpha_df$group))
  groups <- levels(alpha_df$group)
  if (length(groups) != 2) {
    stop("Alpha boxplot requires exactly 2 groups; found: ", paste(groups, collapse = ", "))
  }

  group_palette <- c(case = "#E64B35", control = "#4DBBD5")
  if (all(groups %in% names(group_palette))) {
    group_palette <- group_palette[groups]
  } else {
    group_palette <- stats::setNames(c("#E64B35", "#4DBBD5")[seq_along(groups)], groups)
  }

  plot_list <- list()

  for (idx in indices) {
    df_idx <- alpha_df[, c("sample_id", "group", idx)]
    colnames(df_idx)[3] <- "value"
    df_idx <- df_idx[!is.na(df_idx$value) & !is.na(df_idx$group), , drop = FALSE]
    df_idx$group <- factor(df_idx$group, levels = groups)

    pval <- suppressWarnings(
      df_idx %>%
        rstatix::wilcox_test(value ~ group, paired = FALSE) %>%
        rstatix::adjust_pvalue(method = "BH") %>%
        rstatix::add_significance(p.col = "p.adj") %>%
        rstatix::add_xy_position(x = "group")
    )

    p <- ggplot2::ggplot(df_idx, ggplot2::aes(x = group, y = value)) +
      ggplot2::geom_boxplot(
        ggplot2::aes(fill = group),
        staplewidth = 0.3,
        outlier.shape = NA,
        linewidth = sci_linewidth,
        width = 0.5
      ) +
      ggplot2::geom_point(
        position = ggplot2::position_jitter(width = 0.15),
        alpha = 0.25,
        size = 0.5,
        stroke = 0
      ) +
      ggpubr::stat_pvalue_manual(
        pval,
        label = "p.adj.signif",
        tip.length = 0.02,
        bracket.size = sci_linewidth,
        label.size = sci_text_size,
        hide.ns = FALSE
      ) +
      ggplot2::scale_fill_manual(values = group_palette, drop = FALSE) +
      ggplot2::labs(x = NULL, y = index_labels[[idx]]) +
      theme_pub() +
      ggplot2::theme(
        legend.position = "none",
        plot.margin = ggplot2::margin(3, 3, 3, 3)
      )

    plot_list[[idx]] <- p
  }

  p_combined <- (plot_list[["shannon"]] | plot_list[["simpson"]]) /
    (plot_list[["observed"]] | plot_list[["chao1"]]) +
    patchwork::plot_annotation(
      title = paste0(toupper(dimension), " Alpha Diversity Comparison"),
      theme = ggplot2::theme(plot.title = ggplot2::element_text(size = 9, face = "bold"))
    )

  export_pub_figure(
    p_combined,
    file.path(out_dir, "alpha_boxplot_comparison"),
    width_mm = 183,
    height_mm = 160
  )

  invisible(p_combined)
}

cat("[INFO] Starting alpha diversity analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Metadata:", metadata_csv, "\n")
cat("  Dimension:", dimension, "\n")
cat("  Output:", out_dir, "\n")

metadata <- run_step("load_metadata", {
  meta <- load_metadata(metadata_csv, group_col)
  append_status(
    "metadata_summary",
    "OK",
    paste0(nrow(meta), " samples; groups=", paste(table(meta[[group_col]]), collapse = "/"))
  )
  meta
})

abundance_matrix <- run_step("load_abundance", {
  mat <- load_abundance_by_dimension(workdir, dimension)
  append_status(
    "abundance_summary",
    "OK",
    paste0(nrow(mat), " features x ", ncol(mat), " samples")
  )
  mat
})

alpha_df <- run_step("calculate_alpha_diversity", {
  calculate_alpha_diversity(abundance_matrix)
})

invisible(run_step("write_alpha_diversity_indices", {
  out_path <- file.path(out_dir, "alpha_diversity_indices.tsv")
  write_tsv(alpha_df, out_path)
  append_status("alpha_indices_output", "OK", out_path)
}))

alpha_grouped <- run_step("merge_metadata", {
  grouped <- prepare_grouped_alpha(alpha_df, metadata, group_col)
  append_status(
    "overlap_summary",
    "OK",
    paste0(nrow(grouped), " overlapping samples; groups=", paste(table(grouped[[group_col]]), collapse = "/"))
  )
  grouped
})

comparison_stats <- run_step("compare_alpha_diversity", {
  compare_alpha_diversity(alpha_grouped, group_col)
})

invisible(run_step("write_alpha_comparison_stats", {
  out_path <- file.path(out_dir, "alpha_comparison_stats.tsv")
  write_tsv(comparison_stats, out_path)
  append_status("comparison_stats_output", "OK", out_path)
}))

invisible(run_step("export_alpha_figures", {
  legacy_figures <- c(
    paste0(file.path(out_dir, "alpha_violin_distribution"), c(".pdf", ".svg", ".tiff")),
    paste0(file.path(out_dir, "alpha_richness_shannon_correlation"), c(".pdf", ".svg", ".tiff"))
  )
  unlink(legacy_figures, force = TRUE)

  plot_alpha <- alpha_grouped
  if (!identical(group_col, "group")) {
    plot_alpha$group <- plot_alpha[[group_col]]
  }
  generate_alpha_boxplot_grid(plot_alpha, dimension, out_dir)

  append_status("figure_outputs", "OK", paste(
    paste0(file.path(out_dir, "alpha_boxplot_comparison"), c(".pdf", ".svg", ".tiff")),
    collapse = ";"
  ))
}))

invisible(run_step("write_sentinel", {
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), sentinel)
  append_status("sentinel", "OK", sentinel)
}))

append_status("write_status", "OK", status_tsv)
write_status()

cat("[INFO] Alpha diversity analysis completed\n")
cat("  Sentinel:", sentinel, "\n")
