#!/usr/bin/env Rscript
# ==============================================================================
# Script: 91_diversity.R
# Purpose: Alpha and beta diversity using microeco pipeline
#          (microeco_protocol v2.1 style — Nature-quality figures)
#
# Pipeline:
#   abundance table + taxonomy + sample metadata
#   → microtable$new()
#   → cal_alphadiv() + trans_alpha$new() → cal_diff(wilcox) → plot_alpha()
#   → cal_betadiv(bray) + trans_beta$new() → cal_ordination(PCoA)
#     + cal_manova() → plot_ordination(point+ellipse)
#   → cowplot::save_plot(dpi=300)
#
# Visual design (matches microeco_protocol):
#   theme_bw() global, no inner grid, ggdotplot alpha panels,
#   PCoA point+ellipse, NPG colours, dpi=300
# ==============================================================================

options(stringsAsFactors = FALSE, warn = 1)
# Suppress stray Rplots.pdf
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

# Use only the conda env library (avoid R_LIBS_USER version conflicts)
conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                normalizePath(conda_lib, mustWork = FALSE)])))
}

required_pkgs <- c(
  "microeco", "magrittr", "ggplot2", "cowplot", "dplyr", "tidyr",
  "readr", "tibble", "phyloseq", "vegan"
)
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) stop("Missing packages: ", paste(miss, collapse = ", "))

suppressPackageStartupMessages({
  library(microeco); library(magrittr); library(ggplot2)
  library(cowplot);  library(dplyr);   library(tidyr)
  library(readr);    library(tibble);  library(phyloseq)
  library(vegan)
})

# microeco_protocol: set theme globally
theme_set(theme_bw())

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ── Environment variables ──────────────────────────────────────────────────────
workdir      <- Sys.getenv("WORKDIR")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col    <- Sys.getenv("GROUP_COL")   %||% "group"
bact_table   <- Sys.getenv("BACT_TABLE")
vir_table    <- Sys.getenv("VIR_TABLE")
fungi_dir    <- Sys.getenv("FUNGI_DIR")
result_dir   <- Sys.getenv("RESULT_DIR")
if (!nzchar(result_dir))
  result_dir <- file.path(workdir, "result", "stat", "diversity")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dim_dirs <- setNames(
  lapply(c("bacteria", "virus", "fungi"), function(d) {
    p <- file.path(result_dir, d)
    dir.create(p, recursive = TRUE, showWarnings = FALSE)
    p
  }),
  c("bacteria", "virus", "fungi")
)

cat("[INFO] Starting diversity analysis (microeco pipeline)\n")
cat("  Workdir:", workdir, "\n")
cat("  Metadata:", metadata_csv, "\n")
cat("  Group:", group_col, "\n")

status_log <- list()
log_status <- function(step, status, msg = "") {
  status_log[[length(status_log) + 1]] <<-
    tibble(step = step, status = status, message = msg)
}

# ══════════════════════════════════════════════════════════════════════════════
# NPG colour palette (Nature Publishing Group)
# ══════════════════════════════════════════════════════════════════════════════
npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488",
              "#F39B7F","#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) {
  if (n <= length(npg_base)) npg_base[seq_len(n)]
  else colorRampPalette(npg_base)(n)
}

# ══════════════════════════════════════════════════════════════════════════════
# METADATA LOADER
# ══════════════════════════════════════════════════════════════════════════════
load_meta <- function(path, grp) {
  meta <- read.csv(path)
  cands <- c("sample_id","SampleID","sample","Sample","id")
  sc    <- (cands[cands %in% names(meta)])[1] %||% names(meta)[1]
  meta  <- meta %>%
    rename(sample_id = !!sc) %>%
    mutate(sample_id = as.character(sample_id),
           !!grp := as.factor(.data[[grp]])) %>%
    filter(!is.na(sample_id), !is.na(.data[[grp]])) %>%
    distinct(sample_id, .keep_all = TRUE) %>%
    as.data.frame()
  rownames(meta) <- meta$sample_id
  meta
}

