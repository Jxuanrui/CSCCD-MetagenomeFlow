#!/usr/bin/env Rscript
# 96_functional_cross_dimension.R - Cross-dimension functional visualization
# Outputs: result/stat/cross_dimension/functional/
#   - dimension_contribution_bubble.{pdf,svg,tiff}
#   - joint_heatmap_significant.{pdf,svg,tiff}
#   - correlation_network.{pdf,svg,graphml}
#   - cross_dimension_summary.tsv
#   - cross_dimension_status.tsv

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
    "Usage: Rscript 96_functional_cross_dimension.R [-w WORKDIR] [-r REPO] [-m METADATA_CSV]\n",
    "\n",
    "Optional:\n",
    "  -w, --workdir      Project work directory (default: WORKDIR env or current directory)\n",
    "  -r, --repo         Repository root (default: REPO env)\n",
    "  -m, --metadata     Metadata CSV/TSV (default: METADATA_CSV env or result/stat/metadata.tsv)\n",
    "  -g, --group-col    Metadata group column (default: GROUP_COL env or group)\n",
    "  -h, --help         Show this help message\n",
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
    } else if (flag %in% c("-g", "--group-col")) {
      opts$group_col <- next_value(flag); i <- i + 2
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
out_dir      <- Sys.getenv("OUT_DIR") %||% file.path(stat_root, "cross_dimension", "functional")
sentinel     <- Sys.getenv("SENTINEL") %||% file.path(out_dir, "cross_dimension_functional_done.txt")
status_tsv   <- file.path(out_dir, "cross_dimension_status.tsv")
summary_tsv  <- file.path(out_dir, "cross_dimension_summary.tsv")

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

required_pkgs <- c(
  "ggplot2", "dplyr", "tidyr", "tibble", "stringr", "ggsci",
  "ComplexHeatmap", "circlize", "svglite", "ragg", "igraph"
)
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  stop(
    "Missing packages: ", paste(miss, collapse = ", "),
    ". Install them in the r_stat environment, for example: conda install -c conda-forge ",
    paste(paste0("r-", miss), collapse = " ")
  )
}

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(stringr)
  library(ggsci)
})

grDevices::pdf(file = NULL)

mm2in <- function(x) x / 25.4
sci_linewidth <- 0.35 / 0.353
sci_text_size <- 7 / ggplot2::.pt
width_1col <- 89
width_1_5col <- 140
width_2col <- 183

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

export_heatmap <- function(ht, path_noext, width_mm, height_mm, dpi = 600) {
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
    ComplexHeatmap::draw(
      ht,
      heatmap_legend_side = "right",
      annotation_legend_side = "right",
      merge_legends = TRUE
    )
    grDevices::dev.off()
    invisible(TRUE)
  }

  write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h))
  write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"))
  write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi, compression = "lzw"))
  invisible(paste0(path_noext, ".svg"))
}

export_base_plot <- function(path_noext, width_mm, height_mm, plot_fn) {
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
    plot_fn()
    grDevices::dev.off()
    invisible(TRUE)
  }

  write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h))
  write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"))
  invisible(paste0(path_noext, ".svg"))
}

theme_set(theme_pub())

npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488","#F39B7F",
              "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) {
  if (n <= 0) {
    return(character())
  }
  if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
}

dimensions <- c("bacteria", "fungi", "virus")
dimension_colors <- c(
  bacteria = "#E64B35",
  fungi = "#00A087",
  virus = "#4DBBD5"
)
db_colors <- c(
  pathway = "#E64B35",
  kegg_ko = "#4DBBD5",
  cog = "#00A087",
  cazyme = "#3C5488",
  arg = "#F39B7F",
  vfdb = "#8491B4",
  defense = "#91D1C2",
  ncyc = "#DC0000",
  pcyc = "#7E6148",
  amr = "#B09C85",
  merops = "#FFDC91",
  phrog = "#E64B35",
  vog = "#4DBBD5",
  lifestyle = "#00A087",
  host_genus = "#F39B7F",
  viral_family = "#8491B4"
)

