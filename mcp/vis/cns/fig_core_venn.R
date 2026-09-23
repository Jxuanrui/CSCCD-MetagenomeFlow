#!/usr/bin/env Rscript
# ==============================================================================
# fig_core_venn.R — two-set Venn of group-specific core microbiomes, drawn with
# ggforce circles (CNS single-figure style; no VennDiagram dependency).
# Usage: Rscript fig_core_venn.R <workdir> <out_dir>
# Input : <workdir>/result/stat/bacteria/abundance/species_relabund.tsv
#         <workdir>/result/stat/metadata.tsv
# Output: <out_dir>/core_microbiome_venn.{pdf,png}
# Core  : species present (>0.1% relative abundance) in >= 50% of a group's
#         samples.
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(ggforce)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_core_venn.R <workdir> <out_dir>")
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
groups <- setNames(meta$group, meta$sample_id)[colnames(ab)]

core_sets <- lapply(split(colnames(ab), groups), function(ids)
  rownames(ab)[rowMeans(as.matrix(ab[, ids, drop = FALSE]) > 0.001) >= 0.5])
lv  <- levels(factor(groups))
if (length(lv) < 2) stop("Need >= 2 groups for a Venn diagram")
n_gr <- vapply(lv, function(g) sum(groups == g), integer(1))

a <- core_sets[[lv[1]]]
b <- core_sets[[lv[2]]]
n_a_only <- length(setdiff(a, b))
n_b_only <- length(setdiff(b, a))
n_ab     <- length(intersect(a, b))

grp_cols <- setNames(cns_cat[seq_along(lv)], lv)

# ---- geometry: two overlapping circles ---------------------------------------
r <- 1
cdist <- 0.62                              # centre separation / 2
circles <- data.frame(
  x0 = c(-cdist, cdist), y0 = c(0, 0), r = r, group = lv)
counts <- data.frame(
  x = c(-cdist - 0.42, 0, cdist + 0.42),
  y = c(0.05, 0.05, 0.05),
  label = c(n_a_only, n_ab, n_b_only))
set_lab <- data.frame(
  x = c(-cdist - 0.75, cdist + 0.75), y = c(-r - 0.32, -r - 0.32),
  label = sprintf("%s (n = %d)", lv, n_gr))

# ---- plot --------------------------------------------------------------------
p <- ggplot() +
  geom_circle(data = circles,
              aes(x0 = x0, y0 = y0, r = r, fill = group, colour = group),
              linewidth = 0.5, alpha = 0.28) +
  geom_text(data = counts, aes(x = x, y = y, label = label),
            size = 9 / .pt, fontface = "bold", colour = "black") +
  geom_text(data = set_lab, aes(x = x, y = y, label = label),
            size = 8.5 / .pt, fontface = "bold") +
  annotate("text", x = -cdist - 0.75, y = -r - 0.62,
           label = sprintf("Core: %d", length(a)),
           size = 7 / .pt, colour = grp_cols[[lv[1]]]) +
  annotate("text", x = cdist + 0.75, y = -r - 0.62,
           label = sprintf("Core: %d", length(b)),
           size = 7 / .pt, colour = grp_cols[[lv[2]]]) +
  scale_fill_manual(values = grp_cols, guide = "none") +
  scale_colour_manual(values = grp_cols, guide = "none") +
  coord_fixed(xlim = c(-2.75, 2.75), ylim = c(-2.05, 1.35), clip = "off") +
  labs(caption = sprintf(paste0(
    "Core = prevalence \u2265 50%% within group at >0.1%% relative abundance\n",
    "%d of %d species occur in >= 1 group core"),
    length(union(a, b)), nrow(ab))) +
  theme_cns(y_grid = FALSE) +
  theme(axis.title = element_blank(), axis.text = element_blank(),
        axis.ticks = element_blank(), axis.line = element_blank(),
        plot.caption = element_text(size = 6, colour = "grey30", hjust = 0,
                                    lineheight = 0.9))

export_pub_figure(p, file.path(outdir, "core_microbiome_venn"),
                  width_mm = CNS_W_SINGLE, height_mm = 75,
                  formats = c("pdf", "png"))
