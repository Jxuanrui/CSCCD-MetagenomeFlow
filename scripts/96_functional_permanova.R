#!/usr/bin/env Rscript
# 96_functional_permanova.R - PERMANOVA analysis for functional composition
# Outputs: result/stat/{dimension}/functional/
#   - permanova_summary.tsv
#   - permanova_bubble.{pdf,svg,tiff}
#   - {dimension}_permanova_status.tsv
#   - {dimension}_permanova_done.txt

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    return(y)
  }
  if (length(x) == 1 && is.character(x) && !nzchar(x)) {
    return(y)
  }
  x
}

show_help <- function() {
  cat(
    "Usage: Rscript 96_functional_permanova.R [-w WORKDIR] [-r REPO] [-m METADATA_CSV] [-g GROUP_COL] [-d DIMENSION] [-p PERMUTATIONS]\n",
    "\n",
    "Optional:\n",
    "  -w, --workdir       Project work directory (default: WORKDIR env or current directory)\n",
    "  -r, --repo          Repository root (default: REPO env)\n",
    "  -m, --metadata      Metadata CSV/TSV (default: METADATA_CSV env or result/stat/metadata.tsv)\n",
    "  -d, --dimension     bacteria|fungi|virus (default: DIMENSION env or bacteria)\n",
    "  -g, --group-col     Metadata group column (default: GROUP_COL env or group)\n",
    "  -p, --permutations  PERMANOVA permutations (default: PERMUTATIONS env or 999)\n",
    "  -h, --help          Show this help message\n",
    sep = ""
  )
}

parse_cli_args <- function(args) {
  opts <- list()
  i <- 1
  next_value <- function(flag) {
    if (i >= length(args)) {
      stop("Missing value for argument: ", flag)
    }
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
    } else if (flag %in% c("-p", "--permutations")) {
      opts$permutations <- next_value(flag); i <- i + 2
    } else if (flag == "--force") {
      i <- i + 1
    } else {
      stop("Unknown argument: ", flag)
    }
  }
  opts
}

cli_opts <- parse_cli_args(commandArgs(trailingOnly = TRUE))

workdir      <- cli_opts$workdir %||% Sys.getenv("WORKDIR") %||% getwd()
repo         <- cli_opts$repo %||% Sys.getenv("REPO") %||% getwd()
metadata_csv <- cli_opts$metadata_csv %||% Sys.getenv("METADATA_CSV")
group_col    <- cli_opts$group_col %||% Sys.getenv("GROUP_COL") %||% "group"
stat_root    <- Sys.getenv("STAT_ROOT") %||% file.path(workdir, "result", "stat")
dimension    <- tolower(cli_opts$dimension %||% Sys.getenv("DIMENSION") %||% "bacteria")
out_dir      <- Sys.getenv("OUT_DIR") %||% file.path(stat_root, dimension, "functional")
sentinel     <- Sys.getenv("SENTINEL") %||% file.path(out_dir, sprintf("%s_permanova_done.txt", dimension))
status_tsv   <- file.path(out_dir, sprintf("%s_permanova_status.tsv", dimension))
summary_tsv  <- file.path(out_dir, "permanova_summary.tsv")
permutations <- suppressWarnings(as.integer(
  cli_opts$permutations %||% Sys.getenv("PERMUTATIONS") %||% "999"
))
if (is.na(permutations) || permutations < 1) {
  stop("PERMUTATIONS must be a positive integer")
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

status_steps <- c("data_loading", "permanova_analysis", "visualization", "export")
status_log <- data.frame(
  step = status_steps,
  status = "PENDING",
  message = "",
  stringsAsFactors = FALSE
)

write_status <- function() {
  utils::write.table(status_log, status_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
}

timestamp_now <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

update_status <- function(step, status, message = "") {
  idx <- match(step, status_log$step)
  if (is.na(idx)) {
    stop("Unknown status step: ", step)
  }
  status_log$status[idx] <<- status
  status_log$message[idx] <<- sprintf("%s | %s", timestamp_now(), as.character(message %||% ""))
  write_status()
}

mark_pending_failed <- function(message) {
  pending <- which(status_log$status == "PENDING")
  if (length(pending)) {
    status_log$status[pending] <<- "FAIL"
    status_log$message[pending] <<- sprintf(
      "%s | Skipped after prior failure: %s",
      timestamp_now(),
      as.character(message)
    )
    write_status()
  }
}

extract_result_field <- function(x, field, default) {
  if (is.list(x) && !is.null(x[[field]])) {
    x[[field]]
  } else {
    default
  }
}

run_step <- function(step, expr) {
  tryCatch({
    result <- eval.parent(substitute(expr))
    update_status(step, "OK", extract_result_field(result, "message", ""))
    invisible(result)
  }, error = function(e) {
    msg <- conditionMessage(e)
    update_status(step, "FAIL", msg)
    mark_pending_failed(msg)
    stop("Required step failed: ", step, ": ", msg, call. = FALSE)
  })
}

write_status()

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("vegan", "ggplot2", "dplyr", "ggsci", "svglite", "ragg")

load_dependencies <- function() {
  miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) {
    stop(
      "Missing packages: ", paste(miss, collapse = ", "),
      ". Install them in the r_stat environment, for example: conda install -c conda-forge ",
      paste(paste0("r-", miss), collapse = " ")
    )
  }

  suppressPackageStartupMessages({
    library(vegan)
    library(ggplot2)
    library(dplyr)
    library(ggsci)
  })
  invisible(TRUE)
}

grDevices::pdf(file = NULL)

mm2in <- function(x) x / 25.4
sci_linewidth <- 0.35 / 0.353
sci_text_size <- 7 / (72.27 / 25.4)

theme_pub <- function(base_size = 7, base_family = "Arial") {
  ggplot2::theme_bw(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      line = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.line = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.title = ggplot2::element_text(size = base_size + 1),
      axis.text = ggplot2::element_text(size = base_size, colour = "black"),
      legend.title = ggplot2::element_text(size = base_size, face = "bold"),
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
  write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi, compression = "lzw"))
  invisible(paste0(path_noext, ".svg"))
}

