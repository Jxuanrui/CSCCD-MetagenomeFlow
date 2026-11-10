#!/usr/bin/env Rscript
# 96_functional_network.R - Functional-functional co-occurrence network (SpiecEasi)
# Outputs: result/stat/{dimension}/functional/network/
#   - results/network_edges.tsv
#   - results/network_summary.tsv
#   - figures/network_{dimension}.{pdf,svg,tiff}
#   - {dimension}_functional_network_done.txt

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    return(y)
  }
  if (length(x) == 1 && is.character(x) && !nzchar(x)) {
    return(y)
  }
  x
}

show_help <- function() {
  cat(
    "Usage: Rscript 96_functional_network.R [-w WORKDIR] [-r REPO] [-d DIMENSION]\n",
    "\n",
    "Optional:\n",
    "  -w, --workdir      Project work directory (default: WORKDIR env or current directory)\n",
    "  -r, --repo         Repository root (default: REPO env)\n",
    "  -d, --dimension    bacteria|fungi|virus (default: DIMENSION env or bacteria)\n",
    "  -h, --help         Show this help message\n",
    sep = ""
  )
}

parse_cli_args <- function(args) {
  opts <- list()
  i <- 1
  next_value <- function(flag) {
    if (i >= length(args)) {
      stop("Missing value for argument: ", flag)
    }
    args[[i + 1]]
  }

  while (i <= length(args)) {
    flag <- args[[i]]
    if (flag %in% c("-h", "--help")) {
      show_help()
      quit(status = 0)
    } else if (flag %in% c("-w", "--workdir")) {
      opts$workdir <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-r", "--repo")) {
      opts$repo <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-d", "--dimension")) {
      opts$dimension <- next_value(flag); i <- i + 2
    } else if (flag == "--force") {
      i <- i + 1
    } else {
      stop("Unknown argument: ", flag)
    }
  }
  opts
}

cli_opts <- parse_cli_args(commandArgs(trailingOnly = TRUE))

workdir     <- cli_opts$workdir %||% Sys.getenv("WORKDIR") %||% getwd()
repo        <- cli_opts$repo %||% Sys.getenv("REPO") %||% getwd()
stat_root   <- Sys.getenv("STAT_ROOT") %||% file.path(workdir, "result", "stat")
dimension   <- tolower(cli_opts$dimension %||% Sys.getenv("DIMENSION") %||% "bacteria")
out_dir     <- Sys.getenv("OUT_DIR") %||% file.path(stat_root, dimension, "functional", "network")
results_dir <- file.path(out_dir, "results")
figures_dir <- file.path(out_dir, "figures")
sentinel    <- Sys.getenv("SENTINEL") %||%
  file.path(out_dir, sprintf("%s_functional_network_done.txt", dimension))

dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

skip_with_reason <- function(reason) {
  writeLines(paste0("SKIPPED: ", reason), sentinel)
  cat("[INFO] SKIPPED:", reason, "\n")
  quit(status = 0)
}

## Same ABI-mismatch pitfall as 96_stat_functional.R / 96_functional_permanova.R:
## a stale user-level Rlib/Matrix.so (compiled against a different R ABI) can
## shadow the conda-env Matrix build and make library(SpiecEasi) fail/hang
## with "undefined symbol: ANY_ATTRIB". Force the conda lib path first.
conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("SpiecEasi", "igraph", "ggsci", "svglite", "ragg")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {
  skip_with_reason(paste0("Missing packages: ", paste(missing_pkgs, collapse = ", ")))
}

suppressPackageStartupMessages({
  library(SpiecEasi)
  library(igraph)
  library(ggsci)
})

grDevices::pdf(file = NULL)

# Optional PNG companion figures, only when MGX_FIGURE_FORMATS requests "png"
mgx_want_png <- function() {
  fmts <- tolower(trimws(strsplit(Sys.getenv("MGX_FIGURE_FORMATS", ""), ",")[[1]]))
  "png" %in% fmts
}

## Reuse the exact source-table map + loader from 96_stat_functional.R instead
## of duplicating it, following the pattern established in
## 96_functional_permanova.R's load_functional_api().
assignment_name <- function(expr) {
  if (!is.call(expr) || !is.symbol(expr[[1]])) {
    return(NULL)
  }
  op <- as.character(expr[[1]])
  if (!op %in% c("<-", "=") || length(expr) < 3 || !is.symbol(expr[[2]])) {
    return(NULL)
  }
  as.character(expr[[2]])
}

load_functional_api <- function(repo) {
  source_file <- file.path(repo, "scripts", "96_stat_functional.R")
  if (!file.exists(source_file)) {
    stop("Functional analysis source script not found: ", source_file)
  }

  helper_env <- new.env(parent = baseenv())
  wanted <- c("functional_source_map", "load_functional_matrix")
  exprs <- parse(file = source_file, keep.source = FALSE)
  for (expr in exprs) {
    target <- assignment_name(expr)
    if (!is.null(target) && target %in% wanted) {
      eval(expr, envir = helper_env)
    }
  }

  missing_helpers <- wanted[!vapply(wanted, exists, logical(1), envir = helper_env, inherits = FALSE)]
  if (length(missing_helpers)) {
    stop("Could not extract helpers from 96_stat_functional.R: ", paste(missing_helpers, collapse = ", "))
  }

  list(
    functional_source_map = get("functional_source_map", envir = helper_env),
    load_functional_matrix = get("load_functional_matrix", envir = helper_env)
  )
}