functional_source_map <- list(
  bacteria = list(
    pathway = list(
      rel_path = file.path("result", "humann3", "merged", "pathabundance_relab.tsv"),
      feature_col = "# Pathway"
    ),
    kegg_ko = list(
      rel_path = file.path("result", "integration", "bacteria", "kegg_ko_abundance.tsv"),
      feature_col = "KEGG_KO"
    ),
    cog = list(
      rel_path = file.path("result", "integration", "bacteria", "cog_abundance.tsv"),
      feature_col = "COG_category"
    ),
    cazyme = list(
      rel_path = file.path("result", "integration", "bacteria", "cazyme_abundance.tsv"),
      feature_col = "CAZyme_family"
    ),
    arg = list(
      rel_path = file.path("result", "integration", "bacteria", "arg_abundance.tsv"),
      feature_col = "ARG_gene"
    ),
    vfdb = list(
      rel_path = file.path("result", "integration", "bacteria", "vfdb_abundance.tsv"),
      feature_col = "VF_gene"
    ),
    defense = list(
      rel_path = file.path("result", "integration", "bacteria", "defense_abundance.tsv"),
      feature_col = "Defense_system"
    ),
    ncyc = list(
      rel_path = file.path("result", "integration", "bacteria", "ncyc_abundance.tsv"),
      feature_col = "NCyc_gene"
    ),
    pcyc = list(
      rel_path = file.path("result", "integration", "bacteria", "pcyc_abundance.tsv"),
      feature_col = "PCyc_gene"
    )
  ),
  fungi = list(
    kegg_ko = list(
      rel_path = file.path("result", "integration", "fungi", "kegg_ko_gene_count.tsv"),
      feature_col = "KEGG_KO"
    ),
    cog = list(
      rel_path = file.path("result", "integration", "fungi", "cog_gene_count.tsv"),
      feature_col = "COG_category"
    ),
    cazyme = list(
      rel_path = file.path("result", "integration", "fungi", "cazyme_gene_count.tsv"),
      feature_col = "CAZyme_family"
    ),
    vfdb = list(
      rel_path = file.path("result", "integration", "fungi", "vfdb_gene_count.tsv"),
      feature_col = "VF_gene"
    ),
    amr = list(
      rel_path = file.path("result", "integration", "fungi", "amr_gene_count.tsv"),
      feature_col = "ARG_symbol"
    ),
    merops = list(
      rel_path = file.path("result", "integration", "fungi", "merops_family_gene_count.tsv"),
      feature_col = "MEROPS_family"
    )
  ),
  virus = list(
    phrog = list(
      rel_path = file.path("result", "integration", "virus", "phrog_category_abundance.tsv"),
      feature_col = "PHROG_category"
    ),
    vog = list(
      rel_path = file.path("result", "integration", "virus", "vog_abundance.tsv"),
      feature_col = "VOG_ID"
    ),
    lifestyle = list(
      rel_path = file.path("result", "integration", "virus", "lifestyle_abundance.tsv"),
      feature_col = "lifestyle"
    ),
    host_genus = list(
      rel_path = file.path("result", "integration", "virus", "host_genus_abundance.tsv"),
      feature_col = "host_genus"
    ),
    viral_family = list(
      rel_path = file.path("result", "integration", "virus", "viral_family_abundance.tsv"),
      feature_col = "viral_family"
    )
  )
)
func_types_by_dimension <- lapply(functional_source_map, names)
all_func_levels <- unique(unlist(func_types_by_dimension, use.names = FALSE))

load_functional_matrix <- function(workdir, dimension, func_type) {
  if (!dimension %in% names(functional_source_map)) {
    stop("Unsupported dimension: ", dimension)
  }
  if (!func_type %in% names(functional_source_map[[dimension]])) {
    stop("Functional type '", func_type, "' is not valid for dimension '", dimension, "'")
  }

  source <- functional_source_map[[dimension]][[func_type]]
  feature_file <- file.path(workdir, source$rel_path)
  if (!file.exists(feature_file)) {
    stop("Functional matrix not found for '", func_type, "': ", feature_file)
  }

  raw <- utils::read.delim(feature_file, sep = "\t", header = TRUE,
                           check.names = FALSE, comment.char = "",
                           stringsAsFactors = FALSE)
  if (!source$feature_col %in% colnames(raw)) {
    stop("Expected feature column '", source$feature_col, "' not found in: ", feature_file)
  }

  raw <- raw[!is.na(raw[[source$feature_col]]) & nzchar(raw[[source$feature_col]]), , drop = FALSE]

  if (identical(func_type, "pathway")) {
    raw <- raw[!grepl("UNMAPPED|\\|", raw[[source$feature_col]]), , drop = FALSE]
  }

  abundance_cols <- setdiff(colnames(raw), source$feature_col)
  if (!length(abundance_cols)) {
    stop("No sample abundance columns found in: ", feature_file)
  }

  abundance <- raw[, abundance_cols, drop = FALSE]
  abundance[] <- lapply(abundance, function(x) suppressWarnings(as.numeric(x)))
  if (anyNA(as.matrix(abundance))) {
    stop("Non-numeric abundance values detected in: ", feature_file)
  }

  rownames(abundance) <- make.unique(raw[[source$feature_col]])
  feature_df <- as.data.frame(t(abundance), check.names = FALSE)
  feature_df$sample_id <- rownames(feature_df)

  list(
    data = feature_df,
    n_features = nrow(abundance),
    n_samples = ncol(abundance),
    feature_col = source$feature_col,
    feature_file = feature_file
  )
}

status_steps <- c(
  "data_loading",
  "bubble_plot",
  "joint_heatmap",
  "network_analysis"
)
status_log <- data.frame(
  step = status_steps,
  status = "PENDING",
  message = "",
  timestamp = "",
  stringsAsFactors = FALSE
)

timestamp_now <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

