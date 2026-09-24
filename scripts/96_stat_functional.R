#!/usr/bin/env Rscript
# 96_stat_functional.R - Functional differential abundance analysis
# Methods: Maaslin3 (differential analysis) + Hypergeometric test (enrichment)
# Outputs: result/stat/{dimension}/functional/{func_type}/
#   - results/maaslin3_results.tsv / results/maaslin3_significant.tsv
#   - results/enrichment.tsv
#   - figures/volcano.{pdf,svg,tiff}
#   - figures/barplot_top20.{pdf,svg,tiff}
#   - figures/boxplot_top10.{pdf,svg,tiff}
#   - figures/heatmap_significant.{pdf,svg,tiff}
#   - figures/sankey_enrichment.{pdf,svg,tiff}
#   - maaslin3_raw/
#   - {func_type}_status.tsv

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(x)) y else x

show_help <- function() {
  cat(
    "Usage: Rscript 96_stat_functional.R [-w WORKDIR] [-r REPO] [-m METADATA_CSV] [-d DIMENSION] [-t FUNC_TYPE]\n",
    "\n",
    "Optional:\n",
    "  -w, --workdir      Project work directory (default: WORKDIR env or current directory)\n",
    "  -r, --repo         Repository root (default: REPO env)\n",
    "  -m, --metadata     Metadata CSV (default: METADATA_CSV env or result/stat/metadata.tsv)\n",
    "  -d, --dimension    bacteria|fungi|virus (default: DIMENSION env or bacteria)\n",
    "  -t, --func-type    pathway|kegg_ko|cog|cazyme|arg|vfdb|defense|ncyc|pcyc|funomic|amr|merops|phrog|vog|lifestyle|host_genus|viral_family\n",
    "                     default: FUNC_TYPE env or pathway\n",
    "  -g, --group-col    Metadata group column (default: GROUP_COL env or group)\n",
    "  -h, --help         Show this help message\n",
    sep = ""
  )
}

parse_cli_args <- function(args) {
  opts <- list()
  i <- 1
  next_value <- function(flag) {
    if (i >= length(args)) {
      stop("Missing value for argument: ", flag)
    }
    args[[i + 1]]
  }

  while (i <= length(args)) {
    flag <- args[[i]]
    if (flag %in% c("-h", "--help")) {
      show_help()
      quit(status = 0)
    } else if (flag %in% c("-w", "--workdir")) {
      opts$workdir <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-r", "--repo")) {
      opts$repo <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-m", "--metadata")) {
      opts$metadata_csv <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-d", "--dimension")) {
      opts$dimension <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-t", "--func-type")) {
      opts$func_type <- next_value(flag); i <- i + 2
    } else if (flag %in% c("-g", "--group-col")) {
      opts$group_col <- next_value(flag); i <- i + 2
    } else if (flag == "--force") {
      i <- i + 1
    } else {
      stop("Unknown argument: ", flag)
    }
  }
  opts
}

cli_opts <- parse_cli_args(commandArgs(trailingOnly = TRUE))

workdir      <- cli_opts$workdir %||% Sys.getenv("WORKDIR") %||% getwd()
repo         <- cli_opts$repo %||% Sys.getenv("REPO")
metadata_csv <- cli_opts$metadata_csv %||% Sys.getenv("METADATA_CSV")
group_col    <- cli_opts$group_col %||% Sys.getenv("GROUP_COL") %||% "group"
stat_root    <- Sys.getenv("STAT_ROOT") %||% file.path(workdir, "result", "stat")
dimension    <- tolower(cli_opts$dimension %||% Sys.getenv("DIMENSION") %||% "bacteria")
func_type    <- tolower(cli_opts$func_type %||% Sys.getenv("FUNC_TYPE") %||% "pathway")
dim_root     <- file.path(stat_root, dimension)
out_dir      <- Sys.getenv("OUT_DIR") %||% file.path(dim_root, "functional", func_type)
results_dir  <- file.path(out_dir, "results")
figures_dir  <- file.path(out_dir, "figures")
maaslin_raw_dir <- file.path(out_dir, "maaslin3_raw")
sentinel     <- Sys.getenv("SENTINEL") %||%
  file.path(out_dir, sprintf("%s_functional_%s_done.txt", dimension, func_type))

functional_source_map <- list(
  bacteria = list(
    pathway = list(
      rel_path = file.path("result", "humann3", "merged", "pathabundance_relab.tsv"),
      feature_col = "# Pathway"
    ),
    kegg_ko = list(
      rel_path = file.path("result", "integration", "bacteria", "kegg_ko_abundance.tsv"),
      feature_col = "KEGG_KO"
    ),
    cog = list(
      rel_path = file.path("result", "integration", "bacteria", "cog_abundance.tsv"),
      feature_col = "COG_category"
    ),
    cazyme = list(
      rel_path = file.path("result", "integration", "bacteria", "cazyme_abundance.tsv"),
      feature_col = "CAZyme_family"
    ),
    arg = list(
      rel_path = file.path("result", "integration", "bacteria", "arg_abundance.tsv"),
      feature_col = "ARG_gene"
    ),
    vfdb = list(
      rel_path = file.path("result", "integration", "bacteria", "vfdb_abundance.tsv"),
      feature_col = "VF_gene"
    ),
    defense = list(
      rel_path = file.path("result", "integration", "bacteria", "defense_abundance.tsv"),
      feature_col = "Defense_system"
    ),
    ncyc = list(
      rel_path = file.path("result", "integration", "bacteria", "ncyc_abundance.tsv"),
      feature_col = "NCyc_gene"
    ),
    pcyc = list(
      rel_path = file.path("result", "integration", "bacteria", "pcyc_abundance.tsv"),
      feature_col = "PCyc_gene"
    )
  ),
  fungi = list(
    kegg_ko = list(
      rel_path = file.path("result", "integration", "fungi", "kegg_ko_gene_count.tsv"),
      feature_col = "KEGG_KO"
    ),
    cog = list(
      rel_path = file.path("result", "integration", "fungi", "cog_gene_count.tsv"),
      feature_col = "COG_category"
    ),
    cazyme = list(
      rel_path = file.path("result", "integration", "fungi", "cazyme_gene_count.tsv"),
      feature_col = "CAZyme_family"
    ),
    vfdb = list(
      rel_path = file.path("result", "integration", "fungi", "vfdb_gene_count.tsv"),
      feature_col = "VF_gene"
    ),
    amr = list(
      rel_path = file.path("result", "integration", "fungi", "amr_gene_count.tsv"),
      feature_col = "ARG_symbol"
    ),
    merops = list(
      rel_path = file.path("result", "integration", "fungi", "merops_family_gene_count.tsv"),
      feature_col = "MEROPS_family"
    ),
    funomic = list(
      rel_path = file.path("result", "integration", "fungi", "funomic_species_count.tsv"),
      feature_col = "species"
    )
  ),
  virus = list(
    phrog = list(
      rel_path = file.path("result", "integration", "virus", "phrog_category_abundance.tsv"),
      feature_col = "PHROG_category"
    ),
    vog = list(
      rel_path = file.path("result", "integration", "virus", "vog_abundance.tsv"),
      feature_col = "VOG_ID"
    ),
    lifestyle = list(
      rel_path = file.path("result", "integration", "virus", "lifestyle_abundance.tsv"),
      feature_col = "lifestyle"
    ),
    host_genus = list(
      rel_path = file.path("result", "integration", "virus", "host_genus_abundance.tsv"),
      feature_col = "host_genus"
    ),
    viral_family = list(
      rel_path = file.path("result", "integration", "virus", "viral_family_abundance.tsv"),
      feature_col = "viral_family"
    )
  )
)

