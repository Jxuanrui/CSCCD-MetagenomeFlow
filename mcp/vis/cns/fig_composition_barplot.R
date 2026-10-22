#!/usr/bin/env Rscript
# ==============================================================================
# fig_composition_barplot.R — CNS-style group-mean stacked taxonomic composition.
# Layout idea from blueprints "轻松搞定分组物种组成图" / "NC图表复现_从物种组成
# 到多样性" / "nature图表复现_多重注释物种组成图": vertical 100% stacked bars,
# percent-clean y axis, taxa ordered by overall abundance, "Others" in neutral
# gray last. All styling/code rewritten for the theme_cns design system.
#
# Usage:   Rscript fig_composition_barplot.R <workdir> <out_dir>
# Inputs:  <workdir>/result/stat/bacteria/abundance/genus_relabund.tsv
#          <workdir>/result/stat/metadata.tsv   (rownames + sample_id + group)
# Output:  <out_dir>/composition_barplot.{pdf,png}  (double-column, 183 mm)
# ==============================================================================
suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
workdir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "."
out_dir <- if (length(args) >= 2 && nzchar(args[2])) args[2] else
  file.path(workdir, "result", "figure")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Locate this script so theme_cns.R / pub_theme.R resolve env-independently.
.ca <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .ca, value = TRUE)
script_dir <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]))) else getwd()
source(file.path(script_dir, "theme_cns.R"))
source(file.path(script_dir, "..", "..", "..", "scripts", "R", "pub_theme.R"))

TOP_N  <- 15
RANK   <- "genus"
OUT    <- "composition_barplot"

# ---- data --------------------------------------------------------------------
ab <- read.delim(file.path(workdir, "result", "stat", "bacteria", "abundance",
                           paste0(RANK, "_relabund.tsv")),
                 row.names = 1, check.names = FALSE)
meta <- read.delim(file.path(workdir, "result", "stat", "metadata.tsv"),
                   row.names = 1, check.names = FALSE)

tax <- sub("^.*\\|", "", rownames(ab))           # last rank token of lineage
tax[!nzchar(tax)] <- "Unclassified"
mat <- rowsum(ab, group = tax, reorder = FALSE)  # merge duplicate labels if any

grp <- meta[colnames(mat), "group"]
grp <- factor(grp, levels = sort(unique(grp)))
cap <- function(g) paste0(toupper(substring(g, 1, 1)), substring(g, 2))
levels(grp) <- cap(levels(grp))

# Top-N taxa by overall mean abundance; rest -> "Others".
overall <- sort(rowMeans(mat, na.rm = TRUE), decreasing = TRUE)
top <- names(overall)[seq_len(min(TOP_N, length(overall)))]
lab <- ifelse(rownames(mat) %in% top, rownames(mat), "Others")
taxon_lv <- c(top, "Others")

# Group means (taxa x group), merged through the same top/Others mapping.
gmean <- vapply(levels(grp), function(g)
  rowMeans(mat[, which(grp == g), drop = FALSE], na.rm = TRUE),
  numeric(nrow(mat)))
agg <- rowsum(gmean, group = lab, reorder = FALSE)

df <- data.frame(
  group_lab = factor(rep(sprintf("%s (n = %d)", levels(grp), as.integer(table(grp))),
                         each = nrow(agg))),
  taxon = factor(rep(rownames(agg), times = ncol(agg)), levels = taxon_lv),
  ab = as.numeric(agg))

# ---- plot --------------------------------------------------------------------
cols <- cns_fill_discrete(length(taxon_lv))      # last entry = Others gray

p <- ggplot(df, aes(x = "Mean", y = ab, fill = taxon)) +
  geom_col(width = 0.52, colour = NA) +
  facet_wrap(~ group_lab, nrow = 1) +
  scale_fill_manual(values = cols, name = NULL) +
  # ggplot2 >= 3.5 stacks first level at top; default legend (no reverse)
  # therefore matches the stack top-to-bottom exactly.
  scale_y_continuous(breaks = seq(0, 1, 0.25),
                     expand = expansion(mult = c(0, 0))) +
  coord_cartesian(ylim = c(0, 1)) +
  labs(x = NULL, y = "Relative abundance") +
  theme_cns() +
  theme(axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        legend.position = "right",
        legend.text = element_text(face = "italic"),   # genus names italic
        legend.key.height = unit(3.6, "mm"),
        strip.text = element_text(face = "bold"))

export_pub_figure(p, file.path(out_dir, OUT),
                  width_mm = CNS_W_DOUBLE, height_mm = 95,
                  formats = c("pdf", "png"))
message("written: ", file.path(out_dir, paste0(OUT, c(".pdf", ".png"))))
