#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, warn = 1)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
      normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("microeco", "magrittr", "dplyr", "tidyr")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))

suppressPackageStartupMessages({
  library(microeco)
  library(magrittr)
  library(dplyr)
  library(tidyr)
})

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")

plot_fns_available <- all(vapply(c("ggplot2", "ggrepel", "ggtext"), requireNamespace, logical(1), quietly = TRUE))
if (plot_fns_available) {
  source(file.path(repo, "scripts", "R", "plot_differential.R"))
}

# Optional PNG companion figures, only when MGX_FIGURE_FORMATS requests "png"
mgx_want_png <- function() {
  fmts <- tolower(trimws(strsplit(Sys.getenv("MGX_FIGURE_FORMATS", ""), ",")[[1]]))
  "png" %in% fmts && requireNamespace("ragg", quietly = TRUE)
}
threads <- suppressWarnings(as.integer(Sys.getenv("THREADS", "1")))
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
result_dir <- Sys.getenv("RESULT_DIR")
dimension_req <- Sys.getenv("DIMENSION", "all")
if (!nzchar(result_dir)) result_dir <- file.path(workdir, "result", "stat")
if (!is.na(threads) && threads > 0) options(mc.cores = threads)

stat_root <- Sys.getenv("STAT_ROOT")
if (!nzchar(stat_root)) {
  result_base <- basename(normalizePath(result_dir, winslash = "/", mustWork = FALSE))
  stat_root <- if (result_base == "diff") dirname(result_dir) else result_dir
}
dir.create(stat_root, recursive = TRUE, showWarnings = FALSE)

status_rows <- list()
summary_rows <- list()

add_status <- function(dimension, step, method = "", taxa_level = "", status = "OK", message = "", output_file = "") {
  status_rows[[length(status_rows) + 1]] <<- data.frame(
    dimension = dimension,
    step = step,
    method = method,
    taxa_level = taxa_level,
    status = status,
    message = message,
    output_file = output_file,
    stringsAsFactors = FALSE
  )
}

add_summary <- function(dimension, method, n_sig, top_feature, output_file) {
  summary_rows[[length(summary_rows) + 1]] <<- data.frame(
    dimension = dimension,
    method = method,
    n_sig = n_sig,
    top_feature = top_feature %||% "",
    output_file = output_file,
    stringsAsFactors = FALSE
  )
}

empty_status <- function() data.frame(
  dimension = character(),
  step = character(),
  method = character(),
  taxa_level = character(),
  status = character(),
  message = character(),
  output_file = character(),
  stringsAsFactors = FALSE
)

empty_summary <- function() data.frame(
  dimension = character(),
  method = character(),
  n_sig = integer(),
  top_feature = character(),
  output_file = character(),
  stringsAsFactors = FALSE
)

write_tsv <- function(x, path, row_names = FALSE) {
  write.table(x, path, sep = "\t", quote = FALSE, row.names = row_names, col.names = !row_names, na = "")
}

clone_mt <- function(mt) {
  if (!is.null(mt$clone) && is.function(mt$clone)) {
    mt$clone(deep = TRUE)
  } else {
    mt
  }
}

safe_write <- function(dimension, step, method, taxa_level, path, expr) {
  tryCatch({
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    force(expr)
    add_status(dimension, step, method, taxa_level, "OK", "", path)
    TRUE
  }, error = function(e) {
    message("[WARN] ", dimension, " ", method, ": ", conditionMessage(e))
    add_status(dimension, step, method, taxa_level, "FAILED", conditionMessage(e), path)
    FALSE
  })
}

count_sig <- function(res) {
  if (is.null(res) || !nrow(res)) return(0L)
  if ("diff" %in% names(res)) return(sum(!is.na(res$diff) & res$diff, na.rm = TRUE))
  if ("P.adj" %in% names(res)) return(sum(!is.na(res$P.adj) & res$P.adj < 0.05, na.rm = TRUE))
  if ("padj" %in% names(res)) return(sum(!is.na(res$padj) & res$padj < 0.05, na.rm = TRUE))
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
  } else if ("padj" %in% names(res)) {
    x <- res[!is.na(res$padj) & res$padj < 0.05, , drop = FALSE]
    if (nrow(x)) x <- x[order(x$padj), , drop = FALSE]
  } else {
    x <- res
  }
  if (!nrow(x)) return("")
  feat <- x$Taxa[1]
  if (!length(feat) || is.na(feat)) return("")
  as.character(feat)
}

