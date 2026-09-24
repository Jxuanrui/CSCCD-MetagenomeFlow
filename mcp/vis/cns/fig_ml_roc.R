#!/usr/bin/env Rscript
# ==============================================================================
# fig_ml_roc.R — multi-model ROC comparison (SIAMCAT lasso/ridge/enet/randomForest)
# in CNS single-figure style. Direct end-of-curve labels "MODEL AUC", no legend.
#
# Usage: Rscript fig_ml_roc.R <workdir> <out_dir>
#   <workdir>  project workdir containing result/stat/bacteria/ml/
#   <out_dir>  destination for ml_roc.{pdf,png}
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: Rscript fig_ml_roc.R <workdir> <out_dir>")
workdir <- normalizePath(args[[1]], mustWork = TRUE)
out_dir <- args[[2]]
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]
)))
repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(repo_root, "scripts", "R", "pub_theme.R"))

suppressPackageStartupMessages({
  library(SIAMCAT); library(ggplot2)
})

ml_dir <- file.path(workdir, "result", "stat", "bacteria", "ml")
models <- c(lasso = "LASSO", ridge = "Ridge", enet = "Enet",
            randomForest = "Random forest")

# ---- collect ROC curves (pROC object inside eval_data) -----------------------
curve_rows <- list(); aucs <- numeric(0)
for (m in names(models)) {
  rds <- file.path(ml_dir, paste0("siamcat_", m, ".rds"))
  sc <- try(readRDS(rds), silent = TRUE)
  ev <- if (!inherits(sc, "try-error"))
    try(SIAMCAT::eval_data(sc), silent = TRUE) else NULL
  roc <- if (!inherits(ev, "try-error") && !is.null(ev)) ev$roc else NULL
  if (is.null(roc) || is.null(roc$specificities)) next
  d <- data.frame(fpr = 1 - as.numeric(roc$specificities),
                  sens = as.numeric(roc$sensitivities))
  d <- d[order(d$fpr, d$sens), ]
  curve_rows[[m]] <- data.frame(fpr = d$fpr, sens = d$sens,
                                model = models[[m]])
  aucs[m] <- suppressWarnings(as.numeric(ev$auroc))
}
if (!length(curve_rows)) stop("no evaluable ROC curves found in ", ml_dir)
roc_df <- do.call(rbind, curve_rows)
roc_df$model <- factor(roc_df$model, levels = models[models %in% roc_df$model])

# ---- deterministic direct labels "MODEL AUC" at mid-curve anchors ------------
# (manual stacking instead of ggrepel: identical placement in pdf and png)
anchor <- do.call(rbind, lapply(names(aucs), function(m) {
  d <- curve_rows[[m]]
  i <- which.min(abs(d$fpr - 0.35))
  data.frame(fpr = d$fpr[i], sens = d$sens[i], model = factor(models[[m]],
    levels = levels(roc_df$model)),
    label = sprintf("%s %.2f", models[[m]], aucs[[m]]))
}))
anchor$lx <- anchor$fpr + 0.045
o <- order(-anchor$sens)
ylab <- anchor$sens[o]
for (i in seq_along(ylab)[-1])
  ylab[i] <- min(ylab[i], ylab[i - 1] - 0.085)   # stack downwards
anchor$ylab <- NA_real_
anchor$ylab[o] <- pmax(ylab, 0.03)

pal <- setNames(cns_cat[seq_len(nlevels(roc_df$model))], levels(roc_df$model))

p <- ggplot(roc_df, aes(fpr, sens, colour = model)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed",
              colour = "grey70", linewidth = 0.25) +
  geom_path(linewidth = 0.35, show.legend = FALSE) +
  geom_segment(data = anchor, show.legend = FALSE,
               aes(x = fpr + 0.01, y = sens, xend = lx - 0.006, yend = ylab),
               colour = "grey55", linewidth = 0.25, inherit.aes = FALSE) +
  geom_point(data = anchor, show.legend = FALSE,
             aes(x = fpr, y = sens, colour = model), size = 0.9,
             inherit.aes = FALSE) +
  geom_text(data = anchor, show.legend = FALSE,
            aes(x = lx, y = ylab, colour = model, label = label),
            hjust = 0, vjust = 0.5, size = 6.8 / .pt, family = "Arial",
            inherit.aes = FALSE) +
  scale_colour_manual(values = pal, guide = "none") +
  scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1),
                     expand = expansion(mult = c(0.01, 0.14))) +
  scale_y_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1),
                     expand = expansion(mult = c(0.01, 0.02))) +
  coord_equal() +
  labs(x = "1 \u2212 Specificity", y = "Sensitivity") +
  theme_cns(y_grid = FALSE)

export_pub_figure(p, file.path(out_dir, "ml_roc"),
                  width_mm = CNS_W_SINGLE, height_mm = CNS_W_SINGLE,
                  formats = c("pdf", "png"))
message("written: ml_roc.{pdf,png} (AUC: ",
        paste(sprintf("%s %.2f", models[names(aucs)], aucs), collapse = ", "),
        ")")
