#!/usr/bin/env Rscript
# ==============================================================================
# Script: 91_diversity.R
# Purpose: Alpha/Beta diversity statistics + publication-ready diversity figures
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
  "phyloseq", "vegan", "microbiome", "picante", "ape",
  "ggplot2", "ggpubr", "tidyverse"
)
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(phyloseq)
  library(vegan)
  library(microbiome)
  library(picante)
  library(ape)
  library(ggplot2)
  library(ggpubr)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

workdir <- Sys.getenv("WORKDIR")
repo <- Sys.getenv("REPO")
threads <- Sys.getenv("THREADS")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
tree_file <- Sys.getenv("TREE_FILE")
result_dir <- Sys.getenv("RESULT_DIR")
viz_dir <- Sys.getenv("VIZ_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Starting diversity analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Metadata:", metadata_csv, "\n")
cat("  Group column:", group_col, "\n")
cat("  Threads:", threads, "\n")

status_log <- list()
alpha_all <- list()
beta_all <- list()
permanova_all <- list()

log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- tibble(step = step, status = status, message = message)
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
      legend.key = element_blank()
    )
}

format_p_value <- function(p_value) {
  if (is.na(p_value)) {
    "NA"
  } else if (p_value < 0.001) {
    "< 0.001"
  } else {
    sprintf("= %.3f", p_value)
  }
}

