#!/usr/bin/env bash
# ==============================================================================
# Script: 91_stat_diversity.sh
# Purpose: Alpha/Beta diversity analysis for bacteria, virus, and fungi tables
# Usage:   bash 91_stat_diversity.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                   [-g GROUP_COL] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 91_stat_diversity.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                 [-g GROUP_COL] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV

Optional:
  -g  Group column in metadata (default: group)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
THREADS=""
METADATA_CSV=""
GROUP_COL="group"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ] || [ -z "${THREADS}" ] || [ -z "${METADATA_CSV}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
TREE_FILE="${WORKDIR}/result/metaphlan4/merged/mpa_tree.nwk"
RESULT_DIR="${WORKDIR}/result/stat/diversity"
LOG_DIR="${WORKDIR}/logs/stat/diversity"
SENTINEL="${RESULT_DIR}/alpha_diversity.tsv"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/91_stat_diversity.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running diversity statistics"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV}"
echo "[INFO] Group column: ${GROUP_COL}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL BACT_TABLE VIR_TABLE FUNGI_DIR TREE_FILE RESULT_DIR

conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)

required_pkgs <- c("phyloseq", "vegan", "microbiome", "picante", "ggplot2", "ggpubr", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(phyloseq)
  library(vegan)
  library(microbiome)
  library(picante)
  library(ggplot2)
  library(ggpubr)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

workdir <- Sys.getenv("WORKDIR")
metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
tree_file <- Sys.getenv("TREE_FILE")
result_dir <- Sys.getenv("RESULT_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

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

read_metadata <- function(path, group_col) {
  meta <- readr::read_csv(path, show_col_types = FALSE)
  if (nrow(meta) == 0) stop("Metadata is empty")
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>%
    dplyr::rename(sample_id = !!sample_col)
  if (!group_col %in% names(meta)) stop("Metadata group column not found: ", group_col)
  meta <- meta %>%
    dplyr::mutate(sample_id = as.character(sample_id), !!group_col := as.factor(.data[[group_col]])) %>%
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
  if (!file.exists(path)) stop("Missing input table: ", path)
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  if (nrow(raw) == 0) stop(label, " table is empty")
  feature_col <- names(raw)[1]
  candidate_numeric <- names(raw)[vapply(raw, function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0, logical(1))]
  sample_cols <- setdiff(candidate_numeric, feature_col)
  if (length(sample_cols) == 0) stop("No sample columns detected in ", path)
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
  if (length(files) == 0) stop("No fungi profile files found in ", dir_path)
  prof_list <- lapply(files, function(fp) {
    # Read with col_names=FALSE to avoid header stripping issue (header line starts with #)
    raw_lines <- readLines(fp)
    data_lines <- raw_lines[!startsWith(raw_lines, "#")]
    if (length(data_lines) == 0) return(NULL)
    tab <- readr::read_tsv(I(paste(data_lines, collapse = "\n")), show_col_types = FALSE,
                           col_names = c("clade_name", "ncbi_tax_id", "relative_abundance", "additional_species"),
                           col_types = "ccdc")
    tab <- tab[tab$clade_name != "UNCLASSIFIED" & !is.na(tab$relative_abundance), ]
    if (nrow(tab) == 0) return(NULL)
    sample_id <- basename(dirname(fp))
    tibble::tibble(feature = as.character(tab$clade_name), sample_id = sample_id,
                   abundance = tab$relative_abundance)
  })
  prof_list <- Filter(Negate(is.null), prof_list)
  if (length(prof_list) == 0) stop("No fungi taxa found in any profile (all UNCLASSIFIED)")
  prof_df <- dplyr::bind_rows(prof_list) %>% dplyr::filter(!is.na(feature), !is.na(abundance))
  if (nrow(prof_df) == 0) stop("No usable fungi abundances parsed")
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
  if (length(common) < 2) stop("Need at least two overlapping samples")
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

safe_pcoa <- function(d, metric, dimension, meta, group_col) {
  if (length(d) == 0) stop("Distance matrix is empty")
  if (!requireNamespace("ape", quietly = TRUE)) stop("ape package is required for PCoA outputs")
  ord <- ape::pcoa(d)
  vectors <- as.data.frame(ord$vectors[, 1:2, drop = FALSE])
  vectors$sample_id <- rownames(vectors)
  colnames(vectors)[1:2] <- c("Axis1", "Axis2")
  vectors <- vectors %>%
    dplyr::left_join(meta %>% tibble::rownames_to_column("sample_id"), by = "sample_id") %>%
    dplyr::mutate(metric = metric, dimension = dimension)
  perm <- tibble()
  if (group_col %in% names(meta) && nlevels(as.factor(meta[[group_col]])) > 1) {
    perm_df <- meta %>% tibble::rownames_to_column("sample_id")
    rownames(perm_df) <- perm_df$sample_id
    fit <- vegan::adonis2(d ~ .data[[group_col]], data = perm_df)
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
  if (nrow(alpha_df) == 0) return(invisible(NULL))
  pdf(out_file, width = 11, height = 8)
  p <- alpha_df %>%
    tidyr::pivot_longer(cols = c("Shannon", "Chao1", "Simpson", "Observed", "FaithPD"), names_to = "metric", values_to = "value") %>%
    dplyr::filter(!is.na(value)) %>%
    ggplot(aes(x = .data[[group_col]], y = value, fill = .data[[group_col]])) +
    geom_boxplot(outlier.shape = NA, alpha = 0.8) +
    geom_jitter(width = 0.15, size = 1.4, alpha = 0.7) +
    facet_grid(metric ~ dimension, scales = "free_y") +
    theme_bw(base_size = 11) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "none") +
    labs(x = group_col, y = "Alpha diversity", title = "Alpha diversity across groups")
  if (length(unique(alpha_df[[group_col]])) > 1) {
    p <- p + ggpubr::stat_compare_means(label = "p.format", method = "wilcox.test")
  }
  print(p)
  dev.off()
}

plot_beta <- function(beta_df, out_file, group_col) {
  if (nrow(beta_df) == 0) return(invisible(NULL))
  pdf(out_file, width = 11, height = 8)
  p <- ggplot(beta_df, aes(x = Axis1, y = Axis2, color = .data[[group_col]])) +
    geom_point(size = 2.4, alpha = 0.85) +
    facet_grid(metric ~ dimension, scales = "free") +
    theme_bw(base_size = 11) +
    labs(title = "PCoA of beta diversity", color = group_col)
  print(p)
  dev.off()
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
  # vOTU table uses "S01_tpm" column names — strip "_tpm" suffix to match metadata sample IDs
  colnames(vir_mat) <- sub("_tpm$", "", colnames(vir_mat))
  datasets$virus <- vir_mat
})
run_step("fungi_import", {
  datasets$fungi <- read_fungi_profiles(fungi_dir)
})

tree_obj <- NULL
run_step("tree_import", {
  if (file.exists(tree_file) && requireNamespace("ape", quietly = TRUE)) {
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
status_df <- bind_rows(status_log)

if (nrow(alpha_df) == 0) stop("No alpha diversity results were generated")

readr::write_tsv(alpha_df, file.path(result_dir, "alpha_diversity.tsv"))
readr::write_tsv(beta_df, file.path(result_dir, "beta_pcoa.tsv"))
readr::write_tsv(permanova_df, file.path(result_dir, "permanova.tsv"))
readr::write_tsv(status_df, file.path(result_dir, "diversity_status.tsv"))

plot_alpha(alpha_df, file.path(result_dir, "alpha_diversity_boxplot.pdf"), group_col)
plot_beta(beta_df, file.path(result_dir, "beta_pcoa.pdf"), group_col)
RSCRIPT

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 91_stat_diversity.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Diversity analysis completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
