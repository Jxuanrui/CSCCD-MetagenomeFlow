#!/usr/bin/env bash
# ==============================================================================
# Script: 93_stat_cooccurrence.sh
# Purpose: Co-occurrence network analysis for intra- and cross-domain matrices
# Usage:   bash 93_stat_cooccurrence.sh -w WORKDIR -r REPO -t THREADS -m METADATA_CSV
#                                      [-g GROUP_COL] [-n NET_TYPE] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

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

GROUP_COL=""
NET_TYPE="all"

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:THREADS m:METADATA_CSV g:GROUP_COL n:NET_TYPE"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO THREADS METADATA_CSV

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

mgx_begin

BACT_TABLE="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_TABLE="${WORKDIR}/result/virus/votu/votu_table.tsv"
FUNGI_DIR="${WORKDIR}/result/fungi/metaphlan4"
# PHF (Yan2024 Cell187 method) is the preferred fungi abundance source.
# Falls back to metaphlan4 per-sample profiles when PHF table is absent.
FUNGI_PHF_TABLE="${WORKDIR}/result/integration/fungi/funomic_species_count.tsv"
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

export WORKDIR REPO THREADS METADATA_CSV GROUP_COL NET_TYPE BACT_TABLE VIR_TABLE FUNGI_DIR FUNGI_PHF_TABLE RESULT_DIR

R_LIBS_USER="" mgx_conda r_stat Rscript - <<'RSCRIPT'
options(stringsAsFactors = FALSE)
options(warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

required_pkgs <- c("SpiecEasi", "NetCoMi", "MetaNet", "igraph", "ggplot2", "phyloseq", "tidyverse", "svglite", "ragg")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Missing R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(SpiecEasi)
  library(NetCoMi)
  library(MetaNet)
  library(igraph)
  library(ggplot2)
  library(phyloseq)
  library(tidyverse)
})

grDevices::pdf(file = NULL)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

# Shared publication theme/export helpers (scripts/R/pub_theme.R); this
# heredoc R session has no --file= arg, so locate it via REPO from the wrapper.
pub_theme_path <- file.path(Sys.getenv("REPO"), "scripts", "R", "pub_theme.R")
if (!file.exists(pub_theme_path)) stop("pub_theme.R not found: ", pub_theme_path)
source(pub_theme_path)

theme_pub_void <- function(base_size = 7, base_family = "Arial") {
  ggplot2::theme_void(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = base_size),
      legend.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(size = base_size + 2, face = "bold", hjust = 0.5),
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA)
    )
}

metadata_csv <- Sys.getenv("METADATA_CSV")
group_col <- Sys.getenv("GROUP_COL")
net_type <- Sys.getenv("NET_TYPE")
bact_table <- Sys.getenv("BACT_TABLE")
vir_table <- Sys.getenv("VIR_TABLE")
fungi_dir <- Sys.getenv("FUNGI_DIR")
fungi_phf_table <- Sys.getenv("FUNGI_PHF_TABLE")
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

tax_ranks <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")

parse_lineage_tax <- function(features, default_kingdom = NA_character_) {
  pfx <- c(
    Kingdom = "k__", Phylum = "p__", Class = "c__", Order = "o__",
    Family = "f__", Genus = "g__", Species = "s__"
  )
  rows <- lapply(features, function(feature) {
    parts <- strsplit(feature, "\\|")[[1]]
    vals <- vapply(pfx, function(px) {
      hit <- parts[startsWith(parts, px)]
      if (length(hit)) sub(paste0("^", px), "", hit[1]) else NA_character_
    }, character(1))
    if (is.na(vals[["Kingdom"]]) && !is.na(default_kingdom)) vals[["Kingdom"]] <- default_kingdom
    vals
  })
  tax <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  tax <- cbind(name = features, tax[, tax_ranks, drop = FALSE])
  rownames(tax) <- NULL
  tax
}

make_domain_tax <- function(features, kingdom) {
  tax <- data.frame(name = features, stringsAsFactors = FALSE)
  for (rank in tax_ranks) tax[[rank]] <- NA_character_
  tax$Kingdom <- kingdom
  tax
}

