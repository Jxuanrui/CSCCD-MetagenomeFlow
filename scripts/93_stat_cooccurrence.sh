#!/usr/bin/env bash
# ==============================================================================
# Script: 93_stat_cooccurrence.sh
# Purpose: Co-occurrence network analysis for intra- and cross-domain matrices
# Usage:   bash 93_stat_cooccurrence.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                      [-g GROUP_COL] [-n NET_TYPE] [--force]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 93_stat_cooccurrence.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
                                    [-g GROUP_COL] [-n NET_TYPE] [--force]

Required:
  -w  Project work directory
  -r  Repository root
  -t  Threads
  -m  Metadata CSV

Optional:
  -g  Group column in metadata
  -n  Network type: bac|vir|fun|cross_bac_vir|cross_bac_fun|all (default: all)
  --force  Re-run even if sentinel exists
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
THREADS=""
METADATA_CSV=""
GROUP_COL=""
NET_TYPE="all"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        -g) GROUP_COL="$2"; shift 2 ;;
        -n) NET_TYPE="$2"; shift 2 ;;
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
RESULT_DIR="${WORKDIR}/result/stat/network"
LOG_DIR="${WORKDIR}/logs/stat/network"
SENTINEL="${RESULT_DIR}/network_summary.txt"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/93_stat_cooccurrence.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Sentinel exists, skipping: ${SENTINEL}"
    exit 0
fi

echo "[INFO] Running co-occurrence network analysis"
echo "[INFO] Network type: ${NET_TYPE}"

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL NET_TYPE BACT_TABLE VIR_TABLE FUNGI_DIR RESULT_DIR

R_LIBS_USER="" conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)

required_pkgs <- c("SpiecEasi", "NetCoMi", "igraph", "ggraph", "phyloseq", "tidyverse")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(SpiecEasi)
  library(NetCoMi)
  library(igraph)
  library(ggraph)
  library(phyloseq)
  library(tidyverse)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
net_type <- Sys.getenv("NET_TYPE")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
result_dir <- Sys.getenv("RESULT_DIR")
threads <- as.integer(Sys.getenv("THREADS", "1"))
repo <- Sys.getenv("REPO")

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

read_metadata <- function(path) {
  meta <- readr::read_csv(path, show_col_types = FALSE)
  sample_col <- c("sample", "sample_id", "SampleID", "Sample", "id")[c("sample", "sample_id", "SampleID", "Sample", "id") %in% names(meta)][1] %||% names(meta)[1]
  meta <- meta %>% dplyr::rename(sample_id = !!sample_col)
  meta <- meta %>% dplyr::mutate(sample_id = as.character(sample_id)) %>% dplyr::distinct(sample_id, .keep_all = TRUE)
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
  # Strip _tpm suffix from vOTU column names to match metadata sample_id
  colnames(mat) <- sub("_tpm$", "", colnames(mat))
  mat[rowSums(mat) > 0, , drop = FALSE]
}

