# ==============================================================================
# pub_theme.R — shared publication theme + multi-format figure export helpers.
# Merged from the duplicated helper blocks in 94_visualization.R, 91_diversity.R
# and 93_stat_cooccurrence.sh (embedded R). Consumers source this file and call
# theme_set(theme_pub()) on their own side (this module never touches the global
# theme).
#
# export_pub_figure() / export_pub_figure_base() format selection:
#   formats = NULL  -> env var MGX_FIGURE_FORMATS (comma-separated, e.g.
#                      "pdf,png") -> if unset, legacy default "svg,pdf,tiff"
#   Supported: svg, pdf, tiff, png. Unknown tokens are skipped with a warning
#   to stderr (never an error).
# ==============================================================================

mm2in <- function(x) x / 25.4

theme_pub <- function(base_size = 7, base_family = "Arial") {
  ggplot2::theme_classic(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      axis.line = ggplot2::element_line(linewidth = 0.35, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = 0.35, colour = "black"),
      axis.title = ggplot2::element_text(size = base_size + 1),
      axis.text = ggplot2::element_text(size = base_size, colour = "black"),
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = base_size),
      legend.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(size = base_size + 1, face = "bold"),
      plot.title = ggplot2::element_text(size = base_size + 2, face = "bold"),
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.grid = ggplot2::element_blank()
    )
}

npg_base <- c("#E64B35", "#4DBBD5", "#00A087", "#3C5488", "#F39B7F",
              "#8491B4", "#91D1C2", "#DC0000", "#7E6148", "#B09C85")

npg_pal <- function(n) {
  if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
}

resolve_formats <- function(formats = NULL) {
  if (is.null(formats)) {
    env_formats <- Sys.getenv("MGX_FIGURE_FORMATS", "")
    formats <- if (nzchar(env_formats)) env_formats else "svg,pdf,tiff"
  }
  if (length(formats) == 1) formats <- strsplit(formats, ",", fixed = TRUE)[[1]]
  tolower(trimws(formats[nzchar(formats)]))
}

write_device <- function(open_device, draw_fn) {
  open_device()
  dev_id <- grDevices::dev.cur()
  on.exit({
    if (grDevices::dev.cur() == dev_id) {
      try(grDevices::dev.off(), silent = TRUE)
    }
  }, add = TRUE)
  draw_fn()
  grDevices::dev.off()
  invisible(TRUE)
}

# Multi-format export for ggplot objects (drawn via print()).
export_pub_figure <- function(plot, path_noext, width_mm, height_mm, dpi = 600, formats = NULL) {
  formats <- resolve_formats(formats)
  w <- mm2in(width_mm)
  h <- mm2in(height_mm)

  first_path <- NULL
  for (fmt in formats) {
    written <- switch(fmt,
      svg  = write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h), function() print(plot)),
      pdf  = write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"), function() print(plot)),
      tiff = write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi), function() print(plot)),
      png  = write_device(function() ragg::agg_png(paste0(path_noext, ".png"), width = w, height = h, units = "in", res = dpi), function() print(plot)),
      NULL
    )
    if (is.null(written)) {
      message(sprintf("[WARN] export_pub_figure: unsupported figure format '%s' skipped", fmt))
      next
    }
    if (is.null(first_path)) first_path <- paste0(path_noext, ".", fmt)
  }
  invisible(first_path)
}

# Multi-format export for base-graphics plots (drawn via a plot_fn closure).
export_pub_figure_base <- function(plot_fn, path_noext, width_mm, height_mm, dpi = 600, formats = NULL) {
  formats <- resolve_formats(formats)
  w <- mm2in(width_mm)
  h <- mm2in(height_mm)

  first_path <- NULL
  for (fmt in formats) {
    written <- switch(fmt,
      svg  = write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h), plot_fn),
      pdf  = write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"), plot_fn),
      tiff = write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi), plot_fn),
      png  = write_device(function() ragg::agg_png(paste0(path_noext, ".png"), width = w, height = h, units = "in", res = dpi), plot_fn),
      NULL
    )
    if (is.null(written)) {
      message(sprintf("[WARN] export_pub_figure_base: unsupported figure format '%s' skipped", fmt))
      next
    }
    if (is.null(first_path)) first_path <- paste0(path_noext, ".", fmt)
  }
  invisible(first_path)
}
