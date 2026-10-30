#!/usr/bin/env Rscript
# ==============================================================================
# fig_core_microbiome.R — core microbiome lollipop (prevalence / abundance),
# CNS single-figure style.
# Usage: Rscript fig_core_microbiome.R <workdir> <out_dir>
# Input : <workdir>/result/stat/bacteria/abundance/species_relabund.tsv
#         <workdir>/result/stat/metadata.tsv
# Output: <out_dir>/core_microbiome.{pdf,png}
# Core  : species present (>0.1% relative abundance) in >= 50% of samples.
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_core_microbiome.R <workdir> <out_dir>")
workdir <- normalizePath(args[1])
outdir  <- args[2]
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(script_dir, "../../../scripts/R/pub_theme.R"))

# ---- data --------------------------------------------------------------------
ab <- read.delim(file.path(workdir,
  "result/stat/bacteria/abundance/species_relabund.tsv"),
  row.names = 1, check.names = FALSE)
meta <- read.delim(file.path(workdir, "result/stat/metadata.tsv"),
                   check.names = FALSE)

taxon_name <- function(lineage) {
  parts <- strsplit(lineage, "|", fixed = TRUE)[[1]]
  gsub("_", " ", sub("^[a-z]__", "", parts[length(parts)]))
}

prev <- rowMeans(ab > 0.001) * 100          # prevalence (%) at >0.1% abundance
mab  <- rowMeans(as.matrix(ab)) * 100       # mean relative abundance (%)
d <- data.frame(lineage = rownames(ab), prev = prev, mab = mab)
d <- d[d$prev >= 50, ]                      # core species
d <- d[order(d$mab, decreasing = TRUE), ]
d <- head(d, 10)                            # top-10 core taxa by abundance
d$name <- factor(vapply(d$lineage, taxon_name, character(1)),
                 levels = rev(vapply(d$lineage, taxon_name, character(1))))

# ---- plot --------------------------------------------------------------------
# Top-10 core taxa all sit at ~100% prevalence (core >= 50% by definition,
# abundance-ranked head), so a prevalence colour scale encodes no variation —
# single accent colour, no legend.
p <- ggplot(d, aes(x = mab, y = name)) +
  geom_segment(aes(x = 0, xend = mab, y = name, yend = name),
               linewidth = 0.35, colour = "grey55", show.legend = FALSE) +
  geom_point(shape = 16, size = 1.7, stroke = 0,
             colour = cns_cat[1], show.legend = FALSE) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.06))) +
  labs(x = "Mean relative abundance (%)", y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.y = element_text(face = "italic", size = 6.5,
                                   lineheight = 0.85),
        plot.margin = margin(4, 3, 2, 2, "mm"))

export_pub_figure(p, file.path(outdir, "core_microbiome"),
                  width_mm = CNS_W_SINGLE, height_mm = 70,
                  formats = c("pdf", "png"))
