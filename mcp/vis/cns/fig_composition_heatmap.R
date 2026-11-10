#!/usr/bin/env Rscript
# ==============================================================================
# fig_composition_heatmap.R — CNS-style discrete-sample abundance heatmap.
# Layout idea from blueprints "跟着nature_microbiology学绘制离散热图" /
# "nature_microbiology风格热图": top annotation strip (group colors, in-strip
# labels), white hairline cell borders, fixed deterministic ordering (group
# blocks, then within-group abundance) instead of dendrograms. Styling/code
# rewritten for the theme_cns design system (cns_seq continuous fill).
#
# Usage:   Rscript fig_composition_heatmap.R <workdir> <out_dir>
# Inputs:  <workdir>/result/stat/bacteria/abundance/genus_relabund.tsv
#          <workdir>/result/stat/metadata.tsv   (rownames + sample_id + group)
# Output:  <out_dir>/composition_heatmap.{pdf,png}  (double-column, 183 mm)
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
})

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

TOP_N <- 30
RANK  <- "genus"
OUT   <- "composition_heatmap"
PT_MM <- 25.4 / 72                    # 1 pt in mm (ggplot linewidth/size is mm)
txt   <- function(pt) pt * PT_MM      # geom_text size from points

# ---- data --------------------------------------------------------------------
ab <- read.delim(file.path(workdir, "result", "stat", "bacteria", "abundance",
                           paste0(RANK, "_relabund.tsv")),
                 row.names = 1, check.names = FALSE)
meta <- read.delim(file.path(workdir, "result", "stat", "metadata.tsv"),
                   row.names = 1, check.names = FALSE)

tax <- sub("^.*\\|", "", rownames(ab))
tax[!nzchar(tax)] <- "Unclassified"
mat <- as.matrix(rowsum(ab, group = tax, reorder = FALSE))

grp <- meta[colnames(mat), "group"]
grp <- factor(grp, levels = sort(unique(grp)))
cap <- function(g) paste0(toupper(substring(g, 1, 1)), substring(g, 2))
levels(grp) <- cap(levels(grp))

top <- names(sort(rowMeans(mat, na.rm = TRUE), decreasing = TRUE))[
  seq_len(min(TOP_N, nrow(mat)))]
sub <- mat[top, , drop = FALSE]                        # taxa x samples

# Sample order: group blocks, then descending mean abundance of the top set.
sord <- unlist(lapply(levels(grp), function(g) {
  idx <- which(grp == g)
  colnames(sub)[idx][order(colMeans(sub[, idx, drop = FALSE]),
                           decreasing = TRUE)]
}), use.names = FALSE)
grp_o <- grp[match(sord, colnames(mat))]   # factor() drops names -> match

long <- data.frame(
  sample = factor(rep(sord, each = nrow(sub)), levels = sord),
  taxon  = factor(rep(rownames(sub), times = ncol(sub)), levels = rev(top)),
  ab     = as.numeric(sub))

ann <- data.frame(sample = factor(sord, levels = sord), group = grp_o)
ctr <- data.frame(
  x = as.numeric(tapply(as.numeric(ann$sample), ann$group, mean)),
  label = levels(grp))

# Identical continuous x scales on both panels -> patchwork aligns them 1:1.
n  <- length(sord)
xn <- seq_len(n)
xscale <- scale_x_continuous(breaks = xn, labels = sord,
                             limits = c(0.5, n + 0.5),
                             expand = expansion(add = 0.6))

# ---- panels ------------------------------------------------------------------
p_ann <- ggplot(ann, aes(x = as.numeric(sample), y = 1)) +
  geom_tile(aes(fill = group), colour = "white", linewidth = 0.2 * PT_MM) +
  geom_text(data = ctr, aes(x = x, y = 1, label = label),
            colour = "white", fontface = "bold", size = txt(6.5)) +
  scale_fill_manual(values = cns_cat[seq_along(levels(grp))], name = NULL) +
  xscale +
  scale_y_continuous(expand = expansion(c(0, 0))) +
  labs(x = NULL, y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.line = element_blank(), axis.ticks = element_blank(),
        axis.text = element_blank(),
        legend.key.height = unit(3.6, "mm"))

p_heat <- ggplot(long, aes(x = as.numeric(sample), y = taxon, fill = ab)) +
  geom_tile(colour = "white", linewidth = 0.2 * PT_MM) +
  xscale +
  scale_fill_gradientn(colours = cns_seq(64), trans = "sqrt",
                       name = "Relative abundance",
                       labels = function(x) sprintf("%.2f", x)) +
  labs(x = NULL, y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.line = element_blank(), axis.ticks = element_blank(),
        axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1,
                                   size = 6.5),
        axis.text.y = element_text(face = "italic"),
        legend.key.height = unit(12, "mm"),
        legend.key.width = unit(3.2, "mm"))

fig <- p_ann / p_heat + plot_layout(heights = c(1.4, length(top)))

export_pub_figure(fig, file.path(out_dir, OUT),
                  width_mm = CNS_W_DOUBLE, height_mm = 118,
                  formats = c("pdf", "png"))
message("written: ", file.path(out_dir, paste0(OUT, c(".pdf", ".png"))))
