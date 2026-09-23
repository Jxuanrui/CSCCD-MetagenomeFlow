#!/usr/bin/env Rscript
# ==============================================================================
# fig_alpha_diversity.R — CNS-style 4-panel alpha diversity boxplots.
# Layout idea from blueprint "NC图表复现_从物种组成到多样性": boxplot + jittered
# points + significance bracket per comparison. Rewritten for the theme_cns
# design system; p labels via cns_p_label / cns_stars with a thin bracket.
#
# Usage:   Rscript fig_alpha_diversity.R <workdir> <out_dir>
# Inputs:  <workdir>/result/stat/bacteria/diversity/alpha_diversity.tsv
#          <workdir>/result/stat/metadata.tsv   (rownames + sample_id + group)
# Output:  <out_dir>/alpha_diversity.{pdf,png}  (single-column, 89 mm)
# ==============================================================================
suppressPackageStartupMessages(library(ggplot2))

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

IDX <- c("Observed", "Chao1", "Shannon", "Simpson")
OUT <- "alpha_diversity"
PT_MM <- 25.4 / 72
txt <- function(pt) pt * PT_MM

# ---- data --------------------------------------------------------------------
alpha <- read.delim(file.path(workdir, "result", "stat", "bacteria", "diversity",
                              "alpha_diversity.tsv"),
                    row.names = 1, check.names = FALSE)
meta <- read.delim(file.path(workdir, "result", "stat", "metadata.tsv"),
                   row.names = 1, check.names = FALSE)

grp <- meta[rownames(alpha), "group"]
grp <- factor(grp, levels = sort(unique(grp)))
cap <- function(g) paste0(toupper(substring(g, 1, 1)), substring(g, 2))
levels(grp) <- cap(levels(grp))
glv <- levels(grp)

long <- do.call(rbind, lapply(IDX, function(j)
  data.frame(index = j, group = grp, value = as.numeric(alpha[, j]))))
long$index <- factor(long$index, levels = IDX)

# Wilcoxon rank-sum per index + bracket geometry (2 groups -> single pair).
stat <- do.call(rbind, lapply(IDX, function(j) {
  p <- tryCatch(wilcox.test(alpha[grp == glv[1], j],
                            alpha[grp == glv[2], j],
                            exact = FALSE)$p.value, error = function(e) NA_real_)
  r <- range(long$value[long$index == j], na.rm = TRUE)
  span <- diff(r)
  data.frame(index = j, p = p,
             y = max(r) + 0.10 * span,
             ytxt = max(r) + 0.14 * span,
             drop = 0.025 * span)
}))
stat$lab <- paste0(vapply(stat$p, cns_stars, character(1)), "\n",
                   vapply(stat$p, cns_p_label, character(1)))

segs <- rbind(
  transform(stat, x = 1, xend = 2, yend = stat$y),
  transform(stat, x = 1, xend = 1, yend = stat$y - stat$drop),
  transform(stat, x = 2, xend = 2, yend = stat$y - stat$drop))

# ---- plot --------------------------------------------------------------------
gcols <- cns_cat[seq_along(glv)]

p <- ggplot(long, aes(x = group, y = value, fill = group, colour = group)) +
  geom_boxplot(width = 0.5, linewidth = 0.45, alpha = 0.4,
               outlier.shape = NA, show.legend = FALSE) +
  geom_point(position = position_jitter(width = 0.12, height = 0, seed = 42),
             size = 0.8, alpha = 0.8, show.legend = FALSE) +
  geom_segment(data = segs, aes(x = x, xend = xend, y = y, yend = yend),
               inherit.aes = FALSE, linewidth = 0.3, lineend = "butt",
               colour = "black") +
  geom_text(data = stat, aes(x = 1.5, y = ytxt, label = lab),
            inherit.aes = FALSE, size = txt(6.8), lineheight = 0.9,
            colour = "black") +
  scale_fill_manual(values = gcols) +
  scale_colour_manual(values = gcols) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.30))) +
  facet_wrap(~ index, ncol = 2, scales = "free_y") +
  labs(x = NULL, y = "Alpha diversity index") +
  theme_cns() +
  theme(legend.position = "none")

export_pub_figure(p, file.path(out_dir, OUT),
                  width_mm = CNS_W_SINGLE, height_mm = 82,
                  formats = c("pdf", "png"))
message("written: ", file.path(out_dir, paste0(OUT, c(".pdf", ".png"))))
