#!/usr/bin/env Rscript
# ==============================================================================
# fig_lefse_barplot.R — LEfSe LDA bar plot (diverging, CNS single-figure style).
# Usage: Rscript fig_lefse_barplot.R <workdir> <out_dir>
# Input : <workdir>/result/stat/bacteria/lefse/lefse_results.tsv
#         (fallback: result/stat/bacteria/differential/lefse_results.tsv)
# Output: <out_dir>/lefse_barplot.{pdf,png}
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_lefse_barplot.R <workdir> <out_dir>")
workdir <- normalizePath(args[1])
outdir  <- args[2]
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(script_dir, "../../../scripts/R/pub_theme.R"))

# ---- data --------------------------------------------------------------------
lefse_path <- file.path(workdir, "result/stat/bacteria/lefse/lefse_results.tsv")
if (!file.exists(lefse_path))
  lefse_path <- file.path(workdir,
    "result/stat/bacteria/differential/lefse_results.tsv")
l <- read.delim(lefse_path, check.names = FALSE, stringsAsFactors = FALSE)
names(l)[names(l) == "feature" | names(l) == "Taxa"] <- "feature"
names(l)[names(l) == "lda_score" | names(l) == "LDA_score"] <- "lda"
names(l)[names(l) == "enriched_group" | names(l) == "Group"] <- "grp"

taxon_name <- function(lineage) {
  parts <- strsplit(lineage, "|", fixed = TRUE)[[1]]
  gsub("_", " ", sub("^[a-z]__", "", parts[length(parts)]))
}

# Drop shadow lineages: a prefix kept only when its clade is not already
# represented by a deeper lineage with the identical LDA score and group.
l <- l[order(l$lda, decreasing = TRUE, -nchar(l$feature)), ]
kept <- character(0)
drop <- logical(nrow(l))
for (i in seq_len(nrow(l))) {
  pref <- l$feature[i]
  if (any(startsWith(kept, paste0(pref, "|")))) drop[i] <- TRUE else
    kept <- c(kept, pref)
}
l <- l[!drop, ]

l <- head(l[order(l$lda, decreasing = TRUE), ], 25)         # top-25 |LDA|
l$name  <- vapply(l$feature, taxon_name, character(1))
l$x     <- ifelse(l$grp == levels(factor(l$grp))[1], -l$lda, l$lda)  # 1st level left
grp_lv  <- levels(factor(l$grp))
l$name  <- factor(l$name, levels = l$name[order(l$x)])
l$grp   <- factor(l$grp, levels = grp_lv)

grp_cols <- setNames(cns_cat[seq_along(grp_lv)], grp_lv)

# ---- plot --------------------------------------------------------------------
p <- ggplot(l, aes(x = x, y = name, fill = grp)) +
  geom_col(width = 0.68, colour = NA, show.legend = TRUE) +
  geom_vline(xintercept = 0, linewidth = 0.3, colour = "black") +
  scale_fill_manual(values = grp_cols, name = "Enriched group") +
  scale_x_continuous(limits = c(-5.2, 5.2),
                     breaks = seq(-4, 4, 2), labels = abs) +
  labs(x = "LDA score (log10)", y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.y = element_text(face = "italic",
                                   size = 6.5, lineheight = 0.85),
        legend.position = "bottom",
        legend.title = element_text(size = 8),
        legend.text = element_text(size = 7)) +
  guides(fill = guide_legend(override.aes = list(colour = grp_cols),
                             nrow = 1, keywidth = unit(4, "mm")))

export_pub_figure(p, file.path(outdir, "lefse_barplot"),
                  width_mm = CNS_W_SINGLE, height_mm = 95,
                  formats = c("pdf", "png"))