assignment_name <- function(expr) {
  if (!is.call(expr) || !is.symbol(expr[[1]])) {
    return(NULL)
  }
  op <- as.character(expr[[1]])
  if (!op %in% c("<-", "=") || length(expr) < 3 || !is.symbol(expr[[2]])) {
    return(NULL)
  }
  as.character(expr[[2]])
}

load_functional_api <- function(repo) {
  source_file <- file.path(repo, "scripts", "96_stat_functional.R")
  if (!file.exists(source_file)) {
    stop("Functional analysis source script not found: ", source_file)
  }

  helper_env <- new.env(parent = baseenv())
  wanted <- c("functional_source_map", "load_functional_matrix")
  exprs <- parse(file = source_file, keep.source = FALSE)
  for (expr in exprs) {
    target <- assignment_name(expr)
    if (!is.null(target) && target %in% wanted) {
      eval(expr, envir = helper_env)
    }
  }

  missing_helpers <- wanted[!vapply(wanted, exists, logical(1), envir = helper_env, inherits = FALSE)]
  if (length(missing_helpers)) {
    stop("Could not extract helpers from 96_stat_functional.R: ", paste(missing_helpers, collapse = ", "))
  }

  list(
    functional_source_map = get("functional_source_map", envir = helper_env),
    load_functional_matrix = get("load_functional_matrix", envir = helper_env),
    source_file = source_file
  )
}

read_metadata_table <- function(metadata_csv, stat_root, group_col) {
  metadata_file <- metadata_csv
  if (!nzchar(metadata_file)) {
    metadata_file <- file.path(stat_root, "metadata.tsv")
  }
  if (!file.exists(metadata_file)) {
    stop("Metadata not found at: ", metadata_file)
  }

  ext <- tolower(tools::file_ext(metadata_file))
  metadata <- if (identical(ext, "csv")) {
    utils::read.csv(metadata_file, check.names = FALSE, stringsAsFactors = FALSE)
  } else {
    utils::read.delim(metadata_file, sep = "\t", header = TRUE, check.names = FALSE,
                      comment.char = "", stringsAsFactors = FALSE)
  }

  if (!nrow(metadata)) {
    stop("Metadata has zero rows: ", metadata_file)
  }

  if (!"sample_id" %in% colnames(metadata)) {
    sample_col <- colnames(metadata)[[1]]
    metadata$sample_id <- metadata[[sample_col]]
  }
  metadata$sample_id <- trimws(as.character(metadata$sample_id))
  metadata <- metadata[nzchar(metadata$sample_id), , drop = FALSE]

  if (anyDuplicated(metadata$sample_id)) {
    duplicated_ids <- unique(metadata$sample_id[duplicated(metadata$sample_id)])
    stop("Duplicated sample_id values in metadata: ", paste(head(duplicated_ids, 10), collapse = ", "))
  }
  if (!group_col %in% colnames(metadata)) {
    stop("Group column '", group_col, "' not found in metadata")
  }

  metadata[[group_col]] <- trimws(as.character(metadata[[group_col]]))
  metadata
}