# Simplify node names for better visualization
# Extract Genus_species or shortest meaningful name
simplify_node_names <- function(features) {
  vapply(features, function(feature) {
    # For virus vOTUs, keep as-is (already short)
    if (startsWith(feature, "vOTU_")) return(feature)

    # Parse hierarchical taxonomy
    parts <- strsplit(feature, "\\|")[[1]]

    # Extract genus and species
    genus <- parts[grepl("^g__", parts)]
    species <- parts[grepl("^s__", parts)]

    if (length(genus) > 0 && length(species) > 0) {
      g <- sub("^g__", "", genus[1])
      s <- sub("^s__", "", species[1])
      # Remove genus prefix from species if present
      s <- sub(paste0("^", g, "_"), "", s)
      return(paste0(g, "_", s))
    } else if (length(genus) > 0) {
      return(sub("^g__", "", genus[1]))
    } else if (length(species) > 0) {
      return(sub("^s__", "", species[1]))
    } else {
      # Fallback: use last non-empty part
      non_empty <- parts[nzchar(parts)]
      if (length(non_empty) > 0) {
        last_part <- non_empty[length(non_empty)]
        return(sub("^[a-z]__", "", last_part))
      }
      return(feature)
    }
  }, character(1), USE.NAMES = FALSE)
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
  colnames(mat) <- sub("_tpm$", "", colnames(mat))
  mat <- mat[rowSums(mat) > 0, , drop = FALSE]
  list(mat = mat, tax = parse_lineage_tax(rownames(mat)))
}

read_virus_table <- function(votu_path) {
  # Read simple vOTU table: vOTU_ID (rows) x Samples (columns)
  raw <- readr::read_tsv(votu_path, show_col_types = FALSE)

  # First column is vOTU ID, rest are samples
  votu_col <- names(raw)[1]
  sample_cols <- setdiff(names(raw), votu_col)

  # Convert to matrix
  mat <- as.matrix(raw[, sample_cols, drop = FALSE])
  rownames(mat) <- raw[[votu_col]]

  # Coerce to numeric and handle NAs
  mat <- apply(mat, 2, as.numeric)
  rownames(mat) <- raw[[votu_col]]
  mat[is.na(mat)] <- 0

  # Filter out zero-sum rows
  mat <- mat[rowSums(mat) > 0, , drop = FALSE]

  if (nrow(mat) == 0) stop("No non-zero vOTUs found in virus table")

  # Simple taxonomy placeholder for viruses
  list(mat = mat, tax = make_domain_tax(rownames(mat), "Virus"))
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
  sp_idx <- grepl("(^|\\|)s__", rownames(merged)) & !grepl("(^|\\|)t__", rownames(merged))
  if (sum(sp_idx) >= 2) merged <- merged[sp_idx, , drop = FALSE]
  merged <- merged[rowSums(merged) > 0, , drop = FALSE]
  list(mat = merged, tax = parse_lineage_tax(rownames(merged), default_kingdom = "Fungi"))
}

# PHF (Yan2024 Cell187) abundance table: rows=taxa, cols=samples, tab-separated.
# First column is "cluster_id" or a taxonomy label column — detect automatically.
read_phf_table <- function(path) {
  raw <- readr::read_tsv(path, show_col_types = FALSE)
  # Drop non-numeric columns that are clearly taxonomy/annotation
  numeric_cols <- names(raw)[vapply(raw, is.numeric, logical(1))]
  label_col <- names(raw)[1]
  if (length(numeric_cols) == 0) stop("PHF table has no numeric columns: ", path)
  mat <- as.matrix(raw[, numeric_cols, drop = FALSE])
  rownames(mat) <- as.character(raw[[label_col]])
  mat <- mat[rowSums(mat, na.rm = TRUE) > 0, , drop = FALSE]
  features <- rownames(mat)
  genus <- ifelse(grepl("g__", features), sub(".*g__([^\\.\\|]+).*", "\\1", features), NA_character_)
  species <- ifelse(grepl("s__", features), sub(".*s__([^\\|]+).*", "\\1", features), features)
  tax <- make_domain_tax(features, "Fungi")
  tax$Genus <- genus
  tax$Species <- species
  list(mat = mat, tax = tax)
}

