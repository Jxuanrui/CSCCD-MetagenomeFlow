#!/usr/bin/env bash
# ==============================================================================
# Script: 94_stat_visualization.sh
# Purpose: Unified downstream visualization across bacteria, virus, and fungi
# Usage:   bash 94_stat_visualization.sh -w WORKDIR -r REPO [-m METADATA_CSV] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 94_stat_visualization.sh -w WORKDIR -r REPO [-m METADATA_CSV] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
METADATA_CSV=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
DIVERSITY_DIR="${WORKDIR}/result/stat/diversity"
RESULT_DIR="${WORKDIR}/result/stat/visualization"
LOG_DIR="${WORKDIR}/logs/stat/visualization"
SENTINEL="${RESULT_DIR}/plots.done"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/94_stat_visualization.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ -n "${METADATA_CSV}" ] && [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running unified visualization"

export WORKDIR REPO METADATA_CSV BACT_TABLE VIR_TABLE FUNGI_DIR DIVERSITY_DIR RESULT_DIR

conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)

required_pkgs <- c("ComplexHeatmap", "ggplot2", "ggpubr", "ggalluvial", "UpSetR", "patchwork", "phyloseq", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(ComplexHeatmap)
  library(ggplot2)
  library(ggpubr)
  library(ggalluvial)
  library(UpSetR)
  library(patchwork)
  library(phyloseq)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

metadata_csv <- Sys.getenv("METADATA_CSV")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
diversity_dir <- Sys.getenv("DIVERSITY_DIR")
result_dir <- Sys.getenv("RESULT_DIR")

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

status_log <- list()

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

read_metadata <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  meta <- readr::read_csv(path, show_col_types = FALSE)
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)
  meta$sample_id <- as.character(meta$sample_id)
  meta
}

coerce_numeric_df <- function(df) {
  for (i in seq_along(df)) df[[i]] <- suppressWarnings(as.numeric(df[[i]]))
  df
}

