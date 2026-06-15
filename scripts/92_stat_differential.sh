#!/usr/bin/env bash
# ==============================================================================
# Script: 92_stat_differential.sh
# Purpose: Differential abundance analysis across bacteria, virus, and fungi
# Usage:   bash 92_stat_differential.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                      -g GROUP_COL [-d DIMENSION] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 92_stat_differential.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                    -g GROUP_COL [-d DIMENSION] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV
  -g  Group column in metadata

Optional:
  -d  Dimension: bacteria|virus|fungi|all (default: all)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
THREADS=""
METADATA_CSV=""
GROUP_COL=""
DIMENSION="all"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        -d) DIMENSION="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ] || [ -z "${THREADS}" ] || [ -z "${METADATA_CSV}" ] || [ -z "${GROUP_COL}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

SECONDS=0

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/table/vOTU_table_ann.txt"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
RESULT_DIR="${WORKDIR}/result/stat/diff"
LOG_DIR="${WORKDIR}/logs/stat/diff"
SENTINEL="${RESULT_DIR}/diff_summary.tsv"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/92_stat_differential.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running differential abundance analysis"
echo "[INFO] Dimension: ${DIMENSION}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL DIMENSION BACT_TABLE VIR_TABLE FUNGI_DIR RESULT_DIR

conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)

required_pkgs <- c("ALDEx2", "Maaslin2", "MicrobiomeStat", "ANCOMBC", "phyloseq", "tidyverse", "UpSetR")
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
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
dimension_req <- Sys.getenv("DIMENSION")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
result_dir <- Sys.getenv("RESULT_DIR")
threads <- as.integer(Sys.getenv("THREADS", "1"))

dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

status_log <- list()
summary_rows <- list()

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
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)
  if (!group_col %in% names(meta)) stop("Group column missing: ", group_col)
  meta <- meta %>%
    dplyr::mutate(sample_id = as.character(sample_id), !!group_col := as.factor(.data[[group_col]])) %>%
    dplyr::filter(!is.na(sample_id), !is.na(.data[[group_col]])) %>%
    dplyr::distinct(sample_id, .keep_all = TRUE) %>%
    as.data.frame()
  rownames(meta) <- meta$sample_id
  meta
}

coerce_numeric_df <- function(df) {
  for (i in seq_along(df)) df[[i]] <- suppressWarnings(as.numeric(df[[i]]))
  df
}

read_abundance_table <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE, comment = "#")
  feature_col <- names(raw)[1]
  candidate_numeric <- names(raw)[vapply(raw, function(x) is.numeric(x) || suppressWarnings(sum(!is.na(as.numeric(x)))) > 0, logical(1))]
  sample_cols <- setdiff(candidate_numeric, feature_col)
  if (length(sample_cols) == 0) stop("No sample columns found in ", path)
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
  if (length(files) == 0) stop("No fungi profile files found in ", dir_path)
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

make_phyloseq <- function(mat, meta) {
  common <- intersect(colnames(mat), rownames(meta))
  if (length(common) < 4) stop("Need at least four overlapping samples for DA")
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
  if (length(lvls) < 2) stop("Need at least two groups")
  keep <- meta[[group_col]] %in% lvls[1:2]
  meta2 <- meta[keep, , drop = FALSE]
  meta2[[group_col]] <- droplevels(as.factor(meta2[[group_col]]))
  meta2
}

write_method_result <- function(df, dimension, method) {
  out <- file.path(result_dir, paste0(dimension, "_", method, ".tsv"))
  readr::write_tsv(df, out)
  out
}

plot_upset <- function(sig_lists, out_file) {
  if (length(sig_lists) == 0 || all(lengths(sig_lists) == 0)) return(invisible(NULL))
  pdf(out_file, width = 10, height = 8)
  suppressWarnings(print(UpSetR::upset(UpSetR::fromList(sig_lists), nsets = length(sig_lists), order.by = "freq")))
  dev.off()
}

plot_heatmap <- function(df, out_file) {
  if (nrow(df) == 0) return(invisible(NULL))
  pdf(out_file, width = 12, height = 8)
  p <- df %>%
    ggplot(aes(x = method, y = forcats::fct_reorder(taxon, effect, .fun = max, na.rm = TRUE), fill = effect)) +
    geom_tile(color = "white") +
    facet_wrap(~dimension, scales = "free_y") +
    scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0) +
    theme_bw(base_size = 11) +
    labs(x = NULL, y = "Taxon", title = "Top differential taxa across methods")
  print(p)
  dev.off()
}

meta <- read_metadata(metadata_csv, group_col)
datasets <- list(
  bacteria = tryCatch(read_abundance_table(bact_table), error = function(e) NULL),
  virus = tryCatch(read_abundance_table(vir_table), error = function(e) NULL),
  fungi = tryCatch(read_fungi_profiles(fungi_dir), error = function(e) NULL)
)

dimensions <- if (dimension_req == "all") names(datasets) else dimension_req
dimensions <- dimensions[dimensions %in% names(datasets)]
if (length(dimensions) == 0) stop("No valid dimensions selected")