valid_dimensions <- names(functional_source_map)
valid_func_types <- sort(unique(unlist(lapply(functional_source_map, names), use.names = FALSE)))

if (!dimension %in% valid_dimensions) {
  stop("Invalid dimension: ", dimension)
}
if (!func_type %in% valid_func_types) {
  stop("Invalid functional type: ", func_type)
}
if (!func_type %in% names(functional_source_map[[dimension]])) {
  stop(
    "Functional type '", func_type, "' is not valid for dimension '", dimension,
    "'. Valid types for ", dimension, ": ",
    paste(names(functional_source_map[[dimension]]), collapse = ", ")
  )
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(maaslin_raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(sentinel), recursive = TRUE, showWarnings = FALSE)

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("maaslin3", "ggplot2", "dplyr", "tidyr", "tibble", "stringr", "RColorBrewer",
                    "svglite", "ragg", "ggrepel", "ggtext", "ggsci", "ComplexHeatmap",
                    "circlize", "ggsankeyfier", "patchwork")
miss <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  stop("Missing packages: ", paste(miss, collapse = ", "))
}

suppressPackageStartupMessages({
  library(maaslin3)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(ggrepel)
  library(ggtext)
  library(ggsci)
  library(ggsankeyfier)
  library(patchwork)
})

grDevices::pdf(file = NULL)

mm2in <- function(x) x / 25.4
sci_linewidth <- 0.35 / 0.353
sci_text_size <- 7 / ggplot2::.pt
width_1col <- 89
width_1_5col <- 140
width_2col <- 183

theme_pub <- function(base_size = 7, base_family = "Arial") {
  ggplot2::theme_bw(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      line = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.line = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = sci_linewidth, colour = "black"),
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
      panel.border = ggplot2::element_rect(linewidth = sci_linewidth, colour = "black", fill = NA),
      panel.grid = ggplot2::element_blank()
    )
}

export_pub_figure <- function(plot, path_noext, width_mm, height_mm, dpi = 600) {
  w <- mm2in(width_mm)
  h <- mm2in(height_mm)

  write_device <- function(open_device) {
    open_device()
    dev_id <- grDevices::dev.cur()
    on.exit({
      if (grDevices::dev.cur() == dev_id) {
        try(grDevices::dev.off(), silent = TRUE)
      }
    }, add = TRUE)
    print(plot)
    grDevices::dev.off()
    invisible(TRUE)
  }

  write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h))
  write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"))
  write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi, compression = "lzw"))
  invisible(paste0(path_noext, ".svg"))
}

export_heatmap <- function(ht, path_noext, width_mm, height_mm, dpi = 600) {
  w <- mm2in(width_mm)
  h <- mm2in(height_mm)

  write_device <- function(open_device) {
    open_device()
    dev_id <- grDevices::dev.cur()
    on.exit({
      if (grDevices::dev.cur() == dev_id) {
        try(grDevices::dev.off(), silent = TRUE)
      }
    }, add = TRUE)
    ComplexHeatmap::draw(
      ht,
      heatmap_legend_side = "right",
      annotation_legend_side = "right",
      merge_legends = TRUE
    )
    grDevices::dev.off()
    invisible(TRUE)
  }

  write_device(function() svglite::svglite(paste0(path_noext, ".svg"), width = w, height = h))
  write_device(function() grDevices::cairo_pdf(paste0(path_noext, ".pdf"), width = w, height = h, family = "Arial"))
  write_device(function() ragg::agg_tiff(paste0(path_noext, ".tiff"), width = w, height = h, units = "in", res = dpi, compression = "lzw"))
  invisible(paste0(path_noext, ".svg"))
}

theme_set(theme_pub())

