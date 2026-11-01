#!/usr/bin/env Rscript
# 96_functional_integrated.R - Cross-database integrated functional visualization
# Outputs: result/stat/{dimension}/functional/00_summary/
#   - heatmap_multidatabase.{pdf,svg,tiff}
#   - volcano_faceted.{pdf,svg,tiff}
#   - summary_table.tsv
#   - {dimension}_summary_status.tsv

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
    "Usage: Rscript 96_functional_integrated.R [-w WORKDIR] [-r REPO] [-m METADATA_CSV] [-d DIMENSION]\n",
    "\n",
    "Optional:\n",
    "  -w, --workdir      Project work directory (default: WORKDIR env or current directory)\n",
    "  -r, --repo         Repository root (default: REPO env)\n",
    "  -m, --metadata     Metadata CSV (default: METADATA_CSV env or result/stat/metadata.tsv)\n",
    "  -d, --dimension    bacteria|fungi|virus (default: DIMENSION env or bacteria)\n",
    "  -g, --group-col    Metadata group column (default: GROUP_COL env or group)\n",
    "  -c, --cpus         CPU threads for parallel loading (default: CPUS env or 1)\n",
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
    } else if (flag %in% c("-d", "--dimension")) {
      opts$dimension <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-g", "--group-col")) {
      opts$group_col <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-c", "--cpus")) {
      opts$cpus <- next_value(flag); i <- i + 2
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
repo         <- cli_opts$repo %||% Sys.getenv("REPO")
metadata_csv <- cli_opts$metadata_csv %||% Sys.getenv("METADATA_CSV")
group_col    <- cli_opts$group_col %||% Sys.getenv("GROUP_COL") %||% "group"
stat_root    <- Sys.getenv("STAT_ROOT") %||% file.path(workdir, "result", "stat")
dimension    <- tolower(cli_opts$dimension %||% Sys.getenv("DIMENSION") %||% "bacteria")
cpus         <- suppressWarnings(as.integer(cli_opts$cpus %||% Sys.getenv("CPUS") %||% "1"))
if (is.na(cpus) || cpus < 1) {
  cpus <- 1L
}
default_out_dir <- file.path(stat_root, dimension, "functional", "00_summary")
out_dir_env <- Sys.getenv("OUT_DIR")
out_dir      <- if (nzchar(out_dir_env)) {
  if (basename(out_dir_env) == "integrated") {
    file.path(dirname(out_dir_env), "00_summary")
  } else {
    out_dir_env
  }
} else {
  default_out_dir
}
sentinel     <- Sys.getenv("SENTINEL") %||%
  file.path(out_dir, sprintf("%s_summary_done.txt", dimension))
status_tsv   <- file.path(out_dir, sprintf("%s_summary_status.tsv", dimension))

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

valid_dimensions <- names(functional_source_map)
if (!dimension %in% valid_dimensions) {
  stop("Invalid dimension: ", dimension)
}

func_types <- names(functional_source_map[[dimension]])

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
  "ggplot2", "dplyr", "tidyr", "tibble", "stringr", "ggtext",
  "ggsci", "ComplexHeatmap", "circlize", "svglite", "ragg",
  "purrr", "rlang"
)
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  stop("Missing packages: ", paste(miss, collapse = ", "))
}

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(stringr)
  library(ggtext)
  library(ggsci)
  library(purrr)
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

theme_set(theme_pub())

npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488","#F39B7F",
              "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) {
  if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
}

sci_diff_colors <- function() {
  list(
    up = "#E64B35",
    down = "#4DBBD5",
    nonsig = "#BBBBBB"
  )
}

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
  "heatmap_generation",
  "volcano_generation",
  "table_generation",
  "export"
)
status_log <- data.frame(
  step_name = status_steps,
  status = "PENDING",
  n_features = NA_integer_,
  timestamp = "",
  message = "",
  stringsAsFactors = FALSE
)

timestamp_now <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