load_fungi_data <- function(phf_table_path, metaphlan4_dir) {
  # Priority 1: PHF abundance table (Yan2024 Cell187 method, gut-optimised)
  if (nzchar(phf_table_path) && file.exists(phf_table_path)) {
    ds <- tryCatch(read_phf_table(phf_table_path), error = function(e) NULL)
    if (!is.null(ds) && nrow(ds$mat) > 0) {
      message("[fungi] Using PHF abundance table: ", phf_table_path,
              " (", nrow(ds$mat), " taxa)")
      return(ds)
    }
  }
  # Priority 2: MetaPhlAn4 per-sample profiles (fallback)
  ds <- tryCatch(read_fungi_profiles(metaphlan4_dir), error = function(e) NULL)
  if (!is.null(ds) && nrow(ds$mat) > 0) {
    message("[fungi] Using MetaPhlAn4-euk profiles: ", metaphlan4_dir,
            " (", nrow(ds$mat), " taxa)")
    return(ds)
  }
  stop("No usable fungi abundance data found. Checked: '", phf_table_path,
       "' and '", metaphlan4_dir, "'")
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

fastspar_cor <- function(mat, label, fastspar_bin, threads) {
  tmp_dir <- file.path(tempdir(), paste0("netcomi_fastspar_", label, "_", Sys.getpid()))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  in_file <- file.path(tmp_dir, "otu.tsv")
  cor_file <- file.path(tmp_dir, "cor.tsv")
  cov_file <- file.path(tmp_dir, "cov.tsv")

  readr::write_tsv(tibble::rownames_to_column(as.data.frame(round(mat)), "#OTU ID"), in_file)
  status <- system2(
    fastspar_bin,
    c("--otu_table", in_file, "--correlation", cor_file, "--covariance", cov_file, "--threads", as.character(threads))
  )
  if (!identical(as.integer(status), 0L)) stop("FastSpar failed for NetCoMi comparison: ", label)

  cor_df <- readr::read_tsv(cor_file, show_col_types = FALSE)
  cor_mat <- as.matrix(cor_df[, -1, drop = FALSE])
  rownames(cor_mat) <- cor_df[[1]]
  colnames(cor_mat) <- colnames(cor_mat) %||% rownames(cor_mat)
  missing_taxa <- setdiff(rownames(mat), intersect(rownames(cor_mat), colnames(cor_mat)))
  if (length(missing_taxa) > 0) {
    stop("FastSpar correlation matrix missing taxa: ", paste(head(missing_taxa, 5), collapse = ", "))
  }
  cor_mat <- cor_mat[rownames(mat), rownames(mat), drop = FALSE]
  diag(cor_mat) <- 1
  cor_mat
}

is_domain_dataset <- function(x) {
  is.list(x) && all(c("mat", "tax") %in% names(x))
}

complete_tax_table <- function(features, tax) {
  tax <- as.data.frame(tax, stringsAsFactors = FALSE)
  if (!"name" %in% names(tax)) tax$name <- rownames(tax)
  for (rank in tax_ranks) {
    if (!rank %in% names(tax)) tax[[rank]] <- NA_character_
  }
  tax <- tax[!duplicated(tax$name), c("name", tax_ranks), drop = FALSE]
  missing <- setdiff(features, tax$name)
  if (length(missing)) {
    tax <- dplyr::bind_rows(tax, make_domain_tax(missing, "Unclassified"))
  }
  tax[match(features, tax$name), c("name", tax_ranks), drop = FALSE]
}

subset_dataset_samples <- function(ds, samples) {
  list(mat = ds$mat[, samples, drop = FALSE], tax = ds$tax)
}

preprocess_dataset <- function(ds) {
  mat <- preprocess_mat(ds$mat)
  list(mat = mat, tax = complete_tax_table(rownames(mat), ds$tax))
}

resolve_v_class <- function(tax_df) {
  phylum <- if ("Phylum" %in% names(tax_df)) as.character(tax_df$Phylum) else rep(NA_character_, nrow(tax_df))
  kingdom <- if ("Kingdom" %in% names(tax_df)) as.character(tax_df$Kingdom) else rep(NA_character_, nrow(tax_df))
  cls <- ifelse(!is.na(phylum) & nzchar(phylum), phylum,
                ifelse(!is.na(kingdom) & nzchar(kingdom), kingdom, "Unclassified"))
  names(cls) <- tax_df$name
  cls
}

# Node color legend title per v_group: most domains have real Phylum-level
# taxonomy, but virus/fungi domain sentinels only carry a Kingdom-level label.
# Without this, MetaNet's default legend title is the internal "v_group1"
# placeholder, which does not tell a reader what the node colors mean.
legend_titles_from_graph <- function(go) {
  v_group <- igraph::V(go)$v_group
  phylum <- igraph::V(go)$Phylum
  groups <- unique(v_group)
  titles <- vapply(groups, function(g) {
    has_phylum <- any(!is.na(phylum[v_group == g]) & nzchar(phylum[v_group == g]))
    if (has_phylum) "Phylum" else "Kingdom"
  }, character(1))
  stats::setNames(titles, groups)
}

apply_metanet_style <- function(go, tax_df) {
  tax_df <- complete_tax_table(igraph::V(go)$name, tax_df)
  go <- MetaNet::c_net_annotate(go, tax_df, mode = "v", verbose = FALSE)

  # Simplify node names for better visualization
  simple_names <- simplify_node_names(igraph::V(go)$name)
  igraph::V(go)$label <- simple_names

  class_map <- resolve_v_class(tax_df)
  v_class <- class_map[igraph::V(go)$name]
  v_class[is.na(v_class) | !nzchar(v_class)] <- "Unclassified"
  igraph::V(go)$v_class <- v_class
  class_levels <- sort(unique(v_class))
  pal <- stats::setNames(npg_pal(length(class_levels)), class_levels)
  igraph::V(go)$color <- pal[v_class]
  if (igraph::ecount(go) > 0) {
    igraph::E(go)$color <- ifelse(igraph::E(go)$e_type == "positive", "#4DBBD5", "#F39B7F")
  }
  igraph::graph_attr(go, "legend_title") <- legend_titles_from_graph(go)
  MetaNet::c_net_update(go, initialize = TRUE, verbose = FALSE)
}

build_metanet_graph <- function(mat_list, label, r_threshold = 0.3, p_threshold = 0.05, method = "spearman") {
  if (is_domain_dataset(mat_list)) {
    ds <- preprocess_dataset(mat_list)
    if (ncol(ds$mat) < 5 || nrow(ds$mat) < 10) stop("Insufficient matrix size for network inference")
    corr <- MetaNet::c_net_cal(t(ds$mat), method = method, threads = threads, verbose = FALSE)
    go <- MetaNet::c_net_build(
      corr, r_threshold = r_threshold, p_threshold = p_threshold,
      use_p_adj = FALSE, delete_single = TRUE
    )
    go <- apply_metanet_style(go, ds$tax)
    method_name <- paste0("MetaNet_", method)
  } else {
    ds_list <- lapply(mat_list, preprocess_dataset)
    if (length(ds_list) != 2 || any(!nzchar(names(ds_list)))) {
      stop("Cross-domain MetaNet input must be a named list of two domain datasets")
    }
    for (nm in names(ds_list)) {
      if (ncol(ds_list[[nm]]$mat) < 5 || nrow(ds_list[[nm]]$mat) < 2) {
        stop("Insufficient matrix size for cross-domain network inference: ", nm)
      }
    }
    totu_list <- lapply(ds_list, function(ds) t(ds$mat))
    go <- do.call(
      MetaNet::multi_net_build,
      c(totu_list, list(
        mode = "full", method = method, r_threshold = r_threshold,
        p_threshold = p_threshold, use_p_adj = FALSE, delete_single = TRUE
      ))
    )
    tax_df <- dplyr::bind_rows(lapply(ds_list, `[[`, "tax"))
    go <- apply_metanet_style(go, tax_df)
    method_name <- paste0("MetaNet_multi_", method)
  }

  if (igraph::gorder(go) == 0) stop("MetaNet produced an empty network after thresholding")
  go <- MetaNet::module_detect(go, method = "cluster_fast_greedy", n_node_in_module = 0, delete = FALSE)
  coors <- MetaNet::c_net_layout(go, method = igraph::nicely(), seed = 1234)
  deg <- igraph::degree(go)
  hub_cut <- if (length(deg) > 0) stats::quantile(deg, probs = 0.9, na.rm = TRUE) else 0
  hubs <- names(deg)[deg >= hub_cut]
  list(
    graph = go,
    coors = coors,
    method = method_name,
    hubs = hubs,
    modularity = igraph::graph_attr(go, "modularity") %||% 0,
    edge_density = igraph::edge_density(go),
    legend_title = igraph::graph_attr(go, "legend_title")
  )
}

combine_netcomi_mat <- function(ds_list) {
  prefixes <- c(bacteria = "BAC", virus = "VIR", fungi = "FUN")
  mats <- lapply(names(ds_list), function(nm) {
    mat <- ds_list[[nm]]$mat
    prefix <- prefixes[[nm]] %||% toupper(nm)
    rownames(mat) <- paste0(prefix, "|", rownames(mat))
    mat
  })
  do.call(rbind, mats)
}

save_network_outputs <- function(net, label, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  nodes <- MetaNet::get_v(net$graph)
  edges <- MetaNet::get_e(net$graph)
  readr::write_tsv(nodes, file.path(out_dir, "nodes.tsv"))
  readr::write_tsv(edges, file.path(out_dir, "edges.tsv"))
  export_pub_figure_base(
    function() {
      MetaNet::c_net_plot(
        net$graph, coors = net$coors,
        legend = TRUE, color_legend = TRUE, edge_legend = TRUE,
        mark_module = TRUE, module_legend = TRUE,
        group_legend_title = net$legend_title,
        legend_cex = 0.8,
        # c_net_plot()'s legend_position defaults assume the plot window is
        # rescaled to [-1, 1] (its own default legend_position uses
        # left_leg_x = -2 / right_leg_x = 1.2). With rescale = FALSE (the
        # c_net_plot default), igraph sizes the plot window to the raw
        # layout coordinate range instead, so the legend ends up positioned
        # far outside the actual plot/viewBox and is invisible in the
        # rendered SVG/PDF/TIFF.
        rescale = TRUE
      )
    },
    file.path(out_dir, "network"),
    width_mm = 183,
    height_mm = 120
  )
}

run_netcomi_compare <- function(mat, meta, group_col, label, out_dir) {
  if (!nzchar(group_col) || !group_col %in% names(meta)) return(invisible(NULL))
  lvls <- levels(as.factor(meta[[group_col]]))
  if (length(lvls) < 2) return(invisible(NULL))
  keep <- meta[[group_col]] %in% lvls[1:2]
  meta2 <- meta[keep, , drop = FALSE]
  sample_ids <- if ("sample_id" %in% names(meta2)) as.character(meta2$sample_id) else rownames(meta2)
  sample_ids <- sample_ids[sample_ids %in% colnames(mat)]
  if (length(sample_ids) < 6) return(invisible(NULL))
  if ("sample_id" %in% names(meta2)) {
    meta2 <- meta2[match(sample_ids, as.character(meta2$sample_id)), , drop = FALSE]
  } else {
    meta2 <- meta2[match(sample_ids, rownames(meta2)), , drop = FALSE]
  }
  mat2 <- mat[, sample_ids, drop = FALSE]
  if (ncol(mat2) < 6) return(invisible(NULL))
  idx1 <- sample_ids[meta2[[group_col]] == lvls[1]]
  idx2 <- sample_ids[meta2[[group_col]] == lvls[2]]
  compare_path <- file.path(out_dir, "group_compare.txt")
  cmp <- tryCatch(
    {
      fastspar_bin <- find_fastspar(repo)
      if (nzchar(fastspar_bin)) {
        asso1 <- fastspar_cor(mat2[, idx1, drop = FALSE], paste0(label, "_", lvls[1]), fastspar_bin, threads)
        asso2 <- fastspar_cor(mat2[, idx2, drop = FALSE], paste0(label, "_", lvls[2]), fastspar_bin, threads)
        net_obj <- NetCoMi::netConstruct(
          data = asso1,
          data2 = asso2,
          dataType = "correlation",
          sparsMethod = "threshold",
          thresh = 0.3,
          verbose = 0
        )
      } else {
        net_obj <- NetCoMi::netConstruct(
          data = t(mat2[, idx1, drop = FALSE]),
          data2 = t(mat2[, idx2, drop = FALSE]),
          measure = "sparcc",
          normMethod = "clr",
          zeroMethod = "pseudo",
          sparsMethod = "threshold",
          thresh = 0.3,
          verbose = 0
        )
      }
      net_props <- NetCoMi::netAnalyze(net_obj, graphlet = FALSE, verbose = 0)
      NetCoMi::netCompare(
        net_props,
        testRand = FALSE,
        gcd = FALSE,
        cores = as.integer(Sys.getenv("THREADS", "1")),
        verbose = FALSE
      )
    },
    error = function(e) {
      writeLines(
        c(
          paste("NetCoMi group comparison:", label),
          "Status: unavailable",
          paste("Reason:", conditionMessage(e)),
          "This can occur when thresholded SparCC group networks are edgeless or otherwise degenerate.",
          paste("Features:", nrow(mat2)),
          paste("Samples group 1:", length(idx1)),
          paste("Samples group 2:", length(idx2)),
          "Measure: sparcc; normMethod: clr; zeroMethod: pseudo; sparsMethod: threshold; thresh: 0.3"
        ),
        compare_path
      )
      NULL
    }
  )
  if (!is.null(cmp)) capture.output(cmp, file = compare_path)
}

meta <- read_metadata(metadata_csv)
datasets <- list(
  bacteria = tryCatch(read_abundance_table(bact_table), error = function(e) NULL),
  virus = tryCatch(read_virus_table(vir_table), error = function(e) NULL),
  fungi = tryCatch(load_fungi_data(fungi_phf_table, fungi_dir), error = function(e) NULL)
)

network_jobs <- list(
  bac = function() {
    list(label = "bacteria", mat_list = datasets$bacteria, netcomi_mat = datasets$bacteria$mat)
  },
  vir = function() {
    list(label = "virus", mat_list = datasets$virus, netcomi_mat = datasets$virus$mat)
  },
  fun = function() {
    list(label = "fungi", mat_list = datasets$fungi, netcomi_mat = datasets$fungi$mat)
  },
  cross_bac_vir = function() {
    common <- intersect(colnames(datasets$bacteria$mat), colnames(datasets$virus$mat))
    if (length(common) < 5) stop("Insufficient shared samples for bacteria-virus network")
    ds_list <- list(
      bacteria = subset_dataset_samples(datasets$bacteria, common),
      virus = subset_dataset_samples(datasets$virus, common)
    )
    list(label = "cross_bac_vir", mat_list = ds_list, netcomi_mat = combine_netcomi_mat(ds_list))
  },
  cross_bac_fun = function() {
    common <- intersect(colnames(datasets$bacteria$mat), colnames(datasets$fungi$mat))
    if (length(common) < 5) stop("Insufficient shared samples for bacteria-fungi network")
    ds_list <- list(
      bacteria = subset_dataset_samples(datasets$bacteria, common),
      fungi = subset_dataset_samples(datasets$fungi, common)
    )
    list(label = "cross_bac_fun", mat_list = ds_list, netcomi_mat = combine_netcomi_mat(ds_list))
  }
)

targets <- if (net_type == "all") c("bac", "vir", "fun", "cross_bac_vir", "cross_bac_fun") else net_type

for (target in targets) {
  run_step(paste0("network_", target), {
    if (!target %in% names(network_jobs)) stop("Unsupported network type: ", target)
    job <- network_jobs[[target]]()
    label <- job$label
    mat_list <- job$mat_list
    netcomi_mat <- job$netcomi_mat

    folder_name <- switch(
      target,
      bac = "bacteria",
      vir = "virus",
      fun = "fungi",
      cross_bac_vir = "cross_bac_vir",
      cross_bac_fun = "cross_bac_fun",
      target
    )
    out_dir <- file.path(result_dir, folder_name)

    if (is.null(mat_list) || is.null(netcomi_mat)) stop("Input unavailable for target: ", target)
    common_meta <- intersect(colnames(netcomi_mat), rownames(meta))
    if (length(common_meta) < 5) stop("Need at least five metadata-matched samples")
    netcomi_mat <- netcomi_mat[, common_meta, drop = FALSE]
    if (is_domain_dataset(mat_list)) {
      mat_list <- subset_dataset_samples(mat_list, common_meta)
    } else {
      mat_list <- lapply(mat_list, subset_dataset_samples, samples = common_meta)
    }
    meta_sub <- meta[common_meta, , drop = FALSE]
    net <- build_metanet_graph(mat_list, label)
    save_network_outputs(net, label, out_dir)
    run_step(paste0("netcomi_", label), {
      run_netcomi_compare(netcomi_mat, meta_sub, group_col, label, out_dir)
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

mgx_end "cooccurrence"
echo "[INFO] Sentinel: ${SENTINEL}"