npg_base <- c("#E64B35","#4DBBD5","#00A087","#3C5488","#F39B7F",
              "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
npg_pal <- function(n) {
  if (n <= length(npg_base)) npg_base[seq_len(n)] else grDevices::colorRampPalette(npg_base)(n)
}

sci_diff_colors <- function() {
  list(
    up = "#E64B35",
    down = "#4DBBD5",
    nonsig = "#BBBBBB"
  )
}

## Lazily-loaded lookup tables backed by local reference databases under
## {repo}/db/. Cached per-session in .functional_annotation_cache so repeated
## calls (once per plot) don't re-read/re-parse the source files. Falls back
## to NULL (annotation lookup miss -> raw id is shown) if repo is unset or the
## source file is missing, so this never hard-fails the analysis.
.functional_annotation_cache <- new.env(parent = emptyenv())

load_kegg_ko_annotations <- function() {
  key <- "kegg_ko"
  if (!is.null(.functional_annotation_cache[[key]])) {
    return(.functional_annotation_cache[[key]])
  }
  path <- file.path(repo, "db", "dram_db", "kofam_ko_list.tsv")
  result <- NULL
  if (nzchar(repo) && file.exists(path)) {
    tryCatch({
      tbl <- utils::read.delim(path, sep = "\t", quote = "", stringsAsFactors = FALSE)
      result <- stats::setNames(tbl$definition, tbl$knum)
    }, error = function(e) NULL)
  }
  .functional_annotation_cache[[key]] <- result
  result
}

load_vfdb_annotations <- function() {
  key <- "vfdb"
  if (!is.null(.functional_annotation_cache[[key]])) {
    return(.functional_annotation_cache[[key]])
  }
  path <- file.path(repo, "db", "vfdb", "misc", "annotation.txt")
  result <- NULL
  if (nzchar(repo) && file.exists(path)) {
    tryCatch({
      tbl <- utils::read.delim(path, sep = "\t", quote = "", header = FALSE, stringsAsFactors = FALSE)
      ## column 2 is free text like: (gb|WP_...) (plc1) phospholipase C [Phospholipase C (VF0470) - Exotoxin (VFC0235)] [species]
      ## keep the gene-name + function part before the first "[" for a compact label
      desc <- sub("^\\s*\\(gb\\|[^)]*\\)\\s*", "", tbl[[2]])
      desc <- sub("\\s*\\[.*$", "", desc)
      result <- stats::setNames(trimws(desc), tbl[[1]])
    }, error = function(e) NULL)
  }
  .functional_annotation_cache[[key]] <- result
  result
}

load_merops_annotations <- function() {
  key <- "merops"
  if (!is.null(.functional_annotation_cache[[key]])) {
    return(.functional_annotation_cache[[key]])
  }
  path <- file.path(repo, "db", "merops", "misc", "family.txt")
  result <- NULL
  if (nzchar(repo) && file.exists(path)) {
    tryCatch({
      tbl <- utils::read.delim(path, sep = "\t", quote = "", header = FALSE, stringsAsFactors = FALSE)
      result <- stats::setNames(tbl[[2]], tbl[[1]])
    }, error = function(e) NULL)
  }
  .functional_annotation_cache[[key]] <- result
  result
}

load_cazyme_family_annotations <- function() {
  key <- "cazyme_family"
  if (!is.null(.functional_annotation_cache[[key]])) {
    return(.functional_annotation_cache[[key]])
  }
  path <- file.path(repo, "db", "dbcan3", "CAZyDB.08062022.fam-activities.txt")
  result <- NULL
  if (nzchar(repo) && file.exists(path)) {
    tryCatch({
      lines <- readLines(path, warn = FALSE)
      lines <- lines[!grepl("^#", lines)]
      parts <- strsplit(lines, "\t")
      fam <- vapply(parts, function(p) trimws(p[1]), character(1))
      desc <- vapply(parts, function(p) if (length(p) >= 2) trimws(p[2]) else "", character(1))
      keep <- nzchar(fam) & nzchar(desc)
      result <- stats::setNames(desc[keep], fam[keep])
    }, error = function(e) NULL)
  }
  .functional_annotation_cache[[key]] <- result
  result
}

get_functional_annotation <- function(feature_id, func_type) {
  cog_annotations <- c(
    "A" = "RNA processing",
    "B" = "Chromatin structure",
    "C" = "Energy production",
    "D" = "Cell cycle control",
    "E" = "Amino acid transport",
    "F" = "Nucleotide transport",
    "G" = "Carbohydrate transport",
    "H" = "Coenzyme transport",
    "I" = "Lipid transport",
    "J" = "Translation",
    "K" = "Transcription",
    "L" = "Replication",
    "M" = "Cell wall biogenesis",
    "N" = "Cell motility",
    "O" = "PTM, protein turnover",
    "P" = "Inorganic ion transport",
    "Q" = "Secondary metabolites",
    "R" = "General function",
    "S" = "Function unknown",
    "T" = "Signal transduction",
    "U" = "Intracellular trafficking",
    "V" = "Defense mechanisms",
    "W" = "Extracellular structures",
    "X" = "Mobilome",
    "Y" = "Nuclear structure",
    "Z" = "Cytoskeleton"
  )

  cazyme_prefix_annotations <- c(
    "GH" = "Glycoside Hydrolase",
    "GT" = "Glycosyl Transferase",
    "PL" = "Polysaccharide Lyase",
    "CE" = "Carbohydrate Esterase",
    "AA" = "Auxiliary Activity",
    "CBM" = "Carbohydrate-Binding Module"
  )

  kegg_ko_annotations <- load_kegg_ko_annotations()
  vfdb_annotations <- load_vfdb_annotations()
  merops_annotations <- load_merops_annotations()
  cazyme_family_annotations <- load_cazyme_family_annotations()

  phrog_annotations <- c(
    "head and packaging" = "Phage head/packaging",
    "tail" = "Phage tail",
    "lysis" = "Host lysis",
    "DNA, RNA and nucleotide metabolism" = "Nucleotide metabolism",
    "integration and excision" = "Integration/excision",
    "transcription regulation" = "Transcription regulation",
    "other" = "Other functions",
    "moron, auxiliary metabolic gene and host takeover" = "AMG/host takeover"
  )
  names(phrog_annotations) <- tolower(names(phrog_annotations))

  vapply(as.character(feature_id), function(id) {
    if (is.na(id) || !nzchar(id)) {
      return(id)
    }

    if (identical(func_type, "cog")) {
      cog_id <- sub("^COG[_ -]?", "", toupper(id))
      annot <- cog_annotations[cog_id]
      if (!is.na(annot)) {
        return(unname(annot))
      }
    } else if (identical(func_type, "cazyme")) {
      ## try exact family match against CAZyDB (e.g. "GH1", "AA10") first for a
      ## fine-grained description; fall back to the coarse prefix-level table
      fam_id <- toupper(sub("\\(.*$", "", id))
      if (!is.null(cazyme_family_annotations)) {
        annot <- cazyme_family_annotations[fam_id]
        if (!is.na(annot) && nzchar(annot)) {
          return(unname(annot))
        }
      }
      prefix <- toupper(sub("^([A-Za-z]+).*", "\\1", id))
      annot <- cazyme_prefix_annotations[prefix]
      if (!is.na(annot)) {
        return(paste0(unname(annot), " family"))
      }
    } else if (identical(func_type, "kegg_ko")) {
      if (!is.null(kegg_ko_annotations)) {
        annot <- kegg_ko_annotations[toupper(id)]
        if (!is.na(annot) && nzchar(annot)) {
          return(unname(annot))
        }
      }
    } else if (identical(func_type, "vfdb")) {
      if (!is.null(vfdb_annotations)) {
        annot <- vfdb_annotations[id]
        if (!is.na(annot) && nzchar(annot)) {
          return(unname(annot))
        }
      }
    } else if (identical(func_type, "merops")) {
      fam_id <- toupper(sub("^MEROPS[_ -]?", "", id))
      if (!is.null(merops_annotations)) {
        annot <- merops_annotations[fam_id]
        if (!is.na(annot) && nzchar(annot)) {
          return(unname(annot))
        }
      }
    } else if (identical(func_type, "phrog")) {
      annot <- phrog_annotations[tolower(trimws(id))]
      if (!is.na(annot)) {
        return(unname(annot))
      }
    } else if (identical(func_type, "lifestyle")) {
      return(id)
    } else if (identical(func_type, "host_genus")) {
      return(paste0("Host: ", id))
    } else if (identical(func_type, "viral_family")) {
      if (grepl("family$", id, ignore.case = TRUE)) {
        return(id)
      }
      return(paste0(id, " family"))
    }

    id
  }, character(1), USE.NAMES = FALSE)
}

format_functional_label <- function(feature_id, func_type, width = NULL) {
  ids <- as.character(feature_id)
  annotations <- get_functional_annotation(ids, func_type)
  labels <- ifelse(
    !is.na(annotations) & annotations != ids,
    paste0(ids, "\n", annotations),
    ids
  )

  if (!is.null(width) && is.finite(width)) {
    labels <- stringr::str_trunc(labels, width = width)
  }

  labels
}

load_functional_matrix <- function(workdir, dimension, func_type) {
  if (!dimension %in% names(functional_source_map)) {
    stop("Unsupported dimension: ", dimension)
  }
  if (!func_type %in% names(functional_source_map[[dimension]])) {
    stop("Functional type '", func_type, "' is not valid for dimension '", dimension, "'")
  }

  source <- functional_source_map[[dimension]][[func_type]]
  feature_file <- file.path(workdir, source$rel_path)
  if (!file.exists(feature_file)) {
    stop("Functional matrix not found for '", func_type, "': ", feature_file)
  }

  raw <- utils::read.delim(feature_file, sep = "\t", header = TRUE,
                           check.names = FALSE, comment.char = "",
                           stringsAsFactors = FALSE)
  if (!source$feature_col %in% colnames(raw)) {
    stop("Expected feature column '", source$feature_col, "' not found in: ", feature_file)
  }

  raw <- raw[!is.na(raw[[source$feature_col]]) & nzchar(raw[[source$feature_col]]), , drop = FALSE]

  if (identical(func_type, "pathway")) {
    raw <- raw[!grepl("UNMAPPED|\\|", raw[[source$feature_col]]), , drop = FALSE]
  }

  if (nrow(raw) == 0) {
    stop("No functional features present in: ", feature_file,
         " (table has a header but zero data rows)")
  }

  abundance_cols <- setdiff(colnames(raw), source$feature_col)
  if (!length(abundance_cols)) {
    stop("No sample abundance columns found in: ", feature_file)
  }

  abundance <- raw[, abundance_cols, drop = FALSE]
  abundance[] <- lapply(abundance, function(x) suppressWarnings(as.numeric(x)))
  if (anyNA(as.matrix(abundance))) {
    stop("Non-numeric abundance values detected in: ", feature_file)
  }

  rownames(abundance) <- make.unique(raw[[source$feature_col]])
  feature_df <- as.data.frame(t(abundance), check.names = FALSE)
  feature_df$sample_id <- rownames(feature_df)

  list(
    data = feature_df,
    n_features = nrow(abundance),
    n_samples = ncol(abundance),
    feature_col = source$feature_col,
    feature_file = feature_file
  )
}

write_status <- function(status_log, path) {
  df <- if (length(status_log)) do.call(rbind, status_log) else
    data.frame(step = character(), status = character(), message = character(),
               stringsAsFactors = FALSE)
  utils::write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE)
}

