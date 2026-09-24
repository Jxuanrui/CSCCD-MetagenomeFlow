#!/usr/bin/env Rscript
# ==============================================================================
# Script: scripts/tests/level2/generate_fixture_taxonomy_table.R
# Purpose: Generate a small, realistic-but-synthetic MetaPhlAn4 taxonomy.tsv
#          for Project/Test_CI_fixture (bacteria dimension only -- virus/fungi
#          tables are intentionally omitted so 91_stat_diversity.sh exercises
#          its graceful-skip path for those dimensions, which is itself part
#          of what this layer-2 test verifies).
# Usage:   Rscript generate_fixture_taxonomy_table.R <repo_root>
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript generate_fixture_taxonomy_table.R <repo_root>")
}
repo <- args[1]
set.seed(42)

fixture_dir <- file.path(repo, "Project/Test_CI_fixture")
samples <- c("T01", "T02", "T03", "T04")
groups <- c("control", "control", "treat", "treat")

ref_path <- file.path(repo, "Project/Project01/result/metaphlan4/merged/taxonomy.tsv")
if (!file.exists(ref_path)) {
  stop("Reference table not found: ", ref_path)
}
ref <- read.table(ref_path, header = TRUE, row.names = 1, sep = "\t",
                   comment.char = "#", check.names = FALSE)
sp_idx <- grepl("(^|\\|)s__", rownames(ref)) & !grepl("(^|\\|)t__", rownames(ref))
species_names <- rownames(ref)[sp_idx]
n_species <- min(length(species_names), 100)
species_names <- sample(species_names, n_species)

alpha_base <- rexp(n_species, rate = 2)
alpha_base <- alpha_base / sum(alpha_base) * 20
module_id <- ((seq_len(n_species) - 1) %% 5) + 1
loading <- runif(n_species, 0.8, 1.6)

mat <- matrix(0, nrow = n_species, ncol = length(samples))
for (i in seq_along(samples)) {
  module_factor <- rnorm(5, 0, 1.2)
  multiplier <- exp(loading * module_factor[module_id] + rnorm(n_species, 0, 0.08))
  multiplier <- pmin(pmax(multiplier, 0.1), 10)
  alpha <- alpha_base * multiplier
  if (groups[i] == "treat") {
    alpha <- alpha * exp(rnorm(n_species, 0, 0.3))
    alpha[1:10] <- alpha[1:10] * 1.5
  }
  alpha <- pmax(alpha, 0.01)
  counts <- rgamma(n_species, shape = alpha, rate = 1)
  rel <- (counts / sum(counts)) * (100 - 20)
  mat[, i] <- rel
}

unclassified <- rep(20, length(samples))
out_df <- data.frame(ID = species_names, mat, check.names = FALSE, stringsAsFactors = FALSE)
colnames(out_df)[2:ncol(out_df)] <- samples
unclassified_row <- data.frame(ID = "UNCLASSIFIED", as.list(unclassified), check.names = FALSE)
colnames(unclassified_row) <- colnames(out_df)
out_df <- rbind(unclassified_row, out_df)

out_dir <- file.path(fixture_dir, "result/metaphlan4/merged")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "taxonomy.tsv")
con <- file(out_path, "w")
writeLines(paste(colnames(out_df), collapse = "\t"), con)
writeLines("#metaphlan4", con)
close(con)
write.table(out_df, out_path, sep = "\t", quote = FALSE, row.names = FALSE,
            col.names = FALSE, append = TRUE)
cat("[INFO] Generated fixture taxonomy.tsv:", n_species, "species x", length(samples), "samples\n")