read_fungi_profiles <- function(dir_path) {
  files <- Sys.glob(file.path(dir_path, "*", "*_profile.txt"))
  if (length(files) == 0) stop("No fungi profile files found in ", dir_path)
  prof <- lapply(files, function(fp) {
    raw_lines <- readLines(fp)
    data_lines <- raw_lines[!startsWith(raw_lines, "#")]
    if (length(data_lines) == 0) return(NULL)
    tab <- readr::read_tsv(I(paste(data_lines, collapse = "\n")), show_col_types = FALSE,
                           col_names = c("clade_name", "ncbi_tax_id", "relative_abundance", "additional_species"),
                           col_types = "ccdc")
    tab <- tab[tab$clade_name != "UNCLASSIFIED" & !is.na(tab$relative_abundance), ]
    if (nrow(tab) == 0) return(NULL)
    tibble(feature = as.character(tab$clade_name), sample_id = basename(dirname(fp)),
           abundance = tab$relative_abundance)
  })
  prof <- Filter(Negate(is.null), prof)
  if (length(prof) == 0) stop("No fungi taxa found in any profile (all UNCLASSIFIED)")
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

parse_phylum <- function(features) {
  parts <- strsplit(features, "\\|")
  vapply(parts, function(x) {
    if (length(x) >= 2) gsub("^[a-z]__", "", x[2]) else "Unclassified"
  }, character(1))
}

preprocess_mat <- function(mat) {
  mat <- mat[rowMeans(mat > 0) >= 0.1, , drop = FALSE]
  if (nrow(mat) > 300) {
    keep <- order(rowMeans(mat), decreasing = TRUE)[seq_len(300)]
    mat <- mat[keep, , drop = FALSE]
  }
  mat + 1e-06
}

find_fastspar <- function(repo) {
  path1 <- Sys.which("fastspar")
  if (nzchar(path1)) return(path1)
  path2 <- file.path(repo, "envs", "network", "bin", "fastspar")
  if (file.exists(path2)) return(path2)
  ""
}

infer_network <- function(mat, label, repo, threads) {
  mat <- preprocess_mat(mat)
  if (ncol(mat) < 5 || nrow(mat) < 10) stop("Insufficient matrix size for network inference")
  fastspar_bin <- find_fastspar(repo)
  if (nrow(mat) > 200 && nzchar(fastspar_bin)) {
    tmp_dir <- file.path(tempdir(), paste0("fastspar_", label))
    dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
    in_file <- file.path(tmp_dir, "otu.tsv")
    cor_file <- file.path(tmp_dir, "cor.tsv")
    cov_file <- file.path(tmp_dir, "cov.tsv")
    # FastSpar OTU table: features as rows, samples as cols, first col must be "#OTU ID"
    readr::write_tsv(tibble::rownames_to_column(as.data.frame(round(mat)), "#OTU ID"), in_file)
    system2(fastspar_bin, c("--otu_table", in_file, "--correlation", cor_file, "--covariance", cov_file, "--threads", as.character(threads)))
    cor_df <- readr::read_tsv(cor_file, show_col_types = FALSE)
    cor_mat <- as.matrix(cor_df[, -1, drop = FALSE])
    rownames(cor_mat) <- cor_df[[1]]
    colnames(cor_mat) <- colnames(cor_mat) %||% rownames(cor_mat)
    diag(cor_mat) <- 0
    adj <- abs(cor_mat) >= 0.3
    weights <- cor_mat
    method <- "FastSpar"
  } else {
    sparcc_fit <- SpiecEasi::sparcc(mat)
    cor_mat <- sparcc_fit$Cor %||% stop("SparCC correlations not returned")
    diag(cor_mat) <- 0
    adj <- abs(cor_mat) >= 0.3
    weights <- cor_mat
    method <- "SpiecEasi_SparCC"
  }
  graph <- igraph::graph_from_adjacency_matrix(adj, mode = "undirected", diag = FALSE)
  E(graph)$weight <- weights[as.matrix(igraph::as_edgelist(graph))]
  V(graph)$mean_abundance <- rowMeans(mat)[V(graph)$name]
  V(graph)$phylum <- parse_phylum(V(graph)$name)
  if (igraph::ecount(graph) > 0) {
    # Louvain requires non-negative weights; use absolute correlation for community detection
    E(graph)$weight_abs <- abs(E(graph)$weight)
    community <- igraph::cluster_louvain(graph, weights = E(graph)$weight_abs)
    V(graph)$module <- membership(community)
    modularity_value <- modularity(community)
  } else {
    V(graph)$module <- 1
    modularity_value <- 0
  }
  deg <- igraph::degree(graph)
  hub_cut <- if (length(deg) > 0) stats::quantile(deg, probs = 0.9, na.rm = TRUE) else 0
  hubs <- names(deg)[deg >= hub_cut]
  list(
    graph = graph,
    method = method,
    hubs = hubs,
    modularity = modularity_value,
    edge_density = igraph::edge_density(graph)
  )
}

save_network_outputs <- function(net, label, out_dir) {
  graph <- net$graph
  nodes <- tibble(
    taxon = V(graph)$name,
    mean_abundance = V(graph)$mean_abundance,
    phylum = V(graph)$phylum,
    module = V(graph)$module,
    degree = igraph::degree(graph)
  )
  edges <- igraph::as_data_frame(graph, what = "edges")
  readr::write_tsv(nodes, file.path(out_dir, paste0(label, "_nodes.tsv")))
  readr::write_tsv(edges, file.path(out_dir, paste0(label, "_edges.tsv")))
  pdf(file.path(out_dir, paste0(label, "_network.pdf")), width = 11, height = 8)
  # Use circle layout — weight-free, always valid for signed correlation networks
  p <- ggraph::ggraph(graph, layout = "circle") +
    ggraph::geom_edge_link(aes(alpha = abs(weight), color = weight > 0), show.legend = FALSE) +
    ggraph::geom_node_point(aes(size = mean_abundance, color = phylum)) +
    ggraph::geom_node_text(aes(label = ifelse(degree(graph) >= quantile(degree(graph), 0.9, na.rm = TRUE), name, "")), repel = TRUE, size = 2.8) +
    theme_void() +
    labs(title = paste("Co-occurrence network:", label))
  print(p)
  dev.off()
}

run_netcomi_compare <- function(mat, meta, group_col, label, out_dir) {
  if (!nzchar(group_col) || !group_col %in% names(meta)) return(invisible(NULL))
  lvls <- levels(as.factor(meta[[group_col]]))
  if (length(lvls) < 2) return(invisible(NULL))
  keep <- meta[[group_col]] %in% lvls[1:2]
  meta2 <- meta[keep, , drop = FALSE]
  mat2 <- mat[, rownames(meta2), drop = FALSE]
  if (ncol(mat2) < 6) return(invisible(NULL))
  idx1 <- rownames(meta2)[meta2[[group_col]] == lvls[1]]
  idx2 <- rownames(meta2)[meta2[[group_col]] == lvls[2]]
  net_obj <- NetCoMi::netConstruct(
    data = list(t(mat2[, idx1, drop = FALSE]), t(mat2[, idx2, drop = FALSE])),
    measure = "sparcc",
    normMethod = "clr",
    zeroMethod = "pseudo",
    sparsMethod = "threshold",
    thresh = 0.3,
    verbose = 0
  )
  cmp <- NetCoMi::netCompare(net_obj, verbose = 0)
  capture.output(cmp, file = file.path(out_dir, paste0(label, "_group_compare.txt")))
}

meta <- read_metadata(metadata_csv)
datasets <- list(
  bacteria = tryCatch(read_abundance_table(bact_table), error = function(e) NULL),
  virus = tryCatch(read_abundance_table(vir_table), error = function(e) NULL),
  fungi = tryCatch(read_fungi_profiles(fungi_dir), error = function(e) NULL)
)

network_jobs <- list(
  bac = function() datasets$bacteria,
  vir = function() datasets$virus,
  fun = function() datasets$fungi,
  cross_bac_vir = function() {
    common <- intersect(colnames(datasets$bacteria), colnames(datasets$virus))
    if (length(common) < 5) stop("Insufficient shared samples for bacteria-virus network")
    rbind(paste0("BAC|", rownames(datasets$bacteria)) %>% stats::setNames(NULL), paste0("VIR|", rownames(datasets$virus)) %>% stats::setNames(NULL))
  },
  cross_bac_fun = function() {
    common <- intersect(colnames(datasets$bacteria), colnames(datasets$fungi))
    if (length(common) < 5) stop("Insufficient shared samples for bacteria-fungi network")
    rbind(paste0("BAC|", rownames(datasets$bacteria)) %>% stats::setNames(NULL), paste0("FUN|", rownames(datasets$fungi)) %>% stats::setNames(NULL))
  }
)

targets <- if (net_type == "all") c("bac", "vir", "fun", "cross_bac_vir", "cross_bac_fun") else net_type

for (target in targets) {
  run_step(paste0("network_", target), {
    if (target == "bac") {
      mat <- datasets$bacteria
      label <- "bacteria"
    } else if (target == "vir") {
      mat <- datasets$virus
      label <- "virus"
    } else if (target == "fun") {
      mat <- datasets$fungi
      label <- "fungi"
    } else if (target == "cross_bac_vir") {
      common <- intersect(colnames(datasets$bacteria), colnames(datasets$virus))
      mat <- rbind(
        stats::setNames(as.data.frame(datasets$bacteria[, common, drop = FALSE]), common) %>% as.matrix() %>% `rownames<-`(paste0("BAC|", rownames(datasets$bacteria))),
        stats::setNames(as.data.frame(datasets$virus[, common, drop = FALSE]), common) %>% as.matrix() %>% `rownames<-`(paste0("VIR|", rownames(datasets$virus)))
      )
      label <- "cross_bac_vir"
    } else if (target == "cross_bac_fun") {
      common <- intersect(colnames(datasets$bacteria), colnames(datasets$fungi))
      mat <- rbind(
        stats::setNames(as.data.frame(datasets$bacteria[, common, drop = FALSE]), common) %>% as.matrix() %>% `rownames<-`(paste0("BAC|", rownames(datasets$bacteria))),
        stats::setNames(as.data.frame(datasets$fungi[, common, drop = FALSE]), common) %>% as.matrix() %>% `rownames<-`(paste0("FUN|", rownames(datasets$fungi)))
      )
      label <- "cross_bac_fun"
    } else {
      stop("Unsupported network type: ", target)
    }

    if (is.null(mat)) stop("Input unavailable for target: ", target)
    common_meta <- intersect(colnames(mat), rownames(meta))
    if (length(common_meta) < 5) stop("Need at least five metadata-matched samples")
    mat <- mat[, common_meta, drop = FALSE]
    meta_sub <- meta[common_meta, , drop = FALSE]
    net <- infer_network(mat, label, repo, threads)
    save_network_outputs(net, label, result_dir)
    run_step(paste0("netcomi_", label), {
      run_netcomi_compare(mat, meta_sub, group_col, label, result_dir)
    })
    summary_rows[[length(summary_rows) + 1]] <- tibble(
      network = label,
      inference = net$method,
      nodes = igraph::gorder(net$graph),
      edges = igraph::gsize(net$graph),
      hub_taxa = paste(net$hubs, collapse = ";"),
      modularity = net$modularity,
      edge_density = net$edge_density
    )
  })
}

summary_df <- bind_rows(summary_rows)
status_df <- bind_rows(status_log)
if (nrow(summary_df) == 0) stop("No network results generated")

readr::write_tsv(summary_df, file.path(result_dir, "network_summary.tsv"))
readr::write_tsv(status_df, file.path(result_dir, "network_status.tsv"))
writeLines(
  c(
    "Co-occurrence network summary",
    capture.output(print(summary_df)),
    "",
    "Status log",
    capture.output(print(status_df))
  ),
  file.path(result_dir, "network_summary.txt")
)
RSCRIPT

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 93_stat_cooccurrence.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Co-occurrence analysis completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