append_status <- function(step, status, message = "") {
  status_log[[length(status_log) + 1]] <<- data.frame(
    step = step,
    status = status,
    message = as.character(message),
    stringsAsFactors = FALSE
  )
}

run_step <- function(step, status_log, expr) {
  tryCatch({
    force(expr)
    append_status(step, "OK", "")
    TRUE
  }, error = function(e) {
    msg <- conditionMessage(e)
    append_status(step, "FAILED", msg)
    message("[WARN] ", step, ": ", msg)
    FALSE
  })
}

stop_if_failed <- function(ok, step) {
  if (!isTRUE(ok)) {
    write_status(status_log, status_tsv)
    stop("Required step failed: ", step)
  }
}

status_tsv <- file.path(out_dir, paste0(func_type, "_status.tsv"))
status_log <- list()
managed_visual_outputs <- c(
  volcano_plot = "volcano",
  barplot_top20 = "barplot_top20",
  boxplot_top10 = "boxplot_top10",
  heatmap_significant = "heatmap_significant",
  enrichment_sankey = "sankey_enrichment"
)
small_feature_prevalence_cutoff <- 15
legacy_bacteria_skip_prevalence_types <- c("cog", "ncyc", "pcyc")
skip_prevalence_filter <- FALSE
prevalence_skip_reason <- ""
prevalence_threshold <- if (identical(func_type, "kegg_ko")) 0.20 else 0.10
## Maaslin3 (>=1.5.3) has a native min_prevalence/max_prevalence parameter,
## but it only accepts a single fixed fraction - it can't express the
## conditional logic here (small-feature-set exemption, legacy bacteria
## type exemption, per-func_type threshold). Filtering is therefore done
## manually upstream of the maaslin3() call below, which is passed the
## already-filtered feature set with min_prevalence left at its default
## (0, i.e. no further filtering). This is an intentional divergence, not
## an oversight.
## maaslin3's mirai-based parallelization (cores > 1) is unreliable at this
## feature scale: the mirai/nanonext task dispatcher can deadlock after
## spawning daemons, independent of any other concurrent process (reproduced
## in isolation; not a cross-invocation race). This is a known class of issue
## in the upstream package (biobakery/maaslin3#25: multi-core runs hang/get
## killed; README recommends single-core by default). Single core is slower
## but deterministic, which matters more for pipeline-stability testing.
maaslin_cores <- 1

remove_stale_visual_outputs <- function(allowed_steps) {
  skipped_steps <- setdiff(names(managed_visual_outputs), allowed_steps)
  skipped_basenames <- unname(managed_visual_outputs[skipped_steps])
  skipped_files <- unlist(lapply(skipped_basenames, function(x) {
    paste0(file.path(figures_dir, x), c(".pdf", ".svg", ".tiff"))
  }), use.names = FALSE)

  if (length(skipped_files)) {
    unlink(skipped_files[file.exists(skipped_files)])
  }
  if (!"enrichment_sankey" %in% allowed_steps) {
    unlink(file.path(results_dir, "enrichment.tsv"))
  }

  skipped_steps
}

