#!/usr/bin/env Rscript
# ==============================================================================
# fig_redundancy_heatmap.R — function x species contribution heatmap.
# Contribution = |Spearman rho| between KO abundance (integration tables) and
# species relative abundance (pipeline's correlation_inference method).
# Top-25 functions (by contributor count then FDI) x top-20 species (by mean
# abundance), with a left annotation strip for FDI class (low/mid/high).
#
# Usage: Rscript fig_redundancy_heatmap.R <workdir> <out_dir>
#   <workdir>  project directory containing result/
#   <out_dir>  output directory (redundancy_heatmap.pdf + redundancy_heatmap.png)
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

# ---- contribution proxy: |Spearman rho| KO x species ----------------------------
fns <- intersect(fdi[["function"]], rownames(ko))
M <- abs(suppressWarnings(cor(t(ko[fns, , drop = FALSE]), t(sp),
                               method = "spearman", use = "pairwise")))

# top-25 functions: most contributors first, then highest FDI
frk <- fdi[match(fns, fdi[["function"]]), ]
frk <- frk[order(-frk$n_contributors, -frk$fdi), ]
f25 <- head(frk[["function"]], 25)
# top-20 species by mean abundance, columns ordered by mean contribution
sp_mean <- rowMeans(sp)
s20 <- names(sort(sp_mean, decreasing = TRUE))[seq_len(20)]
s20 <- s20[order(colMeans(M[f25, s20, drop = FALSE]), decreasing = TRUE)]

# ---- FDI class (terciles over all functions) -------------------------------------
q <- quantile(fdi$fdi, c(1 / 3, 2 / 3))
fdi_class <- function(v) factor(
  ifelse(v <= q[[1]], "low", ifelse(v <= q[[2]], "mid", "high")),
  levels = c("low", "mid", "high"))

# ---- long tables ------------------------------------------------------------------
short_sp <- function(x) {
  last <- sub(".*\\|", "", x)
  parts <- strsplit(last, "_", fixed = TRUE)[[1]]
  if (length(parts) >= 2)
    paste(substr(parts[1], 1, 1), ". ", paste(parts[-1], collapse = " "))
  else gsub("_", " ", last)
}
flv <- rev(f25)                       # bottom-to-top on the y axis
heat <- expand.grid(species = s20, function_ko = flv, stringsAsFactors = FALSE)
heat$rho <- mapply(function(f, s) M[f, s], heat$function_ko, heat$species)
heat$species_lab <- factor(short_sp(heat$species), levels = short_sp(s20))
heat$f <- factor(heat$function_ko, levels = flv)

anno <- data.frame(f = factor(flv, levels = flv),
                   cls = fdi_class(fdi$fdi[match(flv, fdi[["function"]])]),
                   stringsAsFactors = FALSE)

# ---- panels ------------------------------------------------------------------------
p_anno <- ggplot(anno, aes(x = "FDI\nclass", y = f, fill = cls)) +
  geom_tile(colour = "white", linewidth = 0.3) +
  scale_fill_manual(values = c(low = cns_cat[3], mid = cns_cat[4],
                               high = cns_cat[2]),
                    name = "FDI class", drop = FALSE,
                    breaks = c("low", "mid", "high"),
                    labels = c("low", "mid", "high")) +
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
  geom_tile(colour = "white", linewidth = 0.3) +
  scale_fill_gradientn(colours = cns_seq(100), limits = c(0, 1),
                       name = expression("|"*rho*"|"),
                       breaks = seq(0, 1, 0.25)) +
  scale_x_discrete(expand = c(0, 0)) +
  scale_y_discrete(expand = c(0, 0)) +
  labs(x = "Top-20 contributor species", y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, face = "italic",
                                   size = 7),
        axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        plot.margin = margin(2, 2, 2, 0, "mm"))

p <- p_anno + p_heat +
  plot_layout(widths = c(1, 26), guides = "collect") &
  theme(legend.position = "bottom", legend.box = "horizontal")

export_pub_figure(p, file.path(out_dir, "redundancy_heatmap"),
                  CNS_W_DOUBLE, 150, formats = c("pdf", "png"))

# ---- self-check -----------------------------------------------------------------
message(sprintf("[fig_redundancy_heatmap] matrix %d functions x %d species; shown %d x %d",
                nrow(M), ncol(M), length(f25), length(s20)))
message(sprintf("[fig_redundancy_heatmap] FDI class colours low=%s mid=%s high=%s | fill cns_seq | %.0f x 150 mm",
                cns_cat[3], cns_cat[4], cns_cat[2], CNS_W_DOUBLE))
for (f in c("pdf", "png"))
  stopifnot(file.exists(file.path(out_dir, sprintf("redundancy_heatmap.%s", f))))
message("[fig_redundancy_heatmap] OK: redundancy_heatmap.{pdf,png} written")