# ══════════════════════════════════════════════════════════════════════════════
# MICROTABLE BUILDERS
# ══════════════════════════════════════════════════════════════════════════════

# Bacteria: from MetaPhlAn4 merged taxonomy.tsv
build_mt_bacteria <- function(bact_path, meta) {
  raw <- read.table(bact_path, header = TRUE, row.names = 1, sep = "\t",
                    comment.char = "#", check.names = FALSE)
  sp_idx <- grepl("(^|\\|)s__", rownames(raw)) &
            !grepl("(^|\\|)t__", rownames(raw))
  if (sum(sp_idx) < 2) stop("< 2 species in bacteria table")
  raw_sp <- raw[sp_idx, , drop = FALSE]

  parse_lin <- function(lin) {
    parts <- strsplit(lin, "\\|")[[1]]
    pfx   <- c(Kingdom="k__",Phylum="p__",Class="c__",Order="o__",
               Family="f__",Genus="g__",Species="s__")
    vapply(pfx, function(px) {
      m <- parts[startsWith(parts, px)]
      if (length(m)) sub(paste0("^",px),"",m[1]) else NA_character_
    }, character(1))
  }
  tax_df <- as.data.frame(do.call(rbind, lapply(rownames(raw_sp), parse_lin)),
                          stringsAsFactors = FALSE)
  rownames(tax_df) <- rownames(raw_sp)

  common <- intersect(colnames(raw_sp), rownames(meta))
  if (length(common) < 2) stop("< 2 overlapping samples (bacteria)")
  # Convert relative abundance (0-100) to pseudo-counts so Chao1/Observed work.
  # Multiply by 1000 and round — preserves richness rank while allowing integer metrics.
  otu_df <- as.data.frame(round(raw_sp[, common, drop = FALSE] * 1000))

  sample_tbl <- meta[common, , drop = FALSE]
  mt <- microtable$new(otu_table  = otu_df,
                       tax_table  = tax_df,
                       sample_table = sample_tbl)
  mt$tidy_dataset()
  cat(sprintf("[INFO] Bacteria microtable: %d taxa × %d samples\n",
              nrow(mt$otu_table), nrow(mt$sample_table)))
  mt
}

