#!/usr/bin/env Rscript
# ==============================================================================
# fig_pathway_activity.R — butterfly bubble plot of treat-discriminating
# pathways (MetaCyc, HUMAnN3). Control mean extends left, treat mean extends
# right from a shared centre axis; bubble area = mean pathway coverage.
#
# Usage: Rscript fig_pathway_activity.R <workdir> <out_dir>
#   <workdir>  project directory containing result/humann3/ and result/stat/
#   <out_dir>  output directory (pathway_activity.pdf + pathway_activity.png)
# ==============================================================================
suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_pathway_activity.R <workdir> <out_dir>", call. = FALSE)
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
meta <- read.delim(file.path(workdir, "result/stat/metadata.tsv"),
                   check.names = FALSE, quote = "")
samples <- meta$sample_id
groups <- meta$group

read_humann <- function(field) {
  do.call(rbind, lapply(samples, function(s) {
    f <- file.path(workdir, "result/humann3", s,
                   paste0(s, "_path", field, ".tsv"))
    d <- read.delim(f, check.names = FALSE, quote = "")
    keep <- !grepl("^UN(MAPPED|INTEGRATED)", d[[1]])
    data.frame(pathway = d[[1]][keep], sample = s, value = d[[2]][keep],
               stringsAsFactors = FALSE)
  }))
}
ab <- read_humann("abundance"); names(ab)[3] <- "abundance"
cv <- read_humann("coverage");  names(cv)[3] <- "coverage"
ab$group <- groups[match(ab$sample, samples)]

# ---- rank pathways by treatment discrimination -------------------------------
gm <- tapply(ab$abundance, list(ab$pathway, ab$group), mean)
cov_mean <- tapply(cv$coverage, cv$pathway, mean)
pvals <- vapply(split(ab, ab$pathway), function(d)
  tryCatch(wilcox.test(abundance ~ group, d)$p.value,
           error = function(e) NA_real_), numeric(1))
stats <- data.frame(
  pathway = rownames(gm),
  control = gm[, "control"],
  treat = gm[, "treat"],
  coverage = cov_mean[rownames(gm)],
  p = pvals[rownames(gm)],
  row.names = NULL, stringsAsFactors = FALSE
)
stats$log2fc <- log2((stats$treat + 1) / (stats$control + 1))
top <- head(stats[order(stats$p, -abs(stats$log2fc)), ], 10)

# ---- butterfly table -----------------------------------------------------------
wrap_lab <- function(x, w = 38) paste(strwrap(x, w), collapse = "\n")
top$lab <- vapply(top$pathway, wrap_lab, character(1))
# y levels ascending in log2FC so treat-enriched pathways sit on top
lv <- top$lab[order(top$log2fc)]
top$f <- factor(top$lab, levels = lv)

plot_df <- rbind(
  data.frame(f = top$f, group = "control", mean = -top$control,
             coverage = top$coverage, stringsAsFactors = FALSE),
  data.frame(f = top$f, group = "treat",   mean =  top$treat,
             coverage = top$coverage, stringsAsFactors = FALSE)
)
plot_df$group <- factor(plot_df$group, levels = c("control", "treat"))

# ---- plot ----------------------------------------------------------------------
lim <- max(abs(range(plot_df$mean, na.rm = TRUE))) * 1.06
brks <- unique(c(-rev(pretty(c(0, lim))), pretty(c(0, lim))))
p <- ggplot(plot_df, aes(x = mean, y = f)) +
  geom_hline(yintercept = seq_along(lv), colour = "#E9E9E9", linewidth = 0.25) +
  geom_vline(xintercept = 0, colour = "black", linewidth = 0.3) +
  geom_point(aes(size = coverage, fill = group), shape = 21,
             colour = "black", stroke = 0.3, alpha = 0.85) +
  scale_fill_manual(values = c(control = cns_cat[1], treat = cns_cat[2]),
                    name = NULL, breaks = c("control", "treat")) +
  scale_size_continuous(range = c(1.5, 4), name = "Pathway coverage",
                        breaks = round(pretty(range(top$coverage), n = 3), 2)) +
  scale_x_continuous(limits = c(-lim, lim), breaks = brks,
                     labels = function(v) format(abs(v), big.mark = ",",
                                                 trim = TRUE),
                     expand = c(0, 0)) +
  labs(x = "Mean pathway abundance (RPKM)", y = NULL) +
  guides(fill = guide_legend(override.aes = list(size = 2.5))) +
  theme_cns() +
  theme(axis.text.y = element_text(size = 7, lineheight = 0.85),
        legend.position = "bottom", legend.box = "horizontal")

export_pub_figure(p, file.path(out_dir, "pathway_activity"),
                  CNS_W_DOUBLE, 105, formats = c("pdf", "png"))

# ---- self-check -----------------------------------------------------------------
message(sprintf("[fig_pathway_activity] pathways tested: %d; top %d shown",
                nrow(stats), nrow(top)))
message(sprintf("[fig_pathway_activity] palette control=%s treat=%s | size=coverage range 1.5-4 mm | %.0f x 105 mm",
                cns_cat[1], cns_cat[2], CNS_W_DOUBLE))
for (f in c("pdf", "png"))
  stopifnot(file.exists(file.path(out_dir, sprintf("pathway_activity.%s", f))))
message("[fig_pathway_activity] OK: pathway_activity.{pdf,png} written")