cat("[INFO] Starting functional analysis\n")
cat("  Workdir:", workdir, "\n")
cat("  Dimension:", dimension, "\n")
cat("  Functional type:", func_type, "\n")
cat("  Group column:", group_col, "\n")
cat("  Output directory:", out_dir, "\n")
cat("  Results directory:", results_dir, "\n")
cat("  Figures directory:", figures_dir, "\n")
cat("  Maaslin3 raw directory:", maaslin_raw_dir, "\n")

# ========== Load functional abundance data ==========
step_ok <- run_step("load_functional_data", status_log, {
  functional_matrix <- load_functional_matrix(workdir, dimension, func_type)
  functional_df <- functional_matrix$data
  skip_prevalence_filter <- functional_matrix$n_features <= small_feature_prevalence_cutoff ||
    (identical(dimension, "bacteria") && func_type %in% legacy_bacteria_skip_prevalence_types)
  prevalence_skip_reason <- if (functional_matrix$n_features <= small_feature_prevalence_cutoff) {
    sprintf("feature count <= %d", small_feature_prevalence_cutoff)
  } else if (skip_prevalence_filter) {
    "legacy bacteria small-category type"
  } else {
    ""
  }

  cat("  Source:", functional_matrix$feature_file, "\n")
  cat("  Feature column:", functional_matrix$feature_col, "\n")
  cat(sprintf("  Loaded: %d functional features x %d samples\n",
              functional_matrix$n_features, functional_matrix$n_samples))
})
stop_if_failed(step_ok, "load_functional_data")

# ========== Load metadata ==========
step_ok <- run_step("load_metadata", status_log, {
  if (nzchar(metadata_csv) && file.exists(metadata_csv)) {
    metadata <- utils::read.csv(metadata_csv, stringsAsFactors = FALSE)
  } else {
    metadata_tsv <- file.path(stat_root, "metadata.tsv")
    if (!file.exists(metadata_tsv)) {
      stop("Metadata not found at: ", metadata_tsv)
    }
    metadata <- utils::read.delim(metadata_tsv, sep = "\t", stringsAsFactors = FALSE)
  }

  if (!group_col %in% colnames(metadata)) {
    stop("Group column '", group_col, "' not found in metadata")
  }

  metadata <- metadata %>% dplyr::select(sample_id, !!rlang::sym(group_col),
                                          dplyr::everything())
  cat(sprintf("  Metadata: %d samples\n", nrow(metadata)))
})
stop_if_failed(step_ok, "load_metadata")

# ========== Merge and filter ==========
step_ok <- run_step("merge_filter", status_log, {
  merged_df <- dplyr::inner_join(metadata, functional_df, by = "sample_id")

  feature_cols <- setdiff(colnames(merged_df), colnames(metadata))
  if (!length(feature_cols)) {
    stop("No matching functional sample IDs found after merging metadata and abundance matrix")
  }

  if (skip_prevalence_filter) {
    keep_features <- feature_cols
    cat(sprintf("  Filtered: %d -> %d functional features (prevalence filter skipped: %s)\n",
                length(feature_cols), length(keep_features), prevalence_skip_reason))
  } else {
    min_prevalence <- ceiling(nrow(merged_df) * prevalence_threshold)
    prevalence <- colSums(merged_df[, feature_cols, drop = FALSE] > 0)
    keep_features <- names(prevalence[prevalence >= min_prevalence])
    cat(sprintf("  Filtered: %d -> %d functional features (prevalence >= %d%%)\n",
                length(feature_cols), length(keep_features),
                as.integer(prevalence_threshold * 100)))
  }

  if (!length(keep_features)) {
    stop("No functional features retained after prevalence filtering")
  }

  merged_df <- merged_df %>% dplyr::select(dplyr::all_of(colnames(metadata)),
                                             dplyr::all_of(keep_features))

  # Save for Maaslin3
  features <- as.data.frame(t(merged_df[, keep_features, drop = FALSE]))
  colnames(features) <- merged_df$sample_id
  metadata_final <- merged_df %>% dplyr::select(dplyr::all_of(colnames(metadata)))
  rownames(metadata_final) <- metadata_final$sample_id
})
stop_if_failed(step_ok, "merge_filter")

# ========== Maaslin3 differential analysis ==========
step_ok <- run_step("maaslin3_analysis", status_log, {
  maaslin_out <- maaslin_raw_dir
  dir.create(maaslin_out, recursive = TRUE, showWarnings = FALSE)

  # Maaslin3 main function
  fit_data <- maaslin3::maaslin3(
    input_data = features,
    input_metadata = metadata_final,
    output = maaslin_out,
    fixed_effects = group_col,
    random_effects = NULL,
    reference = paste0(group_col, ",control"),
    normalization = "TSS",
    transform = "LOG",
    correction = "BH",
    standardize = FALSE,
    max_significance = 0.05,
    plot_summary_plot = FALSE,
    plot_associations = FALSE,
    cores = maaslin_cores
  )

  # Read results
  results_file <- file.path(maaslin_out, "all_results.tsv")
  if (!file.exists(results_file)) {
    stop("Maaslin3 results file not found: ", results_file)
  }

  maaslin_res <- utils::read.delim(results_file, sep = "\t", stringsAsFactors = FALSE)

  # Maaslin3 outputs qval_individual and qval_joint; use qval_individual for single-covariate analysis
  # Rename for downstream compatibility
  if ("qval_individual" %in% colnames(maaslin_res)) {
    maaslin_res <- maaslin_res %>% dplyr::rename(qval = qval_individual, pval = pval_individual)
  }

  # Filter for group effect only (exclude intercept/other covariates)
  maaslin_res <- maaslin_res %>%
    dplyr::filter(grepl(group_col, metadata)) %>%
    dplyr::arrange(qval, desc(abs(coef)))

  utils::write.table(maaslin_res, file.path(results_dir, "maaslin3_results.tsv"),
                     sep = "\t", quote = FALSE, row.names = FALSE)

  sig_features <- maaslin_res %>% dplyr::filter(qval < 0.05)
  utils::write.table(sig_features, file.path(results_dir, "maaslin3_significant.tsv"),
                     sep = "\t", quote = FALSE, row.names = FALSE)

  cat(sprintf("    Maaslin3: %d total, %d significant (qval<0.05)\n",
              nrow(maaslin_res), nrow(sig_features)))
})
stop_if_failed(step_ok, "maaslin3_analysis")

