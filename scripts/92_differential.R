#!/usr/bin/env Rscript
# ==============================================================================
# Script: 92_differential.R
# Purpose: Differential abundance analysis + publication-ready differential figures
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

required_pkgs <- c(
  "ALDEx2", "Maaslin2", "MicrobiomeStat", "ANCOMBC", "phyloseq",
  "tidyverse", "UpSetR", "ggplot2", "ggrepel"
)
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(ALDEx2)
  library(Maaslin2)
  library(MicrobiomeStat)
  library(ANCOMBC)
  library(phyloseq)
  library(tidyverse)
  library(UpSetR)
  library(ggplot2)
  library(ggrepel)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")
threads <- as.integer(Sys.getenv("THREADS", "1"))
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
dimension_req <- Sys.getenv("DIMENSION")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
result_dir <- Sys.getenv("RESULT_DIR")
viz_dir <- Sys.getenv("VIZ_DIR")
force_run <- as.integer(Sys.getenv("FORCE", "0"))

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Starting differential abundance analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Metadata:", metadata_csv, "\n")
cat("  Group column:", group_col, "\n")
cat("  Dimension:", dimension_req, "\n")
cat("  Threads:", threads, "\n")
cat("  Result dir:", result_dir, "\n")
cat("  Visualization dir:", viz_dir, "\n")

status_log <- list()
summary_rows <- list()
viz_rows <- list()
volcano_candidates <- list()

log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- tibble(step = step, status = status, message = message)
}

log_viz_status <- function(plot_name, status, message = "", output = "") {
  viz_rows[[length(viz_rows) + 1]] <<- tibble(
    plot = plot_name,
    status = status,
    message = message,
    output = output
  )
}

add_volcano_candidate <- function(dimension, method, data) {
  existing <- volcano_candidates[[dimension]] %||% list()
  existing[[length(existing) + 1]] <- list(method = method, data = data)
  volcano_candidates[[dimension]] <<- existing
}

init_volcano_dimension <- function(dimension) {
  existing <- volcano_candidates
  existing[[dimension]] <- list()
  volcano_candidates <<- existing
}

add_summary_row <- function(row) {
  summary_rows[[length(summary_rows) + 1]] <<- row
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
      legend.title = element_text(face = "bold"),
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
  meta <- readr::read_csv(path, show_col_types = FALSE)
  if (nrow(meta) == 0) {
    stop("Metadata is empty")
  }

  sample_candidates <- c("sample", "sample_id", "SampleID", "Sample", "id")
  sample_col <- sample_candidates[sample_candidates %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)

  if (!group_col %in% names(meta)) {
    stop("Group column missing: ", group_col)
  }

  meta <- meta %>%
    dplyr::mutate(
      sample_id = as.character(sample_id),
      !!group_col := as.factor(.data[[group_col]])
    ) %>%
    dplyr::filter(!is.na(sample_id), !is.na(.data[[group_col]])) %>%
    dplyr::distinct(sample_id, .keep_all = TRUE) %>%
    as.data.frame()

  rownames(meta) <- meta$sample_id
  meta
}

