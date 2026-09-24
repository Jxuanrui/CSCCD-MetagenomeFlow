#!/usr/bin/env Rscript
# ==============================================================================
# Script: scripts/tests/level2/generate_fixture_functional_table.R
# Purpose: Generate a small, realistic-but-synthetic kegg_ko functional
#          abundance table for Project/Test_CI_fixture, so layer-2 tests can
#          exercise 96_functional_permanova.sh without a full production run.
#          Feature IDs are real KEGG KO IDs (borrowed from Project01's real
#          table shape); abundances are Dirichlet-multinomial simulated with
#          a real group-difference signal (not all-zero), following the same
#          pattern as scripts/utils/generate_test_100samples.R.
# Usage:   Rscript generate_fixture_functional_table.R <repo_root>
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript generate_fixture_functional_table.R <repo_root>")
}
repo <- args[1]
set.seed(42)

fixture_dir <- file.path(repo, "Project/Test_CI_fixture")
samples <- c("T01", "T02", "T03", "T04")
groups <- c("control", "control", "treat", "treat")

ref_path <- file.path(repo, "Project/Project01/result/integration/bacteria/kegg_ko_abundance.tsv")
if (!file.exists(ref_path)) {
  stop("Reference table not found: ", ref_path)
}
ref <- read.delim(ref_path, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE, nrows = 300)
ko_ids <- unique(ref[["KEGG_KO"]])
n_features <- min(length(ko_ids), 200)
ko_ids <- sample(ko_ids, n_features)

alpha_base <- rexp(n_features, rate = 2)
alpha_base <- alpha_base / sum(alpha_base) * 20
module_id <- ((seq_len(n_features) - 1) %% 5) + 1
loading <- runif(n_features, 0.8, 1.6)

mat <- matrix(0, nrow = n_features, ncol = length(samples))
for (i in seq_along(samples)) {
  module_factor <- rnorm(5, 0, 1.2)
  multiplier <- exp(loading * module_factor[module_id] + rnorm(n_features, 0, 0.08))
  multiplier <- pmin(pmax(multiplier, 0.1), 10)
  alpha <- alpha_base * multiplier
  if (groups[i] == "treat") {
    alpha <- alpha * exp(rnorm(n_features, 0, 0.3))
    alpha[1:10] <- alpha[1:10] * 1.5
  }
  alpha <- pmax(alpha, 0.01)
  counts <- rgamma(n_features, shape = alpha, rate = 1)
  mat[, i] <- (counts / sum(counts)) * 100
}

out_df <- data.frame(KEGG_KO = ko_ids, mat, check.names = FALSE, stringsAsFactors = FALSE)
colnames(out_df)[2:ncol(out_df)] <- samples

out_dir <- file.path(fixture_dir, "result/integration/bacteria")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "kegg_ko_abundance.tsv")
write.table(out_df, out_path, sep = "\t", quote = FALSE, row.names = FALSE)
cat("[INFO] Generated fixture kegg_ko_abundance.tsv:", n_features, "features x", length(samples), "samples\n")