write_status <- function() {
  utils::write.table(status_log, status_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
}

update_status <- function(step_name, status, n_features = NA_integer_, message = "") {
  idx <- match(step_name, status_log$step_name)
  if (is.na(idx)) {
    stop("Unknown status step: ", step_name)
  }
  status_log$status[idx] <<- status
  status_log$n_features[idx] <<- suppressWarnings(as.integer(n_features))
  status_log$timestamp[idx] <<- timestamp_now()
  status_log$message[idx] <<- as.character(message %||% "")
  write_status()
}

mark_pending_failed <- function(message) {
  pending <- which(status_log$status == "PENDING")
  if (length(pending)) {
    status_log$status[pending] <<- "FAIL"
    status_log$timestamp[pending] <<- timestamp_now()
    status_log$message[pending] <<- paste("Skipped after prior failure:", message)
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
    update_status(
      step_name,
      "OK",
      extract_result_field(result, "n_features", NA_integer_),
      extract_result_field(result, "message", "")
    )
    invisible(result)
  }, error = function(e) {
    msg <- conditionMessage(e)
    update_status(step_name, "FAIL", NA_integer_, msg)
    mark_pending_failed(msg)
    stop("Required step failed: ", step_name, ": ", msg, call. = FALSE)
  })
}

write_status()

cat("[INFO] Starting integrated functional visualization\n")
cat("  Workdir:", workdir, "\n")
cat("  Dimension:", dimension, "\n")
cat("  Functional databases:", paste(func_types, collapse = ", "), "\n")
cat("  Group column:", group_col, "\n")
cat("  CPUS:", cpus, "\n")
cat("  Output directory:", out_dir, "\n")

read_tsv_safe <- function(path) {
  utils::read.delim(path, sep = "\t", header = TRUE, check.names = FALSE,
                    comment.char = "", quote = "", stringsAsFactors = FALSE)
}

standardize_maaslin <- function(df, func_type, source_file) {
  df <- tibble::as_tibble(df)

  if ("qval_individual" %in% colnames(df) && !"qval" %in% colnames(df)) {
    df$qval <- df$qval_individual
  }
  if ("pval_individual" %in% colnames(df) && !"pval" %in% colnames(df)) {
    df$pval <- df$pval_individual
  }

  n <- nrow(df)
  get_col <- function(name, default = NA_character_) {
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
    model = as.character(get_col("model", "")),
    source_file = rep(source_file, n)
  )
}

read_maaslin_file <- function(func_type, filename) {
  path <- file.path(stat_root, dimension, "functional", func_type, "results", filename)
  if (!file.exists(path)) {
    return(tibble::tibble())
  }
  standardize_maaslin(read_tsv_safe(path), func_type, path)
}

map_dfr_maybe_parallel <- function(items, reader) {
  use_parallel <- length(items) > 5 && cpus > 1 && .Platform$OS.type != "windows"
  if (use_parallel) {
    workers <- min(cpus, length(items))
    res <- parallel::mclapply(items, reader, mc.cores = workers)
    purrr::map_dfr(res, identity)
  } else {
    purrr::map_dfr(items, reader)
  }
}

count_features_by_type <- function(df, count_name) {
  if (!nrow(df)) {
    return(tibble::tibble(func_type = character(), !!count_name := integer()))
  }
  df %>%
    dplyr::filter(!is.na(.data$feature), nzchar(.data$feature)) %>%
    dplyr::distinct(.data$func_type, .data$feature) %>%
    dplyr::count(.data$func_type, name = count_name)
}

