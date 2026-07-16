# Deprecated 2026-07-16: superseded by 92_differential.R (this is an earlier iteration, dated 2026-07-07).
#!/usr/bin/env Rscript
# 95_differential.R — differential abundance analysis per dimension (bacteria / virus / fungi)
# Methods: DESeq2 (primary), LEfSe (secondary), Wilcoxon (quick filter)
# Outputs: result/stat/{dim}/differential/
#   - deseq2_genus_results.tsv / deseq2_genus_significant.tsv
#   - lefse_genus_results.tsv / lefse_genus_significant.tsv
#   - wilcoxon_genus_results.tsv / wilcoxon_genus_significant.tsv
#   - volcano_genus_deseq2.{pdf,svg,tiff}
#   - barplot_genus_deseq2.{pdf,svg,tiff}
#   - boxplot_genus_top10.{pdf,svg,tiff}
#   - heatmap_genus_significant.{pdf,svg,tiff}
#   - upset_method_consistency.{pdf,svg,tiff} / method_overlap_summary.tsv
#   - {dim}_differential_status.tsv
#
# RUN_DEMO=1: generates a synthetic phyloseq/microtable pair with planted
# significant taxa and routes it through the same pipeline, writing to
# result/stat/demo/demo/differential/. Regression-test fixture only — never
# a substitute for real bacteria/virus/fungi results.

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
sentinel     <- Sys.getenv("SENTINEL") %||% file.path(stat_root, "differential_done.txt")

dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("microeco", "phyloseq", "DESeq2", "magrittr", "ggplot2", "dplyr",
                    "RColorBrewer", "svglite", "ragg", "ggrepel", "ggtext", "tidyr",
                    "tibble", "ComplexHeatmap", "circlize", "ggplotify", "ggsci")
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  writeLines(format(Sys.time()), sentinel)
  stop("Missing packages: ", paste(miss, collapse = ", "))
}

suppressPackageStartupMessages({
  library(microeco)
  library(phyloseq)
  library(DESeq2)
  library(magrittr)
  library(ggplot2)
  library(dplyr)
  library(ggrepel)
  library(ggtext)
  library(ggsci)
})

grDevices::pdf(file = NULL)

mm2in <- function(x) x / 25.4

theme_pub <- function(base_size = 7, base_family = "Arial") {
  ggplot2::theme_classic(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      axis.line = ggplot2::element_line(linewidth = 0.35, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = 0.35, colour = "black"),
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
  write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi))
  invisible(paste0(path_noext, ".svg"))
}

theme_set(theme_pub())

# Nature Publishing Group (NPG) color palette - colorblind-safe and print-optimized
npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488","#F39B7F",
              "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) {
  if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
}

