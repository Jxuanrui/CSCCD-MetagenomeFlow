#!/usr/bin/env Rscript
# ==============================================================================
# Script: generate_test_data_1000.R
# Purpose: Generate a 1000-sample synthetic MaxMetagenome test dataset.
# Usage:   Rscript scripts/generate_test_data_1000.R [workdir] [repo_root]
# ==============================================================================

options(stringsAsFactors = FALSE, scipen = 999, warn = 1)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

RNGkind("L'Ecuyer-CMRG")
set.seed(42)

suppressPackageStartupMessages({
  library(MASS)
  library(parallel)
})

has_dirmult <- requireNamespace("dirmult", quietly = TRUE)
if (has_dirmult) {
  suppressPackageStartupMessages(library(dirmult))
} else {
  warning("Package 'dirmult' is not installed; using gamma-normalized Dirichlet fallback.")
}

args <- commandArgs(trailingOnly = TRUE)
repo_root <- normalizePath(args[2] %||% getwd(), winslash = "/", mustWork = FALSE)
workdir <- args[1] %||% file.path("Project", "Test_100samples")
if (!grepl("^/", workdir)) {
  workdir <- file.path(repo_root, workdir)
}
workdir <- normalizePath(workdir, winslash = "/", mustWork = FALSE)

n_samples <- 1000L
n_case <- 500L
n_control <- 500L
sample_ids <- paste0("S", sprintf("%03d", seq_len(n_samples)))
mc_cores <- min(8L, max(1L, parallel::detectCores(logical = FALSE) %||% 1L))
if (.Platform$OS.type == "windows") {
  mc_cores <- 1L
}

