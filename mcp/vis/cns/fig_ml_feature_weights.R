#!/usr/bin/env Rscript
# ==============================================================================
# fig_ml_feature_weights.R — top-20 SIAMCAT features by mean |weight| as a
# horizontal lollipop with per-fold SD whiskers, CNS single-figure style.
# Layout idea from paid blueprints (venn/lollipop 20250613 + forest 20250723),
# code fully rewritten for this design system.
#
# Usage: Rscript fig_ml_feature_weights.R <workdir> <out_dir> [model]
#   <workdir>  project workdir containing result/stat/bacteria/ml/
#   <out_dir>  destination for ml_feature_weights.{pdf,png}
#   [model]    siamcat model name (default "ridge"; lasso/enet/randomForest)
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("usage: Rscript fig_ml_feature_weights.R <workdir> <out_dir> [model]")
workdir <- normalizePath(args[[1]], mustWork = TRUE)
out_dir <- args[[2]]
model <- if (length(args) >= 3) args[[3]] else "ridge"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]
)))
repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(repo_root, "scripts", "R", "pub_theme.R"))

suppressPackageStartupMessages({ library(SIAMCAT); library(ggplot2) })

rds <- file.path(workdir, "result", "stat", "bacteria", "ml",
                 paste0("siamcat_", model, ".rds"))
sc <- try(readRDS(rds), silent = TRUE)
if (inherits(sc, "try-error")) stop("cannot read ", rds)
fw <- SIAMCAT::feature_weights(sc)
if (is.null(fw) || is.null(fw$mean.weight)) stop("no feature weights in ", rds)

# ---- tidy top-20 table -------------------------------------------------------
lab <- rownames(fw)
if (is.null(lab)) stop("feature weights lack feature names")
d <- data.frame(feature = lab,
                mean = abs(fw$mean.weight),
                sd = abs(fw$sd.weight))
d <- d[order(-d$mean), ][seq_len(min(20, nrow(d))), ]

# "k__Bacteria|p__Firmicutes|c__Clostridia" -> "Firmicutes; Clostridia";
# deep taxa (dotted SHAP-style markers) compacted to their two terminal ranks.
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
wrap30 <- function(x) paste(strwrap(x, 30), collapse = "\n")
d$feat_lab <- vapply(clean_taxa(d$feature), wrap30, character(1))
d$feat_lab <- factor(d$feat_lab, levels = rev(d$feat_lab))

p <- ggplot(d, aes(x = mean, y = feat_lab)) +
  geom_errorbarh(aes(xmin = pmax(mean - sd, 0), xmax = mean + sd),
                 height = 0.35, linewidth = 0.3, colour = "grey55") +
  geom_segment(aes(x = 0, xend = mean, y = feat_lab, yend = feat_lab),
               linewidth = 0.35, colour = cns_cat[1]) +
  geom_point(size = 1.2, colour = cns_cat[1], fill = cns_cat[1],
             shape = 21, stroke = 0.3) +
  scale_x_continuous(expand = expansion(mult = c(0.01, 0.06))) +
  labs(x = "Mean |weight| (10-fold CV)", y = NULL,
       subtitle = NULL) +
  theme_cns(y_grid = TRUE) +
  theme(axis.text.y = element_text(face = "italic", size = 6.5,
                                   lineheight = 0.85))

export_pub_figure(p, file.path(out_dir, "ml_feature_weights"),
                  width_mm = CNS_W_SINGLE, height_mm = 105,
                  formats = c("pdf", "png"))
message("written: ml_feature_weights.{pdf,png} (model: ", model, ", n = ",
        nrow(d), ")")
