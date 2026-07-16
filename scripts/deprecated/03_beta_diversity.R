# Deprecated 2026-07-16: superseded by 91_diversity.R due to directory-convention duplication.
#!/usr/bin/env Rscript
# 03_beta_diversity.R - Beta diversity analysis for bacteria, fungi, and virus
# Outputs: result/stat/{dimension}/diversity/
#   - beta_permanova_stats.tsv
#   - beta_pcoa_comparison.{pdf,svg,tiff}
#   - {dimension}_beta_diversity_status.tsv

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(as.character(x)[1])) y else x
}

show_help <- function() {
  cat(
    "Usage: Rscript 03_beta_diversity.R [-w WORKDIR] [-r REPO] [-m METADATA_TSV] [-d DIMENSION]\n",
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
sentinel <- Sys.getenv("SENTINEL") %||% file.path(out_dir, paste0(dimension, "_beta_diversity_done.txt"))

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

required_pkgs <- c("vegan", "ape", "ggplot2", "dplyr", "tidyr", "rstatix", "ggpubr", "patchwork", "MicrobiotaProcess", "ggsci", "svglite", "ragg")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {
  stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(vegan)
  library(ape)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(rstatix)
  library(ggpubr)
  library(patchwork)
  library(MicrobiotaProcess)
  library(ggsci)
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

status_tsv <- file.path(out_dir, paste0(dimension, "_beta_diversity_status.tsv"))
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

calculate_beta_diversity <- function(abundance_matrix, metadata, group_col) {
  abundance_df <- as.data.frame(t(abundance_matrix), check.names = FALSE)
  abundance_df[] <- lapply(abundance_df, function(x) {
    x <- suppressWarnings(as.numeric(x))
    x[!is.finite(x) | is.na(x) | x < 0] <- 0
    x
  })
  rownames(abundance_df) <- colnames(abundance_matrix)

  abundance_df <- abundance_df[rowSums(abundance_df, na.rm = TRUE) > 0, , drop = FALSE]
  if (nrow(abundance_df) < 2) {
    stop("Beta diversity requires at least 2 non-zero samples")
  }

  sample_ids <- rownames(abundance_df)
  keep <- sample_ids %in% metadata$sample_id
  abundance_df <- abundance_df[keep, , drop = FALSE]
  if (nrow(abundance_df) < 2) {
    stop("Beta diversity requires at least 2 samples with metadata")
  }

  metadata_subset <- metadata[match(rownames(abundance_df), metadata$sample_id), , drop = FALSE]
  if (anyNA(metadata_subset$sample_id)) {
    stop("Metadata matching failed for beta diversity samples")
  }

  metadata_subset <- metadata_subset[, unique(c("sample_id", group_col)), drop = FALSE]
  metadata_subset$group <- as.character(metadata_subset[[group_col]])
  groups <- unique(metadata_subset$group)
  if (all(c("case", "control") %in% groups)) {
    metadata_subset$group <- factor(metadata_subset$group, levels = c("case", "control"))
  } else {
    metadata_subset$group <- factor(metadata_subset$group, levels = sort(groups))
  }
  rownames(metadata_subset) <- metadata_subset$sample_id

  abundance_df <- abundance_df[metadata_subset$sample_id, , drop = FALSE]
  abundance_df <- abundance_df[, colSums(abundance_df, na.rm = TRUE) > 0, drop = FALSE]
  if (ncol(abundance_df) < 1) {
    stop("No non-zero features remain for beta diversity")
  }

  pcoa_result <- MicrobiotaProcess::get_pcoa(
    obj = abundance_df,
    distmethod = "bray",
    taxa_are_rows = FALSE,
    sampleda = metadata_subset,
    method = NULL
  )

  dist_matrix <- vegan::vegdist(abundance_df, method = "bray")
  attr(pcoa_result, "dist_matrix") <- dist_matrix
  attr(pcoa_result, "abundance_df") <- abundance_df
  pcoa_result
}

extract_pcoa_distance <- function(pcoa_result) {
  dist_matrix <- attr(pcoa_result, "dist_matrix", exact = TRUE)
  if (inherits(dist_matrix, "dist")) {
    return(dist_matrix)
  }

  abundance_df <- attr(pcoa_result, "abundance_df", exact = TRUE)
  if (is.null(abundance_df)) {
    stop("PCoA object does not expose a distance matrix or source abundance table")
  }
  vegan::vegdist(abundance_df, method = "bray")
}

ordered_beta_metadata <- function(dist_matrix, metadata, group_col) {
  sample_ids <- attr(dist_matrix, "Labels")
  if (is.null(sample_ids) || !length(sample_ids)) {
    stop("Distance matrix has no sample labels")
  }

  idx <- match(sample_ids, metadata$sample_id)
  if (anyNA(idx)) {
    missing_samples <- sample_ids[is.na(idx)]
    stop("Metadata missing samples from distance matrix: ", paste(missing_samples, collapse = ", "))
  }

  meta_ordered <- metadata[idx, , drop = FALSE]
  if (!identical(meta_ordered$sample_id, sample_ids)) {
    stop("Metadata sample order does not match distance matrix")
  }
  meta_ordered$group <- as.character(meta_ordered[[group_col]])
  meta_ordered <- meta_ordered[!is.na(meta_ordered$group) & nzchar(meta_ordered$group), , drop = FALSE]
  if (nrow(meta_ordered) != length(sample_ids)) {
    stop("Metadata contains empty group values for distance matrix samples")
  }

  groups <- unique(meta_ordered$group)
  if (all(c("case", "control") %in% groups)) {
    meta_ordered$group <- factor(meta_ordered$group, levels = c("case", "control"))
  } else {
    meta_ordered$group <- factor(meta_ordered$group, levels = sort(groups))
  }
  rownames(meta_ordered) <- meta_ordered$sample_id
  meta_ordered
}

compare_beta_diversity <- function(dist_matrix, metadata, group_col) {
  meta_ordered <- ordered_beta_metadata(dist_matrix, metadata, group_col)

  permanova <- vegan::adonis2(dist_matrix ~ group, data = meta_ordered, permutations = 999)
  anosim_result <- vegan::anosim(dist_matrix, grouping = meta_ordered$group, permutations = 999)

  data.frame(
    dimension = dimension,
    method = c("PERMANOVA", "ANOSIM"),
    statistic_name = c("R2", "R"),
    statistic_value = c(
      as.numeric(permanova$R2[1]),
      as.numeric(anosim_result$statistic)
    ),
    p_value = c(
      as.numeric(permanova$`Pr(>F)`[1]),
      as.numeric(anosim_result$signif)
    ),
    permutations = 999L,
    distance_method = "bray",
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

generate_beta_pcoa_plot <- function(pcoa_result, metadata, permanova_stats, dimension, out_dir) {
  permanova_row <- permanova_stats[permanova_stats$method == "PERMANOVA", , drop = FALSE]
  anosim_row <- permanova_stats[permanova_stats$method == "ANOSIM", , drop = FALSE]
  format_stat <- function(x) {
    if (!length(x)) return("NA")
    x <- as.numeric(x)[1]
    if (is.na(x)) "NA" else sprintf("%.3f", x)
  }
  format_p <- function(x) {
    if (!length(x)) return("NA")
    x <- as.numeric(x)[1]
    if (is.na(x)) "NA" else if (x < 0.001) "<0.001" else sprintf("%.3f", x)
  }
  stats_text <- paste(
    paste0("PERMANOVA R\u00b2 = ", format_stat(permanova_row$statistic_value),
           "; p = ", format_p(permanova_row$p_value)),
    paste0("ANOSIM R = ", format_stat(anosim_row$statistic_value),
           "; p = ", format_p(anosim_row$p_value)),
    sep = "\n"
  )

  p <- MicrobiotaProcess::ggordpoint(
    pcoa_result,
    mapping = ggplot2::aes(colour = group, fill = group),
    factorNames = "group",
    poinsize = 1.4,
    stroke = 0.15,
    settheme = FALSE
  ) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dotted", linewidth = sci_linewidth) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dotted", linewidth = sci_linewidth) +
    ggsci::scale_color_npg(drop = FALSE) +
    ggsci::scale_fill_npg(drop = FALSE) +
    ggplot2::annotate(
      "text",
      x = -Inf,
      y = Inf,
      label = stats_text,
      hjust = -0.05,
      vjust = 1.15,
      size = sci_text_size
    ) +
    ggplot2::labs(title = paste0(toupper(dimension), " Beta Diversity PCoA")) +
    theme_pub() +
    ggplot2::theme(
      legend.position = c(0.98, 0.98),
      legend.justification = c(1, 1),
      plot.margin = ggplot2::margin(3, 3, 3, 3)
    )

  export_pub_figure(
    p,
    file.path(out_dir, "beta_pcoa_comparison"),
    width_mm = 140,
    height_mm = 120
  )

  invisible(p)
}

cat("[INFO] Starting beta diversity analysis\n")
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

beta_result <- run_step("calculate_beta_diversity", {
  calculate_beta_diversity(abundance_matrix, metadata, group_col)
})

comparison_stats <- run_step("compare_beta_diversity", {
  beta_dist <- extract_pcoa_distance(beta_result)
  meta_ordered <- ordered_beta_metadata(beta_dist, metadata, group_col)
  append_status(
    "overlap_summary",
    "OK",
    paste0(nrow(meta_ordered), " overlapping samples; groups=", paste(table(meta_ordered$group), collapse = "/"))
  )
  compare_beta_diversity(beta_dist, metadata, group_col)
})

invisible(run_step("write_beta_permanova_stats", {
  out_path <- file.path(out_dir, "beta_permanova_stats.tsv")
  write_tsv(comparison_stats, out_path)
  append_status("permanova_stats_output", "OK", out_path)
}))

invisible(run_step("export_beta_figures", {
  generate_beta_pcoa_plot(beta_result, metadata, comparison_stats, dimension, out_dir)

  append_status("figure_outputs", "OK", paste(
    paste0(file.path(out_dir, "beta_pcoa_comparison"), c(".pdf", ".svg", ".tiff")),
    collapse = ";"
  ))
}))

invisible(run_step("write_sentinel", {
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), sentinel)
  append_status("sentinel", "OK", sentinel)
}))

append_status("write_status", "OK", status_tsv)
write_status()

cat("[INFO] Beta diversity analysis completed\n")
cat("  Sentinel:", sentinel, "\n")