extract_sample_feature_matrix <- function(functional_matrix) {
  if (!is.list(functional_matrix) || !"data" %in% names(functional_matrix)) {
    stop("load_functional_matrix() returned an unexpected object")
  }
  functional_df <- functional_matrix$data
  if (!"sample_id" %in% colnames(functional_df)) {
    stop("Functional matrix does not contain sample_id")
  }

  feature_cols <- setdiff(colnames(functional_df), "sample_id")
  if (!length(feature_cols)) {
    return(NULL)
  }

  abundance <- as.matrix(functional_df[, feature_cols, drop = FALSE])
  storage.mode(abundance) <- "numeric"
  rownames(abundance) <- as.character(functional_df$sample_id)
  abundance[!is.finite(abundance)] <- 0
  abundance[abundance < 0] <- 0
  abundance
}

cat("[INFO] Starting functional co-occurrence network analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Repo:", repo, "\n")
cat("  Dimension:", dimension, "\n")
cat("  Output directory:", out_dir, "\n")

api <- load_functional_api(repo)
functional_source_map <- api$functional_source_map
load_functional_matrix <- api$load_functional_matrix

if (!dimension %in% names(functional_source_map)) {
  skip_with_reason(paste0("Invalid dimension for network analysis: ", dimension))
}
func_types <- names(functional_source_map[[dimension]])

## ---- Step 1: load every func_type table for this dimension, prefix feature
## ids with "func_type::" to avoid id collisions, merge on common samples ---
loaded <- list()
for (func_type in func_types) {
  cat("  Loading func_type:", func_type, "\n")
  mat <- tryCatch({
    functional_matrix <- load_functional_matrix(workdir, dimension, func_type)
    extract_sample_feature_matrix(functional_matrix)
  }, error = function(e) {
    cat("    Skipped (load error):", conditionMessage(e), "\n")
    NULL
  })
  if (is.null(mat) || !ncol(mat) || !nrow(mat)) {
    cat("    Skipped (empty table)\n")
    next
  }
  colnames(mat) <- paste0(func_type, "::", colnames(mat))
  loaded[[func_type]] <- mat
}

if (length(loaded) < 2) {
  skip_with_reason(sprintf(
    "Fewer than 2 usable func_type tables loaded for dimension '%s' (got %d)",
    dimension, length(loaded)
  ))
}

common_samples <- Reduce(intersect, lapply(loaded, rownames))
if (length(common_samples) < 15) {
  skip_with_reason(sprintf(
    "Fewer than 15 samples common across all loaded func_type tables (got %d)",
    length(common_samples)
  ))
}

combined_mat <- do.call(cbind, lapply(loaded, function(mat) mat[common_samples, , drop = FALSE]))

## ---- Step 2: prevalence filter (>= 20% of samples) + drop zero-variance --
prevalence <- colSums(combined_mat > 0) / nrow(combined_mat)
combined_mat <- combined_mat[, prevalence >= 0.20, drop = FALSE]
keep_var <- apply(combined_mat, 2, function(x) stats::var(x) > 0)
combined_mat <- combined_mat[, keep_var, drop = FALSE]

if (ncol(combined_mat) < 10) {
  skip_with_reason(sprintf(
    "Fewer than 10 features remain after prevalence >= 20%% filtering (got %d)",
    ncol(combined_mat)
  ))
}

cat(sprintf(
  "  Combined matrix: %d samples x %d features (from %d func_types)\n",
  nrow(combined_mat), ncol(combined_mat), length(loaded)
))

## ---- Step 3: SpiecEasi network inference -------------------------------
se_fit <- tryCatch({
  SpiecEasi::spiec.easi(
    combined_mat,
    method = "mb",
    nlambda = 20,
    lambda.min.ratio = 0.01
  )
}, error = function(e) {
  cat("[WARN] spiec.easi() failed:", conditionMessage(e), "\n")
  NULL
})

if (is.null(se_fit)) {
  skip_with_reason("SpiecEasi::spiec.easi() failed to converge or errored")
}

adj <- tryCatch({
  as.matrix(SpiecEasi::symBeta(SpiecEasi::getOptBeta(se_fit), mode = "maxabs"))
}, error = function(e) {
  cat("[WARN] symBeta() extraction failed:", conditionMessage(e), "\n")
  NULL
})

if (is.null(adj)) {
  skip_with_reason("Failed to extract edge weights from SpiecEasi fit")
}

feature_ids <- colnames(combined_mat)
rownames(adj) <- feature_ids
colnames(adj) <- feature_ids