write_status <- function() {
  utils::write.table(status_log, status_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
}

update_status <- function(step_name, status, message = "") {
  idx <- match(step_name, status_log$step)
  if (is.na(idx)) {
    stop("Unknown status step: ", step_name)
  }
  status_log$status[idx] <<- status
  status_log$message[idx] <<- as.character(message %||% "")
  status_log$timestamp[idx] <<- timestamp_now()
  write_status()
}

mark_pending_failed <- function(message) {
  pending <- which(status_log$status == "PENDING")
  if (length(pending)) {
    status_log$status[pending] <<- "FAIL"
    status_log$message[pending] <<- paste("Skipped after prior failure:", message)
    status_log$timestamp[pending] <<- timestamp_now()
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

run_step <- function(step_name, expr) {
  tryCatch({
    result <- eval.parent(substitute(expr))
    update_status(step_name, "OK", extract_result_field(result, "message", ""))
    invisible(result)
  }, error = function(e) {
    msg <- conditionMessage(e)
    update_status(step_name, "FAIL", msg)
    mark_pending_failed(msg)
    stop("Required step failed: ", step_name, ": ", msg, call. = FALSE)
  })
}

write_status()

cat("[INFO] Starting cross-dimension functional visualization\n")
cat("  Workdir:", workdir, "\n")
cat("  Repository:", repo, "\n")
cat("  Group column:", group_col, "\n")
cat("  Output directory:", out_dir, "\n")

read_tsv_safe <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    return(tibble::tibble())
  }
  utils::read.delim(path, sep = "\t", header = TRUE, check.names = FALSE,
                    comment.char = "", quote = "", stringsAsFactors = FALSE)
}

read_metadata_file <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "csv")) {
    utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    utils::read.delim(path, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE)
  }
}

load_metadata <- function() {
  metadata_path <- metadata_csv
  if (!nzchar(metadata_path)) {
    metadata_path <- file.path(stat_root, "metadata.tsv")
  }
  if (!file.exists(metadata_path)) {
    stop("Metadata not found at: ", metadata_path)
  }

  meta <- read_metadata_file(metadata_path)
  blank_cols <- !nzchar(colnames(meta))
  if (any(blank_cols)) {
    colnames(meta)[blank_cols] <- paste0("rowname_", seq_len(sum(blank_cols)))
  }
  if (!"sample_id" %in% colnames(meta)) {
    stop("Column 'sample_id' not found in metadata: ", metadata_path)
  }
  if (!group_col %in% colnames(meta)) {
    stop("Group column '", group_col, "' not found in metadata: ", metadata_path)
  }

  meta %>%
    dplyr::mutate(sample_id = as.character(.data$sample_id)) %>%
    dplyr::filter(!is.na(.data$sample_id), nzchar(.data$sample_id)) %>%
    dplyr::distinct(.data$sample_id, .keep_all = TRUE)
}

empty_sig_results <- function() {
  tibble::tibble(
    dimension = character(),
    func_type = character(),
    feature = character(),
    coef = numeric(),
    pval = numeric(),
    qval = numeric(),
    metadata = character(),
    value = character(),
    comparison = character(),
    source_file = character()
  )
}

standardize_maaslin <- function(df, dimension, func_type, source_file) {
  df <- tibble::as_tibble(df)

  if ("qval_individual" %in% colnames(df) && !"qval" %in% colnames(df)) {
    df$qval <- df$qval_individual
  }
  if ("pval_individual" %in% colnames(df) && !"pval" %in% colnames(df)) {
    df$pval <- df$pval_individual
  }

  n <- nrow(df)
  get_col <- function(name, default = NA) {
    if (name %in% colnames(df)) {
      df[[name]]
    } else {
      rep(default, n)
    }
  }

  metadata_raw <- as.character(get_col("metadata", ""))
  value_raw <- as.character(get_col("value", ""))
  comparison <- as.character(ifelse(
    nzchar(metadata_raw) & nzchar(value_raw),
    paste(metadata_raw, value_raw, sep = ":"),
    metadata_raw
  ))

  tibble::tibble(
    dimension = rep(dimension, n),
    func_type = rep(func_type, n),
    feature = as.character(get_col("feature", "")),
    coef = suppressWarnings(as.numeric(get_col("coef", NA_real_))),
    pval = suppressWarnings(as.numeric(get_col("pval", NA_real_))),
    qval = suppressWarnings(as.numeric(get_col("qval", NA_real_))),
    metadata = metadata_raw,
    value = value_raw,
    comparison = comparison,
    source_file = rep(source_file, n)
  ) %>%
    dplyr::filter(!is.na(.data$feature), nzchar(.data$feature))
}

