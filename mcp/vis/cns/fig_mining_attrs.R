#!/usr/bin/env Rscript
# ==============================================================================
# fig_mining_attrs.R — seed registry attribute profile, 2x2 panels of
# horizontal bars (top values + Others) for body_site / disease / platform /
# country, one cns_cat colour per panel. Counts are queried read-only from
# mining/seed_registry.sqlite (RSQLite primary, python stdlib fallback).
#
# Usage: Rscript fig_mining_attrs.R <repo_root> <out_dir>
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2)
  stop("usage: Rscript fig_mining_attrs.R <repo_root> <out_dir>")
workdir <- normalizePath(args[[1]], mustWork = TRUE)   # repo root
out_dir <- args[[2]]
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

script_dir <- dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]
)))
source(file.path(script_dir, "theme_cns.R"))
source(file.path(normalizePath(file.path(script_dir, "..", "..", "..")),
                 "scripts", "R", "pub_theme.R"))

suppressPackageStartupMessages({ library(ggplot2) })

db <- file.path(workdir, "mining", "seed_registry.sqlite")
if (!file.exists(db)) stop("missing ", db)

# ---- read-only grouped counts ------------------------------------------------
attr_cols <- c(body_site = "Body site", disease = "Disease",
               platform = "Platform", country = "Country")
counts_for <- function(col) {
  sql <- sprintf(paste0(
    "SELECT %s AS value, COUNT(*) AS n FROM seed_runs ",
    "WHERE %s IS NOT NULL AND TRIM(%s) <> '' GROUP BY value ORDER BY n DESC"),
    col, col, col)
  if (requireNamespace("RSQLite", quietly = TRUE)) {
    con <- DBI::dbConnect(RSQLite::SQLite(), dbname = db,
                          flags = RSQLite::SQLITE_RO)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    as.data.frame(DBI::dbGetQuery(con, sql), stringsAsFactors = FALSE)
  } else {  # python stdlib fallback (no extra R packages allowed)
    py <- Sys.which("python3")
    if (!nzchar(py)) py <- file.path(workdir, "envs", "rag", "bin", "python3")
    code <- sprintf(paste0(
      "import sqlite3,sys; ",
      "con=sqlite3.connect('file:%s?mode=ro',uri=True); ",
      "[sys.stdout.write('%%s\\t%%d\\n' %% r) for r in con.execute('%s')]"),
      db, gsub("'", "''", sql))
    out <- system2(py, c("-c", shQuote(code)), stdout = TRUE)
    do.call(rbind, lapply(out, function(l) {
      p <- strsplit(l, "\t", fixed = TRUE)[[1]]
      data.frame(value = p[1], n = as.numeric(p[2])) }))
  }
}

# ---- prepare long table: case-variant spellings merged, top-7 + Others -------
panels <- do.call(rbind, lapply(names(attr_cols), function(col) {
  d <- counts_for(col)
  d$key <- tolower(trimws(d$value))
  agg <- stats::aggregate(n ~ key, d, sum)
  # modal spelling as the display label for each case-insensitive group
  lab <- vapply(agg$key, function(k) {
    g <- d[d$key == k, ]; g$value[which.max(g$n)]
  }, character(1))
  d <- data.frame(label = lab, n = agg$n)
  d <- d[order(-d$n), ]
  top <- utils::head(d, 7)
  rest <- sum(utils::tail(d$n, if (nrow(d) > 7) -7 else 0))
  if (rest > 0)
    top <- rbind(top, data.frame(label = "Others", n = rest))
  data.frame(panel = attr_cols[[col]], label = top$label, n = top$n,
             stringsAsFactors = FALSE)
}))

wrap24 <- function(x) vapply(x, function(s)
  paste(strwrap(s, 24), collapse = "\n"), character(1))
panels$lab <- wrap24(panels$label)

panel_cols <- setNames(cns_cat[seq_along(attr_cols)], attr_cols)
panels$fill_col <- ifelse(panels$label == "Others", "#C9CDD3",
                          panel_cols[panels$panel])
panels$panel <- factor(panels$panel, levels = attr_cols)

# per-panel ordering (largest bar on top), "Others" pinned last
panels <- do.call(rbind, lapply(levels(panels$panel), function(pn) {
  g <- panels[panels$panel == pn, ]
  o <- g$label == "Others"
  g <- g[order(o, g$n), ]                        # FALSE(0) first, ascending n
  g$lab <- factor(g$lab, levels = unique(g$lab))
  g
}))

p <- ggplot(panels, aes(x = n, y = lab, fill = fill_col)) +
  geom_col(width = 0.68, colour = "white", linewidth = 0.2) +
  geom_text(aes(label = scales::comma(n)), hjust = -0.12, size = 7 / .pt,
            family = "Arial", colour = "black") +
  scale_fill_identity() +
  scale_x_continuous(expand = expansion(mult = c(0, 0.16)),
                     labels = scales::comma) +
  facet_wrap(~ panel, ncol = 2, scales = "free") +
  labs(x = "Samples", y = NULL) +
  theme_cns(y_grid = FALSE) +
  theme(axis.text.y = element_text(size = 7, lineheight = 0.85),
        strip.text = element_text(size = 8.5))

export_pub_figure(p, file.path(out_dir, "mining_attrs"),
                  width_mm = CNS_W_DOUBLE, height_mm = 130,
                  formats = c("pdf", "png"))
message("written: mining_attrs.{pdf,png} (",
        paste(sprintf("%s: %d values", attr_cols,
                      as.integer(table(panels$panel))), collapse = ", "),
        ")")