dir.create(workdir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Workdir:", workdir, "\n")
cat("[INFO] Repo root:", repo_root, "\n")
cat("[INFO] Parallel cores:", mc_cores, "\n")
cat("[INFO] Dirichlet sampler:", if (has_dirmult) "dirmult::rdirichlet" else "rgamma fallback", "\n")

truth_rows <- list()

add_truth <- function(dimension, database, truth_df) {
  if (is.null(truth_df) || !nrow(truth_df)) {
    return(invisible(NULL))
  }
  truth_df$dimension <- dimension
  truth_df$database <- database
  truth_rows[[length(truth_rows) + 1L]] <<- truth_df[
    ,
    c("dimension", "database", "feature", "direction", "expected_log2FC", "diff_rank"),
    drop = FALSE
  ]
  invisible(NULL)
}

bounded_normal <- function(n, mean, sd, lower, upper, digits = 0L) {
  x <- rnorm(n, mean, sd)
  tries <- 0L
  while (any(x < lower | x > upper) && tries < 100L) {
    idx <- which(x < lower | x > upper)
    x[idx] <- rnorm(length(idx), mean, sd)
    tries <- tries + 1L
  }
  x <- pmin(pmax(x, lower), upper)
  round(x, digits)
}

dirichlet_one <- function(alpha) {
  alpha <- pmax(as.numeric(alpha), 1e-8)
  if (has_dirmult) {
    as.numeric(dirmult::rdirichlet(1L, alpha))
  } else {
    x <- stats::rgamma(length(alpha), shape = alpha, rate = 1)
    x / sum(x)
  }
}

split_indices <- function(n, chunk_size = 25L) {
  split(seq_len(n), ceiling(seq_len(n) / chunk_size))
}

make_base_alpha <- function(n_features, concentration = 50, power = 1.1) {
  raw <- 1 / (seq_len(n_features)^power)
  raw <- raw * exp(rnorm(n_features, 0, 0.35))
  raw <- sort(raw, decreasing = TRUE)
  pmax(raw / sum(raw) * concentration, 1e-5)
}

simulate_dm_counts <- function(
  feature_ids,
  metadata,
  n_diff,
  total_counts,
  concentration = 60,
  power = 1.1,
  min_prev = 0.05,
  max_prev = 0.80,
  diff_prev = 0.90,
  batch_sd = 0.15,
  log2fc_range = c(1.5, 3.0),
  chunk_size = 25L
) {
  n_features <- length(feature_ids)
  stopifnot(n_features > 1L, nrow(metadata) == length(total_counts))

  base_alpha <- make_base_alpha(n_features, concentration = concentration, power = power)

  n_diff <- min(n_diff, n_features)
  n_up <- ceiling(n_diff / 2)
  n_down <- n_diff - n_up
  candidate_n <- min(n_features, max(n_diff * 4L, n_diff))
  diff_idx <- sort(sample(seq_len(candidate_n), n_diff))
  up_idx <- diff_idx[seq_len(n_up)]
  down_idx <- if (n_down > 0L) diff_idx[(n_up + 1L):n_diff] else integer(0L)

  up_log2fc <- runif(n_up, log2fc_range[1], log2fc_range[2])
  down_log2fc <- if (n_down > 0L) -runif(n_down, log2fc_range[1], log2fc_range[2]) else numeric(0L)

  case_multiplier <- rep(1, n_features)
  case_multiplier[up_idx] <- 2^up_log2fc
  if (length(down_idx)) {
    case_multiplier[down_idx] <- 2^down_log2fc
  }

  abundance_rank <- rank(base_alpha, ties.method = "average") / n_features
  prevalence <- min_prev + (max_prev - min_prev) * abundance_rank^0.55
  prevalence <- prevalence + rnorm(n_features, 0, 0.04)
  prevalence <- pmin(pmax(prevalence, min_prev), max_prev)
  prevalence[diff_idx] <- pmax(prevalence[diff_idx], diff_prev)

  batch_effect <- matrix(
    2^rnorm(n_features * 5L, mean = 0, sd = batch_sd),
    nrow = n_features,
    ncol = 5L
  )

  draw_one <- function(i) {
    alpha <- base_alpha
    if (identical(metadata$group[i], "case")) {
      alpha <- alpha * case_multiplier
    }
    batch_i <- suppressWarnings(as.integer(sub("^batch", "", metadata$batch[i])))
    if (is.na(batch_i) || batch_i < 1L || batch_i > 5L) {
      batch_i <- 1L
    }
    alpha <- alpha * batch_effect[, batch_i]

    active <- runif(n_features) < prevalence
    if (length(diff_idx)) {
      active[diff_idx] <- runif(length(diff_idx)) < diff_prev
    }
    if (sum(active) < 2L) {
      active[order(alpha, decreasing = TRUE)[seq_len(min(2L, n_features))]] <- TRUE
    }

    p <- numeric(n_features)
    p[active] <- dirichlet_one(alpha[active])
    as.numeric(stats::rmultinom(1L, size = as.integer(total_counts[i]), prob = p))
  }

  chunks <- split_indices(nrow(metadata), chunk_size = chunk_size)
  if (mc_cores > 1L && length(chunks) > 1L) {
    res <- parallel::mclapply(
      chunks,
      function(idx) do.call(cbind, lapply(idx, draw_one)),
      mc.cores = min(mc_cores, length(chunks)),
      mc.set.seed = TRUE
    )
  } else {
    res <- lapply(chunks, function(idx) do.call(cbind, lapply(idx, draw_one)))
  }
  counts <- do.call(cbind, res)
  rownames(counts) <- feature_ids
  colnames(counts) <- metadata$sample_id

  truth <- data.frame(
    feature = feature_ids[c(up_idx, down_idx)],
    direction = c(rep("case_enriched", length(up_idx)), rep("control_enriched", length(down_idx))),
    expected_log2FC = c(up_log2fc, down_log2fc),
    diff_rank = seq_len(length(c(up_idx, down_idx))),
    stringsAsFactors = FALSE
  )

  list(counts = counts, truth = truth)
}

counts_to_relab <- function(counts, scale = 1) {
  totals <- colSums(counts)
  totals[totals == 0] <- 1
  sweep(counts, 2L, totals, "/") * scale
}

counts_to_tpm <- function(counts) {
  counts_to_relab(counts, scale = 1e6)
}

safe_write_tsv <- function(df, path, append = FALSE, col_names = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.table(
    df,
    file = path,
    sep = "\t",
    quote = FALSE,
    row.names = FALSE,
    col.names = col_names,
    append = append,
    na = ""
  )
}

write_feature_table <- function(path, feature_col, feature_ids, values) {
  df <- data.frame(feature_ids, values, check.names = FALSE)
  colnames(df) <- c(feature_col, colnames(values))
  safe_write_tsv(df, path)
  invisible(path)
}

clean_tax_value <- function(x, fallback = "unclassified") {
  x <- trimws(as.character(x))
  x <- sub("^[a-z]__", "", x)
  x <- gsub("\\[[^]]*\\]", "", x)
  x <- gsub("\\([^)]*\\)", "", x)
  x <- gsub("[^A-Za-z0-9_. -]", " ", x)
  x <- gsub("\\s+", "_", trimws(x))
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  ifelse(nzchar(x), x, fallback)
}

standardize_metaphlan_clade <- function(clade, kingdom = "Bacteria") {
  parts <- strsplit(clade, "\\|")[[1]]
  parts <- parts[!grepl("^str__", parts)]
  ranks <- c("k__", "p__", "c__", "o__", "f__", "g__", "s__")
  out <- character(length(ranks))
  for (i in seq_along(ranks)) {
    hit <- parts[startsWith(parts, ranks[i])]
    if (length(hit)) {
      out[i] <- paste0(ranks[i], clean_tax_value(hit[1]))
    } else if (i == 1L) {
      out[i] <- paste0("k__", kingdom)
    } else {
      out[i] <- paste0(ranks[i], paste0("unclassified_", i))
    }
  }
  paste(out, collapse = "|")
}

parse_gtdb_lineage <- function(lineage) {
  parts <- strsplit(lineage, ";", fixed = TRUE)[[1]]
  get_rank <- function(prefix, fallback) {
    hit <- parts[startsWith(parts, prefix)]
    if (length(hit)) clean_tax_value(hit[1], fallback = fallback) else fallback
  }
  vals <- c(
    k = "Bacteria",
    p = get_rank("p__", "Bacteria_unclassified_phylum"),
    c = get_rank("c__", "Bacteria_unclassified_class"),
    o = get_rank("o__", "Bacteria_unclassified_order"),
    f = get_rank("f__", "Bacteria_unclassified_family"),
    g = get_rank("g__", "Bacteria_unclassified_genus"),
    s = get_rank("s__", "Bacteria_unclassified_species")
  )
  if (grepl("unclassified_species$|^sp$|^$", vals[["s"]])) {
    return(NA_character_)
  }
  paste0(
    "k__", vals[["k"]], "|p__", vals[["p"]], "|c__", vals[["c"]],
    "|o__", vals[["o"]], "|f__", vals[["f"]], "|g__", vals[["g"]],
    "|s__", vals[["s"]]
  )
}

manual_bacteria_taxa <- function() {
  c(
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Oscillospiraceae|g__Faecalibacterium|s__Faecalibacterium_prausnitzii",
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Lachnospiraceae|g__Roseburia|s__Roseburia_inulinivorans",
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Lachnospiraceae|g__Eubacterium|s__Eubacterium_rectale",
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Lachnospiraceae|g__Blautia|s__Blautia_wexlerae",
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Ruminococcaceae|g__Ruminococcus|s__Ruminococcus_bromii",
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Oscillospiraceae|g__Anaerostipes|s__Anaerostipes_hadrus",
    "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__Eubacteriaceae|g__Eubacterium|s__Eubacterium_eligens",
    "k__Bacteria|p__Bacteroidetes|c__Bacteroidia|o__Bacteroidales|f__Bacteroidaceae|g__Bacteroides|s__Bacteroides_fragilis",
    "k__Bacteria|p__Bacteroidetes|c__Bacteroidia|o__Bacteroidales|f__Bacteroidaceae|g__Bacteroides|s__Bacteroides_uniformis",
    "k__Bacteria|p__Bacteroidetes|c__Bacteroidia|o__Bacteroidales|f__Bacteroidaceae|g__Bacteroides|s__Bacteroides_vulgatus",
    "k__Bacteria|p__Bacteroidetes|c__Bacteroidia|o__Bacteroidales|f__Prevotellaceae|g__Prevotella|s__Prevotella_copri",
    "k__Bacteria|p__Bacteroidetes|c__Bacteroidia|o__Bacteroidales|f__Rikenellaceae|g__Alistipes|s__Alistipes_putredinis",
    "k__Bacteria|p__Actinobacteria|c__Actinomycetia|o__Bifidobacteriales|f__Bifidobacteriaceae|g__Bifidobacterium|s__Bifidobacterium_longum",
    "k__Bacteria|p__Actinobacteria|c__Actinomycetia|o__Bifidobacteriales|f__Bifidobacteriaceae|g__Bifidobacterium|s__Bifidobacterium_adolescentis",
    "k__Bacteria|p__Actinobacteria|c__Coriobacteriia|o__Coriobacteriales|f__Coriobacteriaceae|g__Collinsella|s__Collinsella_aerofaciens",
    "k__Bacteria|p__Verrucomicrobia|c__Verrucomicrobiae|o__Verrucomicrobiales|f__Akkermansiaceae|g__Akkermansia|s__Akkermansia_muciniphila",
    "k__Bacteria|p__Proteobacteria|c__Gammaproteobacteria|o__Enterobacterales|f__Enterobacteriaceae|g__Escherichia|s__Escherichia_coli",
    "k__Bacteria|p__Proteobacteria|c__Gammaproteobacteria|o__Enterobacterales|f__Enterobacteriaceae|g__Klebsiella|s__Klebsiella_pneumoniae",
    "k__Bacteria|p__Firmicutes|c__Negativicutes|o__Veillonellales|f__Veillonellaceae|g__Dialister|s__Dialister_invisus",
    "k__Bacteria|p__Firmicutes|c__Bacilli|o__Lactobacillales|f__Lactobacillaceae|g__Lactobacillus|s__Lactobacillus_rhamnosus"
  )
}

load_bacteria_taxa <- function(n) {
  taxa <- manual_bacteria_taxa()
  gtdb_path <- file.path(repo_root, "db", "gtdbtk", "taxonomy", "bac120_taxonomy_r214_reps.tsv")
  if (file.exists(gtdb_path)) {
    lines <- readLines(gtdb_path, warn = FALSE)
    fields <- strsplit(lines, "\t", fixed = TRUE)
    lineage <- vapply(fields, function(x) if (length(x) >= 2L) x[2L] else NA_character_, character(1))
    gtdb_taxa <- unique(stats::na.omit(vapply(lineage, parse_gtdb_lineage, character(1))))
    if (length(gtdb_taxa)) {
      taxa <- unique(c(taxa, sample(gtdb_taxa, min(length(gtdb_taxa), n * 3L))))
    }
  }

  if (length(taxa) < n) {
    genera <- c("Bacteroides", "Prevotella", "Alistipes", "Blautia", "Roseburia",
                "Ruminococcus", "Eubacterium", "Clostridium", "Coprococcus",
                "Parabacteroides", "Odoribacter", "Oscillibacter", "Dorea")
    for (i in seq_len(n - length(taxa))) {
      genus <- genera[(i - 1L) %% length(genera) + 1L]
      taxa <- c(
        taxa,
        paste0(
          "k__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|",
          "f__", genus, "aceae|g__", genus, "|s__", genus, "_sp_", sprintf("%03d", i)
        )
      )
    }
  }
  taxa <- unique(taxa)
  taxa[seq_len(n)]
}

manual_fungi_taxa <- function() {
  c(
    "k__Fungi|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|f__Saccharomycetaceae|g__Saccharomyces|s__Saccharomyces_cerevisiae",
    "k__Fungi|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|f__Debaryomycetaceae|g__Candida|s__Candida_albicans",
    "k__Fungi|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|f__Debaryomycetaceae|g__Candida|s__Candida_tropicalis",
    "k__Fungi|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|f__Debaryomycetaceae|g__Candida|s__Candida_parapsilosis",
    "k__Fungi|p__Ascomycota|c__Eurotiomycetes|o__Eurotiales|f__Aspergillaceae|g__Aspergillus|s__Aspergillus_fumigatus",
    "k__Fungi|p__Ascomycota|c__Eurotiomycetes|o__Eurotiales|f__Aspergillaceae|g__Aspergillus|s__Aspergillus_niger",
    "k__Fungi|p__Ascomycota|c__Eurotiomycetes|o__Eurotiales|f__Aspergillaceae|g__Penicillium|s__Penicillium_chrysogenum",
    "k__Fungi|p__Basidiomycota|c__Tremellomycetes|o__Tremellales|f__Cryptococcaceae|g__Cryptococcus|s__Cryptococcus_neoformans",
    "k__Fungi|p__Basidiomycota|c__Malasseziomycetes|o__Malasseziales|f__Malasseziaceae|g__Malassezia|s__Malassezia_restricta",
    "k__Fungi|p__Mucoromycota|c__Mucoromycetes|o__Mucorales|f__Mucoraceae|g__Mucor|s__Mucor_circinelloides"
  )
}

load_fungi_taxa <- function(n) {
  taxa <- manual_fungi_taxa()
  funomic_path <- file.path(repo_root, "db", "funomic", "T", "taxonomy.txt")
  if (file.exists(funomic_path)) {
    lines <- readLines(funomic_path, warn = FALSE)
    fields <- strsplit(lines, "\t", fixed = TRUE)
    clades <- vapply(fields, function(x) if (length(x) >= 2L) x[2L] else NA_character_, character(1))
    clades <- clades[grepl("k__Fungi", clades) & grepl("\\|s__", clades)]
    clades <- sub("\\|str__.*$", "", clades)
    clades <- unique(vapply(clades, standardize_metaphlan_clade, character(1), kingdom = "Fungi"))
    if (length(clades)) {
      taxa <- unique(c(taxa, sample(clades, min(length(clades), n * 3L))))
    }
  }

  gut_path <- file.path(repo_root, "db", "gut_fungi_db", "db.fungi.taxonomy.tsv")
  if (file.exists(gut_path) && length(taxa) < n) {
    gut <- tryCatch(read.delim(gut_path, sep = "\t", check.names = FALSE), error = function(e) NULL)
    if (!is.null(gut) && all(c("Phylum", "Class", "Order", "family", "genus", "species") %in% names(gut))) {
      gut_clades <- paste0(
        "k__Fungi|p__", clean_tax_value(gut$Phylum),
        "|c__", clean_tax_value(gut$Class),
        "|o__", clean_tax_value(gut$Order),
        "|f__", clean_tax_value(gut$family),
        "|g__", clean_tax_value(gut$genus),
        "|s__", clean_tax_value(gut$species)
      )
      taxa <- unique(c(taxa, sample(unique(gut_clades), min(length(unique(gut_clades)), n * 2L))))
    }
  }

  if (length(taxa) < n) {
    genera <- c("Candida", "Saccharomyces", "Aspergillus", "Penicillium", "Malassezia", "Cryptococcus")
    for (i in seq_len(n - length(taxa))) {
      genus <- genera[(i - 1L) %% length(genera) + 1L]
      taxa <- c(
        taxa,
        paste0(
          "k__Fungi|p__Ascomycota|c__Saccharomycetes|o__Saccharomycetales|",
          "f__", genus, "aceae|g__", genus, "|s__", genus, "_sp_", sprintf("%03d", i)
        )
      )
    }
  }
  taxa <- unique(taxa)
  taxa[seq_len(n)]
}

aggregate_taxa_levels <- function(species_clades, species_matrix) {
  parts_list <- strsplit(species_clades, "\\|")
  max_level <- max(vapply(parts_list, length, integer(1)))
  all_names <- character()
  all_rows <- list()

  for (level in seq_len(max_level)) {
    prefixes <- vapply(parts_list, function(x) paste(x[seq_len(min(level, length(x)))], collapse = "|"), character(1))
    prefix_order <- unique(prefixes)
    agg <- t(vapply(
      prefix_order,
      function(prefix) colSums(species_matrix[prefixes == prefix, , drop = FALSE]),
      numeric(ncol(species_matrix))
    ))
    rownames(agg) <- prefix_order
    all_names <- c(all_names, prefix_order)
    all_rows[[length(all_rows) + 1L]] <- agg
  }

  out <- do.call(rbind, all_rows)
  out <- out[!duplicated(rownames(out)), , drop = FALSE]
  out
}

write_metaphlan_table <- function(path, clade_matrix) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cat("# Metaphlan4 v4.0.6\n", file = path)
  df <- data.frame(clade_name = rownames(clade_matrix), clade_matrix, check.names = FALSE)
  cat(paste(colnames(df), collapse = "\t"), "\n", file = path, append = TRUE, sep = "")
  safe_write_tsv(df, path, append = TRUE, col_names = FALSE)
  invisible(path)
}

