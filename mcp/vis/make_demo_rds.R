#!/usr/bin/env Rscript
# Build microeco microtable RDS files for the synthetic VisDemo project.
# Usage: Rscript make_demo_rds.R <workdir>
# Mirrors the microtable construction in scripts/91_diversity.R (build_mt_bacteria
# / build_mt_virus / enrich_virus_taxonomy) so downstream consumers (92/94) see
# exactly the object shape they expect.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript make_demo_rds.R <workdir>")
workdir <- normalizePath(args[[1]])

suppressPackageStartupMessages(library(microeco))

parse_lin <- function(lin, pfx = c(Kingdom = "k__", Phylum = "p__", Class = "c__",
                                   Order = "o__", Family = "f__", Genus = "g__",
                                   Species = "s__")) {
  parts <- strsplit(lin, "\\|")[[1]]
  vapply(pfx, function(px) {
    m <- parts[startsWith(parts, px)]
    if (length(m)) sub(paste0("^", px), "", m[1]) else NA_character_
  }, character(1))
}

meta <- read.delim(file.path(workdir, "result", "stat", "metadata.tsv"), sep = "\t",
                   header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
if (!nzchar(names(meta)[1])) meta <- meta[, -1, drop = FALSE]  # unnamed rownames col
rownames(meta) <- meta$sample_id
meta$group <- factor(meta$group)

save_mt <- function(mt, dim) {
  mt$tidy_dataset()
  path <- file.path(workdir, "result", "stat", dim, paste0(dim, "_microtable.rds"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(mt, path)
  cat("wrote", path, sprintf("(%d taxa x %d samples)\n", nrow(mt$otu_table), nrow(mt$sample_table)))
}

# --- bacteria: species-level rows of the MetaPhlAn merged table ---------------
raw <- read.table(file.path(workdir, "result", "metaphlan4", "merged", "taxonomy.tsv"),
                  header = TRUE, row.names = 1, sep = "\t", comment.char = "#",
                  check.names = FALSE)
sp_idx <- grepl("(^|\\|)s__", rownames(raw)) & !grepl("(^|\\|)t__", rownames(raw))
raw_sp <- raw[sp_idx, , drop = FALSE]
tax_df <- as.data.frame(do.call(rbind, lapply(rownames(raw_sp), parse_lin)), stringsAsFactors = FALSE)
rownames(tax_df) <- rownames(raw_sp)
common <- intersect(colnames(raw_sp), rownames(meta))
save_mt(microeco::microtable$new(
  otu_table = as.data.frame(round(raw_sp[, common, drop = FALSE] * 1000)),
  tax_table = tax_df,
  sample_table = meta[common, , drop = FALSE]
), "bacteria")

# --- virus: vOTU counts + geNomad taxonomy via clusters.tsv ------------------
votu <- read.delim(file.path(workdir, "result", "virus", "votu", "votu_table.tsv"),
                   sep = "\t", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
otu_df <- as.data.frame(lapply(votu[-1], as.numeric), check.names = FALSE)
rownames(otu_df) <- as.character(votu[[1]])
otu_df <- otu_df[rowSums(otu_df) > 0, , drop = FALSE]
clusters <- read.delim(file.path(workdir, "result", "virus", "votu", "vclust", "clusters.tsv"),
                       sep = "\t", header = TRUE, stringsAsFactors = FALSE)
genomad <- read.delim(file.path(workdir, "result", "virus", "votu", "genomad", "virus_taxonomy.tsv"),
                      sep = "\t", header = TRUE, stringsAsFactors = FALSE)
lineage_of <- function(lin) {
  p <- strsplit(lin, ";", fixed = TRUE)[[1]]
  p <- p[nzchar(p)]
  c(Domain = p[1], Phylum = p[4], Class = p[5], Order = p[6], Family = p[7], Genus = p[8])[1:6]
}
seq_to_votu <- setNames(clusters$cluster, clusters$object)
taxv <- data.frame(vOTU = rownames(otu_df), row.names = rownames(otu_df), stringsAsFactors = FALSE)
for (col in c("Domain", "Phylum", "Class", "Order", "Family", "Genus")) taxv[[col]] <- NA_character_
for (i in seq_len(nrow(taxv))) {
  contig <- names(seq_to_votu)[seq_to_votu == rownames(taxv)[i]][1]
  if (is.na(contig) || !contig %in% genomad$seq_name) next
  lin <- lineage_of(genomad$lineage[genomad$seq_name == contig][1])
  for (j in seq_along(lin)) if (!is.na(lin[j])) taxv[i, names(lin)[j]] <- lin[j]
}
common <- intersect(colnames(otu_df), rownames(meta))
save_mt(microeco::microtable$new(
  otu_table = otu_df[, common, drop = FALSE],
  tax_table = taxv,
  sample_table = meta[common, , drop = FALSE]
), "virus")
