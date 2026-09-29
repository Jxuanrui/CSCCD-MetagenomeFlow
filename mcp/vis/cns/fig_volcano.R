#!/usr/bin/env Rscript
# ==============================================================================
# fig_volcano.R — DESeq2 volcano plot, CNS single-figure style.
# Usage: Rscript fig_volcano.R <workdir> <out_dir>
# Input : <workdir>/result/stat/bacteria/differential/deseq2_results.tsv
# Output: <out_dir>/volcano.{pdf,png}
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(ggrepel)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_volcano.R <workdir> <out_dir>")
workdir <- normalizePath(args[1])
outdir  <- args[2]
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(script_dir, "../../../scripts/R/pub_theme.R"))

# ---- data --------------------------------------------------------------------
d <- read.delim(file.path(workdir,
  "result/stat/bacteria/differential/deseq2_results.tsv"),
  check.names = FALSE, stringsAsFactors = FALSE)

# Display name: last rank of the pipe lineage, rank prefix stripped.
taxon_name <- function(lineage) {
  parts <- strsplit(lineage, "|", fixed = TRUE)[[1]]
  gsub("_", " ", sub("^[a-z]__", "", parts[length(parts)]))
}

pval <- ifelse(is.na(d$padj), d$pvalue, d$padj)          # NA padj -> raw p
d$nlp  <- -log10(pmax(pval, .Machine$double.xmin))
d$lfc  <- d$log2FoldChange
d$class <- with(d, ifelse(!is.na(padj) & padj < 0.05 & lfc >  1, "Up",
                   ifelse(!is.na(padj) & padj < 0.05 & lfc < -1, "Down", "NS")))

class_cols <- c(Up   = cns_cat[2],
                Down = cns_cat[3],
                NS   = "#B9BEC6")

# Top-8 significant features (smallest padj, |log2FC| as tie-breaker).
sig <- d[!is.na(d$padj) & d$padj < 0.05, ]
top8 <- head(sig[order(sig$padj, -abs(sig$lfc)), ], 8)
top8$label <- vapply(top8$Taxa, taxon_name, character(1))

n_up   <- sum(d$class == "Up")
n_down <- sum(d$class == "Down")
n_ns   <- sum(d$class == "NS")

# ---- plot --------------------------------------------------------------------
p <- ggplot(d, aes(x = lfc, y = nlp)) +
  geom_hline(yintercept = -log10(0.05), linetype = 2,
             linewidth = 0.3, colour = "grey60") +
  geom_vline(xintercept = c(-1, 1), linetype = 2,
             linewidth = 0.3, colour = "grey60") +
  geom_point(data = d[d$class == "NS", ],
             aes(colour = class), shape = 16, size = 0.7,
             alpha = 0.6, show.legend = FALSE) +
  geom_point(data = d[d$class != "NS", ],
             aes(colour = class), shape = 16, size = 1.1, show.legend = FALSE) +
  geom_text_repel(data = top8, aes(label = label),
                  size = 6.5 / ggplot2::.pt, fontface = "italic",
                  colour = "black", segment.size = 0.25,
                  segment.colour = "grey50", min.segment.length = 0,
                  max.overlaps = 20, box.padding = 0.35, seed = 1) +
  scale_colour_manual(values = class_cols) +
  labs(x = expression(log[2]~"fold change"),
       y = expression(-log[10]~italic("P")[adj])) +
  theme_cns()

export_pub_figure(p, file.path(outdir, "volcano"),
                  width_mm = CNS_W_SINGLE, height_mm = 80,
                  formats = c("pdf", "png"))