write_fungi_profiles <- function(profile_root, clade_matrix, metadata) {
  for (sid in metadata$sample_id) {
    sample_dir <- file.path(profile_root, sid)
    dir.create(sample_dir, recursive = TRUE, showWarnings = FALSE)
    path <- file.path(sample_dir, paste0(sid, "_profile.txt"))
    cat(
      "#mpa_vOct22_CHOCOPhlAnSGB_202212\n",
      "#synthetic MetaPhlAn4-euk profile for MaxMetagenome tests\n",
      "#clade_name\tNCBI_tax_id\trelative_abundance\tadditional_species\n",
      file = path,
      sep = ""
    )
    df <- data.frame(
      clade_name = rownames(clade_matrix),
      NCBI_tax_id = "-1",
      relative_abundance = clade_matrix[, sid],
      additional_species = "",
      check.names = FALSE
    )
    safe_write_tsv(df, path, append = TRUE, col_names = FALSE)
  }
}

generate_metadata <- function() {
  seq_depth_raw <- rlnorm(n_samples, meanlog = log(10e6), sdlog = 0.38)
  seq_depth <- round(pmin(pmax(seq_depth_raw, 5e6), 20e6))
  data.frame(
    sample_id = sample_ids,
    group = c(rep("case", n_case), rep("control", n_control)),
    age = bounded_normal(n_samples, 50, 10, 25, 75, digits = 0L),
    gender = sample(c("male", "female"), n_samples, replace = TRUE),
    bmi = bounded_normal(n_samples, 24, 4, 18, 35, digits = 1L),
    batch = sample(paste0("batch", 1:5), n_samples, replace = TRUE),
    seq_depth = as.integer(seq_depth),
    stringsAsFactors = FALSE
  )
}

