#!/usr/bin/env Rscript
# ==============================================================================
# render_mining.R — mining overview figures from pre-aggregated TSVs.
# Usage:   Rscript render_mining.R <spec.json>
# Spec:    {"out_dir": ..., "attrs_tsv": ..., "overlap_tsv": ..., "sources_tsv": ...}
#          (all paths absolute; created out_dir if missing)
# Inputs:
#   attrs_tsv    long table, columns: attribute <TAB> value <TAB> count
#   overlap_tsv  square matrix, header: source <TAB> <src1> <TAB> ..., int cells
#   sources_tsv  columns: source <TAB> count
# Outputs: <out_dir>/mining_attrs.{pdf,png}, <out_dir>/mining_overlap.{pdf,png}
# If jsonlite is unavailable, spec fields may come from env vars instead:
#   MGX_MINING_OUT_DIR, MGX_MINING_ATTRS_TSV, MGX_MINING_OVERLAP_TSV,
#   MGX_MINING_SOURCES_TSV
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
})

# Shared publication theme/export helpers (scripts/R/pub_theme.R), resolved
# from this script's own location (mcp/vis/ -> ../../scripts/R/) so any cwd works.
local({
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  script_dir <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  source(file.path(script_dir, "..", "..", "scripts", "R", "pub_theme.R"))
})

theme_set(theme_pub())

spec_from_json <- function(path) {
  if (!file.exists(path)) stop("spec file not found: ", path)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("spec file given but jsonlite is not installed: ", path)
  }
  spec <- jsonlite::fromJSON(path)
  as.list(spec)
}

spec_from_env <- function() {
  list(
    out_dir     = Sys.getenv("MGX_MINING_OUT_DIR"),
    attrs_tsv   = Sys.getenv("MGX_MINING_ATTRS_TSV"),
    overlap_tsv = Sys.getenv("MGX_MINING_OVERLAP_TSV"),
    sources_tsv = Sys.getenv("MGX_MINING_SOURCES_TSV")
  )
}

read_spec <- function(args) {
  spec <- if (length(args) >= 1 && nzchar(args[1])) spec_from_json(args[1]) else spec_from_env()
  fields <- c("out_dir", "attrs_tsv", "overlap_tsv", "sources_tsv")
  spec <- lapply(spec, function(x) if (is.null(x)) "" else as.character(x)[1])
  missing <- fields[!nzchar(unlist(spec[fields], use.names = FALSE))]
  if (length(missing)) {
    stop("spec is missing required fields: ", paste(missing, collapse = ", "))
  }
  spec
}

read_tsv <- function(path, what) {
  if (!file.exists(path)) stop(what, " not found: ", path)
  utils::read.delim(path, sep = "\t", header = TRUE, check.names = FALSE,
                    quote = "", stringsAsFactors = FALSE)
}

# Chart 1: horizontal bar charts per attribute (body_site / disease / ...),
# combined with patchwork; one NPG color per attribute, counts labeled.
plot_attrs <- function(attrs) {
  attrs$count <- suppressWarnings(as.numeric(attrs$count))
  attrs <- attrs[!is.na(attrs$count) &
                   nzchar(trimws(attrs$attribute)) & !is.na(attrs$attribute) &
                   nzchar(trimws(attrs$value)) & !is.na(attrs$value) &
                   attrs$count > 0, , drop = FALSE]
  if (!nrow(attrs)) stop("attrs_tsv has no usable rows")

  attr_levels <- unique(attrs$attribute)
  pal <- npg_pal(length(attr_levels))

  panels <- lapply(seq_along(attr_levels), function(i) {
    a <- trimws(attr_levels[i])
    d <- attrs[trimws(attrs$attribute) == a, , drop = FALSE]
    if (!nrow(d)) return(NULL)
    d <- d[order(d$count, decreasing = TRUE), , drop = FALSE]
    d$label <- factor(trimws(d$value), levels = rev(unique(trimws(d$value))))
    title <- tools::toTitleCase(gsub("_", " ", a))
    ggplot2::ggplot(d, ggplot2::aes(x = count, y = label)) +
      ggplot2::geom_col(fill = pal[i], width = 0.7) +
      ggplot2::geom_text(ggplot2::aes(label = format(count, trim = TRUE, big.mark = ",")),
                         hjust = -0.15, size = 2.2) +
      ggplot2::scale_x_continuous(
        labels = function(x) format(x, big.mark = ","),
        expand = ggplot2::expansion(mult = c(0, 0.25))
      ) +
      ggplot2::labs(x = "Datasets", y = NULL, title = title) +
      theme_pub()
  })
  panels <- Filter(Negate(is.null), panels)
  patchwork::wrap_plots(panels, ncol = 2) +
    patchwork::plot_annotation(tag_levels = "a")
}

