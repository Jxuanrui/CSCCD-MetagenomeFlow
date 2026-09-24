# ==============================================================================
# theme_cns.R — shared design system for CNS-style single figures.
# Companion to scripts/R/pub_theme.R: reuse its export_pub_figure() for
# the dual PDF+PNG devices; this module fixes the LOOK so every gallery
# figure is pixel-consistent and stackable into user-assembled composites.
#
# Conventions (do not deviate per-figure):
#   - axes/ticks 0.3 pt black, no panel border, no background fill
#   - Arial: axis text 7.5 pt, axis title 8.5 pt bold, title 9.5 pt bold,
#     tag 10 pt bold, legend text 7 pt / title 8 pt
#   - optional y-only major grid, 0.25 pt #E9E9E9
#   - sizes: single-column 89 mm, double-column 183 mm
#   - palettes: cns_cat (categorical), cns_seq (sequential), cns_div (diverging)
# ==============================================================================

mm2in <- function(x) x / 25.4  # also in pub_theme.R; harmless re-def

CNS_W_SINGLE <- 89   # mm
CNS_W_DOUBLE <- 183  # mm

# Categorical palette: muted Nature/NEJM-leaning hues (8), colorblind-ordered.
cns_cat <- c(
  "#2F5C9E",  # muted blue
  "#C0392B",  # brick red
  "#1B9E9E",  # teal
  "#E3A008",  # amber
  "#7B5EA7",  # muted purple
  "#5E8C61",  # sage green
  "#C96DA8",  # rose
  "#8A8F98"   # neutral gray
)

# Sequential (viridis-family gradient) and diverging (RdBu) ramps.
cns_seq <- function(n) {
  grDevices::colorRampPalette(c(
    "#440154", "#3B528B", "#21918C", "#5EC962", "#FDE725"
  ))(n)
}
cns_div <- function(n) {
  grDevices::colorRampPalette(c("#2166AC", "#F7F7F7", "#B2182B"))(n)
}

# Fill scale for grouped compositions ("Others" always neutral gray).
cns_fill_discrete <- function(n, others = "Others") {
  cols <- if (n <= length(cns_cat)) cns_cat[seq_len(n)] else
    grDevices::colorRampPalette(cns_cat)(n)
  if (!is.null(others)) cols[length(cols)] <- "#C9CDD3"
  cols
}

theme_cns <- function(base_size = 7.5, base_family = "Arial",
                      y_grid = TRUE) {
  ggplot2::theme_classic(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      axis.line = ggplot2::element_line(linewidth = 0.3, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = 0.3, colour = "black"),
      axis.ticks.length = ggplot2::unit(1.2, "mm"),
      axis.title = ggplot2::element_text(size = base_size + 1, face = "bold",
                                         colour = "black"),
      axis.text = ggplot2::element_text(size = base_size, colour = "black"),
      panel.border = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      plot.background = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank(),
      panel.grid.major.y = if (y_grid)
        ggplot2::element_line(linewidth = 0.25, colour = "#E9E9E9") else
        ggplot2::element_blank(),
      legend.title = ggplot2::element_text(size = base_size + 0.5),
      legend.text = ggplot2::element_text(size = base_size - 0.5),
      legend.key.size = ggplot2::unit(3.2, "mm"),
      legend.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(size = base_size + 1, face = "bold"),
      plot.title = ggplot2::element_text(size = base_size + 2, face = "bold",
                                         hjust = 0),
      plot.tag = ggplot2::element_text(size = base_size + 2.5, face = "bold"),
      plot.margin = ggplot2::margin(2, 2, 2, 2, "mm")
    )
}

# Standard p-value / significance label formatting used across all figures.
cns_p_label <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) "p < 0.001" else sprintf("p = %.3f", p)
}
cns_stars <- function(p) {
  if (is.na(p)) "" else if (p < 0.001) "***" else if (p < 0.01) "**" else
    if (p < 0.05) "*" else "ns"
}