# SCI-optimized differential expression colors (high contrast, colorblind-friendly)
# Based on Nature/Cell standards: saturated red/blue for significance, muted grey for non-sig
sci_diff_colors <- function() {
  list(
    up = "#E64B35",      # NPG red (warm, high saturation)
    down = "#4DBBD5",    # NPG cyan-blue (cool, high saturation)
    nonsig = "#BBBBBB"   # Neutral grey (60% luminance, optimal for background)
  )
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

# ========== Demo mode ==========
# RUN_DEMO=1 builds a synthetic phyloseq/microtable pair with deliberately
# planted significant taxa and routes it through the exact same analysis
# loop below. This exists purely to regression-test the DESeq2/LEfSe/Wilcoxon/
# plotting/UpSet code paths when the real bacteria/virus data legitimately
# has 0 significant taxa — it must never be used to stand in for real results.
run_demo <- identical(Sys.getenv("RUN_DEMO"), "1")

make_demo_phyloseq <- function(seed = 42, n_samples = 40, n_taxa = 60, n_sig = 12) {
  set.seed(seed)
  sample_ids <- paste0("DemoS", seq_len(n_samples))
  groups <- factor(rep(c("control", "case"), each = n_samples / 2), levels = c("control", "case"))

  taxa_ids <- paste0("DemoTaxon", seq_len(n_taxa))
  phyla <- sample(paste0("p__DemoPhylum", 1:4), n_taxa, replace = TRUE)
  genera <- paste0("g__DemoGenus", seq_len(n_taxa))
  tax_mat <- matrix(
    c(rep("k__DemoKingdom", n_taxa), phyla,
      paste0("c__", sub("p__", "", phyla)), paste0("o__", sub("p__", "", phyla)),
      paste0("f__", sub("p__", "", phyla)), genera),
    nrow = n_taxa,
    dimnames = list(taxa_ids, c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus"))
  )

  otu_mat <- matrix(
    stats::rnbinom(n_taxa * n_samples, mu = 50, size = 2),
    nrow = n_taxa, ncol = n_samples, dimnames = list(taxa_ids, sample_ids)
  )
  sig_idx <- sample(seq_len(n_taxa), n_sig)
  case_cols <- which(groups == "case")
  for (i in sig_idx) {
    fc <- sample(c(4, 6, 8), 1) * sample(c(1, -1), 1)
    mu_case <- max(5, 50 * 2^(log2(abs(fc)) * sign(fc)))
    otu_mat[i, case_cols] <- stats::rnbinom(length(case_cols), mu = mu_case, size = 2)
  }

  sample_df <- data.frame(group = groups, row.names = sample_ids)

  ps <- phyloseq::phyloseq(
    phyloseq::otu_table(otu_mat, taxa_are_rows = TRUE),
    phyloseq::tax_table(tax_mat),
    phyloseq::sample_data(sample_df)
  )
  ps
}

make_demo_microtable <- function(ps) {
  otu_df <- as.data.frame(phyloseq::otu_table(ps))
  tax_df <- as.data.frame(phyloseq::tax_table(ps))
  # Force to plain data.frame — as.data.frame(sample_data(ps)) preserves the
  # sample_data S3 class, breaking microeco's single-column subsetting logic
  sample_df <- data.frame(phyloseq::sample_data(ps), check.names = FALSE, stringsAsFactors = FALSE)
  microeco::microtable$new(otu_table = otu_df, tax_table = tax_df, sample_table = sample_df)
}

if (run_demo) {
  demo_stat_root <- file.path(stat_root, "demo")
  demo_ps_dir <- file.path(demo_stat_root, "demo", "phyloseq")
  dir.create(demo_ps_dir, recursive = TRUE, showWarnings = FALSE)

  demo_ps <- make_demo_phyloseq()
  saveRDS(demo_ps, file.path(demo_ps_dir, "demo_phyloseq.rds"))

  demo_mt <- tryCatch(make_demo_microtable(demo_ps), error = function(e) NULL)
  if (!is.null(demo_mt)) {
    saveRDS(demo_mt, file.path(demo_stat_root, "demo", "demo_microtable.rds"))
  }

  cat("[INFO] Demo mode: synthetic dataset generated at", demo_ps_dir, "\n")
  stat_root <- demo_stat_root
  sentinel <- file.path(stat_root, "differential_done.txt")
  dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)
}

dims <- if (run_demo) "demo" else c("bacteria", "virus", "fungi")
completed <- 0L

cat("[INFO] Starting differential abundance analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Group column:", group_col, "\n")
cat("  Stat root:", stat_root, "\n")
if (run_demo) cat("  Mode: DEMO (synthetic regression-test data, not real results)\n")

for (dim in dims) {
  cat(sprintf("\n[INFO] === Dimension: %s ===\n", dim))
  phyloseq_path <- file.path(stat_root, dim, "phyloseq", paste0(dim, "_phyloseq.rds"))
  microtable_path <- file.path(stat_root, dim, paste0(dim, "_microtable.rds"))
  out_dir    <- file.path(stat_root, dim, "differential")
  status_tsv <- file.path(out_dir, paste0(dim, "_differential_status.tsv"))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  status_log <- list()

  if (!file.exists(phyloseq_path)) {
    msg <- paste("phyloseq RDS not found:", phyloseq_path)
    cat("[SKIP]", msg, "\n")
    status_log[[1]] <- data.frame(step = "load_phyloseq", status = "SKIPPED",
                                   message = msg, stringsAsFactors = FALSE)
    write_status(status_log, status_tsv)
    next
  }

  ps <- tryCatch(readRDS(phyloseq_path), error = function(e) NULL)
  if (is.null(ps)) {
    status_log[[1]] <- data.frame(step = "load_phyloseq", status = "FAILED",
                                   message = "readRDS returned NULL", stringsAsFactors = FALSE)
    write_status(status_log, status_tsv)
    next
  }
  status_log[[1]] <- data.frame(step = "load_phyloseq", status = "OK",
                                 message = "", stringsAsFactors = FALSE)
  cat(sprintf("  Loaded phyloseq: %d samples, %d taxa\n",
              phyloseq::nsamples(ps), phyloseq::ntaxa(ps)))

  # Also load microtable for LEfSe/Wilcoxon
  mt <- NULL
  if (file.exists(microtable_path)) {
    mt <- tryCatch(readRDS(microtable_path), error = function(e) NULL)
  }

  # Check group column exists and relevel to set control as reference
  if (!group_col %in% colnames(phyloseq::sample_data(ps))) {
    msg <- paste("Group column", group_col, "not found in sample_data")
    status_log[[2]] <- data.frame(step = "check_group", status = "FAILED",
                                   message = msg, stringsAsFactors = FALSE)
    write_status(status_log, status_tsv)
    next
  }

  # Relevel to set control as reference (fixes DESeq2 warning)
  sample_data(ps)[[group_col]] <- factor(sample_data(ps)[[group_col]])
  grp_levels <- levels(sample_data(ps)[[group_col]])

  if (length(grp_levels) != 2) {
    msg <- paste("Group column must have exactly 2 levels, found:", length(grp_levels))
    status_log[[2]] <- data.frame(step = "check_group", status = "FAILED",
                                   message = msg, stringsAsFactors = FALSE)
    write_status(status_log, status_tsv)
    next
  }

  # Set control as reference level if present
  if ("control" %in% grp_levels) {
    sample_data(ps)[[group_col]] <- relevel(sample_data(ps)[[group_col]], ref = "control")
    grp_levels <- levels(sample_data(ps)[[group_col]])
  }

  status_log[[2]] <- data.frame(step = "check_group", status = "OK",
                                 message = paste("Groups:", paste(grp_levels, collapse=" vs ")),
                                 stringsAsFactors = FALSE)
  cat(sprintf("  Groups: %s (ref) vs %s\n", grp_levels[1], grp_levels[2]))

  # Low abundance filtering: keep taxa present in >= 10% samples
  min_prevalence <- ceiling(phyloseq::nsamples(ps) * 0.1)
  ps_filt <- phyloseq::filter_taxa(ps, function(x) sum(x > 0) >= min_prevalence, prune = TRUE)
  cat(sprintf("  Filtered: %d → %d taxa (prevalence >= 10%%)\n",
              phyloseq::ntaxa(ps), phyloseq::ntaxa(ps_filt)))

  # Aggregate to Genus level (or fallback if Genus unavailable)
  tax_ranks <- colnames(phyloseq::tax_table(ps_filt))
  genus_rank <- if ("Genus" %in% tax_ranks) "Genus" else
                if ("Species" %in% tax_ranks) "Species" else
                if ("Family" %in% tax_ranks) "Family" else
                tax_ranks[length(tax_ranks)]
  cat(sprintf("  Using taxonomic rank: %s\n", genus_rank))

  ps_genus <- phyloseq::tax_glom(ps_filt, taxrank = genus_rank, NArm = TRUE)
  cat(sprintf("  Aggregated to %s level: %d taxa\n", genus_rank, phyloseq::ntaxa(ps_genus)))

  # ========== DESeq2 Analysis ==========
  run_step(paste0(dim, "_deseq2_genus"), status_log, {
    dds <- phyloseq::phyloseq_to_deseq2(ps_genus, stats::as.formula(paste("~", group_col)))

    # Use iterate method for size factor estimation (handles zeros better)
    dds <- tryCatch({
      dds_tmp <- DESeq2::estimateSizeFactors(dds, type = "iterate")
      dds_tmp
    }, error = function(e) {
      # Fallback to poscounts if iterate fails
      message("    iterate method failed, using poscounts")
      dds_tmp <- DESeq2::estimateSizeFactors(dds, type = "poscounts")
      dds_tmp
    })

    dds <- DESeq2::estimateDispersions(dds, fitType = "local", quiet = TRUE)
    dds <- DESeq2::nbinomWaldTest(dds, quiet = TRUE)

    res <- DESeq2::results(dds, contrast = c(group_col, grp_levels[2], grp_levels[1]),
                            cooksCutoff = FALSE, independentFiltering = TRUE)
    res_df <- as.data.frame(res) %>%
      tibble::rownames_to_column("TaxonID") %>%
      dplyr::arrange(padj, desc(abs(log2FoldChange)))

    # Add taxonomy annotation
    tax_df <- as.data.frame(phyloseq::tax_table(ps_genus)) %>%
      tibble::rownames_to_column("TaxonID")
    res_df <- dplyr::left_join(res_df, tax_df, by = "TaxonID")

    # Write full results
    utils::write.table(res_df, file.path(out_dir, "deseq2_genus_results.tsv"),
                       sep = "\t", quote = FALSE, row.names = FALSE)

    # Extract significant taxa (padj alone; log2FC is not used as a significance
    # gate because microbiome fold-changes can be small yet highly significant
    # at this sample size — see plot_df trend logic below for the same rationale)
    sig_df <- res_df %>%
      dplyr::filter(!is.na(padj), padj < 0.05)
    utils::write.table(sig_df, file.path(out_dir, "deseq2_genus_significant.tsv"),
                       sep = "\t", quote = FALSE, row.names = FALSE)

    cat(sprintf("    DESeq2: %d total, %d significant (padj<0.05)\n",
                nrow(res_df), nrow(sig_df)))

    # Volcano plot (SCI-optimized: NPG colors, enhanced contrast, clean layout)
    diff_cols <- sci_diff_colors()
    plot_df <- res_df %>%
      dplyr::mutate(
        neg_log10_padj = -log10(padj),
        trend = dplyr::case_when(
          log2FoldChange > 0 & padj < 0.05 ~ "up",
          log2FoldChange < 0 & padj < 0.05 ~ "down",
          TRUE ~ "non-sig"
        ),
        label = ifelse(padj < 0.01, as.character(.data[[genus_rank]]), NA)
      ) %>%
      dplyr::filter(!is.na(padj))

    p_volcano <- ggplot(plot_df, aes(x = log2FoldChange, y = neg_log10_padj, color = trend)) +
      geom_point(alpha = 0.7, aes(size = neg_log10_padj)) +
      scale_color_manual(
        values = c("up" = diff_cols$up, "down" = diff_cols$down, "non-sig" = diff_cols$nonsig),
        labels = c("up" = paste("Up in", grp_levels[2]),
                   "down" = paste("Up in", grp_levels[1]),
                   "non-sig" = "Not significant"),
        name = NULL
      ) +
      scale_size_continuous(range = c(0.8, 3.5), guide = "none") +
      geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey40", linewidth = 0.35) +
      geom_text_repel(
        aes(label = label), size = 2.2, segment.size = 0.25, color = "grey20",
        max.overlaps = 20, box.padding = 0.35, point.padding = 0.3,
        min.segment.length = 0, na.rm = TRUE
      ) +
      labs(
        x = "log<sub>2</sub>(Fold Change)",
        y = "-log<sub>10</sub>(<i>P</i><sub>adj</sub>)",
        title = paste(toupper(substring(dim, 1, 1)), substring(dim, 2), "Differential Abundance", sep = " ")
      ) +
      theme_pub(base_size = 7) +
      theme(
        axis.title.x = element_markdown(),
        axis.title.y = element_markdown(),
        plot.title = element_text(size = 9, face = "bold", hjust = 0.5),
        legend.position = "right",
        legend.justification = c(0, 1),
        legend.key.size = unit(3, "mm"),
        legend.spacing.y = unit(1, "mm")
      )

    export_pub_figure(p_volcano, file.path(out_dir, "volcano_genus_deseq2"),
                      width_mm = 140, height_mm = 110)

    # Barplot (top 20 significant taxa, SCI-optimized gradient coloring)
    if (nrow(sig_df) > 0) {
      top_n <- min(20, nrow(sig_df))
      bar_df <- sig_df %>%
        dplyr::slice_max(order_by = abs(log2FoldChange), n = top_n) %>%
        dplyr::mutate(
          taxon_label = make.unique(as.character(.data[[genus_rank]])),
          direction = ifelse(log2FoldChange > 0, "up", "down")
        ) %>%
        dplyr::arrange(log2FoldChange)
      bar_df$taxon_label <- factor(bar_df$taxon_label, levels = bar_df$taxon_label)

      # Generate gradient colors based on log2FC magnitude for visual hierarchy
      fc_range <- range(bar_df$log2FoldChange)
      bar_df$color_val <- (bar_df$log2FoldChange - fc_range[1]) / diff(fc_range)

      p_bar <- ggplot(bar_df, aes(x = log2FoldChange, y = taxon_label)) +
        geom_col(aes(fill = color_val), width = 0.75) +
        scale_fill_gradient2(
          low = diff_cols$down, mid = "grey90", high = diff_cols$up,
          midpoint = 0.5, guide = "none"
        ) +
        geom_vline(xintercept = 0, linetype = "solid", color = "grey30", linewidth = 0.4) +
        labs(
          x = "log<sub>2</sub>(Fold Change)",
          y = NULL,
          title = paste("Top", top_n, "Differential Taxa")
        ) +
        theme_pub(base_size = 7) +
        theme(
          axis.title.x = element_markdown(),
          axis.text.y = element_text(size = 6.5, face = "italic"),
          plot.title = element_text(size = 8, face = "bold", hjust = 0.5),
          panel.grid.major.x = element_line(color = "grey92", linewidth = 0.25)
        )

      export_pub_figure(p_bar, file.path(out_dir, "barplot_genus_deseq2"),
                        width_mm = 120, height_mm = top_n * 4 + 20)
    }

    # Boxplot (top 10 significant taxa, SCI-optimized with NPG colors)
    if (nrow(sig_df) >= 1) {
      top10_df <- sig_df %>%
        dplyr::slice_max(order_by = abs(log2FoldChange), n = min(10, nrow(sig_df)))
      top10_taxa <- top10_df$TaxonID

      ps_top10 <- phyloseq::prune_taxa(top10_taxa, ps_genus)
      taxon_label_map <- setNames(
        make.unique(as.character(phyloseq::tax_table(ps_top10)[, genus_rank])),
        phyloseq::taxa_names(ps_top10)
      )
      abund_df <- phyloseq::psmelt(ps_top10) %>%
        dplyr::rename(group_var = !!rlang::sym(group_col)) %>%
        dplyr::mutate(
          taxon = taxon_label_map[OTU],
          rel_abund = Abundance / phyloseq::sample_sums(ps_top10)[as.character(Sample)]
        )

      # NPG color palette for groups
      group_colors <- setNames(npg_pal(length(grp_levels)), grp_levels)

      p_box <- ggplot(abund_df, aes(x = group_var, y = rel_abund * 100, fill = group_var)) +
        geom_boxplot(
          outlier.shape = 21, outlier.size = 0.8, outlier.stroke = 0.25,
          width = 0.65, linewidth = 0.35, alpha = 0.8
        ) +
        geom_jitter(width = 0.18, alpha = 0.4, size = 0.6, shape = 16) +
        facet_wrap(~ taxon, scales = "free_y", ncol = 5) +
        scale_fill_manual(values = group_colors, name = NULL) +
        scale_y_continuous(expand = expansion(mult = c(0.05, 0.15))) +
        labs(x = NULL, y = "Relative Abundance (%)") +
        theme_pub(base_size = 7) +
        theme(
          strip.text = element_text(size = 6.5, face = "bold.italic"),
          strip.background = element_rect(fill = "grey95", color = "grey80", linewidth = 0.3),
          axis.text.x = element_text(angle = 35, hjust = 1, size = 6),
          legend.position = "bottom",
          legend.key.size = unit(3, "mm"),
          panel.spacing = unit(1.5, "mm")
        )

      n_taxa_box <- length(unique(abund_df$taxon))
      n_rows <- ceiling(n_taxa_box / 5)
      export_pub_figure(p_box, file.path(out_dir, "boxplot_genus_top10"),
                        width_mm = 183, height_mm = max(80, n_rows * 38))
    }

    # Heatmap (all significant taxa, SCI-optimized with soft gradient)
    if (nrow(sig_df) >= 2) {
      sig_taxa <- sig_df$TaxonID
      ps_sig <- phyloseq::prune_taxa(sig_taxa, ps_genus)
      abund_mat <- as.matrix(phyloseq::otu_table(ps_sig))
      if (!phyloseq::taxa_are_rows(ps_sig)) abund_mat <- t(abund_mat)
      abund_mat <- abund_mat + 1  # pseudo-count
      abund_mat <- log10(abund_mat)
      abund_mat <- t(scale(t(abund_mat)))  # Z-score per taxon

      tax_labels <- make.unique(as.character(phyloseq::tax_table(ps_sig)[, genus_rank]))
      rownames(abund_mat) <- tax_labels

      sample_df <- as.data.frame(phyloseq::sample_data(ps_sig))
      sample_order <- order(sample_df[[group_col]], rownames(sample_df))
      abund_mat <- abund_mat[, sample_order]

      # Soft blue-white-red gradient (Nature/Cell standard, easier on eyes)
      col_fun <- circlize::colorRamp2(
        c(-2.5, 0, 2.5),
        c("#4DBBD5", "#F7F7F7", "#E64B35")  # NPG cyan-blue, light grey, NPG red
      )

      # Group annotation with NPG colors
      group_colors_annot <- setNames(npg_pal(length(grp_levels)), grp_levels)
      ha <- ComplexHeatmap::HeatmapAnnotation(
        Group = sample_df[[group_col]][sample_order],
        col = list(Group = group_colors_annot),
        show_legend = TRUE,
        annotation_name_side = "left",
        annotation_name_gp = grid::gpar(fontsize = 7, fontface = "bold"),
        simple_anno_size = grid::unit(3, "mm"),
        border = TRUE
      )

      ht <- ComplexHeatmap::Heatmap(
        abund_mat,
        name = "Z-score",
        col = col_fun,
        top_annotation = ha,
        cluster_rows = TRUE,
        cluster_columns = FALSE,
        show_row_names = TRUE,
        show_column_names = FALSE,
        row_names_gp = grid::gpar(fontsize = 6, fontface = "italic"),
        row_names_max_width = grid::unit(8, "cm"),
        column_title = paste(toupper(substring(dim, 1, 1)), substring(dim, 2),
                             "Differential Taxa Heatmap", sep = " "),
        column_title_gp = grid::gpar(fontsize = 9, fontface = "bold"),
        heatmap_legend_param = list(
          title_gp = grid::gpar(fontsize = 7, fontface = "bold"),
          labels_gp = grid::gpar(fontsize = 6),
          legend_height = grid::unit(25, "mm"),
          border = "grey40"
        ),
        border = TRUE,
        row_dend_width = grid::unit(8, "mm"),
        width = grid::unit(120, "mm")
      )

      pdf(file.path(out_dir, "heatmap_genus_significant.pdf"),
          width = mm2in(150), height = mm2in(max(100, nrow(abund_mat) * 4)))
      ComplexHeatmap::draw(ht)
      dev.off()

      svg(file.path(out_dir, "heatmap_genus_significant.svg"),
          width = mm2in(150), height = mm2in(max(100, nrow(abund_mat) * 4)))
      ComplexHeatmap::draw(ht)
      dev.off()

      ragg::agg_tiff(file.path(out_dir, "heatmap_genus_significant.tiff"),
                      width = mm2in(150), height = mm2in(max(100, nrow(abund_mat) * 4)),
                      units = "in", res = 600)
      ComplexHeatmap::draw(ht)
      dev.off()
    }
  })

  # ========== LEfSe Analysis (via microeco trans_diff) ==========
  run_step(paste0(dim, "_lefse_genus"), status_log, {
    if (is.null(mt)) stop("microtable RDS not available")

    # Clone and aggregate to genus level
    mt_clone <- clone(mt)
    mt_clone$cal_abund(rel = TRUE)

    # tax_glom equivalent for microtable
    mt_clone$tax_table <- as.data.frame(mt_clone$tax_table)
    if (!genus_rank %in% colnames(mt_clone$tax_table)) {
      stop(paste("Rank", genus_rank, "not found in tax_table"))
    }

    lefse_obj <- trans_diff$new(dataset = mt_clone, method = "lefse",
                                  group = group_col, alpha = 0.05,
                                  lefse_subgroup = NULL)
    lefse_res <- lefse_obj$res_diff

    if (!is.null(lefse_res) && nrow(lefse_res) > 0) {
      utils::write.table(lefse_res, file.path(out_dir, "lefse_genus_results.tsv"),
                         sep = "\t", quote = FALSE, row.names = FALSE)

      # microeco returns one row per taxonomic depth (Phylum, Class, ... Genus);
      # keep only the deepest level (== genus_rank) so cross-method comparison
      # (UpSet/Venn) operates on a consistent taxonomic unit
      taxa_depth <- lengths(strsplit(lefse_res$Taxa, "\\|"))
      lefse_res_genus <- lefse_res[taxa_depth == max(taxa_depth), , drop = FALSE]
      lefse_res_genus$GenusLabel <- vapply(strsplit(lefse_res_genus$Taxa, "\\|"),
                                            function(x) x[length(x)], character(1))

      sig_lefse <- lefse_res_genus %>%
        dplyr::filter(P.adj < 0.05, abs(LDA) > 2)
      utils::write.table(sig_lefse, file.path(out_dir, "lefse_genus_significant.tsv"),
                         sep = "\t", quote = FALSE, row.names = FALSE)

      cat(sprintf("    LEfSe: %d total, %d significant (P.adj<0.05, |LDA|>2)\n",
                  nrow(lefse_res_genus), nrow(sig_lefse)))
    } else {
      cat("    LEfSe: no results generated\n")
    }
  })

  # ========== Wilcoxon Test (via microeco trans_diff) ==========
  run_step(paste0(dim, "_wilcoxon_genus"), status_log, {
    if (is.null(mt)) stop("microtable RDS not available")

    # Clone and aggregate to genus level
    mt_clone <- clone(mt)
    mt_clone$cal_abund(rel = TRUE)

    wilcox_obj <- trans_diff$new(dataset = mt_clone, method = "wilcox",
                                   group = group_col, p_adjust_method = "fdr")
    wilcox_res <- wilcox_obj$res_diff

    if (!is.null(wilcox_res) && nrow(wilcox_res) > 0) {
      utils::write.table(wilcox_res, file.path(out_dir, "wilcoxon_genus_results.tsv"),
                         sep = "\t", quote = FALSE, row.names = FALSE)

      # Same depth-filtering rationale as LEfSe above
      taxa_depth <- lengths(strsplit(wilcox_res$Taxa, "\\|"))
      wilcox_res_genus <- wilcox_res[taxa_depth == max(taxa_depth), , drop = FALSE]
      wilcox_res_genus$GenusLabel <- vapply(strsplit(wilcox_res_genus$Taxa, "\\|"),
                                             function(x) x[length(x)], character(1))

      sig_wilcox <- wilcox_res_genus %>%
        dplyr::filter(!is.na(P.adj), P.adj < 0.05)
      utils::write.table(sig_wilcox, file.path(out_dir, "wilcoxon_genus_significant.tsv"),
                         sep = "\t", quote = FALSE, row.names = FALSE)

      cat(sprintf("    Wilcoxon: %d total, %d significant (P.adj<0.05)\n",
                  nrow(wilcox_res_genus), nrow(sig_wilcox)))
    } else {
      cat("    Wilcoxon: no results generated\n")
    }
  })

  # ========== Cross-method consistency (UpSet plot) ==========
  # Rationale: different DA methods often disagree substantially (Nearing et al. 2022,
  # "Microbiome differential abundance methods produce disturbingly different results
  # across 38 datasets") — visualize the actual overlap instead of trusting one method
  run_step(paste0(dim, "_upset_consistency"), status_log, {
    method_sets <- list()

    deseq2_sig_path <- file.path(out_dir, "deseq2_genus_significant.tsv")
    if (file.exists(deseq2_sig_path)) {
      d <- utils::read.delim(deseq2_sig_path, sep = "\t", stringsAsFactors = FALSE)
      if (nrow(d) > 0 && genus_rank %in% colnames(d)) {
        method_sets[["DESeq2"]] <- unique(as.character(d[[genus_rank]]))
      } else {
        method_sets[["DESeq2"]] <- character(0)
      }
    }

    lefse_sig_path <- file.path(out_dir, "lefse_genus_significant.tsv")
    if (file.exists(lefse_sig_path)) {
      d <- utils::read.delim(lefse_sig_path, sep = "\t", stringsAsFactors = FALSE)
      method_sets[["LEfSe"]] <- if (nrow(d) > 0) unique(d$GenusLabel) else character(0)
    }

    wilcox_sig_path <- file.path(out_dir, "wilcoxon_genus_significant.tsv")
    if (file.exists(wilcox_sig_path)) {
      d <- utils::read.delim(wilcox_sig_path, sep = "\t", stringsAsFactors = FALSE)
      method_sets[["Wilcoxon"]] <- if (nrow(d) > 0) unique(d$GenusLabel) else character(0)
    }

    if (length(method_sets) < 2) stop("Fewer than 2 methods produced results; skip UpSet")

    total_sig <- sum(lengths(method_sets))
    if (total_sig == 0) {
      # All methods agree on "no significant taxa" — plot an explicit empty-set
      # panel rather than silently omitting the figure, so the three dimensions
      # remain visually comparable in output structure
      p_upset <- ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = paste0(dim, "\nNo significant taxa detected by any method\n",
                                 "(", paste(names(method_sets), collapse = ", "), "; padj<0.05)"),
                 size = 3, hjust = 0.5, vjust = 0.5) +
        xlim(0, 1) + ylim(0, 1) +
        theme_void()
      export_pub_figure(p_upset, file.path(out_dir, "upset_method_consistency"),
                        width_mm = 120, height_mm = 80)
      cat("    UpSet: all methods agree — 0 significant taxa across the board\n")
    } else {
      all_taxa <- unique(unlist(method_sets))
      membership <- sapply(method_sets, function(s) all_taxa %in% s)
      rownames(membership) <- all_taxa

      comb_mat <- ComplexHeatmap::make_comb_mat(membership)
      p_upset_grob <- grid::grid.grabExpr(
        ComplexHeatmap::UpSet(comb_mat,
          comb_col = npg_pal(length(ComplexHeatmap::comb_size(comb_mat))),
          top_annotation = ComplexHeatmap::upset_top_annotation(
            comb_mat, annotation_name_gp = grid::gpar(fontsize = 7),
            axis_param = list(gp = grid::gpar(fontsize = 6))
          ),
          right_annotation = ComplexHeatmap::upset_right_annotation(
            comb_mat, annotation_name_gp = grid::gpar(fontsize = 7),
            axis_param = list(gp = grid::gpar(fontsize = 6))
          ),
          row_names_gp = grid::gpar(fontsize = 7),
          column_title = paste(dim, "- Cross-method significant taxa (padj<0.05)"),
          column_title_gp = grid::gpar(fontsize = 8, fontface = "bold")
        )
      )

      # Fallback to text placeholder if UpSet didn't render (edge case: grob is NULL)
      if (is.null(p_upset_grob)) {
        p_upset <- ggplot() +
          annotate("text", x = 0.5, y = 0.5,
                   label = paste0(dim, "\nUpSet plot could not be rendered\n",
                                   length(all_taxa), " unique taxa across ",
                                   length(method_sets), " methods"),
                   size = 3, hjust = 0.5, vjust = 0.5) +
          xlim(0, 1) + ylim(0, 1) +
          theme_void()
      } else {
        p_upset <- ggplotify::as.ggplot(p_upset_grob)
      }
      export_pub_figure(p_upset, file.path(out_dir, "upset_method_consistency"),
                        width_mm = 140, height_mm = 100)

      # Also report pairwise overlap as a text summary for quick inspection
      overlap_summary <- utils::combn(names(method_sets), 2, function(pair) {
        ov <- length(intersect(method_sets[[pair[1]]], method_sets[[pair[2]]]))
        data.frame(method_a = pair[1], method_b = pair[2], overlap_n = ov,
                   n_a = length(method_sets[[pair[1]]]), n_b = length(method_sets[[pair[2]]]))
      }, simplify = FALSE) %>% dplyr::bind_rows()
      utils::write.table(overlap_summary, file.path(out_dir, "method_overlap_summary.tsv"),
                         sep = "\t", quote = FALSE, row.names = FALSE)

      cat(sprintf("    UpSet: %d total unique significant taxa across %d methods\n",
                  length(all_taxa), length(method_sets)))
    }
  })

  write_status(status_log, status_tsv)
  ok_n <- sum(vapply(status_log, function(x) x$status == "OK", logical(1)))
  if (ok_n > 0) completed <- completed + 1L
  cat(sprintf("  [%s] %d/%d steps OK\n", dim, ok_n, length(status_log)))
}

cat(sprintf("\n[INFO] Completed %d/%d dimensions\n", completed, length(dims)))
writeLines(format(Sys.time()), sentinel)
cat("[INFO] Differential analysis finished\n")