load_metadata <- function() {
  if (nzchar(metadata_csv) && file.exists(metadata_csv)) {
    meta <- utils::read.csv(metadata_csv, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    metadata_tsv <- file.path(stat_root, "metadata.tsv")
    if (!file.exists(metadata_tsv)) {
      stop("Metadata not found at: ", metadata_tsv)
    }
    meta <- utils::read.delim(metadata_tsv, sep = "\t", stringsAsFactors = FALSE,
                              check.names = FALSE)
  }

  blank_cols <- !nzchar(colnames(meta))
  if (any(blank_cols)) {
    colnames(meta)[blank_cols] <- paste0("rowname_", seq_len(sum(blank_cols)))
  }

  if (!"sample_id" %in% colnames(meta)) {
    stop("Column 'sample_id' not found in metadata")
  }
  if (!group_col %in% colnames(meta)) {
    stop("Group column '", group_col, "' not found in metadata")
  }

  meta %>%
    dplyr::mutate(sample_id = as.character(.data$sample_id)) %>%
    dplyr::filter(!is.na(.data$sample_id), nzchar(.data$sample_id)) %>%
    dplyr::distinct(.data$sample_id, .keep_all = TRUE)
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
  cols <- setNames(npg_pal(length(group_levels)), group_levels)
  case_idx <- tolower(names(cols)) == "case"
  control_idx <- tolower(names(cols)) == "control"
  cols[case_idx] <- "#E64B35"
  cols[control_idx] <- "#4DBBD5"
  cols
}

all_results <- tibble::tibble()
sig_results <- tibble::tibble()
summary_table <- tibble::tibble()
metadata <- NULL
zero_signal_databases <- character()
heatmap_generated <- FALSE
volcano_generated <- FALSE
summary_generated <- FALSE

# ========== Step 1: Data loading ==========
run_step("data_loading", {
  if (length(func_types) > 5 && cpus > 1) {
    if (requireNamespace("future", quietly = TRUE)) {
      future::plan(future::multicore, workers = min(cpus, length(func_types)))
      cat(sprintf("  Parallel plan: future::multicore with %d workers\n",
                  min(cpus, length(func_types))))
    } else {
      cat("  Parallel plan: future not installed; using base multicore loading\n")
    }
  }

  result_files <- file.path(stat_root, dimension, "functional", func_types, "results", "maaslin3_results.tsv")
  significant_files <- file.path(stat_root, dimension, "functional", func_types, "results", "maaslin3_significant.tsv")

  if (!any(file.exists(result_files)) && !any(file.exists(significant_files))) {
    stop("No Maaslin3 result files found under: ",
         file.path(stat_root, dimension, "functional"))
  }

  all_results <- map_dfr_maybe_parallel(
    func_types,
    function(ft) read_maaslin_file(ft, "maaslin3_results.tsv")
  )

  sig_from_files <- map_dfr_maybe_parallel(
    func_types,
    function(ft) read_maaslin_file(ft, "maaslin3_significant.tsv")
  )

  missing_sig_types <- func_types[!file.exists(significant_files) & func_types %in% unique(all_results$func_type)]
  sig_from_all <- all_results %>%
    dplyr::filter(.data$func_type %in% missing_sig_types, !is.na(.data$qval), .data$qval < 0.05)

  sig_results <- dplyr::bind_rows(sig_from_files, sig_from_all) %>%
    dplyr::filter(!is.na(.data$qval), .data$qval < 0.05)

  tested_counts <- count_features_by_type(all_results, "Features_tested")
  sig_counts <- count_features_by_type(sig_results, "Significant_features")

  summary_table <- tibble::tibble(Database = func_types) %>%
    dplyr::left_join(tested_counts, by = c("Database" = "func_type")) %>%
    dplyr::left_join(sig_counts, by = c("Database" = "func_type")) %>%
    dplyr::mutate(
      Features_tested = tidyr::replace_na(.data$Features_tested, 0L),
      Significant_features = tidyr::replace_na(.data$Significant_features, 0L),
      Features_tested = dplyr::if_else(
        .data$Features_tested == 0L & .data$Significant_features > 0L,
        .data$Significant_features,
        .data$Features_tested
      ),
      Note = dplyr::case_when(
        !file.exists(result_files[match(.data$Database, func_types)]) &
          .data$Significant_features == 0L ~ "Results file not found",
        .data$Features_tested == 0L ~ "Low prevalence/no features tested",
        .data$Significant_features == 0L ~ "No hits passing FDR<0.05",
        TRUE ~ "Signals detected"
      )
    )

  zero_signal_databases <- summary_table %>%
    dplyr::filter(.data$Features_tested > 0L, .data$Significant_features == 0L) %>%
    dplyr::pull(.data$Database)

  metadata <- load_metadata()

  if (requireNamespace("future", quietly = TRUE)) {
    future::plan(future::sequential)
  }

  cat(sprintf("  Loaded Maaslin rows: %d total, %d significant rows\n",
              nrow(all_results), nrow(sig_results)))
  cat(sprintf("  Significant unique features: %d\n",
              sum(summary_table$Significant_features)))
  if (length(zero_signal_databases)) {
    cat("  Zero-signal databases:", paste(zero_signal_databases, collapse = ", "), "\n")
  } else {
    cat("  Zero-signal databases: none\n")
  }

  list(
    n_features = sum(summary_table$Significant_features),
    message = sprintf(
      "Loaded %d result rows across %d databases; %d zero-signal databases",
      nrow(all_results), length(func_types), length(zero_signal_databases)
    )
  )
})

# ========== Step 2: ComplexHeatmap multi-database heatmap ==========
run_step("heatmap_generation", {
  sig_feature_df <- sig_results %>%
    dplyr::filter(!is.na(.data$feature), nzchar(.data$feature)) %>%
    dplyr::mutate(
      func_type = factor(.data$func_type, levels = func_types),
      abs_coef = abs(.data$coef)
    ) %>%
    dplyr::arrange(.data$func_type, .data$qval, dplyr::desc(.data$abs_coef)) %>%
    dplyr::distinct(.data$func_type, .data$feature, .keep_all = TRUE)

  if (!nrow(sig_feature_df)) {
    heatmap_generated <- FALSE
    cat("  Heatmap: skipped (no significant functional features)\n")
    heatmap_result <- list(n_features = 0L, message = "Skipped: no significant functional features")
  } else {

    sig_db <- as.character(unique(sig_feature_df$func_type))
    cat("  Heatmap databases:", paste(sig_db, collapse = ", "), "\n")
    if (nrow(sig_feature_df) > 200) {
      cat(sprintf("  Heatmap: %d significant features; ComplexHeatmap export may take longer\n",
                  nrow(sig_feature_df)))
    }

    matrix_list <- list()
    row_meta_list <- list()

    for (ft in sig_db) {
      ft_features <- sig_feature_df %>%
        dplyr::filter(as.character(.data$func_type) == ft) %>%
        dplyr::pull(.data$feature)

      matrix_info <- load_functional_matrix(workdir, dimension, ft)
      matrix_df <- matrix_info$data
      available_features <- ft_features[ft_features %in% colnames(matrix_df)]
      missing_features <- setdiff(ft_features, available_features)
      if (length(missing_features)) {
        cat(sprintf("  Heatmap: %s missing %d significant features in source matrix\n",
                    ft, length(missing_features)))
      }
      if (!length(available_features)) {
        next
      }

      ft_mat <- as.matrix(matrix_df[, available_features, drop = FALSE])
      storage.mode(ft_mat) <- "numeric"
      rownames(ft_mat) <- matrix_df$sample_id
      ft_mat <- t(ft_mat)
      rownames(ft_mat) <- paste(ft, available_features, sep = "__")

      matrix_list[[ft]] <- ft_mat
      row_meta_list[[ft]] <- tibble::tibble(
        row_id = rownames(ft_mat),
        func_type = ft,
        feature = available_features
      )
    }

    if (!length(matrix_list)) {
      heatmap_generated <- FALSE
      cat("  Heatmap: skipped (no significant features matched abundance matrices)\n")
      heatmap_result <- list(n_features = 0L, message = "Skipped: no significant features matched source matrices")
    } else {

      common_samples <- Reduce(intersect, lapply(matrix_list, colnames))
      common_samples <- intersect(common_samples, metadata$sample_id)
      if (length(common_samples) < 2) {
        stop("Fewer than 2 common samples between functional matrices and metadata")
      }

      heatmap_meta <- metadata %>%
        dplyr::filter(.data$sample_id %in% common_samples)
      group_levels <- build_group_order(heatmap_meta[[group_col]])
      heatmap_meta <- heatmap_meta %>%
        dplyr::mutate(.group_factor = factor(.data[[group_col]], levels = group_levels)) %>%
        dplyr::arrange(.data$.group_factor, .data$sample_id)
      sample_order <- heatmap_meta$sample_id

      heatmap_mat <- do.call(rbind, lapply(matrix_list, function(x) x[, sample_order, drop = FALSE]))
      row_meta <- dplyr::bind_rows(row_meta_list) %>%
        dplyr::slice(match(rownames(heatmap_mat), .data$row_id))

      heatmap_mat <- pmax(heatmap_mat, 0)
      heatmap_mat <- log10(heatmap_mat + 1e-6)
      heatmap_mat <- t(scale(t(heatmap_mat)))
      heatmap_mat[!is.finite(heatmap_mat)] <- 0

      row_db <- factor(row_meta$func_type, levels = func_types)
      names(row_db) <- row_meta$row_id
      row_labels <- stringr::str_trunc(row_meta$feature, width = 60)

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

      present_db_levels <- levels(droplevels(row_db))
      row_ha <- ComplexHeatmap::rowAnnotation(
        Database = row_db,
        col = list(Database = db_colors[present_db_levels]),
        show_legend = TRUE,
        annotation_name_gp = grid::gpar(fontsize = 7, fontface = "bold"),
        simple_anno_size = grid::unit(3, "mm"),
        border = TRUE
      )

      row_fontsize <- 7
      heatmap_height_mm <- min(max(100, nrow(heatmap_mat) * 3 + 35), 600)

      ht <- row_ha + ComplexHeatmap::Heatmap(
        heatmap_mat,
        name = "Z-score",
        col = col_fun,
        top_annotation = top_ha,
        row_split = row_db,
        column_split = column_group,
        cluster_rows = FALSE,
        cluster_columns = FALSE,
        cluster_row_slices = FALSE,
        cluster_column_slices = FALSE,
        show_row_names = TRUE,
        row_labels = row_labels,
        show_column_names = FALSE,
        row_names_gp = grid::gpar(fontsize = row_fontsize),
        column_names_gp = grid::gpar(fontsize = 7),
        row_names_max_width = grid::unit(80, "mm"),
        column_title = "Integrated Differential Functional Feature Heatmap",
        column_title_gp = grid::gpar(fontsize = 9, fontface = "bold"),
        row_title_gp = grid::gpar(fontsize = 7, fontface = "bold"),
        heatmap_legend_param = list(
          title = "Z-score",
          title_gp = grid::gpar(fontsize = 7, fontface = "bold"),
          labels_gp = grid::gpar(fontsize = 7),
          legend_height = grid::unit(25, "mm"),
          border = "grey40"
        ),
        border = TRUE,
        width = grid::unit(95, "mm")
      )

      export_heatmap(
        ht,
        file.path(out_dir, "heatmap_multidatabase"),
        width_mm = width_2col,
        height_mm = heatmap_height_mm
      )
      heatmap_generated <- TRUE

      heatmap_result <- list(
        n_features = nrow(heatmap_mat),
        message = sprintf("Heatmap exported for %d significant features across %d databases",
                          nrow(heatmap_mat), length(present_db_levels))
      )
    }
  }
  heatmap_result
})

# ========== Step 3: Faceted volcano plot grid ==========
run_step("volcano_generation", {
  q_floor <- 1e-300
  y_cap <- 50

  plot_df <- all_results %>%
    dplyr::filter(!is.na(.data$coef), !is.na(.data$qval)) %>%
    dplyr::mutate(
      func_type = factor(.data$func_type, levels = func_types),
      significance = dplyr::if_else(.data$qval < 0.05, "Significant", "Not significant"),
      neg_log10_qval = -log10(pmax(.data$qval, q_floor)),
      neg_log10_qval = pmin(.data$neg_log10_qval, y_cap),
      significance = factor(.data$significance, levels = c("Not significant", "Significant"))
    ) %>%
    dplyr::arrange(.data$significance)

  facet_blank <- tibble::tibble(
    func_type = factor(func_types, levels = func_types),
    coef = 0,
    neg_log10_qval = 0
  )

  annotation_df <- summary_table %>%
    dplyr::filter(.data$Significant_features == 0L) %>%
    dplyr::mutate(
      func_type = factor(.data$Database, levels = func_types),
      label = dplyr::case_when(
        .data$Features_tested > 0L ~ sprintf(
          "No significant features\n(n=%d tested)",
          .data$Features_tested
        ),
        TRUE ~ "No tested features"
      ),
      coef = 0,
      neg_log10_qval = Inf
    )

  threshold_annotation <- purrr::map_dfr(func_types, function(ft) {
    ft_df <- plot_df %>%
      dplyr::filter(as.character(.data$func_type) == ft)
    coef_values <- ft_df$coef[is.finite(ft_df$coef)]
    coef_range <- if (length(coef_values)) range(coef_values) else c(-1, 1)
    fdr_label_x <- coef_range[1] + diff(coef_range) * 0.72
    if (!is.finite(fdr_label_x) || diff(coef_range) == 0) {
      fdr_label_x <- coef_range[2]
    }
    tibble::tibble(
      func_type = factor(ft, levels = func_types),
      coef = fdr_label_x,
      neg_log10_qval = -log10(0.05) * 1.1,
      label = "FDR = 0.05"
    )
  })

  n_cols <- min(3, length(func_types))
  n_rows <- ceiling(length(func_types) / n_cols)

  p_volcano <- ggplot() +
    geom_blank(data = facet_blank, aes(x = .data$coef, y = .data$neg_log10_qval)) +
    geom_vline(xintercept = 0, linewidth = sci_linewidth, color = "grey50") +
    geom_vline(xintercept = c(-1, 1), linetype = "dashed",
               color = "grey30", linewidth = sci_linewidth) +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed",
               color = "grey30", linewidth = sci_linewidth) +
    geom_text(
      data = threshold_annotation,
      aes(x = .data$coef, y = .data$neg_log10_qval, label = .data$label),
      inherit.aes = FALSE,
      size = sci_text_size,
      color = "grey30",
      hjust = 0
    ) +
    geom_point(
      data = plot_df,
      aes(x = .data$coef, y = .data$neg_log10_qval, color = .data$significance),
      alpha = 0.72,
      size = 0.85,
      stroke = 0
    ) +
    geom_text(
      data = annotation_df,
      aes(x = .data$coef, y = .data$neg_log10_qval, label = .data$label),
      inherit.aes = FALSE,
      size = sci_text_size,
      color = "grey30",
      vjust = 1.25,
      lineheight = 0.9
    ) +
    facet_wrap(~ func_type, scales = "free", ncol = n_cols, drop = FALSE) +
    scale_color_manual(
      values = c("Not significant" = "grey70", "Significant" = "#E64B35"),
      name = NULL
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.04, 0.18))) +
    labs(
      x = "Coefficient (case vs control)",
      y = "-log<sub>10</sub>(<i>q</i>-value)",
      title = "Integrated Functional Differential Abundance"
    ) +
    theme_pub(base_size = 7) +
    theme(
      axis.title.y = ggtext::element_markdown(),
      plot.title = element_text(size = 9, face = "bold", hjust = 0.5),
      legend.position = "bottom",
      legend.key.size = grid::unit(3, "mm"),
      strip.background = element_rect(fill = "grey95", color = "grey80", linewidth = sci_linewidth),
      panel.spacing = grid::unit(2, "mm")
    )

  export_pub_figure(
    p_volcano,
    file.path(out_dir, "volcano_faceted"),
    width_mm = width_2col,
    height_mm = max(95, n_rows * 54 + 22)
  )
  volcano_generated <- TRUE

  list(
    n_features = nrow(plot_df),
    message = sprintf("Volcano grid exported with %d tested feature rows", nrow(plot_df))
  )
})