# ========== Adaptive visualization strategy ==========
n_sig <- nrow(sig_features)
if (n_sig == 0) {
  allowed_visual_steps <- c("volcano_plot")
  visualization_strategy_label <- "Zero significant - volcano only"
  cat("  Zero significant features detected - generating volcano only\n")
} else if (n_sig < 3) {
  allowed_visual_steps <- c("volcano_plot", "barplot_top20")
  visualization_strategy_label <- sprintf("%d significant - volcano + barplot", n_sig)
  cat(sprintf("  Limited significant features (%d) - generating volcano + barplot\n", n_sig))
} else {
  allowed_visual_steps <- c("volcano_plot", "barplot_top20", "boxplot_top10", "heatmap_significant")
  if (identical(func_type, "pathway")) {
    allowed_visual_steps <- c(allowed_visual_steps, "enrichment_sankey")
    visualization_strategy_label <- "Full suite generated"
  } else {
    visualization_strategy_label <- "Full suite generated (sankey skipped for non-pathway)"
  }
  cat(sprintf("  Sufficient significant features (%d) - generating adaptive full suite\n", n_sig))
}

skipped_visual_steps <- remove_stale_visual_outputs(allowed_visual_steps)
visualization_step_ok <- setNames(logical(0), character(0))

# ========== Visualization 1: Volcano Plot ==========
if ("volcano_plot" %in% allowed_visual_steps) {
  visualization_step_ok["volcano_plot"] <- run_step("volcano_plot", status_log, {
  diff_cols <- sci_diff_colors()

  plot_df <- maaslin_res %>%
    dplyr::mutate(
      neg_log10_qval = -log10(qval),
      trend = dplyr::case_when(
        coef > 0 & qval < 0.05 ~ "up",
        coef < 0 & qval < 0.05 ~ "down",
        TRUE ~ "non-sig"
      ),
      label = ifelse(
        qval < 0.05,
        format_functional_label(feature, func_type, width = 70),
        NA_character_
      )
    ) %>%
    dplyr::filter(!is.na(qval))

  coef_values <- plot_df$coef[is.finite(plot_df$coef)]
  coef_range <- if (length(coef_values)) range(coef_values) else c(-1, 1)
  fdr_label_x <- coef_range[1] + diff(coef_range) * 0.72
  if (!is.finite(fdr_label_x) || diff(coef_range) == 0) {
    fdr_label_x <- coef_range[2]
  }

  p_volcano <- ggplot(plot_df, aes(x = coef, y = neg_log10_qval, color = trend)) +
    geom_point(alpha = 0.7, aes(size = neg_log10_qval)) +
    scale_color_manual(
      values = c("up" = diff_cols$up, "down" = diff_cols$down, "non-sig" = diff_cols$nonsig),
      labels = c("up" = "Up in case", "down" = "Up in control", "non-sig" = "Not significant"),
      name = NULL
    ) +
    scale_size_continuous(range = c(0.8, 3.5), guide = "none") +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", linewidth = sci_linewidth, color = "grey30") +
    geom_vline(xintercept = c(-1, 1), linetype = "dashed", linewidth = sci_linewidth, color = "grey30") +
    annotate(
      "text",
      x = fdr_label_x,
      y = -log10(0.05) * 1.1,
      label = "FDR = 0.05",
      size = sci_text_size,
      hjust = 0,
      color = "grey30"
    ) +
    geom_text_repel(
      aes(label = label), size = sci_text_size, segment.size = sci_linewidth, color = "grey20",
      max.overlaps = 20, box.padding = 0.35, point.padding = 0.3,
      min.segment.length = 0, na.rm = TRUE
    ) +
    labs(
      x = "Coefficient (case vs control)",
      y = "-log<sub>10</sub>(<i>q</i>-value)",
      title = "Functional Feature Differential Abundance"
    ) +
    theme_pub(base_size = 7) +
    theme(
      axis.title.y = element_markdown(),
      plot.title = element_text(size = 9, face = "bold", hjust = 0.5),
      legend.position = "right",
      legend.key.size = unit(3, "mm")
    )

  export_pub_figure(p_volcano, file.path(figures_dir, "volcano"),
                    width_mm = width_1_5col, height_mm = 110)
  })
}

# ========== Visualization 2: Barplot (Top 20) ==========
if ("barplot_top20" %in% allowed_visual_steps) {
  visualization_step_ok["barplot_top20"] <- run_step("barplot_top20", status_log, {
  top_n <- min(20, nrow(sig_features))
  bar_df <- sig_features %>%
    dplyr::slice_max(order_by = abs(coef), n = top_n) %>%
    dplyr::mutate(
      feature_label = format_functional_label(feature, func_type, width = 70),
      direction = ifelse(coef > 0, "up", "down"),
      stderr = if ("stderr" %in% colnames(.)) suppressWarnings(as.numeric(stderr)) else NA_real_
    ) %>%
    dplyr::arrange(coef)
  bar_df$feature_label <- make.unique(as.character(bar_df$feature_label), sep = " ")
  bar_df$feature_label <- factor(bar_df$feature_label, levels = bar_df$feature_label)

  coef_range <- range(bar_df$coef)
  if (diff(coef_range) == 0) {
    bar_df$color_val <- 0.5
  } else {
    bar_df$color_val <- (bar_df$coef - coef_range[1]) / diff(coef_range)
  }

  diff_cols <- sci_diff_colors()
  p_bar <- ggplot(bar_df, aes(x = coef, y = feature_label)) +
    geom_col(aes(fill = color_val), width = 0.75) +
    scale_fill_gradient2(
      low = diff_cols$down, mid = "grey90", high = diff_cols$up,
      midpoint = 0.5, guide = "none"
    ) +
    geom_vline(xintercept = 0, linetype = "solid", color = "grey30", linewidth = sci_linewidth) +
    labs(
      x = "Coefficient (case vs control)",
      y = NULL,
      title = paste("Top", top_n, "Differential Functional Features")
    ) +
    theme_pub(base_size = 7) +
    theme(
      axis.text.y = element_text(size = 7),
      plot.title = element_text(size = 8, face = "bold", hjust = 0.5),
      panel.grid.major.x = element_line(color = "grey92", linewidth = sci_linewidth)
    )

  if (any(is.finite(bar_df$stderr))) {
    p_bar <- p_bar +
      geom_errorbarh(
        aes(xmin = coef - stderr, xmax = coef + stderr),
        height = 0.2,
        linewidth = sci_linewidth,
        color = "grey20",
        na.rm = TRUE
      )
  }

  export_pub_figure(p_bar, file.path(figures_dir, "barplot_top20"),
                    width_mm = width_1_5col, height_mm = top_n * 5 + 20)
  })
}

