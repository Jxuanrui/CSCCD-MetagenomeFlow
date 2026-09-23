#!/usr/bin/env Rscript
# ==============================================================================
# fig_lefse_cladogram.R — circular taxonomy cladogram of LEfSe-enriched clades,
# CNS single-figure style (tree built from lineage nesting, ggtree circular).
# Usage: Rscript fig_lefse_cladogram.R <workdir> <out_dir>
# Input : <workdir>/result/stat/bacteria/lefse/lefse_results.tsv
#         (fallback: result/stat/bacteria/differential/lefse_results.tsv)
# Output: <out_dir>/lefse_cladogram.{pdf,png}
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(igraph)
  library(ape)
  library(ggtree)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_lefse_cladogram.R <workdir> <out_dir>")
workdir <- normalizePath(args[1])
outdir  <- args[2]
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(script_dir, "../../../scripts/R/pub_theme.R"))

# ---- data --------------------------------------------------------------------
lefse_path <- file.path(workdir, "result/stat/bacteria/lefse/lefse_results.tsv")
if (!file.exists(lefse_path))
  lefse_path <- file.path(workdir,
    "result/stat/bacteria/differential/lefse_results.tsv")
l <- read.delim(lefse_path, check.names = FALSE, stringsAsFactors = FALSE)
names(l)[names(l) == "feature" | names(l) == "Taxa"] <- "feature"
names(l)[names(l) == "lda_score" | names(l) == "LDA_score"] <- "lda"
names(l)[names(l) == "enriched_group" | names(l) == "Group"] <- "grp"

taxon_name <- function(lineage) {
  parts <- strsplit(lineage, "|", fixed = TRUE)[[1]]
  gsub("_", " ", sub("^[a-z]__", "", parts[length(parts)]))
}

# ---- build trie (nested lineages) -> phylo ------------------------------------
all_prefixes <- unique(unlist(lapply(l$feature, function(f) {
  p <- strsplit(f, "|", fixed = TRUE)[[1]]
  sapply(seq_along(p), function(i) paste(p[1:i], collapse = "|"))
})))
edges <- do.call(rbind, lapply(all_prefixes, function(s) {
  p <- strsplit(s, "|", fixed = TRUE)[[1]]
  if (length(p) == 1) NULL else
    c(paste(p[-length(p)], collapse = "|"), s)
}))
edf <- as.data.frame(edges, stringsAsFactors = FALSE)
names(edf) <- c("from", "to")
tree <- ape::as.phylo(igraph::graph_from_data_frame(edf, directed = TRUE))
tree$edge.length <- rep(1, nrow(tree$edge))

# ---- per-node LDA / group (deepest enrichment wins a node) --------------------
feat_map <- setNames(l$lda, l$feature)
grp_map  <- setNames(l$grp,  l$feature)
node_anno <- do.call(rbind, lapply(all_prefixes, function(s) {
  hits <- which(l$feature == s |
                startsWith(l$feature, paste0(s, "|")))
  if (length(hits) == 0) return(data.frame(label = s, lda = NA, grp = NA))
  h <- hits[which.max(l$lda[hits])]
  data.frame(label = s, lda = l$lda[h], grp = l$grp[h])
}))
grp_lv <- levels(factor(l$grp))
grp_cols <- setNames(cns_cat[seq_along(grp_lv)], grp_lv)

# Label the top species tips by LDA (keep the plot compact).
sp <- node_anno[grepl("[|]s__", node_anno$label) & !is.na(node_anno$lda), ]
top_sp <- head(sp[order(sp$lda, decreasing = TRUE), "label"], 8)
node_anno$show <- node_anno$label %in% top_sp
node_anno$tname <- vapply(node_anno$label, taxon_name, character(1))

# ---- plot ---------------------------------------------------------------------
p <- ggtree(tree, layout = "circular", right = FALSE) %<+% node_anno +
  geom_tree(aes(colour = grp), linewidth = 0.4, na.rm = TRUE) +
  geom_tippoint(aes(colour = grp, size = lda), shape = 16, na.rm = TRUE) +
  geom_tiplab2(aes(subset = show, label = tname, colour = grp),
               fontface = "italic", size = 6.5 / .pt,
               offset = 0.08, show.legend = FALSE) +
  scale_colour_manual(values = grp_cols, na.value = "grey75",
                      name = "Enriched group") +
  scale_size_continuous(range = c(0.8, 2.4), name = "LDA score",
                        breaks = c(4.0, 4.3, 4.6)) +
  guides(colour = guide_legend(order = 1, override.aes = list(size = 2)),
         size  = guide_legend(order = 2)) +
  theme_cns(y_grid = FALSE) +
  theme(axis.title = element_blank(), axis.text = element_blank(),
        axis.ticks = element_blank(), axis.line = element_blank(),
        legend.position = "right",
        legend.title = element_text(size = 8),
        legend.text = element_text(size = 7),
        legend.box = "vertical", legend.key.size = unit(3.2, "mm"))

export_pub_figure(p, file.path(outdir, "lefse_cladogram"),
                  width_mm = CNS_W_SINGLE, height_mm = 89,
                  formats = c("pdf", "png"))