read_significant_result <- function(dimension, func_type) {
  sig_path <- file.path(stat_root, dimension, "functional", func_type, "results", "maaslin3_significant.tsv")
  result_path <- file.path(stat_root, dimension, "functional", func_type, "results", "maaslin3_results.tsv")

  if (file.exists(sig_path)) {
    data <- standardize_maaslin(read_tsv_safe(sig_path), dimension, func_type, sig_path)
    return(list(
      data = data,
      source_file = sig_path,
      source_type = "maaslin3_significant.tsv",
      sig_path = sig_path,
      result_path = result_path
    ))
  }

  if (file.exists(result_path)) {
    data <- standardize_maaslin(read_tsv_safe(result_path), dimension, func_type, result_path)
    data <- data %>% dplyr::filter(!is.na(.data$qval), .data$qval < 0.05)
    return(list(
      data = data,
      source_file = result_path,
      source_type = "maaslin3_results.tsv filtered at qval < 0.05",
      sig_path = sig_path,
      result_path = result_path
    ))
  }

  list(
    data = empty_sig_results(),
    source_file = "",
    source_type = "missing",
    sig_path = sig_path,
    result_path = result_path
  )
}

build_group_order <- function(group_values) {
  group_values <- as.character(group_values)
  priority <- dplyr::case_when(
    tolower(group_values) == "control" ~ 1L,
    tolower(group_values) == "case" ~ 2L,
    TRUE ~ 3L
  )
  unique(group_values[order(priority, group_values)])
}

make_group_colors <- function(group_levels) {
  if (!length(group_levels)) {
    return(character())
  }
  cols <- setNames(npg_pal(length(group_levels)), group_levels)
  case_idx <- tolower(names(cols)) == "case"
  control_idx <- tolower(names(cols)) == "control"
  cols[case_idx] <- "#E64B35"
  cols[control_idx] <- "#4DBBD5"
  cols
}

placeholder_plot <- function(label, title = NULL) {
  ggplot() +
    annotate(
      "text", x = 0.5, y = 0.5, label = label,
      size = 9 / ggplot2::.pt, lineheight = 0.9, color = "grey30"
    ) +
    labs(title = title) +
    xlim(0, 1) +
    ylim(0, 1) +
    theme_void(base_size = 7, base_family = "Arial") +
    theme(
      plot.title = element_text(size = 9, face = "bold", hjust = 0.5),
      plot.background = element_rect(fill = "white", colour = NA)
    )
}

make_empty_graph <- function(row_meta = tibble::tibble()) {
  if (!nrow(row_meta)) {
    return(igraph::make_empty_graph(directed = FALSE))
  }
  vertices <- row_meta %>%
    dplyr::transmute(
      name = .data$row_id,
      dimension = .data$dimension,
      func_type = .data$func_type,
      feature = .data$feature,
      label = stringr::str_trunc(paste(.data$func_type, .data$feature, sep = ":"), width = 40)
    )
  empty_edges <- data.frame(from = character(), to = character(), stringsAsFactors = FALSE)
  igraph::graph_from_data_frame(empty_edges, directed = FALSE, vertices = as.data.frame(vertices))
}

plot_empty_network <- function(message) {
  par(mar = c(1, 1, 3, 1), family = "Arial")
  plot.new()
  text(0.5, 0.5, message, cex = 0.85, col = "grey30", family = "Arial")
  title("Cross-Dimension Functional Correlation Network", cex.main = 0.9, font.main = 2)
}

all_sig_results <- tibble::tibble()
contribution_data <- tibble::tibble()
summary_table <- tibble::tibble()
metadata <- NULL
heatmap_feature_df <- tibble::tibble()
network_mat_raw <- matrix(numeric(0), nrow = 0)
network_row_meta <- tibble::tibble()
edges_df <- tibble::tibble()

# ========== Step 1: Data loading ==========
run_step("data_loading", {
  sig_chunks <- list()
  contribution_rows <- list()
  n_files_seen <- 0L

  for (dim in dimensions) {
    for (ft in func_types_by_dimension[[dim]]) {
      sig_result <- read_significant_result(dim, ft)
      sig_data <- sig_result$data
      if (nzchar(sig_result$source_file)) {
        n_files_seen <- n_files_seen + 1L
      }
      if (nrow(sig_data)) {
        sig_chunks[[paste(dim, ft, sep = "_")]] <- sig_data
      }

      coef_values <- abs(sig_data$coef)
      contribution_rows[[paste(dim, ft, sep = "_")]] <- tibble::tibble(
        dimension = dim,
        func_type = ft,
        sig_path = sig_result$sig_path,
        result_path = sig_result$result_path,
        source_type = sig_result$source_type,
        n_sig = nrow(sig_data),
        n_unique_features = dplyr::n_distinct(sig_data$feature),
        avg_abs_coef = if (any(is.finite(coef_values))) mean(coef_values[is.finite(coef_values)]) else NA_real_
      )
    }
  }

  if (n_files_seen == 0L) {
    stop("No Maaslin3 significant or result files found under: ", stat_root)
  }

  all_sig_results <<- if (length(sig_chunks)) {
    dplyr::bind_rows(sig_chunks)
  } else {
    empty_sig_results()
  }
  contribution_data <<- dplyr::bind_rows(contribution_rows) %>%
    dplyr::mutate(
      dimension = factor(.data$dimension, levels = dimensions),
      func_type = factor(.data$func_type, levels = all_func_levels)
    )

  summary_table <<- contribution_data %>%
    dplyr::group_by(.data$dimension) %>%
    dplyr::summarise(
      n_func_types = dplyr::n(),
      n_sig_feature_sets = sum(.data$n_sig > 0),
      total_sig_features = sum(.data$n_sig),
      total_unique_sig_features = sum(.data$n_unique_features),
      avg_abs_coef = if (any(is.finite(.data$avg_abs_coef))) {
        mean(.data$avg_abs_coef[is.finite(.data$avg_abs_coef)])
      } else {
        NA_real_
      },
      .groups = "drop"
    )

  utils::write.table(
    summary_table,
    summary_tsv,
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )

  metadata <<- load_metadata()

  cat(sprintf("  Loaded %d source result files\n", n_files_seen))
  cat(sprintf("  Significant result rows: %d\n", nrow(all_sig_results)))
  cat(sprintf("  Metadata samples: %d\n", nrow(metadata)))

  list(message = sprintf(
    "Loaded %d significant rows across %d source files",
    nrow(all_sig_results), n_files_seen
  ))
})