read_abundance_table <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  feature_col <- names(raw)[1]
  numeric_cols <- names(raw)[vapply(raw, function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0, logical(1))]
  sample_cols <- setdiff(numeric_cols, feature_col)
  tab <- raw %>%
    dplyr::select(all_of(c(feature_col, sample_cols))) %>%
    dplyr::rename(feature = !!feature_col)
  tab[sample_cols] <- coerce_numeric_df(tab[sample_cols])
  tab <- tab %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(dplyr::across(all_of(sample_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")
  mat <- as.matrix(tab[, sample_cols, drop = FALSE])
  rownames(mat) <- tab$feature
  mat[is.na(mat)] <- 0
  mat[rowSums(mat) > 0, , drop = FALSE]
}

read_fungi_profiles <- function(dir_path) {
  files <- Sys.glob(file.path(dir_path, "*", "*_profile.txt"))
  if (length(files) == 0) stop("No fungi profile files found")
  prof <- lapply(files, function(fp) {
    tab <- readr::read_tsv(fp, show_col_types = FALSE, comment = "#")
    feature_col <- c("clade_name", "taxonomy", names(tab)[1])[c("clade_name", "taxonomy", names(tab)[1]) %in% names(tab)][1]
    abundance_col <- c("relative_abundance", "abundance", "fraction_total_reads", names(tab)[ncol(tab)])[c("relative_abundance", "abundance", "fraction_total_reads", names(tab)[ncol(tab)]) %in% names(tab)][1]
    tibble(feature = tab[[feature_col]], sample_id = basename(dirname(fp)), abundance = suppressWarnings(as.numeric(tab[[abundance_col]])))
  })
  merged <- bind_rows(prof) %>%
    dplyr::filter(!is.na(feature), !is.na(abundance)) %>%
    dplyr::group_by(feature, sample_id) %>%
    dplyr::summarise(abundance = sum(abundance, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = sample_id, values_from = abundance, values_fill = 0)
  rn <- merged$feature
  merged <- as.matrix(merged[, -1, drop = FALSE])
  rownames(merged) <- rn
  merged[rowSums(merged) > 0, , drop = FALSE]
}

parse_taxonomy_levels <- function(features) {
  levels <- c("kingdom", "phylum", "class")
  parts <- strsplit(features, "\\|")
  out <- lapply(parts, function(x) {
    vals <- rep("Unclassified", 3)
    for (i in seq_len(min(3, length(x)))) vals[i] <- gsub("^[a-z]__", "", x[i])
    vals
  })
  out <- do.call(rbind, out)
  colnames(out) <- levels
  tibble::as_tibble(out)
}

clr_matrix <- function(mat) {
  mat <- mat + 1e-06
  log_mat <- log(t(mat))
  clr <- sweep(log_mat, 1, rowMeans(log_mat), "-")
  t(clr)
}

prep_long <- function(mat, dimension) {
  tibble(feature = rownames(mat), mean_abundance = rowMeans(mat)) %>%
    dplyr::arrange(dplyr::desc(mean_abundance)) %>%
    dplyr::mutate(dimension = dimension)
}

metadata <- read_metadata(metadata_csv)
bacteria <- tryCatch(read_abundance_table(bact_table), error = function(e) NULL)
virus <- tryCatch(read_abundance_table(vir_table), error = function(e) NULL)
fungi <- tryCatch(read_fungi_profiles(fungi_dir), error = function(e) NULL)

run_step("stacked_barplot", {
  if (is.null(bacteria)) stop("Bacteria table unavailable")
  top_taxa <- names(sort(rowMeans(bacteria), decreasing = TRUE))[seq_len(min(20, nrow(bacteria)))]
  bar_df <- as.data.frame(bacteria[top_taxa, , drop = FALSE]) %>%
    tibble::rownames_to_column("feature") %>%
    tidyr::pivot_longer(-feature, names_to = "sample_id", values_to = "abundance") %>%
    dplyr::left_join(parse_taxonomy_levels(top_taxa) %>% dplyr::mutate(feature = top_taxa), by = "feature")
  pdf(file.path(result_dir, "bacteria_top20_stacked_barplot.pdf"), width = 10, height = 8)
  p <- ggplot(bar_df, aes(x = sample_id, y = abundance, fill = phylum)) +
    geom_col() +
    facet_wrap(~feature, scales = "free_y", ncol = 4) +
    theme_bw(base_size = 10) +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank()) +
    labs(title = "Top-20 bacteria per sample", x = "Sample", y = "Abundance")
  print(p)
  dev.off()
})

run_step("merged_heatmap", {
  mats <- list()
  if (!is.null(bacteria)) mats$bacteria <- bacteria[names(sort(rowMeans(bacteria), decreasing = TRUE))[seq_len(min(50, nrow(bacteria)))], , drop = FALSE]
  if (!is.null(virus)) mats$virus <- virus[names(sort(rowMeans(virus), decreasing = TRUE))[seq_len(min(20, nrow(virus)))], , drop = FALSE]
  if (!is.null(fungi)) mats$fungi <- fungi[names(sort(rowMeans(fungi), decreasing = TRUE))[seq_len(min(20, nrow(fungi)))], , drop = FALSE]
  common <- Reduce(intersect, lapply(mats, colnames))
  if (length(common) < 2) stop("No common samples across matrices")
  mats <- lapply(names(mats), function(nm) {
    mm <- mats[[nm]][, common, drop = FALSE]
    rownames(mm) <- paste0(toupper(substr(nm, 1, 3)), "|", rownames(mm))
    clr_matrix(mm)
  })
  heat_mat <- do.call(rbind, mats)
  pdf(file.path(result_dir, "merged_multiomics_heatmap.pdf"), width = 10, height = 8)
  ht <- ComplexHeatmap::Heatmap(heat_mat, name = "CLR", cluster_rows = TRUE, cluster_columns = TRUE, show_row_names = FALSE)
  draw(ht)
  dev.off()
})

run_step("alluvial_plot", {
  if (is.null(bacteria)) stop("Bacteria table unavailable")
  top_taxa <- names(sort(rowMeans(bacteria), decreasing = TRUE))[seq_len(min(100, nrow(bacteria)))]
  tax_df <- parse_taxonomy_levels(top_taxa) %>%
    dplyr::mutate(weight = rowMeans(bacteria[top_taxa, , drop = FALSE]))
  pdf(file.path(result_dir, "taxonomy_alluvial.pdf"), width = 10, height = 8)
  p <- ggplot(tax_df, aes(axis1 = kingdom, axis2 = phylum, axis3 = class, y = weight)) +
    ggalluvial::geom_alluvium(aes(fill = phylum), alpha = 0.8) +
    ggalluvial::geom_stratum() +
    ggalluvial::geom_text(stat = "stratum", aes(label = after_stat(stratum)), size = 3) +
    scale_x_discrete(limits = c("Kingdom", "Phylum", "Class"), expand = c(.1, .05)) +
    theme_bw(base_size = 10) +
    labs(title = "Taxonomic flow", y = "Mean abundance", x = NULL)
  print(p)
  dev.off()
})

run_step("upset_presence", {
  mats <- list(bacteria = bacteria, virus = virus, fungi = fungi)
  mats <- mats[!vapply(mats, is.null, logical(1))]
  if (length(mats) < 2) stop("Need at least two dimensions for UpSet")
  feature_presence <- lapply(names(mats), function(nm) {
    mat <- mats[[nm]]
    tibble::tibble(feature = rownames(mat), dimension = nm)
  })
  all_features <- bind_rows(feature_presence) %>%
    dplyr::mutate(flag = 1L) %>%
    tidyr::pivot_wider(names_from = dimension, values_from = flag, values_fill = 0L)
  pdf(file.path(result_dir, "dimension_presence_upset.pdf"), width = 10, height = 8)
  print(UpSetR::upset(as.data.frame(all_features[, -1, drop = FALSE]), sets = names(mats)))
  dev.off()
})

run_step("pcoa_composite", {
  beta_file <- file.path(diversity_dir, "beta_pcoa.tsv")
  if (!file.exists(beta_file)) stop("Missing beta PCoA table: ", beta_file)
  beta <- readr::read_tsv(beta_file, show_col_types = FALSE)
  plots <- lapply(c("bacteria", "virus", "fungi"), function(dim_name) {
    df <- beta %>% dplyr::filter(dimension == dim_name, metric == "BrayCurtis")
    if (nrow(df) == 0) {
      ggplot() + theme_void() + labs(title = paste(dim_name, "(missing)"))
    } else {
      color_col <- setdiff(names(df), c("sample_id", "dimension", "metric", "Axis1", "Axis2"))[1] %||% "dimension"
      ggplot(df, aes(x = Axis1, y = Axis2, color = .data[[color_col]])) +
        geom_point(size = 2.4, alpha = 0.8) +
        theme_bw(base_size = 10) +
        labs(title = paste(dim_name, "PCoA"), color = color_col)
    }
  })
  combo <- plots[[1]] + plots[[2]] + plots[[3]] + patchwork::plot_layout(ncol = 3)
  ggsave(file.path(result_dir, "pcoa_composite.pdf"), combo, width = 10, height = 8)
})

readr::write_tsv(bind_rows(status_log), file.path(result_dir, "visualization_status.tsv"))
writeLines("done", file.path(result_dir, "plots.done"))
RSCRIPT

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 94_stat_visualization.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Visualization completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
