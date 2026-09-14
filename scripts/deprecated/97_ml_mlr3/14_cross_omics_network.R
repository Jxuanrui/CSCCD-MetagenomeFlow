#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE, warn=1)

install_if_missing <- function(package) {
  if(requireNamespace(package, quietly=TRUE)) return(TRUE)
  message("Package ", package, " is missing; attempting installation")
  tryCatch({
    install.packages(package, repos="https://cloud.r-project.org", quiet=TRUE)
    requireNamespace(package, quietly=TRUE)
  }, error=function(error) {
    warning("Could not install ", package, ": ", conditionMessage(error))
    FALSE
  })
}

if(!requireNamespace("optparse", quietly=TRUE)) stop("Package optparse is required")
suppressPackageStartupMessages(library(optparse))

option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character", help="Dimension: bacteria/fungi/virus"),
  make_option(c("--n-taxonomy"), dest="n_taxonomy", type="integer", default=NULL, help="Number of taxonomy features"),
  make_option(c("--n-functional"), dest="n_functional", type="integer", default=NULL, help="Number of functional features"),
  make_option(c("--cor-threshold"), dest="cor_threshold", type="double", default=0.3, help="Absolute correlation threshold [default: %default]"),
  make_option(c("--p-threshold"), dest="p_threshold", type="double", default=0.05, help="P-value threshold [default: %default]")
)
opt <- parse_args(OptionParser(option_list=option_list))
if(is.null(opt$workdir) || is.null(opt$dimension)) stop("--workdir and --dimension are required")
if(!opt$dimension %in% c("bacteria", "fungi", "virus")) stop("--dimension must be bacteria, fungi, or virus")
if(is.null(opt$n_taxonomy)) opt$n_taxonomy <- if(opt$dimension == "bacteria") 30L else 20L
if(is.null(opt$n_functional)) opt$n_functional <- if(opt$dimension == "bacteria") 30L else 20L

available <- vapply(c("compositions", "ppcor", "igraph", "ggraph", "ggplot2"), install_if_missing, logical(1))
names(available) <- c("compositions", "ppcor", "igraph", "ggraph", "ggplot2")

first_existing <- function(paths) {
  hit <- paths[file.exists(paths)]
  if(length(hit) == 0) stop("No input file found among: ", paste(paths, collapse=", "))
  hit[[1]]
}

read_feature_table <- function(path) {
  table <- read.delim(path, check.names=FALSE, comment.char="", quote="", stringsAsFactors=FALSE)
  if(ncol(table) < 2) stop("Abundance table has fewer than two columns: ", path)
  feature_ids <- trimws(as.character(table[[1]]))
  values <- as.matrix(table[-1])
  storage.mode(values) <- "double"
  rownames(values) <- feature_ids
  values
}

read_metaphlan <- function(path) {
  table <- read.delim(path, check.names=FALSE, comment.char="#", quote="", stringsAsFactors=FALSE)
  feature_ids <- trimws(as.character(table[[1]]))
  values <- as.matrix(table[-1])
  storage.mode(values) <- "double"
  rownames(values) <- feature_ids
  values
}

read_importance <- function(path, n) {
  importance <- read.csv(path, check.names=FALSE)
  if(!all(c("feature", "mean_abs_shap") %in% names(importance))) stop("Invalid SHAP file: ", path)
  importance$feature <- as.character(importance$feature)
  importance$mean_abs_shap <- suppressWarnings(as.numeric(importance$mean_abs_shap))
  importance <- importance[is.finite(importance$mean_abs_shap) & !duplicated(importance$feature), , drop=FALSE]
  head(importance[order(importance$mean_abs_shap, decreasing=TRUE), , drop=FALSE], n)
}

clr_transform <- function(feature_by_sample) {
  sample_by_feature <- t(feature_by_sample)
  sample_by_feature[!is.finite(sample_by_feature) | sample_by_feature < 0] <- 0
  sample_by_feature <- sample_by_feature + 1e-6
  if(available[["compositions"]]) {
    return(unclass(compositions::clr(sample_by_feature)))
  }
  log_values <- log(sample_by_feature)
  sweep(log_values, 1, rowMeans(log_values), "-")
}

spearman_pairs <- function(taxonomy, functional) {
  pairs <- expand.grid(taxonomy=colnames(taxonomy), functional=colnames(functional), stringsAsFactors=FALSE)
  results <- lapply(seq_len(nrow(pairs)), function(index) {
    x <- taxonomy[, pairs$taxonomy[index]]
    y <- functional[, pairs$functional[index]]
    test <- suppressWarnings(tryCatch(cor.test(x, y, method="spearman", exact=FALSE), error=function(error) NULL))
    if(is.null(test)) c(correlation=NA_real_, pvalue=NA_real_) else c(correlation=unname(test$estimate), pvalue=test$p.value)
  })
  values <- do.call(rbind, results)
  data.frame(source_feature=pairs$taxonomy, target_feature=pairs$functional,
             correlation=values[, "correlation"], pvalue=values[, "pvalue"], stringsAsFactors=FALSE)
}