# Square matrix with a labeled corner cell ("source\t<src1>\t<src2>..."):
# read.delim(row.names=1) mis-parses this shape, so read it explicitly.
read_overlap <- function(path) {
  if (!file.exists(path)) stop("overlap_tsv not found: ", path)
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) < 2) stop("overlap_tsv must have a header and at least one row")

  fields <- strsplit(lines, "\t", fixed = TRUE)
  hdr <- trimws(fields[[1]][-1])
  if (any(!nzchar(hdr))) stop("overlap_tsv header has empty source labels")
  bad <- fields[-1][vapply(fields[-1], length, integer(1)) != length(hdr) + 1]
  if (length(bad)) stop("overlap_tsv row with wrong field count: ", bad[[1]][1])

  rn <- trimws(vapply(fields[-1], function(x) x[1], character(1)))
  mat <- do.call(rbind, lapply(fields[-1], function(x) as.numeric(x[-1])))
  rownames(mat) <- rn
  colnames(mat) <- hdr
  mat
}

# Chart 2: seed-source overlap heatmap (annotated integer counts) side by side
# with a datasets-per-source barplot.
plot_overlap <- function(ov, src) {
  mat <- as.matrix(ov)
  if (nrow(mat) != ncol(mat)) stop("overlap_tsv is not a square matrix")
  if (anyNA(mat)) stop("overlap_tsv contains non-numeric cells")
  if (!setequal(rownames(mat), colnames(mat))) {
    stop("overlap_tsv row and column source labels differ")
  }

  heat <- data.frame(
    x = factor(rep(colnames(mat), each = nrow(mat)), levels = colnames(mat)),
    y = factor(rep(rownames(mat), times = ncol(mat)), levels = rev(rownames(mat))),
    n = as.vector(mat),
    stringsAsFactors = FALSE
  )

  src$count <- suppressWarnings(as.numeric(src$count))
  src <- src[nzchar(trimws(src$source)) & !is.na(src$count) & src$count > 0, , drop = FALSE]
  src <- src[order(src$count, decreasing = TRUE), , drop = FALSE]
  src$label <- factor(trimws(src$source), levels = rev(unique(trimws(src$source))))

  n_max <- max(heat$n)
  p_heat <- ggplot2::ggplot(heat, ggplot2::aes(x = x, y = y, fill = n)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.4) +
    ggplot2::geom_text(ggplot2::aes(label = format(n, trim = TRUE, big.mark = ",")),
                       size = 2.2,
                       colour = ifelse(heat$n > 0.6 * n_max, "white", "black")) +
    ggplot2::scale_fill_gradient(low = "grey96", high = npg_base[1], name = "Shared\ndatasets") +
    ggplot2::labs(x = NULL, y = NULL, title = "Seed source overlap") +
    theme_pub() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

  p_src <- ggplot2::ggplot(src, ggplot2::aes(x = count, y = label)) +
    ggplot2::geom_col(fill = npg_base[4], width = 0.7, show.legend = FALSE) +
    ggplot2::geom_text(ggplot2::aes(label = format(count, trim = TRUE, big.mark = ",")),
                       hjust = -0.15, size = 2.2) +
    ggplot2::scale_x_continuous(
      labels = function(x) format(x, big.mark = ","),
      expand = ggplot2::expansion(mult = c(0, 0.28))
    ) +
    ggplot2::labs(x = "Datasets", y = NULL, title = "Datasets per seed source") +
    theme_pub()

  p_heat + p_src + patchwork::plot_layout(widths = c(1.6, 1))
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  spec <- read_spec(args)

  dir.create(spec$out_dir, recursive = TRUE, showWarnings = FALSE)

  attrs <- read_tsv(spec$attrs_tsv, "attrs_tsv")
  bad <- setdiff(c("attribute", "value", "count"), colnames(attrs))
  if (length(bad)) stop("attrs_tsv missing columns: ", paste(bad, collapse = ", "))
  ov <- read_overlap(spec$overlap_tsv)
  src <- read_tsv(spec$sources_tsv, "sources_tsv")
  bad <- setdiff(c("source", "count"), colnames(src))
  if (length(bad)) stop("sources_tsv missing columns: ", paste(bad, collapse = ", "))

  message("[render_mining] attrs: ", nrow(attrs), " rows, ",
          length(unique(attrs$attribute)), " attributes")
  message("[render_mining] overlap: ", nrow(ov), "x", ncol(ov), "; sources: ", nrow(src))

  export_pub_figure(plot_attrs(attrs), file.path(spec$out_dir, "mining_attrs"),
                    width_mm = 180, height_mm = 130, formats = c("pdf", "png"))
  export_pub_figure(plot_overlap(ov, src), file.path(spec$out_dir, "mining_overlap"),
                    width_mm = 180, height_mm = 125, formats = c("pdf", "png"))

  message("[render_mining] wrote mining_attrs.{pdf,png} and mining_overlap.{pdf,png} to ",
          spec$out_dir)
}

tryCatch(
  main(),
  error = function(e) {
    message("[render_mining] FATAL: ", conditionMessage(e))
    quit(status = 1)
  }
)