# ========== Step 2: Dimension contribution bubble plot ==========
run_step("bubble_plot", {
  plot_df <- contribution_data %>%
    dplyr::filter(.data$n_sig > 0, is.finite(.data$avg_abs_coef)) %>%
    dplyr::mutate(
      dimension = factor(as.character(.data$dimension), levels = rev(dimensions)),
      func_type = factor(as.character(.data$func_type), levels = all_func_levels)
    )

  if (!nrow(plot_df)) {
    p_bubble <- placeholder_plot(
      "No significant functional signals detected",
      "Cross-Dimension Functional Signal Contribution"
    )
  } else {
    p_bubble <- ggplot(plot_df, aes(x = .data$func_type, y = .data$dimension)) +
      geom_point(aes(size = .data$n_sig, color = .data$avg_abs_coef), alpha = 0.75) +
      geom_text(aes(label = .data$n_sig), size = 7 / ggplot2::.pt, color = "black") +
      scale_size_continuous(name = "# Significant", range = c(2, 15)) +
      scale_color_gradient2(
        low = "#4DBBD5", mid = "white", high = "#E64B35",
        midpoint = 1, name = "Avg |coef|"
      ) +
      scale_x_discrete(drop = FALSE) +
      scale_y_discrete(drop = FALSE) +
      labs(
        title = "Cross-Dimension Functional Signal Contribution",
        x = "Functional Type",
        y = "Dimension"
      ) +
      theme_pub(base_size = 7) +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1),
        plot.title = element_text(size = 9, face = "bold", hjust = 0.5),
        legend.position = "right"
      )
  }

  export_pub_figure(
    p_bubble,
    file.path(out_dir, "dimension_contribution_bubble"),
    width_mm = width_2col,
    height_mm = 120
  )

  list(message = sprintf("%d signal-bearing dimension/database combinations", nrow(plot_df)))
})