# ========== Visualization 3: Boxplot (Top 10) ==========
if ("boxplot_top10" %in% allowed_visual_steps) {
  visualization_step_ok["boxplot_top10"] <- run_step("boxplot_top10", status_log, {
  top10_features <- sig_features %>%
    dplyr::slice_max(order_by = abs(coef), n = min(10, nrow(sig_features))) %>%
    dplyr::pull(feature)

  box_df <- merged_df %>%
    dplyr::select(sample_id, !!rlang::sym(group_col), dplyr::all_of(top10_features)) %>%
    tidyr::pivot_longer(cols = dplyr::all_of(top10_features),
                        names_to = "feature", values_to = "abundance") %>%
    dplyr::mutate(
      feature_short = format_functional_label(feature, func_type, width = 50),
      rel_abund_pct = abundance * 100
    )

  grp_levels <- levels(factor(merged_df[[group_col]]))
  group_colors <- setNames(npg_pal(length(grp_levels)), grp_levels)

  p_box <- ggplot(box_df, aes(x = !!rlang::sym(group_col), y = rel_abund_pct,
                                fill = !!rlang::sym(group_col))) +
    geom_boxplot(
      outlier.shape = NA,
      width = 0.65, linewidth = sci_linewidth, alpha = 0.8
    ) +
    geom_jitter(width = 0.18, alpha = 0.4, size = 0.6, shape = 16) +
    stat_summary(
      fun.data = function(x) {
        n <- sum(!is.na(x))
        ymax <- suppressWarnings(max(x, na.rm = TRUE))
        if (!is.finite(ymax)) {
          ymax <- 0
        }
        data.frame(y = ymax * 1.1 + ifelse(ymax == 0, 0.01, 0), label = paste0("n=", n))
      },
      geom = "text",
      size = sci_text_size,
      vjust = -0.4,
      color = "grey30"
    ) +
    facet_wrap(~ feature_short, scales = "free_y", ncol = 5) +
    scale_fill_manual(values = group_colors, name = NULL) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.15))) +
    labs(x = NULL, y = "Relative Abundance (%)") +
    theme_pub(base_size = 7) +
    theme(
      strip.text = element_text(size = 7, face = "bold"),
      strip.background = element_rect(fill = "grey95", color = "grey80", linewidth = sci_linewidth),
      axis.text.x = element_text(angle = 35, hjust = 1, size = 7),
      legend.position = "bottom",
      legend.key.size = unit(3, "mm"),
      panel.spacing = unit(1.5, "mm")
    )

  n_features <- length(top10_features)
  n_rows <- ceiling(n_features / 5)
  export_pub_figure(p_box, file.path(figures_dir, "boxplot_top10"),
                    width_mm = width_1_5col, height_mm = max(80, n_rows * 38))
  })
}

# ========== Visualization 4: Heatmap ==========
if ("heatmap_significant" %in% allowed_visual_steps) {
  visualization_step_ok["heatmap_significant"] <- run_step("heatmap_significant", status_log, {
  sig_feature_names <- sig_features$feature

  heatmap_mat <- merged_df %>%
    dplyr::select(sample_id, !!rlang::sym(group_col), dplyr::all_of(sig_feature_names)) %>%
    tibble::column_to_rownames("sample_id") %>%
    dplyr::select(-!!rlang::sym(group_col))

  # Transpose: samples as columns, functional features as rows
  heatmap_mat <- t(as.matrix(heatmap_mat))
  heatmap_mat <- log10(heatmap_mat + 1e-6)
  heatmap_mat <- t(scale(t(heatmap_mat)))  # Z-score per functional feature
  heatmap_mat[!is.finite(heatmap_mat)] <- 0
  row_labels_annotated <- format_functional_label(rownames(heatmap_mat), func_type, width = 80)

  sample_groups <- merged_df[[group_col]]
  names(sample_groups) <- merged_df$sample_id
  sample_order <- order(sample_groups, merged_df$sample_id)

  # Reorder columns (samples) by group
  heatmap_mat <- heatmap_mat[, merged_df$sample_id[sample_order], drop = FALSE]

  col_fun <- circlize::colorRamp2(
    c(-2.5, 0, 2.5),
    c("#4DBBD5", "#F7F7F7", "#E64B35")
  )

  grp_levels <- unique(sample_groups)
  group_colors_annot <- setNames(npg_pal(length(grp_levels)), grp_levels)
  ha <- ComplexHeatmap::HeatmapAnnotation(
    Group = sample_groups[merged_df$sample_id[sample_order]],
    col = list(Group = group_colors_annot),
    show_legend = TRUE,
    annotation_name_side = "left",
    annotation_name_gp = grid::gpar(fontsize = 7, fontface = "bold"),
    simple_anno_size = grid::unit(3, "mm"),
    border = TRUE
  )

  ht <- ComplexHeatmap::Heatmap(
    heatmap_mat,
    name = "Z-score",
    col = col_fun,
    top_annotation = ha,
    cluster_rows = TRUE,
    cluster_columns = FALSE,
    show_row_names = TRUE,
    show_column_names = FALSE,
    row_labels = row_labels_annotated,
    row_names_gp = grid::gpar(fontsize = 7),
    column_names_gp = grid::gpar(fontsize = 7),
    row_names_max_width = grid::unit(10, "cm"),
    column_title = "Differential Functional Feature Heatmap",
    column_title_gp = grid::gpar(fontsize = 9, fontface = "bold"),
    heatmap_legend_param = list(
      title = "Z-score",
      title_gp = grid::gpar(fontsize = 7, fontface = "bold"),
      labels_gp = grid::gpar(fontsize = 7),
      legend_height = grid::unit(25, "mm"),
      border = "grey40"
    ),
    border = TRUE,
    row_dend_width = grid::unit(8, "mm"),
    width = grid::unit(120, "mm")
  )

  export_heatmap(
    ht,
    file.path(figures_dir, "heatmap_significant"),
    width_mm = width_2col,
    height_mm = max(100, nrow(heatmap_mat) * 4)
  )
  })
}