for (dimension in dimensions) {
  run_step(paste0(dimension, "_differential"), {
    mat0 <- datasets[[dimension]]
    if (is.null(mat0)) stop("Input unavailable for dimension: ", dimension)
    common <- intersect(colnames(mat0), rownames(meta))
    if (length(common) < 4) stop("Insufficient overlapping samples")
    mat0 <- mat0[, common, drop = FALSE]
    meta0 <- meta[common, , drop = FALSE]
    meta_bin <- extract_binary_subset(meta0, group_col)
    mat <- mat0[, rownames(meta_bin), drop = FALSE]
    mat <- mat[rowMeans(mat > 0) >= 0.05, , drop = FALSE]
    counts <- prep_counts(mat)
    ps <- make_phyloseq(counts, meta_bin)
    dim_dir <- file.path(result_dir, dimension)
    dir.create(dim_dir, recursive = TRUE, showWarnings = FALSE)

    method_results <- list()
    sig_sets <- list()

    run_step(paste0(dimension, "_aldex2"), {
      conds <- meta_bin[[group_col]]
      aldex_res <- ALDEx2::aldex(counts, conds, mc.samples = 128, test = "wilcox", effect = TRUE, denom = "all", verbose = FALSE)
      aldex_tbl <- tibble::rownames_to_column(as.data.frame(aldex_res), "taxon")
      padj_col <- c("wi.eBH", "we.eBH", "kw.eBH")[c("wi.eBH", "we.eBH", "kw.eBH") %in% names(aldex_tbl)][1] %||% "wi.eBH"
      effect_col <- c("effect", "diff.btw", "rab.win.conditionA")[c("effect", "diff.btw", "rab.win.conditionA") %in% names(aldex_tbl)][1] %||% names(aldex_tbl)[2]
      out <- aldex_tbl %>%
        dplyr::transmute(dimension = dimension, method = "ALDEx2", taxon = taxon, effect = .data[[effect_col]], padj = .data[[padj_col]], significant = padj < 0.05, supplementary = FALSE)
      method_results$ALDEx2 <- out
      sig_sets$ALDEx2 <- out$taxon[out$significant]
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
      maaslin_tbl <- maaslin_tbl %>%
        dplyr::filter(metadata == group_col) %>%
        dplyr::transmute(dimension = dimension, method = "MaAsLin2", taxon = feature, effect = coef, padj = qval, significant = qval < 0.05, supplementary = FALSE)
      method_results$MaAsLin2 <- maaslin_tbl
      sig_sets$MaAsLin2 <- maaslin_tbl$taxon[maaslin_tbl$significant]
      write_method_result(maaslin_tbl, dimension, "maaslin2")
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
	      if (!"taxon" %in% names(linda_tbl)) linda_tbl$taxon <- rownames(linda_tbl)
	      padj_col <- c("padj", "p_adj", "qvalue")[c("padj", "p_adj", "qvalue") %in% names(linda_tbl)][1] %||% names(linda_tbl)[grep("padj|q", names(linda_tbl))[1]]
	      effect_col <- c("stat", "estimate", "log2FoldChange")[c("stat", "estimate", "log2FoldChange") %in% names(linda_tbl)][1] %||% names(linda_tbl)[grep("coef|estimate|stat", names(linda_tbl))[1]]
	      linda_tbl <- linda_tbl %>%
	        dplyr::transmute(dimension = dimension, method = "LinDA", taxon = taxon, effect = .data[[effect_col]], padj = .data[[padj_col]], significant = padj < 0.05, supplementary = FALSE)
      method_results$LinDA <- linda_tbl
      sig_sets$LinDA <- linda_tbl$taxon[linda_tbl$significant]
      write_method_result(linda_tbl, dimension, "linda")
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
      if (!"taxon" %in% names(ancom_tbl)) ancom_tbl$taxon <- rownames(ancom_tbl)
      padj_col <- grep("^q_", names(ancom_tbl), value = TRUE)[1] %||% grep("q|adj", names(ancom_tbl), value = TRUE)[1]
      effect_col <- grep("^lfc_", names(ancom_tbl), value = TRUE)[1] %||% grep("lfc|beta", names(ancom_tbl), value = TRUE)[1]
      diff_col <- grep("^diff_", names(ancom_tbl), value = TRUE)[1]
      ancom_tbl <- ancom_tbl %>%
        dplyr::transmute(dimension = dimension, method = "ANCOMBC2", taxon = taxon, effect = .data[[effect_col]], padj = .data[[padj_col]], significant = if (!is.null(diff_col)) as.logical(.data[[diff_col]]) else padj < 0.05, supplementary = TRUE)
      method_results$ANCOMBC2 <- ancom_tbl
      sig_sets$ANCOMBC2 <- ancom_tbl$taxon[ancom_tbl$significant]
      write_method_result(ancom_tbl, dimension, "ancombc2")
    })

    merged <- bind_rows(method_results)
    if (nrow(merged) == 0) stop("No method produced results for ", dimension)
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

    summary_rows[[length(summary_rows) + 1]] <- tibble(
      dimension = dimension,
      n_features = nrow(counts),
      n_samples = ncol(counts),
      consensus_taxa = nrow(merged_consensus)
    )
  })
}

summary_df <- bind_rows(summary_rows)
status_df <- bind_rows(status_log)
if (nrow(summary_df) == 0) stop("No differential abundance summary generated")

readr::write_tsv(summary_df, file.path(result_dir, "diff_summary.tsv"))
readr::write_tsv(status_df, file.path(result_dir, "diff_status.tsv"))
RSCRIPT

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 92_stat_differential.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Differential abundance analysis completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
