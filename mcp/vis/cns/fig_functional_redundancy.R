#!/usr/bin/env Rscript
# ==============================================================================
# fig_functional_redundancy.R — FDI vs max |Spearman rho| scatter for KEGG KO
# functions. Each point is one function; y is its strongest species
# association (recomputed via Spearman KO x species abundances, matching the
# pipeline's correlation_inference contribution method). Loess fit with 85% CI.
#
# Usage: Rscript fig_functional_redundancy.R <workdir> <out_dir>
#   <workdir>  project directory containing result/
#   <out_dir>  output directory (functional_redundancy.pdf + .png)
# ==============================================================================
suppressPackageStartupMessages({
  library(ggplot2)
  library(ggrepel)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("Usage: Rscript fig_functional_redundancy.R <workdir> <out_dir>",
       call. = FALSE)
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

# ---- max |Spearman rho| per function vs all species ---------------------------
fns <- intersect(fdi[["function"]], rownames(ko))
R <- suppressWarnings(cor(t(ko[fns, , drop = FALSE]), t(sp),
                          method = "spearman", use = "pairwise"))
maxrho <- apply(abs(R), 1, max)
df <- data.frame(
  fdi = fdi$fdi[match(fns, fdi[["function"]])],
  maxrho = unname(maxrho[fns]),
  ko = fns,
  stringsAsFactors = FALSE
)
rho_all <- suppressWarnings(cor(df$fdi, df$maxrho, method = "spearman"))
p_all <- suppressWarnings(cor.test(df$fdi, df$maxrho, method = "spearman")$p.value)

# ---- outliers (1.5 x IQR fences on either axis) --------------------------------
fence <- function(v) {
  q <- quantile(v, c(0.25, 0.75)); i <- q[[2]] - q[[1]]
  c(q[[1]] - 1.5 * i, q[[2]] + 1.5 * i)
}
fx <- fence(df$fdi); fy <- fence(df$maxrho)
df$out <- df$fdi < fx[1] | df$fdi > fx[2] | df$maxrho < fy[1] | df$maxrho > fy[2]

# ---- plot ----------------------------------------------------------------------
lab_txt <- sprintf("Spearman rho = %.3f, %s", rho_all, cns_p_label(p_all))
p <- ggplot(df, aes(x = fdi, y = maxrho)) +
  geom_smooth(method = "loess", formula = y ~ x, level = 0.85,
              colour = "black", linewidth = 0.4, fill = "grey55",
              alpha = 0.1) +
  geom_point(colour = cns_cat[1], size = 1, stroke = 0) +
  geom_text_repel(data = df[df$out, ], aes(label = ko),
                  size = 6.5 / ggplot2::.pt, fontface = "italic",
                  colour = "black", segment.size = 0.2,
                  segment.colour = "grey50", min.segment.length = 0,
                  max.overlaps = Inf, show.legend = FALSE) +
  annotate("text", x = -Inf, y = Inf, hjust = -0.1, vjust = 2.4,
           label = lab_txt, size = 7 / ggplot2::.pt, colour = "black") +
  scale_y_continuous(limits = c(NA, 0.95),
                     expand = expansion(mult = c(0.04, 0))) +
  scale_x_continuous(expand = expansion(mult = c(0.04, 0.04))) +
  labs(x = "Functional dispersion index (FDI)",
       y = expression("max |Spearman "*rho*"|")) +
  theme_cns()

export_pub_figure(p, file.path(out_dir, "functional_redundancy"),
                  CNS_W_SINGLE, 72, formats = c("pdf", "png"))

# ---- self-check -----------------------------------------------------------------
message(sprintf("[fig_functional_redundancy] functions plotted: %d; outliers labeled: %d",
                nrow(df), sum(df$out)))
message(sprintf("[fig_functional_redundancy] overall Spearman rho = %.3f (%s)",
                rho_all, cns_p_label(p_all)))
message(sprintf("[fig_functional_redundancy] points cns_cat[1]=%s size 1 | loess 0.4pt CI 85%% alpha 0.1 | %.0f x 72 mm",
                cns_cat[1], CNS_W_SINGLE))
for (f in c("pdf", "png"))
  stopifnot(file.exists(file.path(out_dir, sprintf("functional_redundancy.%s", f))))
message("[fig_functional_redundancy] OK: functional_redundancy.{pdf,png} written")
