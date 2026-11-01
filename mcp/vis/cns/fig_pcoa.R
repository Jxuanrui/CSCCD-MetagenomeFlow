#!/usr/bin/env Rscript
# ==============================================================================
# fig_pcoa.R — CNS-style PCoA scatter with 95% ellipses + PERMANOVA annotation.
# Layout idea from blueprints "跟着Nature_Food学绘图_PCoA统一风格与一体化布局
# 优化" / "PCoA可视化揭示群落结构的多维差异之美": variance-annotated axes,
# group-colored points, PERMANOVA R2/p text. Rewritten for the theme_cns design
# system (cns_cat colors, cns_p_label formatting, coord_fixed).
#
# Usage:   Rscript fig_pcoa.R <workdir> <out_dir>
# Inputs:  <workdir>/result/stat/bacteria/diversity/pcoa_coordinates.tsv
#                                             (sample rows + variance_explained)
#          <workdir>/result/stat/bacteria/diversity/beta_bray_curtis.tsv
#                                             (fallback for variance share)
#          <workdir>/result/stat/bacteria/diversity/permanova_results.tsv
#          <workdir>/result/stat/metadata.tsv   (rownames + sample_id + group)
# Output:  <out_dir>/pcoa.{pdf,png}  (single-column square, 89 x 89 mm)
# ==============================================================================
suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
workdir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "."
out_dir <- if (length(args) >= 2 && nzchar(args[2])) args[2] else
  file.path(workdir, "result", "figure")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

.ca <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .ca, value = TRUE)
script_dir <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]))) else getwd()
source(file.path(script_dir, "theme_cns.R"))
source(file.path(script_dir, "..", "..", "..", "scripts", "R", "pub_theme.R"))

OUT <- "pcoa"
PT_MM <- 25.4 / 72
txt <- function(pt) pt * PT_MM
div <- file.path(workdir, "result", "stat", "bacteria", "diversity")

# ---- data --------------------------------------------------------------------
meta <- read.delim(file.path(workdir, "result", "stat", "metadata.tsv"),
                   row.names = 1, check.names = FALSE)
pc <- read.delim(file.path(div, "pcoa_coordinates.tsv"),
                 row.names = 1, check.names = FALSE)
ve_row <- grep("^variance", rownames(pc), ignore.case = TRUE)

if (length(ve_row) == 1) {                 # fractions on the trailing row
  pct <- as.numeric(pc[ve_row, c("PC1", "PC2")]) * 100
} else {                                   # fallback: eigen share from distance
  d <- as.dist(as.matrix(read.delim(file.path(div, "beta_bray_curtis.tsv"),
                                    row.names = 1, check.names = FALSE)))
  k <- min(3, nrow(pc) - 1)
  ev <- cmdscale(d, k = k, eig = TRUE)$eig
  pct <- ev[1:2] / sum(ev[ev > 0]) * 100
}
coords <- pc[setdiff(rownames(pc), rownames(pc)[ve_row]), c("PC1", "PC2"),
             drop = FALSE]
coords <- coords[rownames(meta), , drop = FALSE]

grp <- meta[rownames(coords), "group"]
grp <- factor(grp, levels = sort(unique(grp)))
cap <- function(g) paste0(toupper(substring(g, 1, 1)), substring(g, 2))
levels(grp) <- cap(levels(grp))

df <- data.frame(PC1 = coords$PC1, PC2 = coords$PC2, group = grp)
if (anyDuplicated(round(df[, c("PC1", "PC2")], 6)) > 0) {   # break exact ties
  set.seed(42)
  df$PC1 <- jitter(df$PC1, amount = 0.002 * diff(range(df$PC1)))
  df$PC2 <- jitter(df$PC2, amount = 0.002 * diff(range(df$PC2)))
}

per <- read.delim(file.path(div, "permanova_results.tsv"),
                  check.names = FALSE)
mrow <- per[per$Term == "Model", ]
r2 <- as.numeric(mrow$R2)
pv <- suppressWarnings(as.numeric(mrow[["Pr(>F)"]]))
per_lab <- paste0("PERMANOVA\nR\u00b2 = ", sprintf("%.2f", r2),
                  "\n", cns_p_label(pv))

# ---- plot --------------------------------------------------------------------
gcols <- cns_cat[seq_along(levels(grp))]

p <- ggplot(df, aes(x = PC1, y = PC2, fill = group)) +
  geom_hline(yintercept = 0, linetype = "dotted", colour = "grey60",
             linewidth = 0.3) +
  geom_vline(xintercept = 0, linetype = "dotted", colour = "grey60",
             linewidth = 0.3) +
  stat_ellipse(geom = "polygon", level = 0.95, type = "norm",
               alpha = 0.15, colour = NA, show.legend = FALSE) +
  geom_point(shape = 21, colour = "black", stroke = 0.25, size = 1.8,
             show.legend = TRUE) +
  annotate("text", x = Inf, y = Inf, label = per_lab,
           hjust = 1, vjust = 1, size = txt(7.5), lineheight = 0.95,
           colour = "black") +
  scale_fill_manual(values = gcols, name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0.06, 0.06))) +
  scale_y_continuous(expand = expansion(mult = c(0.06, 0.06))) +
  coord_fixed() +
  labs(x = sprintf("PC1 (%.1f%%)", pct[1]),
       y = sprintf("PC2 (%.1f%%)", pct[2])) +
  theme_cns(y_grid = FALSE) +
  theme(legend.position = "bottom",
        legend.direction = "horizontal") +
  guides(fill = guide_legend(override.aes = list(size = 2.4, stroke = 0.4)))

export_pub_figure(p, file.path(out_dir, OUT),
                  width_mm = CNS_W_SINGLE, height_mm = CNS_W_SINGLE,
                  formats = c("pdf", "png"))
message("written: ", file.path(out_dir, paste0(OUT, c(".pdf", ".png"))))