## ---- Step 4: build edge table ------------------------------------------
edge_idx <- which(adj != 0 & upper.tri(adj), arr.ind = TRUE)
if (!nrow(edge_idx)) {
  skip_with_reason("SpiecEasi produced zero edges after filtering")
}

parse_func_type <- function(id) sub("::.*$", "", id)

edges_df <- data.frame(
  from_feature = feature_ids[edge_idx[, 1]],
  to_feature = feature_ids[edge_idx[, 2]],
  weight = adj[edge_idx],
  stringsAsFactors = FALSE
)
edges_df$from_func_type <- parse_func_type(edges_df$from_feature)
edges_df$to_func_type <- parse_func_type(edges_df$to_feature)
edges_df <- edges_df[order(-abs(edges_df$weight)), ]

edges_tsv <- file.path(results_dir, "network_edges.tsv")
utils::write.table(edges_df, edges_tsv, sep = "\t", quote = FALSE, row.names = FALSE)

n_cross <- sum(edges_df$from_func_type != edges_df$to_func_type)
n_within <- sum(edges_df$from_func_type == edges_df$to_func_type)
node_ids <- union(edges_df$from_feature, edges_df$to_feature)

summary_df <- data.frame(
  dimension = dimension,
  n_func_types_loaded = length(loaded),
  n_samples = nrow(combined_mat),
  n_features_filtered = ncol(combined_mat),
  n_nodes = length(node_ids),
  n_edges = nrow(edges_df),
  n_cross_func_type_edges = n_cross,
  n_within_func_type_edges = n_within,
  stringsAsFactors = FALSE
)
summary_tsv <- file.path(results_dir, "network_summary.tsv")
utils::write.table(summary_df, summary_tsv, sep = "\t", quote = FALSE, row.names = FALSE)

cat(sprintf("  Nodes: %d, Edges: %d (cross=%d, within=%d)\n",
            length(node_ids), nrow(edges_df), n_cross, n_within))

## ---- Step 5: igraph plot, colored by func_type -------------------------
fig_path_noext <- file.path(figures_dir, sprintf("network_%s", dimension))

plot_ok <- tryCatch({
  g <- igraph::graph_from_data_frame(
    edges_df[, c("from_feature", "to_feature", "weight")],
    directed = FALSE,
    vertices = data.frame(
      name = node_ids,
      func_type = parse_func_type(node_ids),
      stringsAsFactors = FALSE
    )
  )

  set.seed(123)
  layout_xy <- igraph::layout_with_fr(g)

  func_type_levels <- sort(unique(igraph::V(g)$func_type))
  palette <- ggsci::pal_d3("category20")(max(3, length(func_type_levels)))
  vertex_colors <- palette[match(igraph::V(g)$func_type, func_type_levels)]

  plot_network <- function() {
    igraph::plot.igraph(
      g,
      layout = layout_xy,
      vertex.size = 4,
      vertex.label = NA,
      vertex.color = vertex_colors,
      vertex.frame.color = NA,
      edge.width = pmin(3, abs(igraph::E(g)$weight) * 10),
      edge.color = ifelse(igraph::E(g)$weight > 0, "#4DBBD5AA", "#E64B35AA"),
      main = sprintf("Functional co-occurrence network: %s", dimension)
    )
    legend(
      "topright",
      legend = func_type_levels,
      col = palette[seq_along(func_type_levels)],
      pch = 19,
      cex = 0.7,
      bty = "n"
    )
  }

  grDevices::cairo_pdf(paste0(fig_path_noext, ".pdf"), width = 8, height = 8)
  plot_network()
  grDevices::dev.off()

  tryCatch({
    svglite::svglite(paste0(fig_path_noext, ".svg"), width = 8, height = 8)
    plot_network()
    grDevices::dev.off()
  }, error = function(e) cat("[WARN] svg export failed:", conditionMessage(e), "\n"))

  tryCatch({
    ragg::agg_tiff(paste0(fig_path_noext, ".tiff"), width = 8, height = 8, units = "in",
                   res = 300, compression = "lzw")
    plot_network()
    grDevices::dev.off()
  }, error = function(e) cat("[WARN] tiff export failed:", conditionMessage(e), "\n"))

  if (mgx_want_png()) {
    tryCatch({
      ragg::agg_png(paste0(fig_path_noext, ".png"), width = 8, height = 8, units = "in", res = 600)
      plot_network()
      grDevices::dev.off()
    }, error = function(e) cat("[WARN] png export failed:", conditionMessage(e), "\n"))
  }

  TRUE
}, error = function(e) {
  cat("[WARN] Network plot generation failed:", conditionMessage(e), "\n")
  FALSE
})

if (!plot_ok) {
  cat("[WARN] Continuing without a figure; edge/summary tables were written successfully\n")
}

writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), sentinel)
cat("[INFO] Functional network analysis completed\n")
cat("  Edges:", edges_tsv, "\n")
cat("  Summary:", summary_tsv, "\n")
cat("  Sentinel:", sentinel, "\n")