# ========== Step 4: Summary table ==========
run_step("table_generation", {
  summary_out <- summary_table %>%
    dplyr::select(dplyr::all_of(c(
      "Database", "Features_tested", "Significant_features", "Note"
    )))

  utils::write.table(
    summary_out,
    file.path(out_dir, "summary_table.tsv"),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )
  summary_generated <- TRUE

  list(
    n_features = nrow(summary_out),
    message = sprintf("Summary table exported for %d databases", nrow(summary_out))
  )
})

# ========== Step 5: Export verification ==========
run_step("export", {
  expected_files <- c(
    file.path(out_dir, "volcano_faceted.pdf"),
    file.path(out_dir, "volcano_faceted.svg"),
    file.path(out_dir, "volcano_faceted.tiff"),
    file.path(out_dir, "summary_table.tsv")
  )

  if (isTRUE(heatmap_generated)) {
    expected_files <- c(
      expected_files,
      file.path(out_dir, "heatmap_multidatabase.pdf"),
      file.path(out_dir, "heatmap_multidatabase.svg"),
      file.path(out_dir, "heatmap_multidatabase.tiff")
    )
  }

  missing_files <- expected_files[!file.exists(expected_files) | file.info(expected_files)$size == 0]
  if (length(missing_files)) {
    stop("Missing or empty export files: ", paste(missing_files, collapse = ", "))
  }

  writeLines(format(Sys.time()), sentinel)

  list(
    n_features = sum(summary_table$Significant_features),
    message = sprintf("Verified %d exported files", length(expected_files))
  )
})

cat("[INFO] Integrated functional visualization finished\n")