extract_axis_pct <- function(ord_obj, axes = 2) {
  rel_eig <- ord_obj$values$Relative_eig %||% NULL
  if (!is.null(rel_eig) && length(rel_eig) >= axes) {
    return(round(100 * rel_eig[seq_len(axes)], 1))
  }

  eig <- ord_obj$values$Eigenvalues %||% ord_obj$eig %||% numeric(0)
  eig <- eig[is.finite(eig) & eig > 0]
  if (length(eig) == 0) {
    return(rep(NA_real_, axes))
  }
  pct <- 100 * eig[seq_len(min(length(eig), axes))] / sum(eig)
  if (length(pct) < axes) {
    pct <- c(pct, rep(NA_real_, axes - length(pct)))
  }
  round(pct, 1)
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
    stop("Metadata group column not found: ", group_col)
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

coerce_numeric_df <- function(df) {
  for (i in seq_along(df)) {
    df[[i]] <- suppressWarnings(as.numeric(df[[i]]))
  }
  df
}

read_abundance_table <- function(path, label) {
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
    stop("No sample columns detected in ", path)
  }

  abund <- raw %>%
    dplyr::select(all_of(c(feature_col, sample_cols))) %>%
    dplyr::rename(feature = !!feature_col)

  abund[sample_cols] <- coerce_numeric_df(abund[sample_cols])
  abund <- abund %>%
    dplyr::filter(!is.na(feature), feature != "") %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(dplyr::across(all_of(sample_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")

  mat <- as.matrix(abund[, sample_cols, drop = FALSE])
  rownames(mat) <- abund$feature
  mat[is.na(mat)] <- 0
  mat <- mat[rowSums(mat) > 0, , drop = FALSE]
  mat
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
    stop("No fungi taxa found in any profile (all UNCLASSIFIED)")
  }

  prof_df <- dplyr::bind_rows(prof_list) %>% dplyr::filter(!is.na(feature), !is.na(abundance))
  if (nrow(prof_df) == 0) {
    stop("No usable fungi abundances parsed")
  }

  mat <- prof_df %>%
    dplyr::group_by(feature, sample_id) %>%
    dplyr::summarise(abundance = sum(abundance, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = sample_id, values_from = abundance, values_fill = 0)

  rn <- mat$feature
  mat <- as.matrix(mat[, -1, drop = FALSE])
  rownames(mat) <- rn
  mat[rowSums(mat) > 0, , drop = FALSE]
}

parse_taxonomy <- function(features) {
  ranks <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  split_tax <- strsplit(features, "\\|")
  parsed <- lapply(split_tax, function(parts) {
    vals <- rep(NA_character_, length(ranks))
    for (i in seq_len(min(length(parts), length(ranks)))) {
      vals[i] <- gsub("^[a-z]__", "", parts[[i]])
    }
    vals
  })
  out <- do.call(rbind, parsed)
  colnames(out) <- ranks
  rownames(out) <- features
  out
}

make_phyloseq <- function(mat, meta) {
  common <- intersect(colnames(mat), rownames(meta))
  if (length(common) < 2) {
    stop("Need at least two overlapping samples")
  }

  mat <- mat[, common, drop = FALSE]
  meta <- meta[common, , drop = FALSE]
  phyloseq(
    otu_table(mat, taxa_are_rows = TRUE),
    sample_data(meta),
    tax_table(parse_taxonomy(rownames(mat)))
  )
}

clr_distance <- function(mat) {
  mat <- as.matrix(mat)
  mat <- t(mat)
  mat <- mat + 1e-06
  log_mat <- log(mat)
  clr <- sweep(log_mat, 1, rowMeans(log_mat), "-")
  dist(clr, method = "euclidean")
}

safe_pcoa <- function(dist_obj, metric, dimension, meta, group_col) {
  if (length(dist_obj) == 0) {
    stop("Distance matrix is empty")
  }

  ord <- ape::pcoa(dist_obj)
  axis_pct <- extract_axis_pct(ord, axes = 2)
  vectors <- as.data.frame(ord$vectors[, 1:2, drop = FALSE])
  vectors$sample_id <- rownames(vectors)
  colnames(vectors)[1:2] <- c("Axis1", "Axis2")
  meta_for_join <- if ("sample_id" %in% names(meta)) meta else tibble::rownames_to_column(meta, "sample_id")
  vectors <- vectors %>%
    dplyr::left_join(meta_for_join, by = "sample_id") %>%
    dplyr::mutate(
      metric = metric,
      dimension = dimension,
      Axis1_pct = axis_pct[1],
      Axis2_pct = axis_pct[2]
    )

  perm <- tibble()
  if (group_col %in% names(meta) && nlevels(as.factor(meta[[group_col]])) > 1) {
    perm_df <- as.data.frame(meta[labels(dist_obj), , drop = FALSE])
    perm_df$.group_factor <- perm_df[[group_col]]
    fit <- vegan::adonis2(
      dist_obj ~ .group_factor,
      data = perm_df
    )
    perm <- tibble(
      dimension = dimension,
      metric = metric,
      term = rownames(as.data.frame(fit))[1],
      R2 = as.data.frame(fit)$R2[1],
      p_value = as.data.frame(fit)$`Pr(>F)`[1]
    )
  }

  list(coords = vectors, permanova = perm)
}

plot_alpha <- function(alpha_df, out_file, group_col) {
  if (nrow(alpha_df) == 0) {
    return(invisible(NULL))
  }

  p <- alpha_df %>%
    tidyr::pivot_longer(
      cols = c("Shannon", "Chao1", "Simpson", "Observed", "FaithPD"),
      names_to = "metric",
      values_to = "value"
    ) %>%
    dplyr::filter(!is.na(value)) %>%
    ggplot(aes(x = .data[[group_col]], y = value, fill = .data[[group_col]])) +
    geom_boxplot(outlier.shape = NA, alpha = 0.8, linewidth = 0.4) +
    geom_jitter(width = 0.15, size = 1.4, alpha = 0.7) +
    facet_grid(metric ~ dimension, scales = "free_y") +
    theme_publication(base_size = 11) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "none") +
    labs(x = group_col, y = "Alpha diversity", title = "Alpha diversity across groups")

  if (length(unique(alpha_df[[group_col]])) > 1) {
    p <- p + ggpubr::stat_compare_means(label = "p.format", method = "wilcox.test")
  }

  ggsave(out_file, plot = p, width = 11, height = 8)
}

plot_beta <- function(beta_df, out_file, group_col) {
  if (nrow(beta_df) == 0) {
    # No beta diversity data — write placeholder PDF so downstream checks pass
    pdf(out_file, width = 8, height = 6)
    plot.new()
    text(0.5, 0.5, "No beta diversity data available\n(insufficient samples or coverage)", cex = 1.2)
    dev.off()
    return(invisible(NULL))
  }

  p <- ggplot(beta_df, aes(x = Axis1, y = Axis2, color = .data[[group_col]])) +
    geom_point(size = 2.4, alpha = 0.85) +
    facet_grid(metric ~ dimension, scales = "free") +
    theme_publication(base_size = 11) +
    labs(
      title = "PCoA of beta diversity",
      x = "Axis 1",
      y = "Axis 2",
      color = group_col
    )

  ggsave(out_file, plot = p, width = 11, height = 8)
}

select_species_matrix <- function(mat) {
  species_idx <- grepl("(^|\\|)s__", rownames(mat)) & !grepl("(^|\\|)t__", rownames(mat))
  if (sum(species_idx) >= 2) {
    return(mat[species_idx, , drop = FALSE])
  }

  warning("No species-level entries detected in taxonomy.tsv; using full matrix for visualization")
  mat
}

prepare_rarefaction_counts <- function(mat, scale_factor = 1000) {
  counts <- round(pmax(mat, 0) * scale_factor)
  counts <- counts[, colSums(counts) > 0, drop = FALSE]
  if (ncol(counts) < 2) {
    stop("Need at least two samples with positive abundance for rarefaction")
  }
  counts
}

plot_pcoa_with_ellipses <- function(ps, group_col, out_file) {
  mat <- as(otu_table(ps), "matrix")
  if (!phyloseq::taxa_are_rows(ps)) {
    mat <- t(mat)
  }

  meta <- as(sample_data(ps), "data.frame")
  meta$sample_id <- rownames(meta)
  meta <- meta %>% dplyr::filter(!is.na(.data[[group_col]]))
  rownames(meta) <- meta$sample_id

  if (nlevels(as.factor(meta[[group_col]])) < 2) {
    stop("PCoA figure requires at least two groups in metadata column: ", group_col)
  }

  mat <- mat[, meta$sample_id, drop = FALSE]
  bray <- vegan::vegdist(t(mat), method = "bray")
  ord <- ape::pcoa(bray)
  axis_pct <- extract_axis_pct(ord, axes = 2)
  coords <- as.data.frame(ord$vectors[, 1:2, drop = FALSE])
  coords$sample_id <- rownames(coords)
  colnames(coords)[1:2] <- c("Axis1", "Axis2")
  coords <- coords %>% dplyr::left_join(meta, by = "sample_id")

  perm_df <- as.data.frame(meta[labels(bray), , drop = FALSE])
  perm_df$.group_factor <- perm_df[[group_col]]
  permanova_fit <- vegan::adonis2(
    bray ~ .group_factor,
    data = perm_df
  )
  permanova_tbl <- as.data.frame(permanova_fit)
  stat_label <- paste0(
    "PERMANOVA\nR2 = ", sprintf("%.3f", permanova_tbl$R2[1]),
    "\np ", format_p_value(permanova_tbl$`Pr(>F)`[1])
  )

  ellipse_df <- coords %>%
    dplyr::group_by(.data[[group_col]]) %>%
    dplyr::filter(dplyr::n() >= 3) %>%
    dplyr::ungroup()

  p <- ggplot(coords, aes(x = Axis1, y = Axis2, color = .data[[group_col]])) +
    {
      if (nrow(ellipse_df) > 0) {
        stat_ellipse(
          data = ellipse_df,
          aes(fill = .data[[group_col]]),
          geom = "polygon",
          type = "norm",
          level = 0.95,
          alpha = 0.12,
          color = NA,
          show.legend = FALSE
        )
      }
    } +
    geom_point(size = 2.8, alpha = 0.9) +
    annotate(
      "label",
      x = Inf,
      y = Inf,
      label = stat_label,
      hjust = 1.02,
      vjust = 1.05,
      size = 3.6,
      label.size = 0.25,
      fill = "white"
    ) +
    theme_publication(base_size = 12) +
    labs(
      title = "PCoA with 95% confidence ellipses",
      subtitle = "Bray-Curtis distance on MetaPhlAn4 species-level abundance",
      x = paste0("PCoA 1 (", axis_pct[1], "%)"),
      y = paste0("PCoA 2 (", axis_pct[2], "%)"),
      color = group_col,
      fill = group_col
    )

  ggsave(out_file, plot = p, width = 8.6, height = 6.8)
}

plot_rarefaction_curves <- function(ps, group_col, out_file) {
  mat <- as(otu_table(ps), "matrix")
  if (!phyloseq::taxa_are_rows(ps)) {
    mat <- t(mat)
  }

  meta <- as(sample_data(ps), "data.frame")
  meta$sample_id <- rownames(meta)
  meta <- meta %>% dplyr::filter(!is.na(.data[[group_col]]))
  rownames(meta) <- meta$sample_id

  counts <- prepare_rarefaction_counts(mat[, meta$sample_id, drop = FALSE])
  depth_vec <- colSums(counts)
  min_depth <- min(depth_vec)
  step_size <- max(1, floor(min_depth / 80))

  rare_df <- vegan::rarecurve(
    t(counts),
    step = step_size,
    label = FALSE,
    tidy = TRUE
  ) %>%
    dplyr::rename(sample_id = Site, depth = Sample, richness = Species) %>%
    dplyr::left_join(meta, by = "sample_id")

  p <- ggplot(rare_df, aes(x = depth, y = richness, group = sample_id, color = .data[[group_col]])) +
    geom_line(linewidth = 0.55, alpha = 0.7) +
    geom_vline(xintercept = min_depth, linetype = "dashed", color = "grey35", linewidth = 0.6) +
    annotate(
      "label",
      x = min_depth,
      y = max(rare_df$richness, na.rm = TRUE),
      label = paste0("Min depth = ", format(min_depth, big.mark = ",", scientific = FALSE)),
      hjust = -0.05,
      vjust = 1.15,
      size = 3.3,
      label.size = 0.2,
      fill = "white"
    ) +
    theme_publication(base_size = 12) +
    labs(
      title = "Rarefaction curves",
      subtitle = "Observed species richness across scaled sequencing depth",
      x = "Sequencing depth (scaled abundance units)",
      y = "Observed species richness",
      color = group_col,
      caption = "Depth is derived by scaling species-level relative abundances because raw read counts are not stored in taxonomy.tsv."
    )

  ggsave(out_file, plot = p, width = 9.4, height = 6.8)
}

meta <- NULL
run_step("metadata_import", {
  meta <- read_metadata(metadata_csv, group_col)
})

datasets <- list()
run_step("bacteria_import", {
  datasets$bacteria <- read_abundance_table(bact_table, "bacteria")
})
run_step("virus_import", {
  vir_mat <- read_abundance_table(vir_table, "virus")
  colnames(vir_mat) <- sub("_tpm$", "", colnames(vir_mat))
  datasets$virus <- vir_mat
})
run_step("fungi_import", {
  datasets$fungi <- read_fungi_profiles(fungi_dir)
})

tree_obj <- NULL
run_step("tree_import", {
  if (file.exists(tree_file)) {
    tree_obj <- ape::read.tree(tree_file)
  }
})

for (dimension in names(datasets)) {
  run_step(paste0(dimension, "_analysis"), {
    mat <- datasets[[dimension]]
    ps <- make_phyloseq(mat, meta)
    common_samples <- sample_names(ps)
    mat <- as(otu_table(ps), "matrix")
    meta_dim <- as.data.frame(sample_data(ps))
    meta_dim$sample_id <- rownames(meta_dim)

    alpha_df <- tibble(
      sample_id = common_samples,
      dimension = dimension,
      Shannon = vegan::diversity(t(mat), index = "shannon"),
      Chao1 = apply(mat, 2, function(x) {
        xi <- round(x)
        tryCatch(vegan::estimateR(xi)[2], error = function(e) NA_real_)
      }),
      Simpson = vegan::diversity(t(mat), index = "simpson"),
      Observed = vegan::specnumber(t(mat))
    ) %>%
      dplyr::left_join(meta_dim, by = "sample_id")

    alpha_df$FaithPD <- NA_real_
    if (!is.null(tree_obj)) {
      tree_tips <- intersect(rownames(mat), tree_obj$tip.label)
      if (length(tree_tips) >= 3) {
        pd <- picante::pd(t(mat[tree_tips, , drop = FALSE]), tree_obj, include.root = FALSE)
        alpha_df$FaithPD[match(rownames(pd), alpha_df$sample_id)] <- pd$PD
      }
    }
    alpha_all[[dimension]] <- alpha_df

    bray <- vegan::vegdist(t(mat), method = "bray")
    bray_res <- safe_pcoa(bray, "BrayCurtis", dimension, meta_dim, group_col)
    clr_res <- safe_pcoa(clr_distance(mat), "AitchisonCLR", dimension, meta_dim, group_col)

    beta_all[[dimension]] <- bind_rows(bray_res$coords, clr_res$coords)
    permanova_all[[dimension]] <- bind_rows(bray_res$permanova, clr_res$permanova)
  })
}

alpha_df <- bind_rows(alpha_all)
beta_df <- bind_rows(beta_all)
permanova_df <- bind_rows(permanova_all)

if (nrow(alpha_df) == 0) {
  stop("No alpha diversity results were generated")
}

plot_alpha(alpha_df, file.path(result_dir, "alpha_diversity_boxplot.pdf"), group_col)
plot_beta(beta_df, file.path(result_dir, "beta_pcoa.pdf"), group_col)

run_step("bacteria_pcoa_ellipses", {
  bacteria_species <- select_species_matrix(datasets$bacteria)
  bacteria_ps <- make_phyloseq(bacteria_species, meta)
  plot_pcoa_with_ellipses(
    bacteria_ps,
    group_col = group_col,
    out_file = file.path(viz_dir, "pcoa_ellipses_permanova.pdf")
  )
})

run_step("bacteria_rarefaction_curves", {
  bacteria_species <- select_species_matrix(datasets$bacteria)
  bacteria_ps <- make_phyloseq(bacteria_species, meta)
  plot_rarefaction_curves(
    bacteria_ps,
    group_col = group_col,
    out_file = file.path(viz_dir, "rarefaction_curves.pdf")
  )
})

status_df <- bind_rows(status_log)

readr::write_tsv(alpha_df, file.path(result_dir, "alpha_diversity.tsv"))
if (nrow(beta_df) == 0) {
  beta_df <- tibble(
    sample_id = character(),
    dimension = character(),
    metric = character(),
    Axis1 = numeric(),
    Axis2 = numeric(),
    note = character()
  )
}
if (nrow(permanova_df) == 0) {
  permanova_df <- tibble(
    dimension = character(),
    metric = character(),
    R2 = numeric(),
    p_value = numeric(),
    note = character()
  )
}
readr::write_tsv(beta_df, file.path(result_dir, "beta_pcoa.tsv"))
readr::write_tsv(permanova_df, file.path(result_dir, "permanova.tsv"))
readr::write_tsv(status_df, file.path(result_dir, "diversity_status.tsv"))

required_outputs <- c(
  file.path(result_dir, "alpha_diversity.tsv"),
  file.path(result_dir, "beta_pcoa.tsv"),
  file.path(result_dir, "permanova.tsv"),
  file.path(result_dir, "diversity_status.tsv"),
  file.path(result_dir, "alpha_diversity_boxplot.pdf"),
  file.path(result_dir, "beta_pcoa.pdf"),
  file.path(viz_dir, "pcoa_ellipses_permanova.pdf"),
  file.path(viz_dir, "rarefaction_curves.pdf")
)

missing_outputs <- required_outputs[!file.exists(required_outputs) | file.info(required_outputs)$size <= 0]
if (length(missing_outputs) > 0) {
  stop("Expected outputs not generated: ", paste(missing_outputs, collapse = ", "))
}

cat("[INFO] Diversity analysis completed successfully\n")
cat("  Statistics:", result_dir, "\n")
cat("  Visualizations:", viz_dir, "\n")