partial_pairs <- function(taxonomy, functional, group) {
  group_design <- model.matrix(~ group)[, -1, drop=FALSE]
  pairs <- expand.grid(source_feature=colnames(taxonomy), target_feature=colnames(functional), stringsAsFactors=FALSE)
  results <- lapply(seq_len(nrow(pairs)), function(index) {
    test <- suppressWarnings(tryCatch(
      ppcor::pcor.test(taxonomy[, pairs$source_feature[index]], functional[, pairs$target_feature[index]],
                       group_design, method="spearman"),
      error=function(error) NULL
    ))
    if(is.null(test)) c(correlation=NA_real_, pvalue=NA_real_) else c(correlation=unname(test$estimate[[1]]), pvalue=unname(test$p.value[[1]]))
  })
  values <- do.call(rbind, results)
  pairs$correlation <- values[, "correlation"]
  pairs$pvalue <- values[, "pvalue"]
  pairs
}

short_taxonomy <- function(feature) {
  last <- sub("^.*\\|", "", feature)
  sub("^[a-z]__", "", last)
}

plot_base <- function(nodes, edges, path, title) {
  pdf(path, width=10, height=8)
  on.exit(dev.off(), add=TRUE)
  if(nrow(edges) == 0) {
    plot.new(); title(main=title); text(0.5, 0.5, "No significant cross-omics edges")
    return(invisible(NULL))
  }
  if(available[["igraph"]]) {
    graph <- igraph::graph_from_data_frame(edges[, c("source_feature", "target_feature")], directed=FALSE, vertices=nodes)
    set.seed(2026)
    layout <- igraph::layout_with_fr(graph)
    edge_index <- match(paste(igraph::as_edgelist(graph)[,1], igraph::as_edgelist(graph)[,2]), paste(edges$source_feature, edges$target_feature))
    plot(graph, layout=layout, vertex.label=nodes$label[match(igraph::V(graph)$name, nodes$name)],
         vertex.color=ifelse(nodes$type[match(igraph::V(graph)$name, nodes$name)] == "Taxonomy", "#E69F00", "#009E73"),
         vertex.shape=ifelse(nodes$type[match(igraph::V(graph)$name, nodes$name)] == "Taxonomy", "circle", "square"),
         vertex.size=8 + 10 * sqrt(nodes$importance[match(igraph::V(graph)$name, nodes$name)] / max(nodes$importance)),
         vertex.label.cex=0.65, vertex.frame.color="white",
         edge.color=ifelse(edges$correlation[edge_index] > 0, "#2C7BB6", "#D7191C"),
         edge.width=1 + 5 * abs(edges$correlation[edge_index]), edge.lty=ifelse(edges$correlation[edge_index] > 0, 1, 2),
         main=title)
  } else {
    plot.new(); title(main=title); text(0.5, 0.5, paste(nrow(nodes), "nodes;", nrow(edges), "edges"))
  }
}

plot_network <- function(nodes, edges, path, title) {
  if(!(available[["igraph"]] && available[["ggraph"]] && available[["ggplot2"]])) return(plot_base(nodes, edges, path, title))
  if(nrow(edges) == 0) return(plot_base(nodes, edges, path, title))
  graph <- igraph::graph_from_data_frame(edges, directed=FALSE, vertices=nodes)
  set.seed(2026)
  plot <- ggraph::ggraph(graph, layout="fr") +
    ggraph::geom_edge_link(ggplot2::aes(edge_colour=edge_type, edge_width=abs(correlation), edge_linetype=edge_type), alpha=0.75) +
    ggraph::geom_node_point(ggplot2::aes(size=importance, colour=type, shape=type), stroke=0.5) +
    ggraph::geom_node_text(ggplot2::aes(label=label), repel=TRUE, size=3, max.overlaps=Inf) +
    ggplot2::scale_edge_colour_manual(values=c("Positive"="#2C7BB6", "Negative"="#D7191C"), name="Correlation") +
    ggplot2::scale_edge_linetype_manual(values=c("Positive"="solid", "Negative"="dashed"), name="Correlation") +
    ggraph::scale_edge_width(range=c(0.5, 2.5), name="|Correlation|") +
    ggplot2::scale_colour_manual(values=c("Taxonomy"="#E69F00", "Functional"="#009E73"), name="Node type") +
    ggplot2::scale_shape_manual(values=c("Taxonomy"=21, "Functional"=22), name="Node type") +
    ggplot2::scale_size_continuous(range=c(3.5, 9), name="Mean |SHAP|") +
    ggplot2::labs(title=title, subtitle=paste(nrow(nodes), "nodes and", nrow(edges), "cross-omics edges")) +
    ggraph::theme_graph(base_family="sans") +
    ggplot2::theme(plot.title=ggplot2::element_text(face="bold", size=15), legend.position="right")
  ggplot2::ggsave(path, plot, width=10, height=8, device=cairo_pdf)
}