read_abundance_table <- function(path, label = basename(path)) {
  if (!file.exists(path)) {
    stop("Missing input table: ", path)
  }

  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  if (nrow(raw) == 0) {
    stop(label, " table is empty")
  }

  feature_col <- names(raw)[1]
  candidate_numeric <- names(raw)[vapply(
    raw,
    function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0,
    logical(1)
  )]
  sample_cols <- setdiff(candidate_numeric, feature_col)
  if (length(sample_cols) == 0) {
    stop("No sample columns found in ", path)
  }

  tab <- raw %>%
    dplyr::select(all_of(c(feature_col, sample_cols))) %>%
    dplyr::rename(feature = !!feature_col)

  tab[sample_cols] <- coerce_numeric_df(tab[sample_cols])
  tab <- tab %>%
    dplyr::filter(!is.na(feature), feature != "") %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(dplyr::across(all_of(sample_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")

  mat <- as.matrix(tab[, sample_cols, drop = FALSE])
  rownames(mat) <- tab$feature
  mat[is.na(mat)] <- 0
  mat[rowSums(mat) > 0, , drop = FALSE]
}

read_fungi_profiles <- function(dir_path) {
  files <- Sys.glob(file.path(dir_path, "*", "*_profile.txt"))
  if (length(files) == 0) {
    stop("No fungi profile files found in ", dir_path)
  }

  prof_list <- lapply(files, function(fp) {
    raw_lines <- readLines(fp)
    data_lines <- raw_lines[!startsWith(raw_lines, "#")]
    if (length(data_lines) == 0) {
      return(NULL)
    }

    tab <- readr::read_tsv(
      I(paste(data_lines, collapse = "\n")),
      show_col_types = FALSE,
      col_names = c("clade_name", "ncbi_tax_id", "relative_abundance", "additional_species"),
      col_types = "ccdc"
    )
    tab <- tab[tab$clade_name != "UNCLASSIFIED" & !is.na(tab$relative_abundance), ]
    if (nrow(tab) == 0) {
      return(NULL)
    }

    sample_id <- basename(dirname(fp))
    tibble(feature = as.character(tab$clade_name), sample_id = sample_id, abundance = tab$relative_abundance)
  })

  prof_list <- Filter(Negate(is.null), prof_list)
  if (length(prof_list) == 0) {
    stop("No fungi taxa found in any profile")
  }

  prof_df <- dplyr::bind_rows(prof_list) %>%
    dplyr::filter(!is.na(feature), !is.na(abundance))
  if (nrow(prof_df) == 0) {
    stop("No usable fungi abundances parsed")
  }

  merged <- prof_df %>%
    dplyr::group_by(feature, sample_id) %>%
    dplyr::summarise(abundance = sum(abundance, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = sample_id, values_from = abundance, values_fill = 0)

  rn <- merged$feature
  merged <- as.matrix(merged[, -1, drop = FALSE])
  rownames(merged) <- rn
  merged[rowSums(merged) > 0, , drop = FALSE]
}

make_phyloseq <- function(mat, meta) {
  common <- intersect(colnames(mat), rownames(meta))
  if (length(common) < 4) {
    stop("Need at least four overlapping samples for DA")
  }

  mat <- mat[, common, drop = FALSE]
  meta <- meta[common, , drop = FALSE]
  phyloseq(otu_table(mat, taxa_are_rows = TRUE), sample_data(meta))
}

prep_counts <- function(mat) {
  scaled <- sweep(mat, 2, colSums(mat), "/")
  scaled[is.na(scaled)] <- 0
  round(scaled * 1e6) + 1L
}

extract_binary_subset <- function(meta, group_col) {
  lvls <- levels(as.factor(meta[[group_col]]))
  if (length(lvls) < 2) {
    stop("Need at least two groups")
  }

  keep <- meta[[group_col]] %in% lvls[1:2]
  meta2 <- meta[keep, , drop = FALSE]
  meta2[[group_col]] <- droplevels(as.factor(meta2[[group_col]]))
  meta2
}

standardize_method_result <- function(
  df,
  dimension,
  method,
  feature_col,
  effect_col,
  padj_col,
  pvalue_col = NULL,
  significant = NULL,
  supplementary = FALSE
) {
  out <- tibble(
    dimension = dimension,
    method = method,
    taxon = as.character(df[[feature_col]]),
    feature = as.character(df[[feature_col]]),
    effect = suppressWarnings(as.numeric(df[[effect_col]])),
    log2FoldChange = suppressWarnings(as.numeric(df[[effect_col]])),
    pvalue = if (!is.null(pvalue_col) && pvalue_col %in% names(df)) suppressWarnings(as.numeric(df[[pvalue_col]])) else NA_real_,
    padj = suppressWarnings(as.numeric(df[[padj_col]])),
    supplementary = supplementary
  ) %>%
    dplyr::filter(!is.na(taxon), taxon != "")

  if (is.null(significant)) {
    out <- out %>% dplyr::mutate(significant = !is.na(padj) & padj < 0.05)
  } else if (is.character(significant) && length(significant) == 1 && significant %in% names(df)) {
    out <- out %>% dplyr::mutate(significant = as.logical(df[[significant]]))
  } else {
    out <- out %>% dplyr::mutate(significant = as.logical(significant))
  }

  out
}

write_method_result <- function(df, dimension, method) {
  out <- file.path(result_dir, paste0(dimension, "_", method, ".tsv"))
  readr::write_tsv(df, out)
  out
}

plot_upset <- function(sig_lists, out_file) {
  if (length(sig_lists) == 0 || all(lengths(sig_lists) == 0)) {
    return(invisible(NULL))
  }

  pdf(out_file, width = 10, height = 8)
  suppressWarnings(print(UpSetR::upset(UpSetR::fromList(sig_lists), nsets = length(sig_lists), order.by = "freq")))
  dev.off()
}

plot_heatmap <- function(df, out_file) {
  if (nrow(df) == 0) {
    return(invisible(NULL))
  }

  pdf(out_file, width = 12, height = 8)
  p <- df %>%
    ggplot(aes(x = method, y = forcats::fct_reorder(taxon, effect, .fun = max, na.rm = TRUE), fill = effect)) +
    geom_tile(color = "white") +
    facet_wrap(~dimension, scales = "free_y") +
    scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0) +
    theme_publication(base_size = 11) +
    labs(x = NULL, y = "Taxon", fill = "Effect", title = "Top differential taxa across methods")
  print(p)
  dev.off()
}

safe_padj_transform <- function(x) {
  -log10(pmax(x, .Machine$double.xmin))
}

pick_volcano_source <- function(candidates_by_dimension) {
  priority <- c("DESeq2", "ANCOMBC2", "edgeR", "LinDA", "MaAsLin2", "ALDEx2")
  chosen <- list()

  for (dimension in names(candidates_by_dimension)) {
    entries <- candidates_by_dimension[[dimension]]
    if (length(entries) == 0) {
      next
    }

    methods <- vapply(entries, function(x) x$method, character(1))
    idx <- match(priority, methods)
    idx <- idx[!is.na(idx)][1] %||% 1L
    chosen[[dimension]] <- entries[[idx]]
  }

  chosen
}

generate_volcano_plot <- function(candidates_by_dimension, out_file, case_label, control_label, force_run = 0) {
  if (force_run == 0 && file.exists(out_file) && file.info(out_file)$size > 0) {
    message("[INFO] Existing volcano plot detected, skipping: ", out_file)
    log_viz_status("volcano_plot", "SKIPPED", "Existing output", out_file)
    return(invisible(FALSE))
  }

  chosen <- pick_volcano_source(candidates_by_dimension)
  if (length(chosen) == 0) {
    msg <- "No eligible differential results found for volcano plot"
    message("[WARN] ", msg)
    log_viz_status("volcano_plot", "SKIPPED", msg, out_file)
    return(invisible(FALSE))
  }

  volcano_df <- bind_rows(lapply(chosen, function(entry) entry$data))
  volcano_df <- volcano_df %>%
    dplyr::filter(!is.na(log2FoldChange), !is.na(padj)) %>%
    dplyr::mutate(
      feature = feature %||% taxon,
      significance = dplyr::case_when(
        padj < 0.05 & log2FoldChange > 1 ~ "Up",
        padj < 0.05 & log2FoldChange < -1 ~ "Down",
        TRUE ~ "ns"
      ),
      neg_log10_padj = safe_padj_transform(padj)
    )

  if (nrow(volcano_df) == 0) {
    msg <- "Differential results lacked usable log2FoldChange/padj values"
    message("[WARN] ", msg)
    log_viz_status("volcano_plot", "SKIPPED", msg, out_file)
    return(invisible(FALSE))
  }

  label_df <- volcano_df %>%
    dplyr::filter(significance != "ns") %>%
    dplyr::group_by(dimension) %>%
    dplyr::arrange(padj, dplyr::desc(abs(log2FoldChange)), .by_group = TRUE) %>%
    dplyr::slice_head(n = 20) %>%
    dplyr::ungroup()

  x_label <- paste0("log2FoldChange (positive = enriched in ", case_label, "; negative = enriched in ", control_label, ")")

  pdf_width <- if (dplyr::n_distinct(volcano_df$dimension) > 1) 12 else 8.5
  pdf(out_file, width = pdf_width, height = 8)
  p <- ggplot(volcano_df, aes(x = log2FoldChange, y = neg_log10_padj, color = significance)) +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", linewidth = 0.5, color = "grey50") +
    geom_vline(xintercept = c(-1, 1), linetype = "dashed", linewidth = 0.5, color = "grey50") +
    geom_point(alpha = 0.8, size = 2) +
    ggrepel::geom_text_repel(
      data = label_df,
      aes(label = feature),
      size = 3,
      box.padding = 0.35,
      point.padding = 0.2,
      max.overlaps = Inf,
      segment.alpha = 0.5,
      show.legend = FALSE
    ) +
    scale_color_manual(values = c(Up = "#b2182b", Down = "#2166ac", ns = "grey75")) +
    theme_publication() +
    labs(
      title = "Differential abundance volcano plot",
      subtitle = "Thresholds: FDR < 0.05 and |log2FoldChange| > 1",
      x = x_label,
      y = expression(-log[10]("adjusted p-value")),
      color = "Class"
    )

  if (dplyr::n_distinct(volcano_df$dimension) > 1) {
    p <- p + facet_wrap(~dimension, scales = "free")
  }

  print(p)
  dev.off()

  log_viz_status("volcano_plot", "GENERATED", paste0("Labeled top 20 significant features per dimension; case=", case_label), out_file)
  invisible(TRUE)
}

first_matching_col <- function(df, candidates, pattern = NULL) {
  exact <- candidates[candidates %in% names(df)][1]
  if (!is.na(exact) && length(exact) > 0) {
    return(exact)
  }

  if (!is.null(pattern)) {
    hits <- grep(pattern, names(df), ignore.case = TRUE, value = TRUE)
    if (length(hits) > 0) {
      return(hits[1])
    }
  }

  NULL
}

infer_dimension_from_path <- function(path) {
  lower_path <- tolower(path)
  for (dimension in c("bacteria", "virus", "fungi")) {
    if (grepl(dimension, lower_path, fixed = TRUE)) {
      return(dimension)
    }
  }
  "all"
}

read_lefse_candidate <- function(path, case_label, control_label) {
  df <- tryCatch(
    readr::read_tsv(path, show_col_types = FALSE, comment = "#"),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) == 0) {
    return(NULL)
  }

  feature_col <- first_matching_col(df, c("feature", "taxon", "taxa", "biomarker", "name"), "feature|tax|biomarker|name")
  score_col <- first_matching_col(df, c("LDA_score", "lda_score", "lda", "LDA", "score"), "lda|score")
  direction_col <- first_matching_col(df, c("direction", "class", "group", "enriched_in", "condition"), "direction|class|group|enriched")
  dimension_col <- first_matching_col(df, c("dimension", "kingdom", "dataset"), "dimension|dataset")

  if (is.null(feature_col) || is.null(score_col)) {
    return(NULL)
  }

  out <- tibble(
    feature = as.character(df[[feature_col]]),
    lda_score = suppressWarnings(as.numeric(df[[score_col]])),
    direction_raw = if (!is.null(direction_col)) as.character(df[[direction_col]]) else NA_character_,
    dimension = if (!is.null(dimension_col)) as.character(df[[dimension_col]]) else infer_dimension_from_path(path),
    source_file = path
  ) %>%
    dplyr::filter(!is.na(feature), feature != "", !is.na(lda_score))

  if (nrow(out) == 0) {
    return(NULL)
  }

  direction_lower <- tolower(out$direction_raw %||% "")
  has_signed_scores <- any(out$lda_score < 0, na.rm = TRUE) && any(out$lda_score > 0, na.rm = TRUE)
  case_pattern <- paste(unique(c(tolower(case_label), "case", "treatment", "disease", "positive", "up")), collapse = "|")
  control_pattern <- paste(unique(c(tolower(control_label), "control", "healthy", "negative", "down")), collapse = "|")
  inferred_sign <- dplyr::case_when(
    !is.na(direction_lower) & grepl(case_pattern, direction_lower) ~ 1,
    !is.na(direction_lower) & grepl(control_pattern, direction_lower) ~ -1,
    TRUE ~ NA_real_
  )

  if (all(is.na(inferred_sign))) {
    if (!has_signed_scores) {
      message("[WARN] Skipping LEfSe file without direction or signed LDA scores: ", path)
      return(NULL)
    }
    inferred_sign <- dplyr::if_else(out$lda_score < 0, -1, 1)
  }

  out %>%
    dplyr::mutate(
      signed_lda = abs(lda_score) * inferred_sign,
      direction = dplyr::if_else(signed_lda >= 0, case_label, control_label)
    )
}

reorder_within <- function(x, by, within, fun = mean, sep = "___", ...) {
  stats::reorder(paste(x, within, sep = sep), by, FUN = fun)
}

scale_y_reordered <- function(..., sep = "___") {
  scale_y_discrete(labels = function(x) gsub(paste0(sep, ".+$"), "", x), ...)
}

generate_lefse_bar_plot <- function(search_roots, out_file, case_label, control_label, force_run = 0) {
  if (force_run == 0 && file.exists(out_file) && file.info(out_file)$size > 0) {
    message("[INFO] Existing LEfSe LDA plot detected, skipping: ", out_file)
    log_viz_status("lefse_lda_bars", "SKIPPED", "Existing output", out_file)
    return(invisible(FALSE))
  }

  candidate_files <- unique(unlist(lapply(search_roots, function(root) {
    if (!dir.exists(root)) {
      return(character(0))
    }
    files <- list.files(root, pattern = "\\.(tsv|txt)$", recursive = TRUE, full.names = TRUE)
    files[grepl("(lefse|lda)", basename(files), ignore.case = TRUE)]
  })))
  candidate_files <- candidate_files[!grepl("viz_status|diff_status|diff_summary", candidate_files, ignore.case = TRUE)]

  lefse_tbls <- lapply(candidate_files, read_lefse_candidate, case_label = case_label, control_label = control_label)
  lefse_tbls <- Filter(function(x) !is.null(x) && nrow(x) > 0, lefse_tbls)

  if (length(lefse_tbls) == 0) {
    msg <- "No LEfSe results found with feature and LDA score columns"
    message("[WARN] ", msg)
    log_viz_status("lefse_lda_bars", "SKIPPED", msg, out_file)
    pdf(out_file, width = 8, height = 6); plot.new()
    text(0.5, 0.5, "LEfSe: no results available\n(insufficient samples or tool not run)", cex = 1.1)
    dev.off()
    return(invisible(FALSE))
  }

  lefse_df <- bind_rows(lefse_tbls) %>%
    dplyr::filter(!is.na(signed_lda))
  if (nrow(lefse_df) == 0) {
    msg <- "LEfSe results were present but contained no usable LDA scores"
    message("[WARN] ", msg)
    log_viz_status("lefse_lda_bars", "SKIPPED", msg, out_file)
    pdf(out_file, width = 8, height = 6); plot.new()
    text(0.5, 0.5, "LEfSe: no usable LDA scores\n(insufficient differential signal)", cex = 1.1)
    dev.off()
    return(invisible(FALSE))
  }

  plot_df <- lefse_df %>%
    dplyr::group_by(dimension) %>%
    dplyr::arrange(dplyr::desc(abs(signed_lda)), .by_group = TRUE) %>%
    dplyr::slice_head(n = 30) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(feature_plot = reorder_within(feature, signed_lda, dimension))

  pdf_width <- if (dplyr::n_distinct(plot_df$dimension) > 1) 13 else 10
  pdf_height <- max(7, min(14, 4 + 0.18 * nrow(plot_df)))
  pdf(out_file, width = pdf_width, height = pdf_height)
  p <- ggplot(plot_df, aes(x = signed_lda, y = feature_plot, fill = direction)) +
    geom_vline(xintercept = 0, linewidth = 0.5, color = "grey40") +
    geom_col(width = 0.75) +
    scale_y_reordered() +
    scale_fill_manual(values = stats::setNames(c("#b2182b", "#2166ac"), c(case_label, control_label))) +
    theme_publication(base_size = 11) +
    labs(
      title = "LEfSe LDA biomarkers",
      subtitle = "Top 30 features ranked by absolute LDA score",
      x = "Signed LDA score",
      y = NULL,
      fill = "Enriched in"
    )

  if (dplyr::n_distinct(plot_df$dimension) > 1) {
    p <- p + facet_wrap(~dimension, scales = "free_y")
  }

  print(p)
  dev.off()

  log_viz_status("lefse_lda_bars", "GENERATED", "Top 30 absolute LDA features per dimension", out_file)
  invisible(TRUE)
}

meta <- read_metadata(metadata_csv, group_col)
datasets <- list(
  bacteria = tryCatch(read_abundance_table(bact_table, "bacteria"), error = function(e) NULL),
  virus = tryCatch(read_abundance_table(vir_table, "virus"), error = function(e) NULL),
  fungi = tryCatch(read_fungi_profiles(fungi_dir), error = function(e) NULL)
)

dimensions <- if (dimension_req == "all") names(datasets) else dimension_req
dimensions <- dimensions[dimensions %in% names(datasets)]
if (length(dimensions) == 0) {
  stop("No valid dimensions selected")
}

case_label <- NA_character_
control_label <- NA_character_

for (dimension in dimensions) {
  run_step(paste0(dimension, "_differential"), {
    mat0 <- datasets[[dimension]]
    if (is.null(mat0)) {
      stop("Input unavailable for dimension: ", dimension)
    }

    common <- intersect(colnames(mat0), rownames(meta))
    if (length(common) < 4) {
      stop("Insufficient overlapping samples")
    }

    mat0 <- mat0[, common, drop = FALSE]
    meta0 <- meta[common, , drop = FALSE]
    meta_bin <- extract_binary_subset(meta0, group_col)

    if (is.na(case_label[1])) {
      control_label <<- levels(meta_bin[[group_col]])[1]
      case_label <<- levels(meta_bin[[group_col]])[2]
    }

    mat <- mat0[, rownames(meta_bin), drop = FALSE]
    mat <- mat[rowMeans(mat > 0) >= 0.05, , drop = FALSE]
    counts <- prep_counts(mat)
    ps <- make_phyloseq(counts, meta_bin)
    dim_dir <- file.path(result_dir, dimension)
    dir.create(dim_dir, recursive = TRUE, showWarnings = FALSE)

    method_results <- list()
    sig_sets <- list()
    init_volcano_dimension(dimension)

    run_step(paste0(dimension, "_aldex2"), {
      conds <- meta_bin[[group_col]]
      aldex_res <- ALDEx2::aldex(counts, conds, mc.samples = 128, test = "wilcox", effect = TRUE, denom = "all", verbose = FALSE)
      aldex_tbl <- tibble::rownames_to_column(as.data.frame(aldex_res), "taxon")
      padj_col <- c("wi.eBH", "we.eBH", "kw.eBH")[c("wi.eBH", "we.eBH", "kw.eBH") %in% names(aldex_tbl)][1] %||% "wi.eBH"
      effect_col <- c("effect", "diff.btw", "rab.win.conditionA")[c("effect", "diff.btw", "rab.win.conditionA") %in% names(aldex_tbl)][1] %||% names(aldex_tbl)[2]
      pvalue_col <- c("wi.ep", "we.ep", "kw.ep")[c("wi.ep", "we.ep", "kw.ep") %in% names(aldex_tbl)][1]
      out <- standardize_method_result(aldex_tbl, dimension, "ALDEx2", "taxon", effect_col, padj_col, pvalue_col, supplementary = FALSE)
      method_results$ALDEx2 <- out
      sig_sets$ALDEx2 <- out$taxon[out$significant]
      add_volcano_candidate(dimension, "ALDEx2", out)
      write_method_result(out, dimension, "aldex2")
    })

    run_step(paste0(dimension, "_maaslin2"), {
      batch_col <- c("batch", "Batch", "batch_id")[c("batch", "Batch", "batch_id") %in% names(meta_bin)][1]
      maaslin_outdir <- file.path(dim_dir, "maaslin2_out")
      dir.create(maaslin_outdir, recursive = TRUE, showWarnings = FALSE)
      Maaslin2::Maaslin2(
        input_data = as.data.frame(t(counts)),
        input_metadata = meta_bin,
        output = maaslin_outdir,
        normalization = "NONE",
        transform = "LOG",
        fixed_effects = group_col,
        random_effects = batch_col,
        analysis_method = "LM"
      )
      maaslin_tbl <- readr::read_tsv(file.path(maaslin_outdir, "all_results.tsv"), show_col_types = FALSE)
      maaslin_tbl <- maaslin_tbl %>% dplyr::filter(metadata == group_col)
      out <- standardize_method_result(maaslin_tbl, dimension, "MaAsLin2", "feature", "coef", "qval", "pval", supplementary = FALSE)
      method_results$MaAsLin2 <- out
      sig_sets$MaAsLin2 <- out$taxon[out$significant]
      add_volcano_candidate(dimension, "MaAsLin2", out)
      write_method_result(out, dimension, "maaslin2")
    })

    run_step(paste0(dimension, "_linda"), {
      linda_fit <- MicrobiomeStat::linda(
        feature.dat = counts,
        meta.dat = meta_bin,
        formula = paste0("~", group_col),
        feature.dat.type = "count"
      )
      linda_tbl <- linda_fit$output[[group_col]] %||% linda_fit$output[[1]] %||%
        stop("LinDA output not recognized for formula term: ", group_col)
      linda_tbl <- tibble::rownames_to_column(as.data.frame(linda_tbl), "taxon")
      if (!"taxon" %in% names(linda_tbl)) {
        linda_tbl$taxon <- rownames(linda_tbl)
      }
      padj_col <- c("padj", "p_adj", "qvalue")[c("padj", "p_adj", "qvalue") %in% names(linda_tbl)][1] %||% names(linda_tbl)[grep("padj|q", names(linda_tbl), ignore.case = TRUE)[1]]
      effect_col <- c("stat", "estimate", "log2FoldChange")[c("stat", "estimate", "log2FoldChange") %in% names(linda_tbl)][1] %||% names(linda_tbl)[grep("coef|estimate|stat", names(linda_tbl), ignore.case = TRUE)[1]]
      pvalue_col <- c("pvalue", "p_value", "pval")[c("pvalue", "p_value", "pval") %in% names(linda_tbl)][1]
      out <- standardize_method_result(linda_tbl, dimension, "LinDA", "taxon", effect_col, padj_col, pvalue_col, supplementary = FALSE)
      method_results$LinDA <- out
      sig_sets$LinDA <- out$taxon[out$significant]
      add_volcano_candidate(dimension, "LinDA", out)
      write_method_result(out, dimension, "linda")
    })

    run_step(paste0(dimension, "_ancombc2"), {
      ps_ancom <- phyloseq(otu_table(counts, taxa_are_rows = TRUE), sample_data(meta_bin))
      ancom_out <- ANCOMBC::ancombc2(
        data = ps_ancom,
        fix_formula = group_col,
        group = if (nlevels(meta_bin[[group_col]]) > 2) group_col else NULL,
        pseudo_sens = TRUE,
        prv_cut = 0.05,
        lib_cut = 0,
        struc_zero = TRUE,
        neg_lb = TRUE,
        alpha = 0.05,
        n_cl = threads,
        global = FALSE,
        pairwise = FALSE,
        verbose = FALSE
      )
      ancom_tbl <- ancom_out$res %||% ancom_out$res_prim %||% stop("ANCOM-BC2 output not recognized")
      if (!"taxon" %in% names(ancom_tbl)) {
        ancom_tbl$taxon <- rownames(ancom_tbl)
      }
      padj_col <- grep("^q_", names(ancom_tbl), value = TRUE)[1] %||% grep("q|adj", names(ancom_tbl), value = TRUE)[1]
      effect_col <- grep("^lfc_", names(ancom_tbl), value = TRUE)[1] %||% grep("lfc|beta", names(ancom_tbl), value = TRUE)[1]
      pvalue_col <- grep("^p_", names(ancom_tbl), value = TRUE)[1] %||% grep("^pvalue$|^p_val$|^p$", names(ancom_tbl), value = TRUE)[1]
      diff_col <- grep("^diff_", names(ancom_tbl), value = TRUE)[1]
      out <- standardize_method_result(
        ancom_tbl,
        dimension,
        "ANCOMBC2",
        "taxon",
        effect_col,
        padj_col,
        pvalue_col,
        significant = if (!is.null(diff_col)) diff_col else NULL,
        supplementary = TRUE
      )
      method_results$ANCOMBC2 <- out
      sig_sets$ANCOMBC2 <- out$taxon[out$significant]
      add_volcano_candidate(dimension, "ANCOMBC2", out)
      write_method_result(out, dimension, "ancombc2")
    })

    merged <- bind_rows(method_results)
    if (nrow(merged) == 0) {
      stop("No method produced results for ", dimension)
    }

    merged_consensus <- merged %>%
      dplyr::filter(significant) %>%
      dplyr::group_by(dimension, taxon) %>%
      dplyr::summarise(
        method_count = dplyr::n_distinct(method),
        methods = paste(sort(unique(method)), collapse = ";"),
        mean_effect = mean(effect, na.rm = TRUE),
        supplementary_hit = any(supplementary),
        .groups = "drop"
      ) %>%
      dplyr::filter(method_count >= 2) %>%
      dplyr::arrange(dplyr::desc(method_count), dplyr::desc(abs(mean_effect)))

    readr::write_tsv(merged, file.path(result_dir, paste0(dimension, "_merged_methods.tsv")))
    readr::write_tsv(merged_consensus, file.path(result_dir, paste0(dimension, "_consensus.tsv")))

    plot_upset(sig_sets, file.path(result_dir, paste0(dimension, "_overlap_upset.pdf")))
    top_heat <- merged %>%
      dplyr::filter(significant) %>%
      dplyr::group_by(taxon) %>%
      dplyr::mutate(top_rank = max(abs(effect), na.rm = TRUE)) %>%
      dplyr::ungroup() %>%
      dplyr::arrange(dplyr::desc(top_rank)) %>%
      dplyr::slice_head(n = 30)
    plot_heatmap(top_heat, file.path(result_dir, paste0(dimension, "_top30_heatmap.pdf")))

    add_summary_row(tibble(
      dimension = dimension,
      n_features = nrow(counts),
      n_samples = ncol(counts),
      consensus_taxa = nrow(merged_consensus)
    ))
  })
}

summary_df <- bind_rows(summary_rows)
status_df <- bind_rows(status_log)
if (nrow(summary_df) == 0) {
  summary_df <- tibble(
    dimension = character(),
    n_features = numeric(),
    n_samples = numeric(),
    consensus_taxa = numeric(),
    note = character()
  )
}

readr::write_tsv(summary_df, file.path(result_dir, "diff_summary.tsv"))
readr::write_tsv(status_df, file.path(result_dir, "diff_status.tsv"))

volcano_pdf <- file.path(viz_dir, "volcano_plot.pdf")
lefse_pdf <- file.path(viz_dir, "lefse_lda_bars.pdf")
viz_status_file <- file.path(result_dir, "viz_status.tsv")

if (is.na(case_label[1]) || is.na(control_label[1])) {
  meta_bin_global <- extract_binary_subset(meta, group_col)
  control_label <- levels(meta_bin_global[[group_col]])[1]
  case_label <- levels(meta_bin_global[[group_col]])[2]
}

run_step("viz_volcano_plot", {
  generate_volcano_plot(volcano_candidates, volcano_pdf, case_label, control_label, force_run)
})

run_step("viz_lefse_lda_bars", {
  generate_lefse_bar_plot(c(result_dir, file.path(workdir, "result")), lefse_pdf, case_label, control_label, force_run)
})

viz_status_df <- if (length(viz_rows) == 0) {
  tibble(plot = character(), status = character(), message = character(), output = character())
} else {
  bind_rows(viz_rows)
}
readr::write_tsv(viz_status_df, viz_status_file)
