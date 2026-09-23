#!/usr/bin/env Rscript
# ==============================================================================
# fig_redundancy_heatmap.R — function x species contribution heatmap (CNS).
# Contribution = |Spearman rho| between KO abundance (integration tables) and
# species relative abundance. READABILITY-FIRST redesign: top-10 functions x
# top-15 species, white->blue single-hue fill with the rho value printed in
# every cell, FDI-class strip on the left.
#
# Usage: Rscript fig_redundancy_heatmap.R <workdir> <out_dir>
#   <workdir>  project directory containing result/
#   <out_dir>  output directory (functional_redundancy_heatmap.pdf + .png)
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_redundancy_heatmap.R <workdir> <out_dir>", call. = FALSE)
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

# ---- data --------------------------------------------------------------------
fdi <- read.csv(file.path(workdir,
          "result/stat/bacteria/functional_redundancy/function_dispersion_index.csv"),
          stringsAsFactors = FALSE, check.names = FALSE)
ko <- read.delim(file.path(workdir, "result/integration/bacteria/kegg_ko_abundance.tsv"),
                 check.names = FALSE, quote = "", row.names = 1)
sp <- read.delim(file.path(workdir, "result/stat/bacteria/abundance/species_relabund.tsv"),
                 check.names = FALSE, quote = "", row.names = 1)
common <- intersect(colnames(ko), colnames(sp))
ko <- as.matrix(ko[, common, drop = FALSE])
sp <- as.matrix(sp[, common, drop = FALSE])

fns <- intersect(fdi[["function"]], rownames(ko))
M <- abs(suppressWarnings(cor(t(ko[fns, , drop = FALSE]), t(sp),
                               method = "spearman", use = "pairwise")))

# top-10 functions (most contributors, then FDI); top-15 species by abundance
frk <- fdi[match(fns, fdi[["function"]]), ]
frk <- frk[order(-frk$n_contributors, -frk$fdi), ]
f10 <- head(frk[["function"]], 10)
sp_mean <- rowMeans(sp)
s15 <- names(sort(sp_mean, decreasing = TRUE))[seq_len(15)]
s15 <- s15[order(colMeans(M[f10, s15, drop = FALSE]), decreasing = TRUE)]

q <- quantile(fdi$fdi, c(1 / 3, 2 / 3))
fdi_class <- function(v) factor(
  ifelse(v <= q[[1]], "low", ifelse(v <= q[[2]], "mid", "high")),
  levels = c("low", "mid", "high"))

short_sp <- function(x) {
  last <- sub(".*\\|", "", x)
  parts <- strsplit(last, "_", fixed = TRUE)[[1]]
  if (length(parts) >= 2)
    paste(substr(parts[1], 1, 1), ". ", paste(parts[-1], collapse = " "))
  else gsub("_", " ", last)
}

flv <- rev(f10)  # bottom-to-top
heat <- expand.grid(species = s15, function_ko = flv, stringsAsFactors = FALSE)
heat$rho <- mapply(function(f, s) M[f, s], heat$function_ko, heat$species)
heat$species_lab <- factor(short_sp(heat$species), levels = short_sp(s15))
heat$f <- factor(heat$function_ko, levels = flv)
heat$rho_lab <- ifelse(heat$rho >= 0.005, sprintf("%.2f", heat$rho), "")

anno <- data.frame(f = factor(flv, levels = flv),
                   cls = fdi_class(fdi$fdi[match(flv, fdi[["function"]])]),
                   stringsAsFactors = FALSE)

# ---- panels --------------------------------------------------------------------
p_anno <- ggplot(anno, aes(x = "FDI", y = f, fill = cls)) +
  geom_tile(colour = "white", linewidth = 0.3) +
  scale_fill_manual(values = c(low = cns_cat[3], mid = cns_cat[4],
                               high = cns_cat[2]),
                    name = "FDI class", drop = FALSE,
                    breaks = c("low", "mid", "high")) +
  scale_x_discrete(expand = c(0, 0), position = "top") +
  scale_y_discrete(expand = c(0, 0)) +
  labs(x = NULL, y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.x = element_text(size = 7, face = "bold"),
        axis.ticks.x = element_blank(),
        axis.line = element_blank(),
        axis.text.y = element_text(size = 7),
        plot.margin = margin(2, 0, 2, 2, "mm"))

p_heat <- ggplot(heat, aes(x = species_lab, y = f, fill = rho)) +
  geom_tile(colour = "white", linewidth = 0.4) +
  geom_text(aes(label = rho_lab), size = 6.2 / .pt, colour = "grey25") +
  scale_fill_gradient(low = "#F4F7FB", high = cns_cat[1],
                      limits = c(0, 1), name = expression("|"*rho*"|"),
                      breaks = seq(0, 1, 0.5)) +
  scale_x_discrete(expand = c(0, 0)) +
  scale_y_discrete(expand = c(0, 0)) +
  labs(x = "Top-15 contributor species", y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.x = element_text(face = "italic", size = 7),
        axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        plot.margin = margin(2, 2, 2, 0, "mm"))

p <- p_anno + p_heat +
  plot_layout(widths = c(1, 14), guides = "collect") &
  theme(legend.position = "bottom", legend.box = "horizontal")

export_pub_figure(p, file.path(out_dir, "functional_redundancy_heatmap"),
                  CNS_W_DOUBLE, 110, formats = c("pdf", "png"))

# ---- self-check -----------------------------------------------------------------
message(sprintf("[fig_redundancy_heatmap] matrix %d functions x %d species; shown %d x %d with in-cell values",
                nrow(M), ncol(M), length(f10), length(s15)))
for (f in c("pdf", "png"))
  stopifnot(file.exists(file.path(out_dir, sprintf("functional_redundancy_heatmap.%s", f))))
message("[fig_redundancy_heatmap] OK: functional_redundancy_heatmap.{pdf,png} written")