# ========== Enrichment Analysis + Sankey Visualization ==========
if ("enrichment_sankey" %in% allowed_visual_steps) {
  visualization_step_ok["enrichment_sankey"] <- run_step("enrichment_sankey", status_log, {
  # Use the prefix before ":" as a lightweight functional category when present.
  sig_features_enrichment <- sig_features %>%
    dplyr::mutate(
      functional_category = sapply(strsplit(feature, ":"), function(x) {
        if (length(x) > 1) trimws(x[1]) else "Other"
      }),
      functional_category = ifelse(functional_category == "", "Other", functional_category)
    )

  # Count functional features per category
  category_counts <- sig_features_enrichment %>%
    dplyr::group_by(functional_category) %>%
    dplyr::summarise(
      n_pathways = n(),
      avg_abs_coef = mean(abs(coef)),
      min_qval = min(qval)
    ) %>%
    dplyr::arrange(desc(n_pathways)) %>%
    dplyr::slice_head(n = 12)  # Top 12 categories for visualization

  # Prepare sankey data
  sankey_data <- sig_features_enrichment %>%
    dplyr::filter(functional_category %in% category_counts$functional_category) %>%
    dplyr::select(functional_category, feature, coef, qval) %>%
    dplyr::mutate(
      feature_short = format_functional_label(feature, func_type, width = 40),
      count = abs(coef) * 100  # Scale for visual weight
    )

  # ggsankeyfier format
  sankey_stages <- sankey_data %>%
    dplyr::select(functional_category, feature_short, count) %>%
    ggsankeyfier::pivot_stages_longer(
      stages_from = c("functional_category", "feature_short"),
      values_from = "count"
    )

  # Color palette
  category_nodes <- unique(sankey_data$functional_category)
  feature_nodes <- unique(sankey_data$feature_short)
  node_colors <- c(
    setNames(
      grDevices::colorRampPalette(RColorBrewer::brewer.pal(12, "Paired"))(length(category_nodes)),
      category_nodes
    ),
    setNames(
      grDevices::colorRampPalette(RColorBrewer::brewer.pal(9, "Set1"))(length(feature_nodes)),
      feature_nodes
    )
  )

  # Sankey plot (left panel)
  p_sankey <- ggplot(sankey_stages, aes(x = stage, y = count,
                                          group = node,
                                          edge_id = edge_id,
                                          connector = connector)) +
    geom_sankeyedge(
      position = position_sankey(order = "ascending", v_space = "auto", width = 0.05)
    ) +
    geom_sankeynode(
      aes(fill = node, color = node),
      position = position_sankey(order = "ascending", v_space = "auto", width = 0.05)
    ) +
    geom_text(
      data = sankey_stages %>% dplyr::filter(connector == "from"),
      aes(label = node), stat = "sankeynode",
      position = position_sankey(v_space = "auto", order = "ascending", nudge_x = -0.05),
      hjust = 1, size = sci_text_size, color = "black"
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.01, 0))) +
    scale_x_discrete(expand = c(0, 0)) +
    scale_fill_manual(values = node_colors) +
    scale_color_manual(values = node_colors) +
    labs(x = NULL, y = NULL, title = "Functional Category to Functional Feature Flow") +
    coord_cartesian(clip = "off") +
    theme_pub(base_size = 7) +
    theme(
      legend.position = "none",
      axis.text = element_blank(),
      axis.ticks = element_blank(),
      plot.margin = margin(0, 0, 0, 5, unit = "cm"),
      plot.title = element_text(size = 8, face = "bold", hjust = 0.5)
    )

  # Bubble plot (right panel) - enrichment summary
  bubble_data <- category_counts %>%
    dplyr::mutate(
      neg_log10_qval = -log10(min_qval),
      enrichment_ratio = n_pathways / nrow(sig_features)
    )

  p_bubble <- ggplot(bubble_data, aes(x = neg_log10_qval, y = reorder(functional_category, n_pathways),
                                        color = enrichment_ratio, size = n_pathways)) +
    geom_point(alpha = 0.8) +
    scale_color_gradientn(
      colours = RColorBrewer::brewer.pal(9, "YlOrRd")[3:8],
      name = "Enrichment\nRatio"
    ) +
    scale_size_continuous(range = c(2, 8), name = "# Functional\nFeatures") +
    scale_x_continuous(expand = expansion(mult = c(0.05, 0.15))) +
    labs(
      x = "-log<sub>10</sub>(<i>q</i>-value)",
      y = NULL,
      title = "Functional Category Enrichment"
    ) +
    theme_pub(base_size = 7) +
    theme(
      axis.title.x = element_markdown(),
      axis.text.y = element_text(size = 7),
      plot.title = element_text(size = 8, face = "bold", hjust = 0.5),
      legend.position = "right",
      legend.key.size = unit(3, "mm")
    )

  # Combine with patchwork
  p_combined <- (p_sankey | p_bubble) +
    patchwork::plot_layout(widths = c(2, 1))

  export_pub_figure(p_combined, file.path(figures_dir, "sankey_enrichment"),
                    width_mm = width_2col, height_mm = 140)

  # Save enrichment table
  enrichment_out <- category_counts %>%
    dplyr::rename(superpathway = functional_category)
  utils::write.table(enrichment_out, file.path(results_dir, "enrichment.tsv"),
                     sep = "\t", quote = FALSE, row.names = FALSE)
  })
}

failed_visual_steps <- names(visualization_step_ok)[!visualization_step_ok]
generated_visuals <- unname(managed_visual_outputs[allowed_visual_steps])
skipped_visuals <- unname(managed_visual_outputs[skipped_visual_steps])
visualization_message <- sprintf(
  "%s; generated: %s; skipped: %s",
  visualization_strategy_label,
  paste(generated_visuals, collapse = ", "),
  if (length(skipped_visuals)) paste(skipped_visuals, collapse = ", ") else "none"
)
if (length(failed_visual_steps)) {
  visualization_message <- paste0(
    visualization_message,
    "; failed: ",
    paste(unname(managed_visual_outputs[failed_visual_steps]), collapse = ", ")
  )
}
append_status(
  "visualization",
  if (length(failed_visual_steps)) "FAILED" else "OK",
  visualization_message
)

write_status(status_log, status_tsv)
writeLines(format(Sys.time()), sentinel)
cat("[INFO] Functional analysis finished\n")