make_pathway_ids <- function(n) {
  labels <- c(
    "Glycolysis", "Amino Acid Biosynthesis", "TCA Cycle", "Pentose Phosphate Pathway",
    "Butyrate Production", "Propionate Production", "Methanogenesis", "Bile Acid Metabolism",
    "Lipopolysaccharide Biosynthesis", "Peptidoglycan Biosynthesis", "Flagellar Assembly",
    "Oxidative Phosphorylation", "Vitamin B12 Biosynthesis", "Folate Biosynthesis",
    "Purine Metabolism", "Pyrimidine Metabolism", "Starch Degradation", "Mucin Degradation",
    "Sulfur Metabolism", "Nitrogen Metabolism"
  )
  paste0(labels[(seq_len(n) - 1L) %% length(labels) + 1L], ": pathway", sprintf("%03d", seq_len(n)))
}

make_kegg_ids <- function(n, offset = 0L) paste0("K", sprintf("%05d", offset + seq_len(n)))

make_cog_ids <- function(n) {
  vals <- c("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
            "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Z")
  vals[seq_len(n)]
}

make_cazyme_ids <- function(n) {
  prefixes <- c("GH", "GT", "PL", "CE", "AA", "CBM")
  paste0(prefixes[(seq_len(n) - 1L) %% length(prefixes) + 1L], ceiling(seq_len(n) / length(prefixes)))
}