workdir <- normalizePath(opt$workdir, mustWork=TRUE)
dimension <- opt$dimension
functional_type <- if(dimension == "virus") "vog" else "kegg_ko"
stat_dir <- file.path(workdir, "result", "stat", dimension)
tax_shap_path <- file.path(stat_dir, "ml_mlr3", paste0("shap_importance_", dimension, ".csv"))
fun_shap_path <- file.path(stat_dir, "ml_mlr3_functional", functional_type, paste0("shap_importance_", dimension, ".csv"))
metadata_path <- file.path(workdir, "metadata.csv")

taxonomy_path <- switch(dimension,
  bacteria=first_existing(c(file.path(workdir, "result/bacteria/metaphlan4/merged_abundance_table.txt"), file.path(workdir, "bacteria/metaphlan4/merged_abundance_table.txt"))),
  fungi=first_existing(c(file.path(workdir, "result/fungi/metaphlan4/merged_abundance_table.txt"), file.path(workdir, "fungi/metaphlan4/merged_abundance_table.txt"))),
  virus=first_existing(c(file.path(workdir, "result/virus/votu/votu_table.tsv"), file.path(workdir, "virus/votu/votu_table.tsv")))
)
functional_path <- switch(dimension,
  bacteria=first_existing(c(file.path(workdir, "result/integration/bacteria/kegg_ko_abundance.tsv"), file.path(workdir, "result/integration/bacteria/kegg_ko_gene_count.tsv"))),
  fungi=first_existing(c(file.path(workdir, "result/integration/fungi/kegg_ko_abundance.tsv"), file.path(workdir, "result/integration/fungi/kegg_ko_gene_count.tsv"))),
  virus=first_existing(c(file.path(workdir, "result/integration/virus/vog_abundance.tsv"), file.path(workdir, "result/integration/virus/vog_gene_count.tsv")))
)

for(path in c(tax_shap_path, fun_shap_path, metadata_path)) if(!file.exists(path)) stop("Input not found: ", path)
tax_importance <- read_importance(tax_shap_path, opt$n_taxonomy)
fun_importance <- read_importance(fun_shap_path, opt$n_functional)
tax_abundance <- if(dimension %in% c("bacteria", "fungi")) read_metaphlan(taxonomy_path) else read_feature_table(taxonomy_path)
fun_abundance <- read_feature_table(functional_path)

missing_tax <- setdiff(tax_importance$feature, rownames(tax_abundance))
missing_fun <- setdiff(fun_importance$feature, rownames(fun_abundance))
if(length(missing_tax)) warning(length(missing_tax), " taxonomy top features absent from abundance table")
if(length(missing_fun)) warning(length(missing_fun), " functional top features absent from abundance table")
tax_importance <- tax_importance[tax_importance$feature %in% rownames(tax_abundance), , drop=FALSE]
fun_importance <- fun_importance[fun_importance$feature %in% rownames(fun_abundance), , drop=FALSE]
if(nrow(tax_importance) == 0 || nrow(fun_importance) == 0) stop("No selected features found in abundance tables")

tax_clr <- clr_transform(tax_abundance[tax_importance$feature, , drop=FALSE])
fun_clr <- clr_transform(fun_abundance[fun_importance$feature, , drop=FALSE])
metadata <- read.csv(metadata_path, check.names=FALSE)
if(!all(c("sample_id", "group") %in% names(metadata))) stop("metadata.csv must contain sample_id and group")
samples <- Reduce(intersect, list(rownames(tax_clr), rownames(fun_clr), metadata$sample_id))
if(length(samples) < 4) stop("Too few common samples: ", length(samples))
metadata <- metadata[match(samples, metadata$sample_id), , drop=FALSE]
tax_clr <- tax_clr[samples, , drop=FALSE]
fun_clr <- fun_clr[samples, , drop=FALSE]
valid <- !is.na(metadata$group) & apply(tax_clr, 1, function(x) all(is.finite(x))) & apply(fun_clr, 1, function(x) all(is.finite(x)))
metadata <- metadata[valid, , drop=FALSE]
tax_clr <- tax_clr[valid, , drop=FALSE]
fun_clr <- fun_clr[valid, , drop=FALSE]