# ========== Step 3: Joint heatmap across dimensions ==========
run_step("joint_heatmap", {
  sig_feature_df <- all_sig_results %>%
    dplyr::filter(!is.na(.data$feature), nzchar(.data$feature)) %>%
    dplyr::mutate(
      abs_coef = abs(.data$coef),
      abs_coef_rank = dplyr::if_else(is.finite(.data$abs_coef), .data$abs_coef, 0),
      qval_rank = dplyr::if_else(is.finite(.data$qval), .data$qval, Inf)
    ) %>%
    dplyr::arrange(.data$dimension, .data$func_type, .data$qval_rank, dplyr::desc(.data$abs_coef_rank)) %>%
    dplyr::distinct(.data$dimension, .data$func_type, .data$feature, .keep_all = TRUE)

  total_sig_features <- nrow(sig_feature_df)
  if (total_sig_features > 200) {
    heatmap_feature_df <<- sig_feature_df %>%
      dplyr::arrange(dplyr::desc(.data$abs_coef_rank), .data$qval_rank) %>%
      dplyr::slice_head(n = 100)
    cat(sprintf(
      "  Heatmap: %d significant features detected; using top 100 by |coef|\n",
      total_sig_features
    ))
  } else {
    heatmap_feature_df <<- sig_feature_df
  }

  if (!nrow(heatmap_feature_df)) {
    p_empty <- placeholder_plot(
      "No significant functional features available for heatmap",
      "Joint Significant Functional Feature Heatmap"
    )
    export_pub_figure(
      p_empty,
      file.path(out_dir, "joint_heatmap_significant"),
      width_mm = width_2col,
      height_mm = 200
    )
    network_mat_raw <<- matrix(numeric(0), nrow = 0)
    network_row_meta <<- tibble::tibble()
    heatmap_result <- list(message = "Skipped heatmap matrix: no significant features")
  } else {
    matrix_list <- list()
    row_meta_list <- list()
    missing_feature_count <- 0L
    load_warning_count <- 0L

    split_keys <- paste(heatmap_feature_df$dimension, heatmap_feature_df$func_type, sep = "\r")
    for (key in unique(split_keys)) {
      key_parts <- strsplit(key, "\r", fixed = TRUE)[[1]]
      dim <- key_parts[[1]]
      ft <- key_parts[[2]]

      ft_feature_df <- heatmap_feature_df[split_keys == key, , drop = FALSE]
      matrix_info <- tryCatch(
        load_functional_matrix(workdir, dim, ft),
        error = function(e) {
          cat(sprintf("  Heatmap: skipping %s/%s (%s)\n", dim, ft, conditionMessage(e)))
          load_warning_count <<- load_warning_count + 1L
          NULL
        }
      )
      if (is.null(matrix_info)) {
        next
      }

      matrix_df <- matrix_info$data
      available_features <- ft_feature_df$feature[ft_feature_df$feature %in% colnames(matrix_df)]
      missing_features <- setdiff(ft_feature_df$feature, available_features)
      missing_feature_count <- missing_feature_count + length(missing_features)
      if (!length(available_features)) {
        next
      }

      ft_mat <- as.matrix(matrix_df[, available_features, drop = FALSE])
      storage.mode(ft_mat) <- "numeric"
      rownames(ft_mat) <- matrix_df$sample_id
      ft_mat <- t(ft_mat)

      row_meta <- ft_feature_df %>%
        dplyr::filter(.data$feature %in% available_features) %>%
        dplyr::slice(match(available_features, .data$feature)) %>%
        dplyr::mutate(
          row_id = paste(.data$dimension, .data$func_type, .data$feature, sep = ":")
        )
      rownames(ft_mat) <- row_meta$row_id

      matrix_list[[paste(dim, ft, sep = "_")]] <- ft_mat
      row_meta_list[[paste(dim, ft, sep = "_")]] <- row_meta
    }

    if (!length(matrix_list)) {
      p_empty <- placeholder_plot(
        "No significant features matched source abundance matrices",
        "Joint Significant Functional Feature Heatmap"
      )
      export_pub_figure(
        p_empty,
        file.path(out_dir, "joint_heatmap_significant"),
        width_mm = width_2col,
        height_mm = 200
      )
      network_mat_raw <<- matrix(numeric(0), nrow = 0)
      network_row_meta <<- tibble::tibble()
      heatmap_result <- list(message = "Skipped heatmap matrix: no features matched abundance matrices")
    } else {
      common_samples <- Reduce(intersect, lapply(matrix_list, colnames))
      common_samples <- intersect(common_samples, metadata$sample_id)

      if (length(common_samples) < 2) {
        p_empty <- placeholder_plot(
          "Fewer than 2 common samples across selected abundance matrices",
          "Joint Significant Functional Feature Heatmap"
        )
        export_pub_figure(
          p_empty,
          file.path(out_dir, "joint_heatmap_significant"),
          width_mm = width_2col,
          height_mm = 200
        )
        network_mat_raw <<- matrix(numeric(0), nrow = 0)
        network_row_meta <<- tibble::tibble()
        heatmap_result <- list(message = "Skipped heatmap matrix: fewer than 2 common samples")
      } else {
        heatmap_meta <- metadata %>%
          dplyr::filter(.data$sample_id %in% common_samples)
        group_levels <- build_group_order(heatmap_meta[[group_col]])
        heatmap_meta <- heatmap_meta %>%
          dplyr::mutate(.group_factor = factor(.data[[group_col]], levels = group_levels)) %>%
          dplyr::arrange(.data$.group_factor, .data$sample_id)
        sample_order <- heatmap_meta$sample_id

        combined_mat <- do.call(rbind, lapply(matrix_list, function(x) x[, sample_order, drop = FALSE]))
        row_meta <- dplyr::bind_rows(row_meta_list) %>%
          dplyr::slice(match(rownames(combined_mat), .data$row_id))

        combined_mat <- pmax(combined_mat, 0)
        combined_mat_log <- log10(combined_mat + 1e-6)
        combined_mat_scaled <- t(scale(t(combined_mat_log)))
        combined_mat_scaled[!is.finite(combined_mat_scaled)] <- 0

        row_dim <- factor(row_meta$dimension, levels = dimensions)
        row_db <- factor(row_meta$func_type, levels = all_func_levels)
        row_labels <- stringr::str_trunc(
          paste(row_meta$func_type, row_meta$feature, sep = ":"),
          width = 70
        )

        present_db_levels <- levels(droplevels(row_db))
        missing_db_cols <- setdiff(present_db_levels, names(db_colors))
        if (length(missing_db_cols)) {
          db_colors <- c(db_colors, setNames(npg_pal(length(missing_db_cols)), missing_db_cols))
        }

        col_fun <- circlize::colorRamp2(
          c(-2.5, 0, 2.5),
          c("#4DBBD5", "#F7F7F7", "#E64B35")
        )

        group_colors <- make_group_colors(group_levels)
        column_group <- heatmap_meta$.group_factor
        names(column_group) <- heatmap_meta$sample_id

        top_ha <- ComplexHeatmap::HeatmapAnnotation(
          Group = column_group,
          col = list(Group = group_colors),
          show_legend = TRUE,
          annotation_name_side = "left",
          annotation_name_gp = grid::gpar(fontsize = 7, fontface = "bold"),
          simple_anno_size = grid::unit(3, "mm"),
          border = TRUE
        )

        row_ha <- ComplexHeatmap::rowAnnotation(
          Dimension = row_dim,
          Database = row_db,
          col = list(
            Dimension = dimension_colors,
            Database = db_colors[present_db_levels]
          ),
          show_legend = TRUE,
          annotation_name_gp = grid::gpar(fontsize = 7, fontface = "bold"),
          simple_anno_size = grid::unit(3, "mm"),
          border = TRUE
        )

        ht <- ComplexHeatmap::Heatmap(
          combined_mat_scaled,
          name = "Z-score",
          col = col_fun,
          left_annotation = row_ha,
          top_annotation = top_ha,
          cluster_rows = TRUE,
          cluster_columns = FALSE,
          row_split = row_dim,
          column_split = column_group,
          row_title_gp = grid::gpar(fontsize = 9, fontface = "bold"),
          column_title = "Cross-Dimension Significant Functional Features",
          column_title_gp = grid::gpar(fontsize = 9, fontface = "bold"),
          row_names_gp = grid::gpar(fontsize = 5),
          column_names_gp = grid::gpar(fontsize = 5),
          row_labels = row_labels,
          show_column_names = FALSE,
          row_names_max_width = grid::unit(80, "mm"),
          heatmap_legend_param = list(
            title = "Z-score",
            title_gp = grid::gpar(fontsize = 7, fontface = "bold"),
            labels_gp = grid::gpar(fontsize = 7),
            legend_height = grid::unit(25, "mm"),
            border = "grey40"
          ),
          border = TRUE
        )

        export_heatmap(
          ht,
          file.path(out_dir, "joint_heatmap_significant"),
          width_mm = width_2col,
          height_mm = 200
        )

        network_mat_raw <<- combined_mat
        network_row_meta <<- row_meta
        heatmap_result <- list(message = sprintf(
          "Heatmap exported for %d features and %d samples; %d missing feature matches; %d matrix load warnings",
          nrow(combined_mat), ncol(combined_mat), missing_feature_count, load_warning_count
        ))
      }
    }
  }

  heatmap_result
})

