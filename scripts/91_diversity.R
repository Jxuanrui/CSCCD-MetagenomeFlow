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

required_pkgs <- c("microeco", "magrittr", "dplyr", "tidyr", "vegan")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))

suppressPackageStartupMessages({
  library(microeco)
  library(magrittr)
  library(dplyr)
  library(tidyr)
  library(vegan)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

workdir <- Sys.getenv("WORKDIR")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL") %||% "group"
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
result_dir <- Sys.getenv("RESULT_DIR")
if (!nzchar(result_dir)) {
  result_dir <- file.path(workdir, "result", "stat", "diversity")
}

stat_root <- dirname(result_dir)
compat_diversity_dir <- file.path(stat_root, "diversity")
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(compat_diversity_dir, recursive = TRUE, showWarnings = FALSE)

status_log <- list()
log_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- data.frame(
    step = step,
    status = status,
    message = message,
    stringsAsFactors = FALSE
  )
}

write_tsv_matrix <- function(x, path) {
  write.table(x, path, sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA, na = "")
}

safe_write <- function(step, path, expr) {
  tryCatch({
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    force(expr)
    log_status(step, "OK", path)
    TRUE
  }, error = function(e) {
    message("[WARN] ", step, ": ", conditionMessage(e))
    log_status(step, "FAILED", conditionMessage(e))
    FALSE
  })
}

write_fungi_skip_sentinels <- function(message) {
  diversity_path <- file.path(stat_root, "fungi", "diversity", "diversity_status.tsv")
  abundance_path <- file.path(stat_root, "fungi", "abundance", ".ok")
  differential_path <- file.path(stat_root, "fungi", "differential", ".skipped")

  dir.create(dirname(diversity_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(abundance_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(differential_path), recursive = TRUE, showWarnings = FALSE)

  write.table(
    data.frame(
      step = "fungi_mt",
      status = "SKIPPED",
      message = message,
      stringsAsFactors = FALSE
    ),
    diversity_path,
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )
  writeLines("", abundance_path)
  writeLines("", differential_path)
}

sanitize_level_name <- function(x) {
  x <- gsub("[^A-Za-z0-9]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  tolower(x)
}

load_meta <- function(path, grp) {
  meta <- read.csv(path, check.names = FALSE)
  cands <- c("sample_id", "SampleID", "sample", "Sample", "id")
  sc <- (cands[cands %in% names(meta)])[1] %||% names(meta)[1]
  meta <- meta %>%
    rename(sample_id = !!sc) %>%
    mutate(
      sample_id = as.character(sample_id),
      !!grp := as.factor(.data[[grp]])
    ) %>%
    filter(!is.na(sample_id), !is.na(.data[[grp]])) %>%
    distinct(sample_id, .keep_all = TRUE) %>%
    as.data.frame(stringsAsFactors = FALSE)
  rownames(meta) <- meta$sample_id
  meta
}

build_mt_bacteria <- function(bact_path, meta) {
  raw <- read.table(
    bact_path,
    header = TRUE,
    row.names = 1,
    sep = "\t",
    comment.char = "#",
    check.names = FALSE
  )
  sp_idx <- grepl("(^|\\|)s__", rownames(raw)) & !grepl("(^|\\|)t__", rownames(raw))
  if (sum(sp_idx) < 2) stop("< 2 species in bacteria table")
  raw_sp <- raw[sp_idx, , drop = FALSE]

  parse_lin <- function(lin) {
    parts <- strsplit(lin, "\\|")[[1]]
    pfx <- c(
      Kingdom = "k__", Phylum = "p__", Class = "c__", Order = "o__",
      Family = "f__", Genus = "g__", Species = "s__"
    )
    vapply(pfx, function(px) {
      m <- parts[startsWith(parts, px)]
      if (length(m)) sub(paste0("^", px), "", m[1]) else NA_character_
    }, character(1))
  }

  tax_df <- as.data.frame(do.call(rbind, lapply(rownames(raw_sp), parse_lin)), stringsAsFactors = FALSE)
  rownames(tax_df) <- rownames(raw_sp)

  common <- intersect(colnames(raw_sp), rownames(meta))
  if (length(common) < 2) stop("< 2 overlapping samples (bacteria)")
  otu_df <- as.data.frame(round(raw_sp[, common, drop = FALSE] * 1000))

  mt <- microtable$new(
    otu_table = otu_df,
    tax_table = tax_df,
    sample_table = meta[common, , drop = FALSE]
  )
  mt$tidy_dataset()
  mt
}

build_mt_virus <- function(votu_path, meta) {
  clusters_path <- file.path(dirname(dirname(votu_path)), "vclust", "clusters.tsv")
  if (!file.exists(clusters_path)) stop("Missing clusters.tsv: ", clusters_path)

  clusters <- read.table(
    clusters_path,
    header = TRUE,
    sep = "\t",
    col.names = c("contig", "votu_rep"),
    stringsAsFactors = FALSE
  )
  raw <- read.table(
    votu_path,
    header = TRUE,
    sep = "\t",
    check.names = FALSE,
    comment.char = "",
    stringsAsFactors = FALSE
  )
  tpm_cols <- names(raw)[grepl("_tpm$", names(raw), ignore.case = TRUE)]
  if (!length(tpm_cols)) stop("No *_tpm columns in vOTU table")
  sample_ids <- sub("_tpm$", "", tpm_cols, ignore.case = TRUE)

  contig_ord <- order(nchar(clusters$contig), decreasing = TRUE)
  contigs <- clusters$contig[contig_ord]
  votus <- clusters$votu_rep[contig_ord]

  orf_to_votu <- vapply(raw$gene, function(orf) {
    for (i in seq_along(contigs)) {
      if (orf == contigs[i] || startsWith(orf, paste0(contigs[i], "_"))) return(votus[i])
    }
    NA_character_
  }, character(1))

  raw[tpm_cols] <- lapply(raw[tpm_cols], function(x) suppressWarnings(as.numeric(x)))
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
  otu_df <- round(otu_df)

  tax_df <- data.frame(vOTU = rownames(otu_df), row.names = rownames(otu_df), stringsAsFactors = FALSE)
  common <- intersect(colnames(otu_df), rownames(meta))
  if (length(common) < 2) stop("< 2 overlapping samples (virus)")

  mt <- microtable$new(
    otu_table = otu_df[, common, drop = FALSE],
    tax_table = tax_df,
    sample_table = meta[common, , drop = FALSE]
  )
  mt$tidy_dataset()
  mt
}

build_mt_fungi <- function(fungi_profile_dir, meta) {
  fls <- Sys.glob(file.path(fungi_profile_dir, "*", "*_profile.txt"))
  if (!length(fls)) stop("No fungi profiles in ", fungi_profile_dir)

  rows <- lapply(fls, function(fp) {
    lines <- readLines(fp, warn = FALSE)
    dat <- lines[!startsWith(lines, "#")]
    if (!length(dat)) return(NULL)
    tab <- tryCatch(
      read.table(
        text = paste(dat, collapse = "\n"),
        sep = "\t",
        header = FALSE,
        quote = "",
        fill = TRUE,
        stringsAsFactors = FALSE,
        comment.char = ""
      ),
      error = function(e) NULL
    )
    if (is.null(tab)) return(NULL)
    if (ncol(tab) < 4) return(NULL)
    tab <- tab[, seq_len(4), drop = FALSE]
    colnames(tab) <- c("clade_name", "ncbi_tax_id", "relative_abundance", "additional_species")
    tab$relative_abundance <- suppressWarnings(as.numeric(tab$relative_abundance))
    tab <- tab[tab$clade_name != "UNCLASSIFIED" & !is.na(tab$relative_abundance), ]
    if (!nrow(tab)) return(NULL)
    data.frame(
      feature = tab$clade_name,
      sample_id = basename(dirname(fp)),
      abundance = tab$relative_abundance,
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) {
    message("[INFO] Fungi: all UNCLASSIFIED")
    return(NULL)
  }

  wide <- bind_rows(rows) %>%
    filter(!is.na(feature), !is.na(abundance)) %>%
    group_by(feature, sample_id) %>%
    summarise(abundance = sum(abundance, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = sample_id, values_from = abundance, values_fill = 0)

  otu_df <- as.data.frame(wide[, -1, drop = FALSE])
  rownames(otu_df) <- wide$feature
  sp_idx <- grepl("(^|\\|)s__", rownames(otu_df)) & !grepl("(^|\\|)t__", rownames(otu_df))
  if (sum(sp_idx) >= 2) otu_df <- otu_df[sp_idx, , drop = FALSE]
  otu_df <- otu_df[rowSums(otu_df) > 0, , drop = FALSE]
  if (nrow(otu_df) < 2) {
    message("[INFO] Fungi: < 2 non-zero species")
    return(NULL)
  }

  parse_lin <- function(lin) {
    parts <- strsplit(lin, "\\|")[[1]]
    pfx <- c(
      Kingdom = "k__", Phylum = "p__", Class = "c__", Order = "o__",
      Family = "f__", Genus = "g__", Species = "s__"
    )
    vapply(pfx, function(px) {
      m <- parts[startsWith(parts, px)]
      if (length(m)) sub(paste0("^", px), "", m[1]) else NA_character_
    }, character(1))
  }

  tax_df <- as.data.frame(do.call(rbind, lapply(rownames(otu_df), parse_lin)), stringsAsFactors = FALSE)
  rownames(tax_df) <- rownames(otu_df)

  common <- intersect(colnames(otu_df), rownames(meta))
  if (length(common) < 2) stop("< 2 overlapping samples (fungi)")

  mt <- microtable$new(
    otu_table = otu_df[, common, drop = FALSE],
    tax_table = tax_df,
    sample_table = meta[common, , drop = FALSE]
  )
  mt$tidy_dataset()
  mt
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
    if (is.na(lin) || !nzchar(lin)) {
      return(c(Domain = NA, Phylum = NA, Class = NA, Order = NA, Family = NA, Genus = NA))
    }
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
  for (col in c("Domain", "Phylum", "Class", "Order", "Family", "Genus")) {
    new_tax[[col]] <- NA_character_
  }

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

# Filter vOTUs with no geNomad taxonomy (Domain = NA) from a virus microtable.
# These are contigs that could not be classified by any method; removing them
# keeps the abundance/diversity/differential outputs to verified viral sequences.
filter_unclassified_virus <- function(mt) {
  if (!"Domain" %in% colnames(mt$tax_table)) return(mt)
  keep <- !is.na(mt$tax_table$Domain)
  n_before <- nrow(mt$tax_table)
  n_keep   <- sum(keep)
  if (n_keep == 0) stop("No classified virus vOTUs remain after filtering")
  if (n_keep < n_before) {
    message(sprintf("[INFO] virus filter: %d / %d vOTUs have taxonomy; dropping %d unclassified",
                    n_keep, n_before, n_before - n_keep))
    keep_ids <- rownames(mt$tax_table)[keep]
    mt$tax_table <- mt$tax_table[keep_ids, , drop = FALSE]
    mt$otu_table  <- mt$otu_table[keep_ids, , drop = FALSE]
    mt$tidy_dataset()
  }
  mt
}

compute_bray_matrix <- function(mt) {
  otu <- as.matrix(mt$otu_table)
  sample_sums <- colSums(otu, na.rm = TRUE)
  sample_sums[sample_sums == 0] <- 1
  rel_otu <- sweep(otu, 2, sample_sums, "/")
  dist_obj <- vegan::vegdist(t(rel_otu), method = "bray")
  as.matrix(dist_obj)
}

compute_pcoa_table <- function(bray_mat) {
  if (nrow(bray_mat) < 2) stop("Need at least 2 samples for PCoA")
  k <- min(3L, nrow(bray_mat) - 1L)
  fit <- stats::cmdscale(as.dist(bray_mat), k = k, eig = TRUE, add = TRUE)

  points <- as.data.frame(fit$points, stringsAsFactors = FALSE)
  if (!nrow(points)) stop("cmdscale returned no coordinates")
  colnames(points) <- paste0("PC", seq_len(ncol(points)))
  for (i in seq_len(3L)) {
    nm <- paste0("PC", i)
    if (!nm %in% colnames(points)) points[[nm]] <- NA_real_
  }
  points <- points[, c("PC1", "PC2", "PC3"), drop = FALSE]

  eig <- fit$eig
  pos_eig <- eig[eig > 0]
  denom <- sum(pos_eig)
  var_exp <- rep(NA_real_, 3L)
  if (length(pos_eig) && is.finite(denom) && denom > 0) {
    var_exp[seq_len(min(3L, length(pos_eig)))] <- pos_eig[seq_len(min(3L, length(pos_eig)))] / denom
  }

  out <- points
  variance_row <- data.frame(
    PC1 = var_exp[1],
    PC2 = var_exp[2],
    PC3 = var_exp[3],
    stringsAsFactors = FALSE
  )
  rownames(variance_row) <- "variance_explained"
  rbind(out, variance_row)
}

compute_permanova_table <- function(bray_mat, sample_table, group_col) {
  if (!group_col %in% names(sample_table)) stop("Group column not found in sample_table: ", group_col)
  meta <- as.data.frame(sample_table, stringsAsFactors = FALSE)
  meta[[group_col]] <- factor(meta[[group_col]])
  if (length(unique(meta[[group_col]])) < 2) stop("Need at least 2 groups for PERMANOVA")

  ad <- vegan::adonis2(as.dist(bray_mat) ~ group, data = data.frame(group = meta[[group_col]]))
  out <- as.data.frame(ad, stringsAsFactors = FALSE)
  out$Term <- rownames(out)
  rownames(out) <- NULL

  keep <- intersect(c("Term", "Df", "SumOfSqs", "R2", "F", "Pr(>F)"), names(out))
  out[, keep, drop = FALSE]
}

export_metadata <- function(meta) {
  safe_write("metadata_tsv", file.path(stat_root, "metadata.tsv"), {
    write.table(meta, file.path(stat_root, "metadata.tsv"), sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA, na = "")
  })
}

# For virus dimension, microeco cal_abund() produces compound row names like
# "k127_XXX||full|Domain|Phylum|Class|Order" because "vOTU" (contig ID) is the
# first tax_table column. Strip the leading vOTU field and return the last
# meaningful taxonomy token; fall back to the bare contig ID when no taxonomy.
clean_virus_compound_label <- function(x) {
  vapply(x, function(label) {
    # Only process labels that contain a | separator
    if (!grepl("|", label, fixed = TRUE)) return(label)
    # Remove leading vOTU field: k127_NNN or k127_NNN||full, then the | after it
    tax_part <- sub("^k127_[0-9]+(\\|\\|full)?\\|", "", label)
    # If regex did not match (no trailing | after vOTU), strip ||full and return
    if (tax_part == label) return(sub("\\|\\|full$", "", label))
    # Split on literal | (fixed=TRUE uses literal string, NOT regex "\\|")
    parts <- strsplit(tax_part, "|", fixed = TRUE)[[1]]
    parts <- parts[nzchar(parts) & parts != "NA"]
    if (!length(parts)) {
      # All NA taxonomy: return plain contig ID (strip ||full suffix)
      contig <- sub("\\|.*", "", label)
      contig <- sub("\\|\\|full$", "", contig)
      return(contig)
    }
    parts[length(parts)]
  }, character(1), USE.NAMES = FALSE)
}

clean_votu_label <- function(x) {
  ifelse(grepl("|", x, fixed = TRUE), sub(".*\\|", "", x), x)
}

export_abundance_levels <- function(mt, dimension, abundance_dir) {
  safe_write(paste0(dimension, "_cal_abund"), file.path(abundance_dir, ".ok"), {
    mt$cal_abund(rel = TRUE)
  })
  if (is.null(mt$taxa_abund) || !length(mt$taxa_abund)) {
    log_status(paste0(dimension, "_abundance"), "SKIPPED", "No taxa_abund levels available")
    return(invisible(NULL))
  }

  for (level in names(mt$taxa_abund)) {
    lvl_path <- file.path(abundance_dir, paste0(sanitize_level_name(level), "_relabund.tsv"))
    safe_write(paste0(dimension, "_abundance_", level), lvl_path, {
      df <- as.data.frame(mt$taxa_abund[[level]], check.names = FALSE)
      if (dimension == "virus" && level == "vOTU") {
        rownames(df) <- clean_votu_label(rownames(df))
      }
      # For virus, microeco compound labels include the contig ID as prefix.
      # Skip cleaning at the vOTU level (those ARE the identifiers); clean higher levels.
      if (dimension == "virus" && level != "vOTU") {
        new_labels <- clean_virus_compound_label(rownames(df))
        # Use rowsum on the numeric matrix (avoids duplicate rowname error in data.frame)
        mat <- as.matrix(df)
        mat <- rowsum(mat, new_labels, na.rm = TRUE)
        df <- as.data.frame(mat, check.names = FALSE)
      }
      write_tsv_matrix(df, lvl_path)
    })
  }
}

export_alpha_diversity <- function(mt, dimension, diversity_dir) {
  alpha_path <- file.path(diversity_dir, "alpha_diversity.tsv")
  alpha_df <- NULL
  safe_write(paste0(dimension, "_alpha_calc"), alpha_path, {
    mt$cal_alphadiv()
    alpha_df <- as.data.frame(mt$alpha_diversity, check.names = FALSE)
    write_tsv_matrix(alpha_df, alpha_path)
    alpha_df
  })
  alpha_df
}

export_beta_outputs <- function(mt, dimension, diversity_dir) {
  beta_path <- file.path(diversity_dir, "beta_bray_curtis.tsv")
  pcoa_path <- file.path(diversity_dir, "pcoa_coordinates.tsv")
  permanova_path <- file.path(diversity_dir, "permanova_results.tsv")

  bray_mat <- NULL
  safe_write(paste0(dimension, "_beta_calc"), beta_path, {
    mt$cal_betadiv(unifrac = FALSE)
    bray_mat <- compute_bray_matrix(mt)
    write_tsv_matrix(as.data.frame(bray_mat, check.names = FALSE), beta_path)
    bray_mat
  })
  if (is.null(bray_mat)) return(invisible(NULL))

  safe_write(paste0(dimension, "_pcoa"), pcoa_path, {
    pcoa_df <- compute_pcoa_table(bray_mat)
    write_tsv_matrix(pcoa_df, pcoa_path)
  })

  safe_write(paste0(dimension, "_permanova"), permanova_path, {
    permanova_df <- compute_permanova_table(bray_mat, mt$sample_table, group_col)
    write.table(permanova_df, permanova_path, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  })
}

write_alpha_sentinel <- function(alpha_results) {
  sentinel_path <- file.path(compat_diversity_dir, "alpha_diversity.tsv")
  if (!length(alpha_results)) {
    write.table(
      data.frame(note = "no alpha computed"),
      sentinel_path,
      sep = "\t",
      quote = FALSE,
      row.names = FALSE
    )
    return(invisible(NULL))
  }

  merged <- do.call(rbind, lapply(names(alpha_results), function(dim_name) {
    df <- alpha_results[[dim_name]]
    if (is.null(df) || !nrow(df)) return(NULL)
    df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
    df$sample_id <- rownames(df)
    df$dimension <- dim_name
    df
  }))

  if (is.null(merged) || !nrow(merged)) {
    write.table(
      data.frame(note = "no alpha computed"),
      sentinel_path,
      sep = "\t",
      quote = FALSE,
      row.names = FALSE
    )
  } else {
    write.table(merged, sentinel_path, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  }
}

meta <- tryCatch(load_meta(metadata_csv, group_col), error = function(e) stop("Cannot load metadata: ", conditionMessage(e)))
export_metadata(meta)

dimension_roots <- setNames(lapply(c("bacteria", "virus", "fungi"), function(dim_name) {
  dim_root <- file.path(stat_root, dim_name)
  dir.create(file.path(dim_root, "abundance"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(dim_root, "diversity"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(dim_root, "differential"), recursive = TRUE, showWarnings = FALSE)
  list(
    root = dim_root,
    abundance = file.path(dim_root, "abundance"),
    diversity = file.path(dim_root, "diversity"),
    differential = file.path(dim_root, "differential"),
    compat = file.path(result_dir, dim_name)
  )
}), c("bacteria", "virus", "fungi"))

for (dim_name in names(dimension_roots)) {
  dir.create(dimension_roots[[dim_name]]$compat, recursive = TRUE, showWarnings = FALSE)
}

mt_list <- list()

tryCatch({
  mt_list[["bacteria"]] <- build_mt_bacteria(bact_table, meta)
  log_status("bacteria_mt", "OK", "")
}, error = function(e) {
  log_status("bacteria_mt", "FAILED", conditionMessage(e))
  message("[WARN] bacteria_mt: ", conditionMessage(e))
})

tryCatch({
  mt_list[["virus"]] <- filter_unclassified_virus(
    enrich_virus_taxonomy(build_mt_virus(vir_table, meta), workdir)
  )
  log_status("virus_mt", "OK", "")
}, error = function(e) {
  log_status("virus_mt", "FAILED", conditionMessage(e))
  message("[WARN] virus_mt: ", conditionMessage(e))
})

tryCatch({
  if (nzchar(fungi_dir) && dir.exists(fungi_dir)) {
    mt_fungi <- build_mt_fungi(fungi_dir, meta)
    if (!is.null(mt_fungi)) {
      mt_list[["fungi"]] <- mt_fungi
      log_status("fungi_mt", "OK", "")
    } else {
      log_status("fungi_mt", "SKIPPED", "all UNCLASSIFIED or < 2 taxa")
      write_fungi_skip_sentinels("all UNCLASSIFIED or < 2 taxa")
    }
  } else {
    log_status("fungi_mt", "SKIPPED", "no fungi_dir")
    write_fungi_skip_sentinels("no fungi_dir")
  }
}, error = function(e) {
  log_status("fungi_mt", "FAILED", conditionMessage(e))
  message("[WARN] fungi_mt: ", conditionMessage(e))
})

alpha_results <- list()

for (dim_name in names(dimension_roots)) {
  mt <- mt_list[[dim_name]]
  dirs <- dimension_roots[[dim_name]]
  if (is.null(mt)) next

  compat_rds_path <- file.path(result_dir, dim_name, paste0(dim_name, "_microtable.rds"))
  safe_write(paste0(dim_name, "_rds"), compat_rds_path, {
    saveRDS(mt, compat_rds_path)
  })

  # Export phyloseq RDS (Phase 1: Phyloseq centralization)
  phyloseq_dir <- file.path(stat_root, dim_name, "phyloseq")
  phyloseq_rds_path <- file.path(phyloseq_dir, paste0(dim_name, "_phyloseq.rds"))
  if (requireNamespace("file2meco", quietly = TRUE)) {
    safe_write(paste0(dim_name, "_phyloseq"), phyloseq_rds_path, {
      dir.create(phyloseq_dir, recursive = TRUE, showWarnings = FALSE)
      ps <- file2meco::meco2phyloseq(mt)
      saveRDS(ps, phyloseq_rds_path)
    })
  } else {
    log_status(paste0(dim_name, "_phyloseq"), "SKIPPED", "file2meco not available")
  }

  export_abundance_levels(mt, dim_name, dirs$abundance)
  alpha_results[[dim_name]] <- export_alpha_diversity(mt, dim_name, dirs$diversity)
  export_beta_outputs(mt, dim_name, dirs$diversity)
}

write_alpha_sentinel(alpha_results)

status_df <- if (length(status_log)) do.call(rbind, status_log) else data.frame(
  step = character(),
  status = character(),
  message = character(),
  stringsAsFactors = FALSE
)
write.table(
  status_df,
  file.path(compat_diversity_dir, "diversity_status.tsv"),
  sep = "\t",
  quote = FALSE,
  row.names = FALSE
)

if (!file.exists(file.path(compat_diversity_dir, "alpha_diversity.tsv"))) {
  stop("No alpha_diversity.tsv produced")
}

message("[INFO] Diversity analysis complete")
