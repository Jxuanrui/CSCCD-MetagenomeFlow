#!/usr/bin/env Rscript
# ==============================================================================
# fig_cross_dimension_network.R — bacteria-virus cross-kingdom co-occurrence
# network (ggraph, force-directed Fruchterman-Reingold layout). Node size maps
# to degree, fill to kingdom; top-10 hub taxa are labelled.
#
# Usage: Rscript fig_cross_dimension_network.R <workdir> <out_dir>
#   <workdir>  project directory containing result/stat/network/
#   <out_dir>  output directory (cross_dimension_network.pdf + .png)
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(igraph)
  library(ggraph)
  library(ggrepel)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_cross_dimension_network.R <workdir> <out_dir>",
       call. = FALSE)
workdir <- normalizePath(args[[1]])
out_dir <- args[[2]]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

script_file <- grep("^--file=", commandArgs(), value = TRUE)[1]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_file)))
source(file.path(script_dir, "theme_cns.R"))
repo_root <- script_dir
while (!file.exists(file.path(repo_root, "scripts", "R", "pub_theme.R")) &&
       basename(repo_root) != "")
  repo_root <- dirname(repo_root)
source(file.path(repo_root, "scripts", "R", "pub_theme.R"))

# ---- data (support both flat and nested network file layouts) ------------------
find_file <- function(...) {
  cand <- file.path(workdir, unlist(list(...), use.names = FALSE))
  cand[file.exists(cand)][1]
}
nodes_f <- find_file("result/stat/network/cross_bac_vir/nodes.tsv",
                     "result/stat/network/cross_bac_vir_nodes.tsv")
edges_f <- find_file("result/stat/network/cross_bac_vir/edges.tsv",
                     "result/stat/network/cross_bac_vir_edges.tsv")
if (is.na(nodes_f) || is.na(edges_f))
  stop("network nodes/edges tsv not found under result/stat/network/", call. = FALSE)
nd <- read.delim(nodes_f, check.names = FALSE, quote = "")
ed <- read.delim(edges_f, check.names = FALSE, quote = "")
n_edges_total <- nrow(ed)

# Keep only the strongest ties: the full 11k-edge hairball renders as an
# opaque PDF (6+ MB of vector arcs that some viewers show as a blank page)
# and hides structure. Top 1,500 by |weight| preserves the backbone.
ed$w <- abs(suppressWarnings(as.numeric(ed$weight)))
if (nrow(ed) > 1500 && all(is.finite(ed$w))) {
  ed <- ed[order(-ed$w), , drop = FALSE][seq_len(1500), , drop = FALSE]
}
# degree/labels computed on the backbone graph
g <- graph_from_data_frame(ed[, c("from", "to")], directed = FALSE,
                           vertices = nd)
g <- delete_vertices(g, which(degree(g) == 0))
set.seed(42)  # reproducible FR layout
ly <- create_layout(g, layout = "fr")
ly$degree <- degree(g)[ly$name]
ly$kingdom <- factor(ifelse(ly$v_group == "bacteria", "Bacteria", "Virus"),
                     levels = c("Bacteria", "Virus"))

# ---- hub labels -----------------------------------------------------------------
hubs <- ly[order(-ly$degree, ly$name), ][seq_len(10), ]
hubs$lab <- sub("^[a-z]__", "", sub(".*\\|", "", hubs$name))
hubs$face <- ifelse(grepl("^[A-Za-z]+( [a-z]+)?$", hubs$lab), "italic",
                    "plain")

# ---- plot -----------------------------------------------------------------------
p <- ggraph(ly) +
  geom_edge_arc(width = 0.2, colour = "grey85", strength = 0.08,
                alpha = 0.35, show.legend = FALSE) +
  geom_node_point(aes(size = degree, fill = kingdom), shape = 21,
                  colour = "black", stroke = 0.25, alpha = 0.85) +
  geom_text_repel(data = hubs, aes(x = x, y = y, label = lab),
                  size = 6.5 / ggplot2::.pt, fontface = hubs$face,
                  colour = "black", segment.size = 0.2,
                  segment.colour = "grey50", min.segment.length = 0,
                  max.overlaps = Inf, box.padding = 0.4,
                  show.legend = FALSE) +
  scale_fill_manual(values = c(Bacteria = cns_cat[1], Virus = cns_cat[2]),
                    name = NULL) +
  scale_size_continuous(range = c(1.5, 4), name = "Degree") +
  coord_fixed() +
  theme_cns(y_grid = FALSE) +
  theme(axis.line = element_blank(), axis.ticks = element_blank(),
        axis.text = element_blank(), axis.title = element_blank(),
        legend.position = "bottom", legend.box = "horizontal")

export_pub_figure(p, file.path(out_dir, "cross_dimension_network"),
                  CNS_W_DOUBLE, 150, formats = c("pdf", "png"))

# ---- self-check -----------------------------------------------------------------
message(sprintf("[fig_cross_dimension_network] nodes: %d (%d bacteria / %d virus); edges: %d",
                vcount(g), sum(ly$kingdom == "Bacteria"),
                sum(ly$kingdom == "Virus"), ecount(g)))
message(sprintf("[fig_cross_dimension_network] top hub: %s (degree %d)",
                hubs$lab[1], max(hubs$degree)))
message(sprintf("[fig_cross_dimension_network] kingdom fill Bacteria=%s Virus=%s | size 1.5-4 mm | %.0f x 150 mm",
                cns_cat[1], cns_cat[2], CNS_W_DOUBLE))
for (f in c("pdf", "png"))
  stopifnot(file.exists(file.path(out_dir, sprintf("cross_dimension_network.%s", f))))
message("[fig_cross_dimension_network] OK: cross_dimension_network.{pdf,png} written")
