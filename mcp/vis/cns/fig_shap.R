#!/usr/bin/env Rscript
# ==============================================================================
# fig_shap.R — SHAP summary via the shapviz package (user-specified).
# sv_importance beeswarm: x = SHAP value, y = top-20 features by mean |SHAP|,
# points coloured by feature value, restyled on theme_cns.
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

suppressPackageStartupMessages({ library(ggplot2); library(shapviz) })

shap_tsv <- file.path(workdir, "result", "stat", "bacteria", "ml",
                      "randomForest_shap_values.tsv")
shap <- read.delim(shap_tsv, check.names = FALSE, stringsAsFactors = FALSE)
# long form: sample_id, feature, shap_value, shap_variance, feature.value
shap$fval <- as.numeric(sub("^.*=", "", shap$feature.value))
shap <- shap[is.finite(shap$shap_value) & is.finite(shap$fval), ]

# top-20 features by mean |SHAP|, strongest at the top of the plot
imp <- sort(tapply(abs(shap$shap_value), shap$feature, mean),
            decreasing = TRUE)
top <- names(imp)[seq_len(min(20, length(imp)))]
sub <- shap[shap$feature %in% top, ]

# SIAMCAT/dotted lineage labels -> compact readable names (same rules as the
# rest of the CNS layer: terminal two ranks for deep taxa, italic-friendly).
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
lab_map <- clean_taxa(top); names(lab_map) <- top
sub$feature_lab <- unname(lab_map[sub$feature])

# shapviz wide matrices: rows = samples, one column per (labelled) feature
sv_shap  <- unclass(xtabs(shap_value ~ sample_id + feature_lab, data = sub))
sv_fval  <- unclass(xtabs(fval ~ sample_id + feature_lab, data = sub))
# xtabs attaches names(dimnames); shapviz's internal melt expects plain ones
names(dimnames(sv_shap)) <- NULL
names(dimnames(sv_fval)) <- NULL
sv <- shapviz(sv_shap, X = sv_fval)

p <- sv_importance(sv, kind = "beeswarm",
                   size = 6.5 / .pt, alpha = 0.85) +
  scale_x_continuous(expand = expansion(mult = c(0.03, 0.08))) +
  ggplot2::coord_cartesian(clip = "on") +
  labs(x = "SHAP value (impact on model output)") +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.y = element_text(face = "italic", size = 6.5),
        legend.position = "right",
        legend.key.height = unit(14, "mm"),
        legend.key.width = unit(2.2, "mm"),
        legend.title = element_text(size = 7.5, angle = 0),
        legend.margin = margin(0, 0, 0, 0, "mm"),
        plot.margin = margin(3, 6, 3, 2, "mm"))

export_pub_figure(p, file.path(out_dir, "shap_summary"),
                  120, 105, formats = c("pdf", "png"))

message(sprintf("[fig_shap] shapviz beeswarm: %d features x %d samples",
                ncol(sv_shap), nrow(sv_shap)))
for (f in c("pdf", "png"))
  stopifnot(file.exists(file.path(out_dir, sprintf("shap_summary.%s", f))))
message("[fig_shap] OK: shap_summary.{pdf,png} written (shapviz)")