make_arg_ids <- function(n) {
  base <- c(
    "blaTEM", "blaCTX-M", "blaSHV", "blaOXA", "mecA", "vanA", "vanB", "tetM", "tetQ", "tetW",
    "ermB", "ermC", "msrD", "mphA", "aac(6')-Ib", "aph(3')-III", "aadA", "sul1", "sul2",
    "dfrA1", "dfrA12", "qnrS", "qnrB", "catA", "floR", "cfr", "optrA", "lnuA", "fosA", "mcr1"
  )
  if (n <= length(base)) return(base[seq_len(n)])
  c(base, paste0(rep(base, length.out = n - length(base)), "_var", seq_len(n - length(base))))
}

make_vfdb_ids <- function(n, offset = 0L) paste0("VFG", sprintf("%06d", offset + seq_len(n)))

make_defense_ids <- function(n) {
  vals <- c(
    "RM_Type_I", "RM_Type_II", "RM_Type_III", "RM_Type_IV", "CRISPR-Cas_I-E",
    "CRISPR-Cas_I-F", "CRISPR-Cas_II-A", "CRISPR-Cas_III-A", "AbiE", "AbiG",
    "BREX", "DISARM", "Dnd", "Druantia", "Gabija", "Gao", "Hachiman", "Kiwa",
    "Lamassu", "Mokosh", "Septu", "Shedu", "Thoeris", "Wadjet", "Zorya"
  )
  vals[seq_len(n)]
}

make_merops_ids <- function(n) {
  vals <- c("M01", "M03", "M04", "M08", "M16", "M20", "S01", "S08", "S09", "S10", "S12", "S16")
  vals[seq_len(n)]
}

make_phrog_ids <- function() {
  c(
    "head and packaging",
    "tail",
    "lysis",
    "DNA, RNA and nucleotide metabolism",
    "integration and excision",
    "transcription regulation",
    "other",
    "moron, auxiliary metabolic gene and host takeover"
  )
}

run_function_table <- function(
  metadata,
  dimension,
  database,
  feature_col,
  feature_ids,
  n_diff,
  path,
  total_counts,
  value_type = c("tpm", "relab", "counts"),
  concentration = 80,
  power = 1.05,
  min_prev = 0.05,
  max_prev = 0.85,
  diff_prev = 0.90,
  batch_sd = 0.12
) {
  value_type <- match.arg(value_type)
  sim <- simulate_dm_counts(
    feature_ids = feature_ids,
    metadata = metadata,
    n_diff = n_diff,
    total_counts = total_counts,
    concentration = concentration,
    power = power,
    min_prev = min_prev,
    max_prev = max_prev,
    diff_prev = diff_prev,
    batch_sd = batch_sd
  )

  values <- switch(
    value_type,
    tpm = counts_to_tpm(sim$counts),
    relab = counts_to_relab(sim$counts, scale = 1),
    counts = round(sim$counts)
  )
  colnames(values) <- metadata$sample_id
  rownames(values) <- feature_ids

  write_feature_table(path, feature_col, feature_ids, values)
  add_truth(dimension, database, sim$truth)
  cat(sprintf("[INFO]   %-24s %5d features -> %s\n", paste0(dimension, ":", database), length(feature_ids), path))
  invisible(values)
}