empty_permanova_result <- function(func_type, error_message) {
  data.frame(
    dimension = dimension,
    func_type = func_type,
    n_features = NA_integer_,
    n_samples = NA_integer_,
    n_groups = NA_integer_,
    R2 = NA_real_,
    F_statistic = NA_real_,
    p_value = NA_real_,
    error = gsub("[\r\n\t]+", " ", as.character(error_message)),
    stringsAsFactors = FALSE
  )
}

extract_sample_feature_matrix <- function(functional_matrix) {
  if (!is.list(functional_matrix) || !"data" %in% names(functional_matrix)) {
    stop("load_functional_matrix() returned an unexpected object")
  }
  functional_df <- functional_matrix$data
  if (!"sample_id" %in% colnames(functional_df)) {
    stop("Functional matrix does not contain sample_id")
  }

  feature_cols <- setdiff(colnames(functional_df), "sample_id")
  if (!length(feature_cols)) {
    stop("Functional matrix has no feature columns")
  }

  abundance <- as.matrix(functional_df[, feature_cols, drop = FALSE])
  storage.mode(abundance) <- "numeric"
  if (any(!is.finite(abundance))) {
    stop("Functional matrix contains non-finite abundance values")
  }
  if (any(abundance < 0)) {
    stop("Bray-Curtis PERMANOVA requires non-negative abundance values")
  }

  rownames(abundance) <- as.character(functional_df$sample_id)
  abundance
}

run_permanova_one <- function(func_type) {
  tryCatch({
    functional_matrix <- load_functional_matrix(workdir, dimension, func_type)
    abundance <- extract_sample_feature_matrix(functional_matrix)

    common_samples <- intersect(metadata$sample_id, rownames(abundance))
    if (length(common_samples) < 3) {
      stop("Fewer than 3 matched samples between metadata and abundance table")
    }

    abundance <- abundance[common_samples, , drop = FALSE]
    metadata_sub <- metadata[match(common_samples, metadata$sample_id), , drop = FALSE]

    valid_group <- !is.na(metadata_sub[[group_col]]) & nzchar(metadata_sub[[group_col]])
    if (!all(valid_group)) {
      abundance <- abundance[valid_group, , drop = FALSE]
      metadata_sub <- metadata_sub[valid_group, , drop = FALSE]
    }
    if (nrow(abundance) < 3) {
      stop("Fewer than 3 samples remain after removing missing group labels")
    }

    group_factor <- factor(metadata_sub[[group_col]])
    if (nlevels(group_factor) < 2) {
      stop("PERMANOVA requires at least 2 groups")
    }

    prevalence <- colSums(abundance > 0) / nrow(abundance)
    keep_features <- prevalence >= 0.10
    abundance <- abundance[, keep_features, drop = FALSE]
    if (ncol(abundance) < 1) {
      stop("No functional features retained after prevalence >= 10% filtering")
    }

    nonempty_samples <- rowSums(abundance) > 0
    if (!all(nonempty_samples)) {
      abundance <- abundance[nonempty_samples, , drop = FALSE]
      metadata_sub <- metadata_sub[nonempty_samples, , drop = FALSE]
      group_factor <- factor(metadata_sub[[group_col]])
    }
    if (nrow(abundance) < 3) {
      stop("Fewer than 3 non-empty samples remain after filtering")
    }
    if (nlevels(group_factor) < 2) {
      stop("Fewer than 2 groups remain after filtering")
    }

    dist_mat <- vegan::vegdist(abundance, method = "bray")
    if (any(!is.finite(as.vector(dist_mat)))) {
      stop("Bray-Curtis distance contains non-finite values")
    }

    adonis_data <- data.frame(permanova_group = group_factor)
    rownames(adonis_data) <- rownames(abundance)

    set.seed(123)
    perm_result <- vegan::adonis2(
      dist_mat ~ permanova_group,
      data = adonis_data,
      permutations = permutations
    )

    data.frame(
      dimension = dimension,
      func_type = func_type,
      n_features = ncol(abundance),
      n_samples = nrow(abundance),
      n_groups = nlevels(group_factor),
      R2 = perm_result$R2[1],
      F_statistic = perm_result$F[1],
      p_value = perm_result$`Pr(>F)`[1],
      error = "",
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    cat(sprintf("    Error: %s\n", conditionMessage(e)))
    empty_permanova_result(func_type, conditionMessage(e))
  })
}

build_bubble_plot <- function(results_df) {
  plot_df <- results_df %>%
    dplyr::filter(!is.na(R2), !is.na(F_statistic), !is.na(p_value))
  if (!nrow(plot_df)) {
    stop("No successful PERMANOVA rows available for plotting")
  }

  max_r2 <- max(plot_df$R2, na.rm = TRUE)
  ymax <- max(0.05, max_r2 * 1.15)

  ggplot2::ggplot(plot_df, ggplot2::aes(x = reorder(func_type, R2), y = R2)) +
    ggplot2::geom_point(ggplot2::aes(size = F_statistic, color = p_value), alpha = 0.7) +
    ggplot2::scale_size_continuous(name = "F-statistic", range = c(3, 12)) +
    ggplot2::scale_color_gradient2(
      low = "#E64B35",
      mid = "#F39B7F",
      high = "#BBBBBB",
      midpoint = 0.05,
      name = "p-value",
      limits = c(0, 1)
    ) +
    ggplot2::geom_hline(
      yintercept = 0.05,
      linetype = "dashed",
      color = "grey50",
      linewidth = sci_linewidth
    ) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.3f", R2)),
      vjust = -1.2,
      size = sci_text_size,
      color = "black"
    ) +
    ggplot2::labs(
      title = paste0("PERMANOVA: ", toupper(dimension), " Functional Composition"),
      subtitle = sprintf("Overall group difference (Bray-Curtis distance, %d permutations)", permutations),
      x = "Functional Type",
      y = expression(R^2 ~ "(Effect Size)")
    ) +
    theme_pub(base_size = 7) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)) +
    ggplot2::coord_cartesian(ylim = c(0, ymax))
}

