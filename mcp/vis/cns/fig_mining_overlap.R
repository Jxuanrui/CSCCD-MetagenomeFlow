#!/usr/bin/env Rscript
# ==============================================================================
# fig_mining_overlap.R — seed source cross-talk: left 3x3 overlap tile heatmap
# (diagonal = per-source final rows, off-diagonal = pairwise sample overlaps,
# annotated integers) + right per-source final-row bars with comma labels.
# All counts come from mining/seed_summary.json (sources + overlap_matrix).
#
# Usage: Rscript fig_mining_overlap.R <repo_root> <out_dir>
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("usage: Rscript fig_mining_overlap.R <repo_root> <out_dir>")
workdir <- normalizePath(args[[1]], mustWork = TRUE)   # repo root
out_dir <- args[[2]]
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]
)))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(normalizePath(file.path(script_dir, "..", "..", "..")),
                 "scripts", "R", "pub_theme.R"))

suppressPackageStartupMessages({ library(ggplot2); library(patchwork) })

js <- jsonlite::fromJSON(file.path(workdir, "mining", "seed_summary.json"),
                         simplifyVector = TRUE)
srcs <- c("cMD3", "GMrepo", "Meta2DB")
final_rows <- vapply(js$sources[srcs],
                     function(s) as.numeric(s$contributed_final_rows),
                     numeric(1))
om <- js$overlap_matrix

m <- matrix(0, length(srcs), length(srcs),
            dimnames = list(srcs, srcs))
m["cMD3", "GMrepo"] <- m["GMrepo", "cMD3"] <- as.numeric(om$cMD3_and_GMrepo)
m["cMD3", "Meta2DB"] <- m["Meta2DB", "cMD3"] <- as.numeric(om$cMD3_and_Meta2DB)
m["GMrepo", "Meta2DB"] <- m["Meta2DB", "GMrepo"] <- as.numeric(om$GMrepo_and_Meta2DB)
diag(m) <- final_rows

tiles <- expand.grid(y = srcs, x = srcs, stringsAsFactors = FALSE)
tiles$n <- m[as.matrix(tiles[c("y", "x")])]
tiles$lab <- format(tiles$n, trim = TRUE, scientific = FALSE)
# white text on dark tiles only (above 60% of the max count)
tiles$txt_col <- ifelse(tiles$n > 0.6 * max(tiles$n), "white", "black")

src_df <- data.frame(source = factor(rev(srcs), levels = rev(srcs)),
                     n = final_rows)

# ---- left: 3x3 overlap tile heatmap ------------------------------------------
p_heat <- ggplot(tiles, aes(x = x, y = factor(y, levels = rev(srcs)),
                            fill = n)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(colour = txt_col, label = lab), size = 7.5 / .pt,
            family = "Arial", fontface = "bold", show.legend = FALSE) +
  scale_colour_identity() +
  # reversed ramp: high counts map to dark purple so white text stays readable
  scale_fill_gradientn(colours = rev(cns_seq(256)), name = "Samples",
                       labels = scales::comma,
                       guide = guide_colourbar(frame.colour = "black",
                                               frame.linewidth = 0.3,
                                               ticks.colour = "black",
                                               ticks.linewidth = 0.3,
                                               barheight = unit(0.8, "null"),
                                               barwidth = unit(1.4, "mm"))) +
  coord_fixed() +
  labs(x = NULL, y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.line = element_blank(), axis.ticks = element_blank(),
        legend.position = "right")

# ---- right: per-source final rows --------------------------------------------
p_bar <- ggplot(src_df, aes(x = n, y = source)) +
  geom_col(fill = cns_cat[1], width = 0.62) +
  geom_text(aes(label = scales::comma(n)), hjust = -0.12, size = 7.5 / .pt,
            family = "Arial", colour = "black") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.17)),
                     labels = scales::comma) +
  labs(x = "Final curated samples", y = NULL) +
  theme_cns(y_grid = FALSE)

p <- p_heat + p_bar + plot_layout(widths = c(1, 1))

export_pub_figure(p, file.path(out_dir, "mining_overlap"),
                  width_mm = CNS_W_DOUBLE, height_mm = 85,
                  formats = c("pdf", "png"))
message("written: mining_overlap.{pdf,png} (diag ",
        paste(final_rows, collapse = "/"),
        "; overlaps ", paste(m[lower.tri(m)], collapse = "/"), ")")