feature_count <- ncol(tax_clr) + ncol(fun_clr)
method <- "Spearman correlation (fallback)"
can_partial <- available[["ppcor"]] && nrow(tax_clr) >= feature_count + (nlevels(factor(metadata$group)) - 1) + 10
all_edges <- NULL
if(can_partial) {
  all_edges <- tryCatch(partial_pairs(tax_clr, fun_clr, factor(metadata$group)), error=function(error) { warning("Partial correlation failed: ", conditionMessage(error)); NULL })
  if(!is.null(all_edges)) method <- "Spearman partial correlation controlling metadata group"
}
if(is.null(all_edges)) all_edges <- spearman_pairs(tax_clr, fun_clr)
all_edges <- all_edges[is.finite(all_edges$correlation) & is.finite(all_edges$pvalue), , drop=FALSE]

cor_cut <- opt$cor_threshold
p_cut <- opt$p_threshold
edges <- all_edges[abs(all_edges$correlation) > cor_cut & all_edges$pvalue < p_cut, , drop=FALSE]
relaxation <- "none"
if(nrow(edges) < 5) {
  candidates <- list(
    list(cor=max(0.25, min(cor_cut, 0.25)), p=p_cut, label="|cor| > 0.25"),
    list(cor=cor_cut, p=max(p_cut, 0.1), label="p < 0.1"),
    list(cor=max(0.25, min(cor_cut, 0.25)), p=max(p_cut, 0.1), label="|cor| > 0.25 and p < 0.1")
  )
  candidate_edges <- lapply(candidates, function(x) all_edges[abs(all_edges$correlation) > x$cor & all_edges$pvalue < x$p, , drop=FALSE])
  counts <- vapply(candidate_edges, nrow, integer(1))
  chosen <- if(any(counts >= 5)) which(counts >= 5)[1] else which.max(counts)
  if(length(chosen)) {
    edges <- candidate_edges[[chosen]]; cor_cut <- candidates[[chosen]]$cor; p_cut <- candidates[[chosen]]$p; relaxation <- candidates[[chosen]]$label
  }
}
edges$edge_type <- ifelse(edges$correlation > 0, "Positive", "Negative")
edges <- edges[order(edges$pvalue, -abs(edges$correlation)), , drop=FALSE]

importance <- rbind(data.frame(name=tax_importance$feature, type="Taxonomy", importance=tax_importance$mean_abs_shap),
                    data.frame(name=fun_importance$feature, type="Functional", importance=fun_importance$mean_abs_shap))
node_names <- importance$name
nodes <- importance[match(node_names, importance$name), , drop=FALSE]
nodes$label <- ifelse(nodes$type == "Taxonomy", vapply(nodes$name, short_taxonomy, character(1)), nodes$name)

outdir <- file.path(stat_dir, "cross_omics_network")
dir.create(outdir, recursive=TRUE, showWarnings=FALSE)
csv_path <- file.path(outdir, paste0("species_function_network_", dimension, ".csv"))
pdf_path <- file.path(outdir, paste0("species_function_network_", dimension, ".pdf"))
stats_path <- file.path(outdir, paste0("network_stats_", dimension, ".txt"))
write.csv(edges[, c("source_feature", "target_feature", "correlation", "pvalue", "edge_type")], csv_path, row.names=FALSE)
plot_network(nodes, edges, pdf_path, paste(tools::toTitleCase(dimension), functional_type, "cross-omics network"))

if(nrow(edges) > 0 && available[["igraph"]]) {
  graph <- igraph::graph_from_data_frame(edges[, c("source_feature", "target_feature")], directed=FALSE, vertices=nodes)
  node_count <- igraph::vcount(graph); edge_count <- igraph::ecount(graph)
  average_degree <- mean(igraph::degree(graph)); components <- igraph::components(graph)$no
} else {
  node_count <- length(node_names); edge_count <- nrow(edges)
  average_degree <- if(node_count > 0) 2 * edge_count / node_count else 0
  components <- if(node_count > 0) node_count else 0
}
cor_range <- if(nrow(edges)) range(edges$correlation) else c(NA_real_, NA_real_)
stats <- c(
  paste0("dimension: ", dimension), paste0("method: ", method), paste0("samples: ", nrow(tax_clr)),
  paste0("taxonomy_features_tested: ", ncol(tax_clr)), paste0("functional_features_tested: ", ncol(fun_clr)),
  paste0("correlation_threshold: ", cor_cut), paste0("pvalue_threshold: ", p_cut), paste0("threshold_relaxation: ", relaxation),
  paste0("nodes: ", node_count), paste0("edges: ", edge_count), paste0("average_degree: ", signif(average_degree, 6)),
  paste0("connected_components: ", components), paste0("correlation_min: ", signif(cor_range[1], 6)),
  paste0("correlation_max: ", signif(cor_range[2], 6))
)
writeLines(stats, stats_path)
message(paste(stats, collapse="\n"))