cat("[INFO] Starting functional PERMANOVA\n")
cat("  Workdir:", workdir, "\n")
cat("  Repo:", repo, "\n")
cat("  Dimension:", dimension, "\n")
cat("  Metadata:", metadata_csv %||% file.path(stat_root, "metadata.tsv"), "\n")
cat("  Group column:", group_col, "\n")
cat("  Permutations:", permutations, "\n")
cat("  Output directory:", out_dir, "\n")

run_step("data_loading", {
  load_dependencies()
  theme_set(theme_pub())

  api <- load_functional_api(repo)
  functional_source_map <- api$functional_source_map
  load_functional_matrix <- api$load_functional_matrix

  valid_dimensions <- names(functional_source_map)
  if (!dimension %in% valid_dimensions) {
    stop("Invalid dimension: ", dimension)
  }
  func_types <- names(functional_source_map[[dimension]])
  if (!length(func_types)) {
    stop("No functional types configured for dimension: ", dimension)
  }

  metadata <- read_metadata_table(metadata_csv, stat_root, group_col)
  cat("  Functional API:", api$source_file, "\n")
  cat("  Functional databases:", paste(func_types, collapse = ", "), "\n")
  cat(sprintf("  Metadata: %d samples\n", nrow(metadata)))

  list(message = sprintf("Loaded %d func_types and %d metadata samples", length(func_types), nrow(metadata)))
})

run_step("permanova_analysis", {
  permanova_results <- list()
  for (func_type in func_types) {
    cat(sprintf("  Processing %s/%s...\n", dimension, func_type))
    permanova_results[[func_type]] <- run_permanova_one(func_type)
  }

  results_df <- do.call(rbind, permanova_results)
  rownames(results_df) <- NULL
  utils::write.table(results_df, summary_tsv, sep = "\t", row.names = FALSE, quote = FALSE)

  n_ok <- sum(!is.na(results_df$R2))
  cat(sprintf("  PERMANOVA completed for %d/%d functional databases\n", n_ok, nrow(results_df)))
  cat("  Summary:", summary_tsv, "\n")

  if (n_ok == 0) {
    stop("No successful PERMANOVA results; summary written to: ", summary_tsv)
  }

  list(message = sprintf("Completed PERMANOVA for %d/%d func_types", n_ok, nrow(results_df)))
})

run_step("visualization", {
  p_bubble <- build_bubble_plot(results_df)
  list(message = "Bubble plot prepared")
})

run_step("export", {
  export_pub_figure(
    p_bubble,
    file.path(out_dir, "permanova_bubble"),
    width_mm = 140,
    height_mm = 120
  )

  expected_files <- c(
    summary_tsv,
    paste0(file.path(out_dir, "permanova_bubble"), c(".pdf", ".svg", ".tiff"))
  )
  missing_files <- expected_files[!file.exists(expected_files) | file.info(expected_files)$size <= 0]
  if (length(missing_files)) {
    stop("Expected output files missing or empty: ", paste(missing_files, collapse = ", "))
  }

  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), sentinel)
  list(message = sprintf("Verified %d output files", length(expected_files)))
})

cat("[INFO] Functional PERMANOVA completed\n")
cat("  Summary:", summary_tsv, "\n")
cat("  Status:", status_tsv, "\n")
cat("  Sentinel:", sentinel, "\n")