prepare_mt <- function(mt) {
  x <- clone_mt(mt)
  if (!group_col %in% names(x$sample_table)) stop("Group column not found in sample_table: ", group_col)
  x$sample_table[[group_col]] <- as.character(x$sample_table[[group_col]])
  x$sample_table <- x$sample_table[
    !is.na(x$sample_table[[group_col]]) & nzchar(x$sample_table[[group_col]]),
    ,
    drop = FALSE
  ]
  x$sample_table[[group_col]] <- factor(x$sample_table[[group_col]])
  x$tidy_dataset()
  if (nrow(x$sample_table) < 2) stop("Fewer than 2 samples after filtering metadata")
  if (length(unique(as.character(x$sample_table[[group_col]]))) < 2) stop("Fewer than 2 groups in sample_table")
  x$cal_abund(rel = TRUE)
  x$filter_taxa(rel_abund = 0.001)
  x
}

enrich_virus_taxonomy <- function(mt, workdir) {
  genomad_path <- file.path(workdir, "result", "virus", "votu", "genomad", "virus_taxonomy.tsv")
  if (!file.exists(genomad_path)) {
    message("[INFO] geNomad taxonomy not found, skipping virus annotation")
    return(mt)
  }
  gdf <- tryCatch(
    read.table(genomad_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE),
    error = function(e) {
      message("[WARN] Cannot read genomad taxonomy: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(gdf) || !all(c("seq_name", "lineage") %in% names(gdf))) return(mt)

  parse_lin <- function(lin) {
    if (is.na(lin) || !nzchar(lin)) return(c(Domain = NA, Phylum = NA, Class = NA, Order = NA, Family = NA, Genus = NA))
    p <- strsplit(lin, ";")[[1]]
    p <- p[nzchar(p)]
    n <- length(p)
    c(
      Domain = if (n >= 1) p[1] else NA_character_,
      Phylum = if (n >= 4) p[4] else NA_character_,
      Class = if (n >= 5) p[5] else NA_character_,
      Order = if (n >= 6) p[6] else NA_character_,
      Family = if (n >= 7) p[7] else NA_character_,
      Genus = if (n >= 8) p[8] else NA_character_
    )
  }

  tax_mat <- do.call(rbind, lapply(gdf$lineage, parse_lin))
  rownames(tax_mat) <- gdf$seq_name
  tax_df_gen <- as.data.frame(tax_mat, stringsAsFactors = FALSE)

  new_tax <- mt$tax_table
  for (col in c("Domain", "Phylum", "Class", "Order", "Family", "Genus")) new_tax[[col]] <- NA_character_

  base_names <- sub("\\|\\|.*", "", rownames(new_tax))
  for (i in seq_len(nrow(new_tax))) {
    bn <- base_names[i]
    if (bn %in% rownames(tax_df_gen)) {
      for (col in c("Domain", "Phylum", "Class", "Order", "Family", "Genus")) {
        new_tax[i, col] <- tax_df_gen[bn, col]
      }
    }
  }
  mt$tax_table <- new_tax
  mt
}

run_diff <- function(mt, method, taxa_level, extra = list()) {
  args <- c(list(dataset = mt, method = method, group = group_col, taxa_level = taxa_level), extra)
  obj <- do.call(trans_diff$new, args)
  list(
    obj = obj,
    res = as.data.frame(obj$res_diff, stringsAsFactors = FALSE),
    n_sig = count_sig(obj$res_diff),
    top_feature = top_feature(obj$res_diff)
  )
}

choose_bacteria_level <- function(mt, output_path) {
  attempts <- c("Species", "Genus", "Phylum")
  best <- NULL
  for (lvl in attempts) {
    res <- tryCatch(
      run_diff(mt, "lefse", lvl, list(filter_thres = 0.001)),
      error = function(e) {
        add_status("bacteria", "diff", "lefse", lvl, "FAILED", conditionMessage(e), output_path)
        NULL
      }
    )
    if (is.null(res)) next
    best <- best %||% res
    if (res$n_sig >= 5L || lvl == "Phylum") return(res)
    if (res$n_sig >= best$n_sig) best <- res
  }
  best
}

has_file2meco <- function() {
  requireNamespace("file2meco", quietly = TRUE)
}

run_deseq2 <- function(mt) {
  if (!requireNamespace("DESeq2", quietly = TRUE)) return(NULL)
  counts <- round(as.matrix(mt$otu_table))
  samples <- intersect(colnames(counts), rownames(mt$sample_table))
  counts <- counts[, samples, drop = FALSE]
  metadata <- mt$sample_table[samples, , drop = FALSE]
  metadata[[group_col]] <- factor(metadata[[group_col]])
  if (nlevels(metadata[[group_col]]) != 2L) stop("DESeq2 requires exactly two groups")
  design <- stats::as.formula(paste("~", group_col))
  dds <- DESeq2::DESeqDataSetFromMatrix(countData = counts, colData = metadata, design = design)
  dds <- DESeq2::DESeq(dds, quiet = TRUE)
  res <- as.data.frame(DESeq2::results(dds), stringsAsFactors = FALSE)
  res$Taxa <- rownames(res)
  res[, c("Taxa", "log2FoldChange", "pvalue", "padj"), drop = FALSE]
}

run_maaslin2 <- function(mt, output_dir) {
  if (!requireNamespace("Maaslin2", quietly = TRUE)) return(NULL)
  abundance <- as.data.frame(t(as.matrix(mt$otu_table)), check.names = FALSE)
  metadata <- data.frame(row.names = rownames(mt$sample_table), stringsAsFactors = FALSE)
  metadata[[group_col]] <- as.character(mt$sample_table[[group_col]])
  samples <- intersect(rownames(abundance), rownames(metadata))
  fit <- Maaslin2::Maaslin2(
    input_data = abundance[samples, , drop = FALSE],
    input_metadata = metadata[samples, , drop = FALSE],
    output = output_dir,
    fixed_effects = group_col,
    transform = "AST",
    normalization = "TSS",
    standardize = FALSE,
    plot_heatmap = FALSE,
    plot_scatter = FALSE,
    min_abundance = 0,
    min_prevalence = 0.1
  )
  res <- as.data.frame(fit$results, stringsAsFactors = FALSE)
  if ("metadata" %in% names(res)) res <- res[res$metadata == group_col, , drop = FALSE]
  data.frame(
    Taxa = res$feature,
    coefficient = res$coef,
    pvalue = res$pval,
    qvalue = res$qval,
    stringsAsFactors = FALSE
  )
}

extract_group_means <- function(obj) {
  abund <- tryCatch(obj$res_abund, error = function(e) NULL)
  if (is.null(abund) || !all(c("Taxa", "Mean", "group") %in% names(abund))) return(NULL)
  if (!"Comparison" %in% names(obj$res_diff) || !nrow(obj$res_diff)) return(NULL)

  pair_example <- strsplit(as.character(obj$res_diff$Comparison[1]), " - ", fixed = TRUE)[[1]]
  grp_levels <- sort(unique(as.character(abund$group)))
  if (length(pair_example) == 2 && length(grp_levels) == 2) {
    grp_map <- setNames(pair_example, grp_levels)
    abund$grp_name <- grp_map[as.character(abund$group)]
  } else {
    abund$grp_name <- as.character(abund$group)
  }

  abund %>%
    select(Taxa, grp_name, Mean) %>%
    pivot_wider(names_from = grp_name, values_from = Mean, values_fill = 0)
}

format_wilcox_results <- function(obj) {
  res <- as.data.frame(obj$res_diff, stringsAsFactors = FALSE)
  if (!nrow(res)) {
    return(data.frame(
      Taxa = character(),
      P.unadj = numeric(),
      P.adj = numeric(),
      Comparison = character(),
      mean_group1 = numeric(),
      mean_group2 = numeric(),
      log2FC = numeric(),
      stringsAsFactors = FALSE
    ))
  }

  means_wide <- extract_group_means(obj)
  eps <- 1e-6
  out <- data.frame(
    Taxa = res$Taxa %||% NA_character_,
    P.unadj = if ("P.unadj" %in% names(res)) res$P.unadj else NA_real_,
    P.adj = if ("P.adj" %in% names(res)) res$P.adj else NA_real_,
    Comparison = if ("Comparison" %in% names(res)) res$Comparison else NA_character_,
    mean_group1 = NA_real_,
    mean_group2 = NA_real_,
    log2FC = NA_real_,
    stringsAsFactors = FALSE
  )

  if (!is.null(means_wide) && nrow(means_wide)) {
    for (i in seq_len(nrow(out))) {
      pair <- strsplit(as.character(out$Comparison[i]), " - ", fixed = TRUE)[[1]]
      rowi <- means_wide[means_wide$Taxa == as.character(out$Taxa[i]), , drop = FALSE]
      if (length(pair) == 2 && nrow(rowi) == 1 && all(pair %in% names(rowi))) {
        g1 <- as.numeric(rowi[[pair[1]]])
        g2 <- as.numeric(rowi[[pair[2]]])
        out$mean_group1[i] <- g1
        out$mean_group2[i] <- g2
        out$log2FC[i] <- log2((g1 + eps) / (g2 + eps))
      }
    }
  }

  out
}

format_lefse_results <- function(res) {
  res <- as.data.frame(res, stringsAsFactors = FALSE)
  if (!nrow(res)) {
    return(data.frame(
      Taxa = character(),
      LDA_score = numeric(),
      P.value = numeric(),
      Group = character(),
      stringsAsFactors = FALSE
    ))
  }

  lda_col <- intersect(c("LDA", "LDA_score", "lda"), names(res))[1]
  p_col <- intersect(c("P.unadj", "P.adj", "P.value", "pvalue", "p_value"), names(res))[1]
  group_col_res <- intersect(c("Group", "Groups", "Comparison", "group"), names(res))[1]

  data.frame(
    Taxa = if ("Taxa" %in% names(res)) res$Taxa else rownames(res),
    LDA_score = if (!is.na(lda_col) && nzchar(lda_col)) res[[lda_col]] else NA_real_,
    P.value = if (!is.na(p_col) && nzchar(p_col)) res[[p_col]] else NA_real_,
    Group = if (!is.na(group_col_res) && nzchar(group_col_res)) res[[group_col_res]] else NA_character_,
    stringsAsFactors = FALSE
  )
}

load_mt <- function(dim) {
  rds_path <- file.path(workdir, "result", "stat", dim, paste0(dim, "_microtable.rds"))
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

message("[INFO] Starting differential analysis")
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
  dim_dir <- file.path(stat_root, dim, "differential")
  dir.create(dim_dir, recursive = TRUE, showWarnings = FALSE)

  mt_raw <- load_mt(dim)
  if (is.null(mt_raw)) next
  if (dim == "virus") {
    mt_raw <- enrich_virus_taxonomy(mt_raw, workdir)
    # Drop vOTUs with no geNomad taxonomy (Domain = NA) — same filter as 91_diversity.R
    if ("Domain" %in% colnames(mt_raw$tax_table)) {
      keep <- !is.na(mt_raw$tax_table$Domain)
      n_drop <- sum(!keep)
      if (n_drop > 0) {
        keep_ids <- rownames(mt_raw$tax_table)[keep]
        mt_raw$tax_table <- mt_raw$tax_table[keep_ids, , drop = FALSE]
        mt_raw$otu_table  <- mt_raw$otu_table[keep_ids, , drop = FALSE]
        mt_raw$tidy_dataset()
        message(sprintf("[INFO] virus: dropped %d unclassified vOTUs; %d remain",
                        n_drop, sum(keep)))
      }
    }
  }

  mt <- tryCatch({
    x <- prepare_mt(mt_raw)
    add_status(dim, "prepare", "", "", "OK", sprintf("%d samples; %d groups", nrow(x$sample_table), length(unique(x$sample_table[[group_col]]))))
    x
  }, error = function(e) {
    add_status(dim, "prepare", "", "", "FAILED", conditionMessage(e))
    NULL
  })
  if (is.null(mt)) next

  success_dims <- success_dims + 1L
  lefse_path <- file.path(dim_dir, "lefse_results.tsv")
  wilcox_path <- file.path(dim_dir, "wilcox_results.tsv")
  ancombc_path <- file.path(dim_dir, "ancombc2_results.tsv")
  deseq2_path <- file.path(dim_dir, "deseq2_results.tsv")
  maaslin2_path <- file.path(dim_dir, "maaslin2_results.tsv")

  lefse_res <- if (dim == "bacteria") {
    choose_bacteria_level(mt, lefse_path)
  } else {
    add_status(dim, "diff", "lefse", "", "SKIPPED", "LEfSe only configured for bacteria", lefse_path)
    NULL
  }

  taxa_level <- if (!is.null(lefse_res)) {
    add_status(dim, "diff", "lefse", lefse_res$obj$taxa_level %||% "", "OK", paste("n_sig =", lefse_res$n_sig), lefse_path)
    safe_write(dim, "export", "lefse", lefse_res$obj$taxa_level %||% "", lefse_path, {
      write_tsv(format_lefse_results(lefse_res$res), lefse_path)
    })
    add_summary(dim, "lefse", lefse_res$n_sig, lefse_res$top_feature %||% "", lefse_path)
    lefse_res$obj$taxa_level
  } else {
    if (dim == "bacteria") "Species" else if (dim == "virus") "vOTU" else "ASV"
  }

  wilcox_res <- tryCatch(
    run_diff(mt, "wilcox", taxa_level, list(transformation = "AST", filter_thres = 0.001)),
    error = function(e) {
      add_status(dim, "diff", "wilcox", taxa_level, "FAILED", conditionMessage(e), wilcox_path)
      NULL
    }
  )
  if (!is.null(wilcox_res)) {
    add_status(dim, "diff", "wilcox", taxa_level, "OK", paste("n_sig =", wilcox_res$n_sig), wilcox_path)
    safe_write(dim, "export", "wilcox", taxa_level, wilcox_path, {
      write_tsv(format_wilcox_results(wilcox_res$obj), wilcox_path)
    })
    add_summary(dim, "wilcox", wilcox_res$n_sig, wilcox_res$top_feature %||% "", wilcox_path)
  }

  if (!requireNamespace("DESeq2", quietly = TRUE)) {
    add_status(dim, "diff", "deseq2", taxa_level, "WARN", "DESeq2 missing; skipped", deseq2_path)
  } else {
    deseq2_res <- tryCatch(run_deseq2(mt_raw), error = function(e) {
      add_status(dim, "diff", "deseq2", taxa_level, "FAILED", conditionMessage(e), deseq2_path)
      NULL
    })
    if (!is.null(deseq2_res)) {
      safe_write(dim, "export", "deseq2", taxa_level, deseq2_path, write_tsv(deseq2_res, deseq2_path))
      add_summary(dim, "deseq2", count_sig(deseq2_res), top_feature(deseq2_res), deseq2_path)

      if (plot_fns_available) {
        volcano_path <- file.path(dim_dir, "volcano_deseq2.pdf")
        volcano_df <- deseq2_res %>%
          rename(feature = Taxa) %>%
          filter(!is.na(padj), !is.na(log2FoldChange))
        tryCatch({
          if (nrow(volcano_df) > 0) {
            p <- plot_volcano_nature(volcano_df, method = "DESeq2")
            ggplot2::ggsave(volcano_path, p, width = 7, height = 6)
            if (mgx_want_png()) {
              ggplot2::ggsave(sub("\\.pdf$", ".png", volcano_path), p, width = 7, height = 6,
                              device = ragg::agg_png, dpi = 600)
            }
            add_status(dim, "plot", "volcano_deseq2", taxa_level, "OK", "", volcano_path)
          }
        }, error = function(e) {
          add_status(dim, "plot", "volcano_deseq2", taxa_level, "FAILED", conditionMessage(e), volcano_path)
        })
      }
    }
  }

  if (!requireNamespace("Maaslin2", quietly = TRUE)) {
    add_status(dim, "diff", "maaslin2", taxa_level, "WARN", "Maaslin2 missing; skipped", maaslin2_path)
  } else {
    maaslin2_res <- tryCatch(run_maaslin2(mt_raw, file.path(dim_dir, "maaslin2_output")), error = function(e) {
      add_status(dim, "diff", "maaslin2", taxa_level, "FAILED", conditionMessage(e), maaslin2_path)
      NULL
    })
    if (!is.null(maaslin2_res)) {
      safe_write(dim, "export", "maaslin2", taxa_level, maaslin2_path, write_tsv(maaslin2_res, maaslin2_path))
      add_summary(dim, "maaslin2", count_sig(maaslin2_res), top_feature(maaslin2_res), maaslin2_path)
    }
  }

  if (!has_file2meco()) {
    add_status(dim, "diff", "ancombc2", taxa_level, "WARN", "file2meco missing; skipped", ancombc_path)
  } else {
    ancombc_res <- tryCatch(
      run_diff(mt, "ancombc2", taxa_level),
      error = function(e) {
        add_status(dim, "diff", "ancombc2", taxa_level, "FAILED", conditionMessage(e), ancombc_path)
        NULL
      }
    )
    if (!is.null(ancombc_res)) {
      add_status(dim, "diff", "ancombc2", taxa_level, "OK", paste("n_sig =", ancombc_res$n_sig), ancombc_path)
      safe_write(dim, "export", "ancombc2", taxa_level, ancombc_path, {
        write_tsv(ancombc_res$res, ancombc_path)
      })
      add_summary(dim, "ancombc2", ancombc_res$n_sig, ancombc_res$top_feature %||% "", ancombc_path)
    }
  }
}

status_df <- if (length(status_rows)) bind_rows(status_rows) else empty_status()
summary_df <- if (length(summary_rows)) bind_rows(summary_rows) else empty_summary()

write_tsv(status_df, file.path(stat_root, "differential_status.tsv"))
write_tsv(summary_df, file.path(stat_root, "differential_summary.tsv"))

if (!success_dims) {
  message("[WARN] No dimension completed successfully; wrote header-only differential_summary.tsv")
}
message("[INFO] Differential analysis finished")
