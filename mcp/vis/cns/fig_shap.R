#!/usr/bin/env Rscript
# ==============================================================================
# fig_shap.R — SHAP beeswarm summary for the randomForest SIAMCAT model.
# x = SHAP value, y = top-20 features by mean |SHAP|, points coloured by
# per-feature percentile of the feature value (cns_seq gradient).
#
# Usage: Rscript fig_shap.R <workdir> <out_dir>
#   <workdir>  project workdir containing result/stat/bacteria/ml/
#   <out_dir>  destination for shap_summary.{pdf,png}
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: Rscript fig_shap.R <workdir> <out_dir>")
workdir <- normalizePath(args[[1]], mustWork = TRUE)
out_dir <- args[[2]]
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]
)))
repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(repo_root, "scripts", "R", "pub_theme.R"))

suppressPackageStartupMessages({ library(ggplot2) })

shap_tsv <- file.path(workdir, "result", "stat", "bacteria", "ml",
                      "randomForest_shap_values.tsv")
shap <- read.delim(shap_tsv, check.names = FALSE,
                   stringsAsFactors = FALSE)
# long form: sample_id, feature, shap_value, shap_variance, feature.value
shap$fval <- as.numeric(sub("^.*=", "", shap$feature.value))
shap <- shap[is.finite(shap$shap_value) & is.finite(shap$fval), ]

# per-feature percentile of the feature value (across samples)
shap$pct <- stats::ave(shap$fval, shap$feature, FUN = function(x)
  base::rank(x, ties.method = "average") / length(x))

# top-20 features by mean |SHAP|, strongest at the top of the plot
imp <- sort(tapply(abs(shap$shap_value), shap$feature, mean),
            decreasing = TRUE)
top <- names(imp)[seq_len(min(20, length(imp)))]
sub <- shap[shap$feature %in% top, ]

# "k__Bacteria|p__Firmicutes|c__Clostridia" (SIAMCAT) or dotted SHAP markers
# "Bacteria.p__Firmicutes.c__Clostridia" -> "Firmicutes; Clostridia";
# deep taxa are compacted to their two terminal ranks to keep labels short.
clean_taxa <- function(x) {
  parts <- strsplit(x, "[|.]")
  vapply(parts, function(p) {
    ranks <- sub("^[a-z]__", "", p[nzchar(p)])
    ranks <- ranks[ranks != "Bacteria" & nzchar(ranks)]
    lab <- paste(ranks, collapse = "; ")
    if (nchar(lab) > 42 && length(ranks) > 2)
      lab <- paste(tail(ranks, 2), collapse = "; ")
    lab
  }, character(1))
}
wrap34 <- function(x) paste(strwrap(x, 34), collapse = "\n")
lab_map <- vapply(clean_taxa(top), wrap34, character(1))
names(lab_map) <- top
lv <- rev(lab_map[top])                      # top feature first (top row)
sub$y <- match(sub$feature, rev(top))        # 1 = bottom row

# deterministic vertical jitter (identical pdf/png), height 0.25
set.seed(20260922)
sub$yj <- sub$y + stats::runif(nrow(sub), -0.25, 0.25)

p <- ggplot(sub, aes(x = shap_value, y = yj)) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.25,
             colour = "grey50") +
  geom_point(aes(colour = pct), size = 0.7, alpha = 0.85,
             shape = 16, stroke = 0) +
  scale_colour_gradientn(
    colours = cns_seq(256), limits = c(0, 1), breaks = c(0, 1),
    labels = c("Low", "High"), name = "Feature value",
    guide = ggplot2::guide_colourbar(
      barwidth = unit(1.1, "mm"), barheight = unit(20, "mm"),
      frame.colour = "black", frame.linewidth = 0.3,
      ticks.colour = "black", ticks.linewidth = 0.3)) +
  scale_y_continuous(breaks = seq_along(lv), labels = lv, expand = c(0.06, 0)) +
  scale_x_continuous(expand = expansion(mult = c(0.04, 0.16))) +
  labs(x = "SHAP value", y = NULL) +
  theme_cns(y_grid = TRUE) +
  theme(axis.text.y = element_text(face = "italic", size = 6.5,
                                   lineheight = 0.85),
        legend.position = c(0.985, 0.03),
        legend.justification = c(1, 0))

export_pub_figure(p, file.path(out_dir, "shap_summary"),
                  width_mm = CNS_W_SINGLE, height_mm = 105,
                  formats = c("pdf", "png"))
message("written: shap_summary.{pdf,png} (", nrow(sub),
        " points across ", length(top), " features)")