# ========== Step 4: Cross-dimension correlation network ==========
run_step("network_analysis", {
  cor_cutoff <- 0.6
  p_cutoff <- 0.05
  network_path <- file.path(out_dir, "correlation_network")

  write_empty_network <- function(message) {
    g <- make_empty_graph(network_row_meta)
    igraph::write_graph(g, paste0(network_path, ".graphml"), format = "graphml")
    export_base_plot(network_path, width_mm = width_1_5col, height_mm = 140, plot_fn = function() {
      plot_empty_network(message)
    })
    list(message = message)
  }

  if (!nrow(network_mat_raw) || nrow(network_row_meta) == 0) {
    network_result <- write_empty_network(
      "No significant features available for correlation network"
    )
  } else if (ncol(network_mat_raw) < 3) {
    network_result <- write_empty_network(
      "Fewer than 3 common samples available for Spearman correlation"
    )
  } else {
    network_mat_log <- log10(pmax(network_mat_raw, 0) + 1e-6)
    row_sd <- apply(network_mat_log, 1, stats::sd, na.rm = TRUE)
    variable_rows <- is.finite(row_sd) & row_sd > 0

    if (sum(variable_rows) < 2) {
      network_result <- write_empty_network(
        "Fewer than 2 variable features available for correlation network"
      )
    } else {
      network_mat_log <- network_mat_log[variable_rows, , drop = FALSE]
      network_meta <- network_row_meta[match(rownames(network_mat_log), network_row_meta$row_id), , drop = FALSE]

      cor_mat <- suppressWarnings(stats::cor(
        t(network_mat_log),
        method = "spearman",
        use = "pairwise.complete.obs"
      ))

      edge_idx <- which(
        upper.tri(cor_mat) & is.finite(cor_mat) & abs(cor_mat) > cor_cutoff,
        arr.ind = TRUE
      )

      if (!nrow(edge_idx)) {
        network_result <- write_empty_network(
          sprintf("No strong cross-dimension correlations detected\n(|Spearman r| > %.1f, p < %.2f)", cor_cutoff, p_cutoff)
        )
      } else {
        dim_lookup <- setNames(network_meta$dimension, network_meta$row_id)
        edge_candidates <- tibble::tibble(
          from = rownames(cor_mat)[edge_idx[, 1]],
          to = rownames(cor_mat)[edge_idx[, 2]],
          correlation = cor_mat[edge_idx],
          from_dim = dim_lookup[rownames(cor_mat)[edge_idx[, 1]]],
          to_dim = dim_lookup[rownames(cor_mat)[edge_idx[, 2]]]
        ) %>%
          dplyr::filter(.data$from_dim != .data$to_dim)

        if (!nrow(edge_candidates)) {
          network_result <- write_empty_network(
            sprintf("No cross-dimension correlations detected\n(|Spearman r| > %.1f, p < %.2f)", cor_cutoff, p_cutoff)
          )
        } else {
          p_values <- vapply(seq_len(nrow(edge_candidates)), function(i) {
            x <- as.numeric(network_mat_log[edge_candidates$from[[i]], ])
            y <- as.numeric(network_mat_log[edge_candidates$to[[i]], ])
            keep <- is.finite(x) & is.finite(y)
            if (sum(keep) < 3) {
              return(NA_real_)
            }
            suppressWarnings(stats::cor.test(
              x[keep], y[keep],
              method = "spearman",
              exact = FALSE
            )$p.value)
          }, numeric(1))

          edges_df <- edge_candidates %>%
            dplyr::mutate(p_value = p_values) %>%
            dplyr::filter(!is.na(.data$p_value), .data$p_value < p_cutoff)

          if (!nrow(edges_df)) {
            network_result <- write_empty_network(
              sprintf("No cross-dimension correlations passed p < %.2f\n(|Spearman r| > %.1f)", p_cutoff, cor_cutoff)
            )
          } else {
            vertices <- network_meta %>%
              dplyr::filter(.data$row_id %in% unique(c(edges_df$from, edges_df$to))) %>%
              dplyr::transmute(
                name = .data$row_id,
                dimension = .data$dimension,
                func_type = .data$func_type,
                feature = .data$feature,
                label = stringr::str_trunc(paste(.data$func_type, .data$feature, sep = ":"), width = 40)
              )

            g <- igraph::graph_from_data_frame(
              as.data.frame(edges_df),
              directed = FALSE,
              vertices = as.data.frame(vertices)
            )

            igraph::V(g)$color <- unname(dimension_colors[igraph::V(g)$dimension])
            igraph::V(g)$color[is.na(igraph::V(g)$color)] <- "grey70"
            degrees <- igraph::degree(g)
            igraph::V(g)$size <- 5 + sqrt(pmax(degrees, 1)) * 2
            igraph::E(g)$weight <- abs(igraph::E(g)$correlation)
            igraph::E(g)$color <- ifelse(igraph::E(g)$correlation > 0, "#E64B35", "#4DBBD5")
            igraph::E(g)$width <- pmax(1, igraph::E(g)$weight * 3)

            igraph::write_graph(g, paste0(network_path, ".graphml"), format = "graphml")

            plot_network <- function() {
              par(mar = c(1, 1, 3, 1), family = "Arial")
              set.seed(123)
              layout <- igraph::layout_with_fr(g, weights = igraph::E(g)$weight)
              plot(
                g,
                layout = layout,
                vertex.color = igraph::V(g)$color,
                vertex.frame.color = "grey35",
                vertex.size = igraph::V(g)$size,
                vertex.label = igraph::V(g)$label,
                vertex.label.cex = 0.45,
                vertex.label.color = "black",
                edge.color = igraph::E(g)$color,
                edge.width = igraph::E(g)$width,
                edge.curved = 0.15,
                main = "Cross-Dimension Functional Correlation Network"
              )
              legend(
                "topright",
                legend = c("Bacteria", "Fungi", "Virus", "Positive corr", "Negative corr"),
                col = c(dimension_colors, "#E64B35", "#4DBBD5"),
                pch = c(19, 19, 19, NA, NA),
                lty = c(NA, NA, NA, 1, 1),
                pt.cex = c(1, 1, 1, NA, NA),
                bty = "n",
                cex = 0.65
              )
            }

            export_base_plot(network_path, width_mm = width_1_5col, height_mm = 140, plot_fn = plot_network)

            network_result <- list(message = sprintf(
              "Network exported with %d nodes and %d cross-dimension edges",
              igraph::vcount(g), igraph::ecount(g)
            ))
          }
        }
      }
    }
  }

  network_result
})

expected_files <- c(
  file.path(out_dir, "dimension_contribution_bubble.pdf"),
  file.path(out_dir, "dimension_contribution_bubble.svg"),
  file.path(out_dir, "dimension_contribution_bubble.tiff"),
  file.path(out_dir, "joint_heatmap_significant.pdf"),
  file.path(out_dir, "joint_heatmap_significant.svg"),
  file.path(out_dir, "joint_heatmap_significant.tiff"),
  file.path(out_dir, "correlation_network.pdf"),
  file.path(out_dir, "correlation_network.svg"),
  file.path(out_dir, "correlation_network.graphml"),
  summary_tsv,
  status_tsv
)
missing_files <- expected_files[!file.exists(expected_files) | file.info(expected_files)$size == 0]
if (length(missing_files)) {
  msg <- paste("Missing or empty export files:", paste(missing_files, collapse = ", "))
  update_status("network_analysis", "FAIL", msg)
  stop(msg, call. = FALSE)
}

writeLines(format(Sys.time()), sentinel)

cat("[INFO] Cross-dimension functional visualization finished\n")
cat("  Summary:", summary_tsv, "\n")
cat("  Status:", status_tsv, "\n")
cat("  Sentinel:", sentinel, "\n")