generate_bacteria_species <- function(metadata) {
  cat("[INFO] Generating bacteria species abundance...\n")
  species <- load_bacteria_taxa(300L)
  sim <- simulate_dm_counts(
    feature_ids = species,
    metadata = metadata,
    n_diff = 30L,
    total_counts = pmax(100000L, round(metadata$seq_depth * 0.55)),
    concentration = 65,
    power = 1.15,
    min_prev = 0.05,
    max_prev = 0.85,
    diff_prev = 0.92,
    batch_sd = 0.12
  )
  species_relab <- counts_to_relab(sim$counts, scale = 1)
  bacteria_total <- runif(nrow(metadata), 96.5, 99.8)
  species_percent <- sweep(species_relab, 2L, bacteria_total, "*")
  rownames(species_percent) <- species
  colnames(species_percent) <- metadata$sample_id
  clade_matrix <- aggregate_taxa_levels(species, species_percent)

  write_metaphlan_table(
    file.path(workdir, "result", "bacteria", "metaphlan4", "merged_abundance_table.txt"),
    clade_matrix
  )
  write_metaphlan_table(
    file.path(workdir, "result", "bacteria", "metaphlan4", "merged", "taxonomy.tsv"),
    clade_matrix
  )
  write_metaphlan_table(
    file.path(workdir, "result", "bacteria", "metaphlan4", "merged", "merged_abundance_table.txt"),
    clade_matrix
  )
  add_truth("bacteria", "species", sim$truth)
  cat(sprintf("[INFO]   bacteria species rows: %d species, %d total clades\n", length(species), nrow(clade_matrix)))
}