# Virus: aggregate ORF-level TPM → vOTU representatives
build_mt_virus <- function(votu_path, meta) {
  clusters_path <- file.path(dirname(dirname(votu_path)), "vclust", "clusters.tsv")
  if (!file.exists(clusters_path))
    stop("Missing clusters.tsv: ", clusters_path)

  clusters <- read.table(clusters_path, header = TRUE, sep = "\t",
                         col.names = c("contig","votu_rep"),
                         stringsAsFactors = FALSE)
  raw      <- read.table(votu_path, header = TRUE, sep = "\t",
                         check.names = FALSE, comment.char = "")
  tpm_cols <- names(raw)[grepl("_tpm$", names(raw), ignore.case = TRUE)]
  if (!length(tpm_cols)) stop("No *_tpm columns in vOTU table")
  sample_ids <- sub("_tpm$", "", tpm_cols, ignore.case = TRUE)

  contig_ord <- order(nchar(clusters$contig), decreasing = TRUE)
  contigs    <- clusters$contig[contig_ord]
  votus      <- clusters$votu_rep[contig_ord]

  orf_to_votu <- vapply(raw$gene, function(orf) {
    for (i in seq_along(contigs))
      if (orf == contigs[i] || startsWith(orf, paste0(contigs[i],"_")))
        return(votus[i])
    NA_character_
  }, character(1))

  raw[tpm_cols] <- lapply(raw[tpm_cols],
                          function(x) suppressWarnings(as.numeric(x)))
  raw$votu_rep <- orf_to_votu

  agg <- raw %>%
    filter(!is.na(votu_rep)) %>%
    group_by(votu_rep) %>%
    summarise(across(all_of(tpm_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")

  otu_df <- as.data.frame(agg[, tpm_cols, drop = FALSE])
  rownames(otu_df) <- agg$votu_rep
  colnames(otu_df) <- sample_ids
  otu_df[is.na(otu_df)] <- 0
  otu_df <- otu_df[rowSums(otu_df) > 0, , drop = FALSE]
  # Convert TPM to pseudo-counts so Chao1/Observed metrics work.
  otu_df <- round(otu_df)

  tax_df <- data.frame(vOTU = rownames(otu_df),
                       row.names = rownames(otu_df),
                       stringsAsFactors = FALSE)

  common <- intersect(colnames(otu_df), rownames(meta))
  if (length(common) < 2) stop("< 2 overlapping samples (virus)")

  mt <- microtable$new(otu_table    = otu_df[, common, drop = FALSE],
                       tax_table    = tax_df,
                       sample_table = meta[common, , drop = FALSE])
  mt$tidy_dataset()
  cat(sprintf("[INFO] Virus microtable: %d vOTUs × %d samples\n",
              nrow(mt$otu_table), nrow(mt$sample_table)))
  mt
}

# Fungi: from per-sample MetaPhlAn4 profiles
build_mt_fungi <- function(fungi_profile_dir, meta) {
  fls <- Sys.glob(file.path(fungi_profile_dir, "*", "*_profile.txt"))
  if (!length(fls)) stop("No fungi profiles in ", fungi_profile_dir)

  rows <- lapply(fls, function(fp) {
    lines <- readLines(fp, warn = FALSE)
    dat   <- lines[!startsWith(lines, "#")]
    if (!length(dat)) return(NULL)
    tab <- tryCatch(
      readr::read_tsv(I(paste(dat, collapse="\n")), show_col_types=FALSE,
        col_names=c("clade_name","ncbi_tax_id","relative_abundance","additional_species"),
        col_types="ccdc"),
      error = function(e) NULL)
    if (is.null(tab)) return(NULL)
    tab <- tab[tab$clade_name != "UNCLASSIFIED" & !is.na(tab$relative_abundance), ]
    if (!nrow(tab)) return(NULL)
    tibble(feature = tab$clade_name, sample_id = basename(dirname(fp)),
           abundance = tab$relative_abundance)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) { message("[INFO] Fungi: all UNCLASSIFIED"); return(NULL) }

  wide <- bind_rows(rows) %>%
    filter(!is.na(feature), !is.na(abundance)) %>%
    group_by(feature, sample_id) %>%
    summarise(abundance = sum(abundance, na.rm=TRUE), .groups="drop") %>%
    tidyr::pivot_wider(names_from=sample_id, values_from=abundance, values_fill=0)

  otu_df <- as.data.frame(wide[, -1, drop=FALSE])
  rownames(otu_df) <- wide$feature
  sp_idx <- grepl("(^|\\|)s__", rownames(otu_df)) &
            !grepl("(^|\\|)t__", rownames(otu_df))
  if (sum(sp_idx) >= 2) otu_df <- otu_df[sp_idx, , drop=FALSE]
  otu_df <- otu_df[rowSums(otu_df) > 0, , drop=FALSE]
  if (nrow(otu_df) < 2) { message("[INFO] Fungi: < 2 non-zero species"); return(NULL) }

  parse_lin <- function(lin) {
    parts <- strsplit(lin, "\\|")[[1]]
    pfx   <- c(Kingdom="k__",Phylum="p__",Class="c__",Order="o__",
               Family="f__",Genus="g__",Species="s__")
    vapply(pfx, function(px) {
      m <- parts[startsWith(parts, px)]
      if (length(m)) sub(paste0("^",px),"",m[1]) else NA_character_
    }, character(1))
  }
  tax_df <- as.data.frame(do.call(rbind, lapply(rownames(otu_df), parse_lin)),
                          stringsAsFactors=FALSE)
  rownames(tax_df) <- rownames(otu_df)

  common <- intersect(colnames(otu_df), rownames(meta))
  if (length(common) < 2) stop("< 2 overlapping samples (fungi)")

  mt <- microtable$new(otu_table    = otu_df[, common, drop=FALSE],
                       tax_table    = tax_df,
                       sample_table = meta[common, , drop=FALSE])
  mt$tidy_dataset()
  cat(sprintf("[INFO] Fungi microtable: %d taxa × %d samples\n",
              nrow(mt$otu_table), nrow(mt$sample_table)))
  mt
}

# ══════════════════════════════════════════════════════════════════════════════
# ALPHA DIVERSITY  —  microeco_protocol style
#   cal_alphadiv() → trans_alpha$new() → cal_diff(wilcox) → plot_alpha(ggdotplot)
#   cowplot::save_plot(dpi=300, base_aspect_ratio=1.2)
# ══════════════════════════════════════════════════════════════════════════════

viz_alpha_microeco <- function(mt, group_col, out_file, out_tsv, title,
                               measures = c("Observed","Chao1","Shannon","Pielou")) {
  # Calculate alpha diversity into mt$alpha_diversity
  mt_clone <- clone(mt)
  tryCatch(mt_clone$cal_alphadiv(measures = measures),
           error = function(e) {
             # Some measures need integer counts; fall back to what works
             message("[WARN] cal_alphadiv full set failed: ", conditionMessage(e))
             tryCatch(mt_clone$cal_alphadiv(measures = c("Observed","Shannon")),
                      error = function(e2) stop("cal_alphadiv: ", conditionMessage(e2)))
           })

  if (!is.null(mt_clone$alpha_diversity) && nrow(mt_clone$alpha_diversity) > 0) {
    write.csv(mt_clone$alpha_diversity, out_tsv)
  }

  grps <- unique(as.character(mt_clone$sample_table[[group_col]]))
  cols <- setNames(npg_pal(length(grps)), sort(grps))

  t1 <- trans_alpha$new(dataset = mt_clone, group = group_col)
  tryCatch(t1$cal_diff(method = "wilcox"), error = function(e)
    message("[WARN] cal_diff wilcox: ", conditionMessage(e)))

  # microeco_protocol Fig 2c style: ggdotplot + mean_se
  avail_measures <- intersect(measures, names(mt_clone$alpha_diversity))
  if (!length(avail_measures)) avail_measures <- names(mt_clone$alpha_diversity)[1]

  plots <- lapply(avail_measures, function(m) {
    tryCatch(
      t1$plot_alpha(measure = m, plot_type = "ggdotplot",
                    fill = group_col, alpha = 0.3, size = 2,
                    add = "mean_se", xtext_angle = 0,
                    color_values = unname(cols)) +
        ggtitle(m) +
        theme(plot.title = element_text(face = "bold", hjust = 0.5, size = 10),
              legend.position = "none"),
      error = function(e) {
        message("[WARN] plot_alpha(", m, "): ", conditionMessage(e)); NULL
      }
    )
  })
  plots <- Filter(Negate(is.null), plots)
  if (!length(plots)) { message("[WARN] No alpha plots for ", title); return(invisible(NULL)) }

  # Combine with cowplot::plot_grid (microeco_protocol style)
  ncols <- min(length(plots), 4)
  fig <- cowplot::plot_grid(plotlist = plots, ncol = ncols, align = "hv")
  fig_title <- cowplot::ggdraw() +
    cowplot::draw_label(paste0(title, " — Alpha Diversity"),
                        fontface = "bold", size = 12, hjust = 0.5)
  fig_combined <- cowplot::plot_grid(fig_title, fig, ncol = 1,
                                     rel_heights = c(0.1, 1))

  w <- max(3.2 * ncols, 7)
  cowplot::save_plot(out_file, fig_combined,
                     base_width = w, base_height = 4.5, dpi = 300)
  cat(sprintf("[INFO] Alpha saved: %s\n", out_file))
  invisible(mt_clone$alpha_diversity)
}

# ══════════════════════════════════════════════════════════════════════════════
# BETA DIVERSITY  —  microeco_protocol style
#   cal_betadiv(bray) → trans_beta$new() → cal_ordination(PCoA)
#   + cal_manova(manova_all=TRUE) → plot_ordination(point+ellipse)
#   cowplot::save_plot(dpi=300, base_aspect_ratio=1.2)
# ══════════════════════════════════════════════════════════════════════════════

viz_beta_microeco <- function(mt, group_col, out_file, out_tsv, title,
                              measure = "bray") {
  mt_clone <- clone(mt)
  mt_clone$cal_betadiv(method = measure)

  grps <- sort(unique(as.character(mt_clone$sample_table[[group_col]])))
  cols <- setNames(npg_pal(length(grps)), grps)

  t1 <- trans_beta$new(dataset = mt_clone, group = group_col, measure = measure)
  t1$cal_ordination(method = "PCoA", ncomp = 2)

  if (!is.null(t1$res_ordination$scores)) {
    write.csv(t1$res_ordination$scores, out_tsv)
  }

  # PERMANOVA annotation
  perm_label <- ""
  tryCatch({
    t1$cal_manova(manova_all = TRUE, group = group_col)
    if (!is.null(t1$res_manova) && nrow(t1$res_manova) > 0) {
      r2  <- round(t1$res_manova$R2[1], 3)
      pv  <- round(t1$res_manova$`Pr(>F)`[1], 3)
      perm_label <- sprintf("PERMANOVA: R² = %.3f, p = %.3f", r2, pv)
    }
  }, error = function(e) message("[WARN] cal_manova: ", conditionMessage(e)))

  # Build base plot: points only (no ellipse from microeco — we add manually)
  g1 <- tryCatch(
    t1$plot_ordination(plot_color   = group_col,
                       plot_shape   = group_col,
                       plot_type    = "point",
                       color_values = unname(cols),
                       shape_values = c(16,17,15,18,8,3,4,7)[seq_along(grps)]),
    error = function(e) {
      message("[WARN] plot_ordination: ", conditionMessage(e)); NULL
    }
  )
  if (is.null(g1)) return(invisible(NULL))

  # Detect the PCo column names from the score data
  scores <- t1$res_ordination$scores
  pco_cols <- grep("^PCo", names(scores), value = TRUE)
  if (length(pco_cols) < 2) {
    message("[WARN] Cannot find PCo columns in scores for ", title)
    return(invisible(NULL))
  }
  pc1 <- pco_cols[1]; pc2 <- pco_cols[2]

  # Add 95% confidence ellipse via stat_ellipse (t-distribution)
  # stat_ellipse needs the same aesthetics as the base plot
  g1 <- g1 +
    stat_ellipse(data    = scores,
                 mapping = aes(x = .data[[pc1]], y = .data[[pc2]],
                               colour = .data[[group_col]],
                               fill   = .data[[group_col]]),
                 geom    = "polygon",
                 type    = "t",
                 level   = 0.95,
                 alpha   = 0.10,
                 lwd     = 0.5,
                 show.legend = FALSE) +
    stat_ellipse(data    = scores,
                 mapping = aes(x = .data[[pc1]], y = .data[[pc2]],
                               colour = .data[[group_col]]),
                 type    = "t",
                 level   = 0.95,
                 lwd     = 0.5,
                 show.legend = FALSE) +
    scale_fill_manual(values = unname(cols), guide = "none") +
    labs(caption = perm_label) +
    ggtitle(sprintf("%s — Bray-Curtis PCoA", title)) +
    theme(plot.title   = element_text(face = "bold", hjust = 0.5, size = 11),
          plot.caption = element_text(size = 8, hjust = 1, colour = "grey40"),
          panel.grid   = element_blank(),
          legend.title = element_text(face = "bold"))

  cowplot::save_plot(out_file, g1,
                     base_aspect_ratio = 1.2, base_height = 5.5, dpi = 300)
  cat(sprintf("[INFO] Beta PCoA saved: %s\n", out_file))
  invisible(t1)
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

# Load metadata
meta <- tryCatch(load_meta(metadata_csv, group_col),
                 error = function(e) stop("Cannot load metadata: ", conditionMessage(e)))
cat(sprintf("[INFO] Metadata: %d samples, group = '%s'\n", nrow(meta), group_col))

# ── Step 1: Build microtable objects ─────────────────────────────────────────
mt_list <- list()

tryCatch({
  mt_list[["bacteria"]] <- build_mt_bacteria(bact_table, meta)
  log_status("bacteria_mt", "OK", "")
}, error = function(e) {
  log_status("bacteria_mt", "FAILED", conditionMessage(e))
  message("[WARN] bacteria_mt: ", conditionMessage(e))
})

tryCatch({
  mt_list[["virus"]] <- build_mt_virus(vir_table, meta)
  log_status("virus_mt", "OK", "")
}, error = function(e) {
  log_status("virus_mt", "FAILED", conditionMessage(e))
  message("[WARN] virus_mt: ", conditionMessage(e))
})

tryCatch({
  if (nzchar(fungi_dir) && dir.exists(fungi_dir)) {
    res <- build_mt_fungi(fungi_dir, meta)
    if (!is.null(res)) {
      mt_list[["fungi"]] <- res
      log_status("fungi_mt", "OK", "")
    } else {
      log_status("fungi_mt", "SKIPPED", "all UNCLASSIFIED")
    }
  } else {
    log_status("fungi_mt", "SKIPPED", "no fungi_dir")
  }
}, error = function(e) {
  log_status("fungi_mt", "FAILED", conditionMessage(e))
  message("[WARN] fungi_mt: ", conditionMessage(e))
})

# ── Step 2: Save microtable RDS for downstream (92/94/96) ────────────────────
for (dim_name in names(mt_list)) {
  tryCatch({
    rds_path <- file.path(dim_dirs[[dim_name]], paste0(dim_name, "_microtable.rds"))
    saveRDS(mt_list[[dim_name]], rds_path)
    log_status(paste0(dim_name, "_rds"), "OK", "")
    cat(sprintf("[INFO] Saved microtable RDS: %s\n", rds_path))
  }, error = function(e) {
    log_status(paste0(dim_name, "_rds"), "FAILED", conditionMessage(e))
  })
}

# ── Step 3 & 4: Alpha + Beta for each dimension ───────────────────────────────
ALPHA_MEASURES <- c("Observed", "Chao1", "Shannon", "Pielou")

dim_config <- list(
  bacteria = list(
    measures  = ALPHA_MEASURES,
    alpha_out = file.path(dim_dirs[["bacteria"]], "alpha_diversity_boxplot.pdf"),
    alpha_tsv = file.path(dim_dirs[["bacteria"]], "alpha_diversity.csv"),
    beta_out  = file.path(dim_dirs[["bacteria"]], "pcoa_ellipses_permanova.pdf"),
    beta_tsv  = file.path(dim_dirs[["bacteria"]], "beta_pcoa_scores.csv"),
    title     = "Bacteria"
  ),
  virus = list(
    measures  = ALPHA_MEASURES,
    alpha_out = file.path(dim_dirs[["virus"]], "alpha_diversity_boxplot.pdf"),
    alpha_tsv = file.path(dim_dirs[["virus"]], "alpha_diversity.csv"),
    beta_out  = file.path(dim_dirs[["virus"]], "pcoa_ellipses_permanova.pdf"),
    beta_tsv  = file.path(dim_dirs[["virus"]], "beta_pcoa_scores.csv"),
    title     = "Virus"
  ),
  fungi = list(
    measures  = ALPHA_MEASURES,
    alpha_out = file.path(dim_dirs[["fungi"]], "alpha_diversity_boxplot.pdf"),
    alpha_tsv = file.path(dim_dirs[["fungi"]], "alpha_diversity.csv"),
    beta_out  = file.path(dim_dirs[["fungi"]], "pcoa_ellipses_permanova.pdf"),
    beta_tsv  = file.path(dim_dirs[["fungi"]], "beta_pcoa_scores.csv"),
    title     = "Fungi"
  )
)

for (dim_name in names(dim_config)) {
  cfg <- dim_config[[dim_name]]
  mt  <- mt_list[[dim_name]]
  if (is.null(mt)) {
    log_status(paste0(dim_name, "_alpha"), "SKIPPED", "no microtable")
    log_status(paste0(dim_name, "_pcoa"),  "SKIPPED", "no microtable")
    next
  }

  # Alpha
  tryCatch({
    viz_alpha_microeco(mt, group_col,
                       out_file = cfg$alpha_out,
                       out_tsv  = cfg$alpha_tsv,
                       title    = cfg$title,
                       measures = cfg$measures)
    log_status(paste0(dim_name, "_alpha"), "OK", "")
  }, error = function(e) {
    log_status(paste0(dim_name, "_alpha"), "FAILED", conditionMessage(e))
    message("[WARN] ", dim_name, "_alpha: ", conditionMessage(e))
  })

  # Beta
  tryCatch({
    viz_beta_microeco(mt, group_col,
                      out_file = cfg$beta_out,
                      out_tsv  = cfg$beta_tsv,
                      title    = cfg$title)
    log_status(paste0(dim_name, "_pcoa"), "OK", "")
  }, error = function(e) {
    log_status(paste0(dim_name, "_pcoa"), "FAILED", conditionMessage(e))
    message("[WARN] ", dim_name, "_pcoa: ", conditionMessage(e))
  })
}

# ── Step 5: Root-level TSV sentinels (Snakemake) ─────────────────────────────
# Collect alpha_diversity.tsv from all dimensions
alpha_rows <- lapply(names(dim_config), function(d) {
  f <- dim_config[[d]]$alpha_tsv
  if (file.exists(f)) {
    df <- tryCatch(read.csv(f), error = function(e) NULL)
    if (!is.null(df)) { df$dimension <- d; return(df) }
  }
  NULL
})
alpha_rows <- Filter(Negate(is.null), alpha_rows)

if (length(alpha_rows)) {
  all_cols <- unique(unlist(lapply(alpha_rows, names)))
  alpha_rows <- lapply(alpha_rows, function(df) {
    miss <- setdiff(all_cols, names(df))
    if (length(miss)) df[miss] <- NA_real_
    df[all_cols]
  })
  write.table(do.call(rbind, alpha_rows),
              file.path(result_dir, "alpha_diversity.tsv"),
              sep = "\t", row.names = FALSE, quote = FALSE)
} else {
  write.table(data.frame(note = "no alpha computed"),
              file.path(result_dir, "alpha_diversity.tsv"),
              sep = "\t", row.names = FALSE, quote = FALSE)
}

if (!file.exists(file.path(result_dir, "beta_pcoa.tsv")))
  write.table(data.frame(note = "see per-dimension beta_pcoa_scores.csv"),
              file.path(result_dir, "beta_pcoa.tsv"),
              sep = "\t", row.names = FALSE, quote = FALSE)

# ── Step 6: Status log ────────────────────────────────────────────────────────
status_df <- do.call(rbind, status_log)
write.table(status_df,
            file.path(result_dir, "diversity_status.tsv"),
            sep = "\t", row.names = FALSE, quote = FALSE)

cat("\n[INFO] Diversity analysis complete.\n")
print(status_df)

if (!file.exists(file.path(result_dir, "alpha_diversity.tsv")))
  stop("No alpha_diversity.tsv produced")

cat("[INFO] All outputs written to:", result_dir, "\n")