generate_bacteria_functions <- function(metadata) {
  cat("[INFO] Generating bacteria functional abundance...\n")
  base <- file.path(workdir, "result", "integration", "bacteria")
  humann <- file.path(workdir, "result", "bacteria", "humann3", "merged")
  totals <- pmax(50000L, round(metadata$seq_depth * 0.08))

  run_function_table(metadata, "bacteria", "pathway", "# Pathway", make_pathway_ids(150L), 20L,
                     file.path(humann, "pathabundance_relab.tsv"), totals,
                     value_type = "relab", concentration = 85, min_prev = 0.35, max_prev = 0.95)
  run_function_table(metadata, "bacteria", "kegg_ko", "KEGG_KO", make_kegg_ids(3650L), 50L,
                     file.path(base, "kegg_ko_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 140, min_prev = 0.02, max_prev = 0.55)
  run_function_table(metadata, "bacteria", "cog", "COG_category", make_cog_ids(25L), 5L,
                     file.path(base, "cog_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 90, min_prev = 0.70, max_prev = 0.99)
  run_function_table(metadata, "bacteria", "cazyme", "CAZyme_family", make_cazyme_ids(120L), 15L,
                     file.path(base, "cazyme_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 80, min_prev = 0.20, max_prev = 0.90)
  run_function_table(metadata, "bacteria", "arg", "ARG_gene", make_arg_ids(80L), 10L,
                     file.path(base, "arg_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 65, min_prev = 0.12, max_prev = 0.78)
  run_function_table(metadata, "bacteria", "vfdb", "VF_gene", make_vfdb_ids(120L), 12L,
                     file.path(base, "vfdb_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 75, min_prev = 0.15, max_prev = 0.85)
  run_function_table(metadata, "bacteria", "defense", "Defense_system", make_defense_ids(25L), 5L,
                     file.path(base, "defense_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 70, min_prev = 0.55, max_prev = 0.98)
  run_function_table(metadata, "bacteria", "ncyc", "NCyc_gene", c("nifH", "amoA", "hao", "nirK", "nosZ"), 2L,
                     file.path(base, "ncyc_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 45, min_prev = 0.70, max_prev = 1.00)
  run_function_table(metadata, "bacteria", "pcyc", "PCyc_gene", c("phoA", "phoD", "ppk1", "ppx"), 1L,
                     file.path(base, "pcyc_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 40, min_prev = 0.75, max_prev = 1.00)
}

generate_fungi_species <- function(metadata) {
  cat("[INFO] Generating fungi species abundance...\n")
  species <- load_fungi_taxa(80L)
  sim <- simulate_dm_counts(
    feature_ids = species,
    metadata = metadata,
    n_diff = 12L,
    total_counts = pmax(20000L, round(metadata$seq_depth * 0.015)),
    concentration = 35,
    power = 1.08,
    min_prev = 0.06,
    max_prev = 0.78,
    diff_prev = 0.90,
    batch_sd = 0.16
  )
  species_percent <- counts_to_relab(sim$counts, scale = 100)
  rownames(species_percent) <- species
  colnames(species_percent) <- metadata$sample_id
  clade_matrix <- aggregate_taxa_levels(species, species_percent)

  fungi_root <- file.path(workdir, "result", "fungi", "metaphlan4")
  write_metaphlan_table(file.path(fungi_root, "merged_abundance_table.txt"), clade_matrix)
  write_metaphlan_table(file.path(fungi_root, "merged", "taxonomy.tsv"), clade_matrix)
  write_metaphlan_table(file.path(fungi_root, "merged", "merged_abundance_table.txt"), clade_matrix)
  write_fungi_profiles(fungi_root, clade_matrix, metadata)
  add_truth("fungi", "species", sim$truth)
  cat(sprintf("[INFO]   fungi species rows: %d species, %d total clades\n", length(species), nrow(clade_matrix)))
}

generate_fungi_functions <- function(metadata) {
  cat("[INFO] Generating fungi functional abundance...\n")
  base <- file.path(workdir, "result", "integration", "fungi")
  totals <- pmax(3000L, round(metadata$seq_depth * 0.0008))

  run_function_table(metadata, "fungi", "kegg_ko", "KEGG_KO", make_kegg_ids(200L, offset = 4000L), 15L,
                     file.path(base, "kegg_ko_gene_count.tsv"), totals,
                     value_type = "counts", concentration = 55, min_prev = 0.18, max_prev = 0.88)
  run_function_table(metadata, "fungi", "cog", "COG_category", make_cog_ids(20L), 4L,
                     file.path(base, "cog_gene_count.tsv"), totals,
                     value_type = "counts", concentration = 45, min_prev = 0.70, max_prev = 1.00)
  run_function_table(metadata, "fungi", "cazyme", "CAZyme_family", make_cazyme_ids(25L), 6L,
                     file.path(base, "cazyme_gene_count.tsv"), totals,
                     value_type = "counts", concentration = 45, min_prev = 0.45, max_prev = 0.96)
  run_function_table(metadata, "fungi", "vfdb", "VF_gene", make_vfdb_ids(10L, offset = 3000L), 3L,
                     file.path(base, "vfdb_gene_count.tsv"), totals,
                     value_type = "counts", concentration = 30, min_prev = 0.55, max_prev = 1.00)
  run_function_table(metadata, "fungi", "amr", "ARG_symbol", make_arg_ids(10L), 3L,
                     file.path(base, "amr_gene_count.tsv"), totals,
                     value_type = "counts", concentration = 30, min_prev = 0.50, max_prev = 1.00)
  run_function_table(metadata, "fungi", "merops", "MEROPS_family", make_merops_ids(8L), 2L,
                     file.path(base, "merops_family_gene_count.tsv"), totals,
                     value_type = "counts", concentration = 25, min_prev = 0.55, max_prev = 1.00)
}

make_virus_lineages <- function(votu_ids) {
  families <- c(
    "Drexlerviridae", "Autographiviridae", "Straboviridae", "Herelleviridae", "Zobellviridae",
    "Kyanoviridae", "Peduoviridae", "Schitoviridae", "Ackermannviridae", "Microviridae"
  )
  genera <- c("Teseptimavirus", "Kayfunavirus", "Tequatrovirus", "Kochikohdavirus", "Lederbergvirus",
              "Lambdavirus", "Peduovirus", "Schitovirus", "Agtrevirus", "Gokushovirus")
  data.frame(
    seq_name = votu_ids,
    lineage = paste0(
      "Viruses;Duplodnaviria;Heunggongvirae;Uroviricota;Caudoviricetes;",
      "Caudovirales;", families[(seq_along(votu_ids) - 1L) %% length(families) + 1L],
      ";", genera[(seq_along(votu_ids) - 1L) %% length(genera) + 1L]
    ),
    stringsAsFactors = FALSE
  )
}

generate_virus_votu <- function(metadata) {
  cat("[INFO] Generating virus vOTU abundance...\n")
  votu_ids <- paste0("vOTU_", sprintf("%05d", seq_len(200L)))
  sim <- simulate_dm_counts(
    feature_ids = votu_ids,
    metadata = metadata,
    n_diff = 30L,
    total_counts = pmax(10000L, round(metadata$seq_depth * 0.01)),
    concentration = 45,
    power = 1.12,
    min_prev = 0.06,
    max_prev = 0.78,
    diff_prev = 0.90,
    batch_sd = 0.18
  )
  counts <- round(sim$counts)
  colnames(counts) <- metadata$sample_id
  rownames(counts) <- votu_ids

  simple_path <- file.path(workdir, "result", "virus", "votu", "votu_table.tsv")
  write_feature_table(simple_path, "vOTU_ID", votu_ids, counts)

  lengths <- sample(seq(10000L, 220000L), length(votu_ids), replace = TRUE)
  names(lengths) <- votu_ids
  length_df <- data.frame(vOTU_ID = votu_ids, length = lengths, check.names = FALSE)
  safe_write_tsv(length_df, file.path(workdir, "result", "virus", "votu", "votu_lengths.tsv"))

  rpk <- sweep(counts, 1L, lengths / 1000, "/")
  rpk_totals <- colSums(rpk)
  rpk_totals[rpk_totals == 0] <- 1
  tpm <- sweep(rpk, 2L, rpk_totals, "/") * 1e6

  table_dir <- file.path(workdir, "result", "virus", "votu", "table")
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  compat <- data.frame(gene = votu_ids, length = lengths, check.names = FALSE)
  for (sid in metadata$sample_id) {
    compat[[paste0(sid, "_tpm")]] <- tpm[, sid]
    compat[[paste0(sid, "_count")]] <- counts[, sid]
  }
  safe_write_tsv(compat, file.path(table_dir, "vOTU_table.txt"))

  taxonomy <- make_virus_lineages(votu_ids)
  ann <- compat
  ann$taxonomy <- taxonomy$lineage
  safe_write_tsv(ann, file.path(table_dir, "vOTU_table_ann.txt"))

  clusters <- data.frame(object = votu_ids, cluster = votu_ids, check.names = FALSE)
  safe_write_tsv(clusters, file.path(workdir, "result", "virus", "vclust", "clusters.tsv"))
  safe_write_tsv(clusters, file.path(workdir, "result", "virus", "votu", "vclust", "clusters.tsv"))
  safe_write_tsv(taxonomy, file.path(workdir, "result", "virus", "votu", "genomad", "virus_taxonomy.tsv"))

  add_truth("virus", "votu", sim$truth)
  cat(sprintf("[INFO]   virus vOTU rows: %d\n", length(votu_ids)))
}

generate_virus_functions <- function(metadata) {
  cat("[INFO] Generating virus functional abundance...\n")
  base <- file.path(workdir, "result", "integration", "virus")
  totals <- pmax(20000L, round(metadata$seq_depth * 0.004))

  run_function_table(metadata, "virus", "phrog", "PHROG_category", make_phrog_ids(), 4L,
                     file.path(base, "phrog_category_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 30, min_prev = 0.65, max_prev = 1.00)
  run_function_table(metadata, "virus", "vog", "VOG_ID", paste0("VOG", sprintf("%05d", seq_len(200L))), 25L,
                     file.path(base, "vog_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 60, min_prev = 0.08, max_prev = 0.80)
  run_function_table(metadata, "virus", "lifestyle", "lifestyle", c("lytic", "lysogenic"), 2L,
                     file.path(base, "lifestyle_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 25, min_prev = 1.00, max_prev = 1.00)
  run_function_table(metadata, "virus", "host_genus", "host_genus",
                     c("Bacteroides", "Escherichia", "Faecalibacterium", "Prevotella", "Roseburia",
                       "Bifidobacterium", "Akkermansia", "Klebsiella", "Enterococcus", "Lactobacillus",
                       "Alistipes", "Blautia", "Ruminococcus", "Clostridium", "Streptococcus"), 6L,
                     file.path(base, "host_genus_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 35, min_prev = 0.50, max_prev = 1.00)
  run_function_table(metadata, "virus", "viral_family", "viral_family",
                     c("Drexlerviridae", "Autographiviridae", "Straboviridae", "Herelleviridae", "Zobellviridae",
                       "Kyanoviridae", "Peduoviridae", "Schitoviridae", "Ackermannviridae", "Microviridae"), 4L,
                     file.path(base, "viral_family_abundance.tsv"), totals,
                     value_type = "tpm", concentration = 32, min_prev = 0.55, max_prev = 1.00)
}

write_truth_table <- function() {
  if (!length(truth_rows)) {
    return(invisible(NULL))
  }
  truth <- do.call(rbind, truth_rows)
  truth <- truth[order(truth$dimension, truth$database, truth$diff_rank), , drop = FALSE]
  safe_write_tsv(truth, file.path(workdir, "differential_truth.tsv"))
  cat(sprintf("[INFO] Differential truth rows: %d -> %s\n", nrow(truth), file.path(workdir, "differential_truth.tsv")))
}

validate_outputs <- function(metadata) {
  required <- c(
    "metadata.csv",
    "result/bacteria/metaphlan4/merged_abundance_table.txt",
    "result/bacteria/metaphlan4/merged/taxonomy.tsv",
    "result/bacteria/humann3/merged/pathabundance_relab.tsv",
    "result/integration/bacteria/kegg_ko_abundance.tsv",
    "result/integration/bacteria/cog_abundance.tsv",
    "result/integration/bacteria/cazyme_abundance.tsv",
    "result/integration/bacteria/arg_abundance.tsv",
    "result/integration/bacteria/vfdb_abundance.tsv",
    "result/integration/bacteria/defense_abundance.tsv",
    "result/integration/bacteria/ncyc_abundance.tsv",
    "result/integration/bacteria/pcyc_abundance.tsv",
    "result/fungi/metaphlan4/merged_abundance_table.txt",
    "result/integration/fungi/kegg_ko_gene_count.tsv",
    "result/integration/fungi/cog_gene_count.tsv",
    "result/integration/fungi/cazyme_gene_count.tsv",
    "result/integration/fungi/vfdb_gene_count.tsv",
    "result/integration/fungi/amr_gene_count.tsv",
    "result/integration/fungi/merops_family_gene_count.tsv",
    "result/virus/votu/votu_table.tsv",
    "result/virus/votu/table/vOTU_table_ann.txt",
    "result/virus/votu/vclust/clusters.tsv",
    "result/virus/vclust/clusters.tsv",
    "result/integration/virus/phrog_category_abundance.tsv",
    "result/integration/virus/vog_abundance.tsv",
    "result/integration/virus/lifestyle_abundance.tsv",
    "result/integration/virus/host_genus_abundance.tsv",
    "result/integration/virus/viral_family_abundance.tsv"
  )
  missing <- required[!file.exists(file.path(workdir, required))]
  if (length(missing)) {
    stop("Missing required outputs:\n", paste(missing, collapse = "\n"))
  }
  if (nrow(metadata) != 1000L) {
    stop("metadata row count is not 1000")
  }
  invisible(TRUE)
}

cat("[INFO] Starting test data generation (1000 samples, 3 dimensions)\n")

metadata <- generate_metadata()
utils::write.csv(metadata, file.path(workdir, "metadata.csv"), row.names = FALSE, quote = FALSE)
writeLines(metadata$sample_id, file.path(workdir, "samples.txt"))
cat("[INFO] Generated metadata.csv:", nrow(metadata), "samples\n")

generate_bacteria_species(metadata)
generate_bacteria_functions(metadata)
invisible(gc())

generate_fungi_species(metadata)
generate_fungi_functions(metadata)
invisible(gc())

generate_virus_votu(metadata)
generate_virus_functions(metadata)
invisible(gc())

write_truth_table()
validate_outputs(metadata)

cat("[INFO] Test data generation completed\n")
