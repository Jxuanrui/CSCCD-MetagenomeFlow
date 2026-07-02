#!/usr/bin/env Rscript
# ==============================================================================
# Script: generate_test_100samples.R
# Purpose: Generate 100-sample synthetic test dataset for downstream analysis
# Usage: Rscript generate_test_100samples.R <repo_root> <output_dir>
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript generate_test_100samples.R <repo_root> <output_dir>")
}

repo <- args[1]
outdir <- args[2]

set.seed(42)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

n_samples <- 100
n_case <- 50
n_ctrl <- 50

# ==============================================================================
# 1. Generate metadata
# ==============================================================================
metadata <- data.frame(
  sample_id = paste0("S", sprintf("%03d", 1:n_samples)),
  group = c(rep("case", n_case), rep("control", n_ctrl)),
  age = round(rnorm(n_samples, 50, 15)),
  sex = sample(c("M", "F"), n_samples, replace = TRUE),
  bmi = round(rnorm(n_samples, 25, 5), 1),
  batch = sample(paste0("batch", 1:5), n_samples, replace = TRUE),
  stringsAsFactors = FALSE
)

metadata_path <- file.path(outdir, "metadata.csv")
write.csv(metadata, metadata_path, row.names = FALSE, quote = FALSE)
cat("[INFO] Generated metadata.csv:", nrow(metadata), "samples\n")

# ==============================================================================
# 2. Bacteria: MetaPhlAn4 species abundance table
# ==============================================================================
# Read Project_example real data to get species list and distribution shape
ref_mpa <- file.path(repo, "Project/Project_example/result/metaphlan4/merged/taxonomy.tsv")
if (!file.exists(ref_mpa)) {
  stop("Reference file not found: ", ref_mpa)
}

ref_data <- read.table(ref_mpa, header = TRUE, sep = "\t", comment.char = "#", check.names = FALSE, skip = 1)
colnames(ref_data)[1] <- "clade_name"
ref_species <- ref_data[grepl("\\|s__", ref_data$clade_name) & !grepl("\\|t__", ref_data$clade_name), ]
n_species <- min(nrow(ref_species), 200)  # Cap at 200 species

species_names <- if (nrow(ref_species) > 0) {
  sample(ref_species$clade_name, n_species)
} else {
  paste0("k__Bacteria|p__Phylum", 1:50, "|c__Class", 1:50, "|o__Order", 1:50,
         "|f__Family", 1:50, "|g__Genus", 1:50, "|s__Species", 1:50)
}

# Simulate abundance with Dirichlet-multinomial (gut microbiome has few dominant + many rare)
alpha_base <- rexp(n_species, rate = 2)  # Long-tail distribution
alpha_base <- alpha_base / sum(alpha_base) * 10  # Scale to reasonable alpha

mpa_matrix <- matrix(0, nrow = n_species, ncol = n_samples)
for (i in 1:n_samples) {
  # Case group: perturb alpha to simulate differential abundance
  alpha <- if (metadata$group[i] == "case") {
    alpha_perturb <- alpha_base * exp(rnorm(n_species, 0, 0.3))
    alpha_perturb[1:10] <- alpha_perturb[1:10] * 1.5  # Top 10 species enriched in case
    alpha_perturb
  } else {
    alpha_base
  }
  alpha <- pmax(alpha, 0.01)  # Floor to avoid zeros

  # Draw from Dirichlet
  counts <- rgamma(n_species, shape = alpha, rate = 1)
  rel_abund <- (counts / sum(counts)) * 100
  mpa_matrix[, i] <- rel_abund
}

mpa_df <- data.frame(
  clade_name = species_names,
  NCBI_tax_id = paste0("taxid", 1:n_species),
  mpa_matrix,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
colnames(mpa_df)[3:ncol(mpa_df)] <- metadata$sample_id

mpa_dir <- file.path(outdir, "result/metaphlan4/merged")
dir.create(mpa_dir, recursive = TRUE, showWarnings = FALSE)
mpa_path <- file.path(mpa_dir, "taxonomy.tsv")
write.table(mpa_df, mpa_path, sep = "\t", quote = FALSE, row.names = FALSE)
cat("[INFO] Generated MetaPhlAn4 taxonomy.tsv:", nrow(mpa_df), "species x", ncol(mpa_matrix), "samples\n")

# ==============================================================================
# 3. Bacteria: HUMAnN3 pathway abundance (merged)
# ==============================================================================
n_pathways <- 200
pathway_names <- paste0("PWY-", 1000 + 1:n_pathways)

humann_matrix <- matrix(rpois(n_pathways * n_samples, lambda = 50), nrow = n_pathways, ncol = n_samples)
humann_df <- data.frame(
  Pathway = pathway_names,
  humann_matrix,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
colnames(humann_df)[2:ncol(humann_df)] <- paste0(metadata$sample_id, "_Abundance")

humann_dir <- file.path(outdir, "result/humann3/merged")
dir.create(humann_dir, recursive = TRUE, showWarnings = FALSE)
humann_path <- file.path(humann_dir, "humann3_pathabundance.tsv")
write.table(humann_df, humann_path, sep = "\t", quote = FALSE, row.names = FALSE)
cat("[INFO] Generated HUMAnN3 pathway abundance:", n_pathways, "pathways x", n_samples, "samples\n")

# ==============================================================================
# 4. Bacteria: Salmon gene quantification (per-sample quant.sf)
# ==============================================================================
n_genes <- 5000
gene_names <- paste0("gene_", sprintf("%05d", 1:n_genes))

for (sid in metadata$sample_id) {
  salmon_dir <- file.path(outdir, "result/assembly/salmon", sid)
  dir.create(salmon_dir, recursive = TRUE, showWarnings = FALSE)

  tpm <- rexp(n_genes, rate = 0.01)
  tpm <- (tpm / sum(tpm)) * 1e6

  quant_df <- data.frame(
    Name = gene_names,
    Length = sample(500:3000, n_genes, replace = TRUE),
    EffectiveLength = sample(400:2900, n_genes, replace = TRUE),
    TPM = tpm,
    NumReads = rpois(n_genes, lambda = tpm * 0.1),
    stringsAsFactors = FALSE
  )

  write.table(quant_df, file.path(salmon_dir, "quant.sf"), sep = "\t", quote = FALSE, row.names = FALSE)
}
cat("[INFO] Generated Salmon quant.sf for", n_samples, "samples:", n_genes, "genes each\n")

# ==============================================================================
# 5. Bacteria: Functional annotations (aggregate tables)
# ==============================================================================
# eggNOG
eggnog_dir <- file.path(outdir, "result/annotation/eggnog")
dir.create(eggnog_dir, recursive = TRUE, showWarnings = FALSE)
eggnog_df <- data.frame(
  query = gene_names[1:min(4000, n_genes)],
  seed_ortholog = paste0("COG", sprintf("%04d", 1:min(4000, n_genes))),
  evalue = runif(min(4000, n_genes), 1e-50, 1e-10),
  score = runif(min(4000, n_genes), 100, 500),
  eggNOG_OGs = paste0("COG", sprintf("%04d", 1:min(4000, n_genes))),
  KEGG_ko = paste0("K", sprintf("%05d", sample(1:20000, min(4000, n_genes), replace = TRUE))),
  KEGG_Pathway = sample(c("ko00010", "ko00020", "ko00030", "ko00040", "ko00051", "ko00052"), min(4000, n_genes), replace = TRUE),
  GO_terms = paste0("GO:", sprintf("%07d", sample(1:9999999, min(4000, n_genes), replace = TRUE))),
  stringsAsFactors = FALSE
)
write.table(eggnog_df, file.path(eggnog_dir, "eggnog.emapper.annotations"), sep = "\t", quote = FALSE, row.names = FALSE)

# KEGG
kegg_dir <- file.path(outdir, "result/annotation/kegg")
dir.create(kegg_dir, recursive = TRUE, showWarnings = FALSE)
kegg_df <- data.frame(
  gene_id = gene_names[1:min(3000, n_genes)],
  KO = paste0("K", sprintf("%05d", sample(1:20000, min(3000, n_genes), replace = TRUE))),
  identity = runif(min(3000, n_genes), 40, 100),
  evalue = runif(min(3000, n_genes), 1e-50, 1e-5),
  stringsAsFactors = FALSE
)
write.table(kegg_df, file.path(kegg_dir, "kegg_diamond.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

# AMRFinder
amr_dir <- file.path(outdir, "result/annotation/amrfinder")
dir.create(amr_dir, recursive = TRUE, showWarnings = FALSE)
amr_df <- data.frame(
  Protein_identifier = gene_names[sample(1:n_genes, 100)],
  Gene_symbol = paste0("ARG", 1:100),
  Sequence_name = paste0("contig_", 1:100),
  Class = sample(c("BETA-LACTAM", "AMINOGLYCOSIDE", "TETRACYCLINE", "MACROLIDE"), 100, replace = TRUE),
  Subclass = sample(c("CEPHALOSPORIN", "PENICILLIN", "CARBAPENEM"), 100, replace = TRUE),
  stringsAsFactors = FALSE
)
write.table(amr_df, file.path(amr_dir, "amrfinder_results.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

# CARD
card_dir <- file.path(outdir, "result/annotation/card")
dir.create(card_dir, recursive = TRUE, showWarnings = FALSE)
card_df <- data.frame(
  ORF_ID = gene_names[sample(1:n_genes, 80)],
  ARO = paste0("ARO:", 3000000 + 1:80),
  Model_type = "protein homolog model",
  Best_Hit_ARO = paste0("ARG_", 1:80),
  stringsAsFactors = FALSE
)
write.table(card_df, file.path(card_dir, "rgi_results.txt"), sep = "\t", quote = FALSE, row.names = FALSE)

# dbCAN
dbcan_dir <- file.path(outdir, "result/annotation/dbcan")
dir.create(dbcan_dir, recursive = TRUE, showWarnings = FALSE)
dbcan_df <- data.frame(
  Gene_ID = gene_names[sample(1:n_genes, 200)],
  HMMER = paste0("GH", sample(1:150, 200, replace = TRUE)),
  Hotpep = paste0("GH", sample(1:150, 200, replace = TRUE)),
  DIAMOND = paste0("GH", sample(1:150, 200, replace = TRUE)),
  num_tools = sample(1:3, 200, replace = TRUE),
  stringsAsFactors = FALSE
)
write.table(dbcan_df, file.path(dbcan_dir, "overview.txt"), sep = "\t", quote = FALSE, row.names = FALSE)

# VFDB
vfdb_dir <- file.path(outdir, "result/annotation/vfdb")
dir.create(vfdb_dir, recursive = TRUE, showWarnings = FALSE)
vfdb_df <- data.frame(
  gene_id = gene_names[sample(1:n_genes, 120)],
  VF_id = paste0("VF", sprintf("%04d", 1:120)),
  VF_name = paste0("VirulenceFactor_", 1:120),
  identity = runif(120, 50, 100),
  stringsAsFactors = FALSE
)
write.table(vfdb_df, file.path(vfdb_dir, "vfdb_hits.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

# NCyc
ncyc_dir <- file.path(outdir, "result/annotation/ncyc")
dir.create(ncyc_dir, recursive = TRUE, showWarnings = FALSE)
ncyc_df <- data.frame(
  gene_id = gene_names[sample(1:n_genes, 60)],
  ncyc_function = sample(c("nirK", "nirS", "nosZ", "nrfA", "amoA"), 60, replace = TRUE),
  identity = runif(60, 60, 100),
  stringsAsFactors = FALSE
)
write.table(ncyc_df, file.path(ncyc_dir, "ncyc_hits.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

# PCyc
pcyc_dir <- file.path(outdir, "result/annotation/pcyc")
dir.create(pcyc_dir, recursive = TRUE, showWarnings = FALSE)
pcyc_df <- data.frame(
  gene_id = gene_names[sample(1:n_genes, 50)],
  pcyc_function = sample(c("phoD", "phoA", "ppk", "ppx"), 50, replace = TRUE),
  identity = runif(50, 60, 100),
  stringsAsFactors = FALSE
)
write.table(pcyc_df, file.path(pcyc_dir, "pcyc_hits.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

cat("[INFO] Generated functional annotation tables (eggNOG/KEGG/AMR/CARD/dbCAN/VFDB/NCyc/PCyc)\n")

# ==============================================================================
# 6. Virus: vOTU abundance table with taxonomy
# ==============================================================================
n_votu <- 100
votu_names <- paste0("vOTU_", 1:n_votu)
votu_matrix <- matrix(rpois(n_votu * n_samples, lambda = 20), nrow = n_votu, ncol = n_samples)

votu_df <- data.frame(
  vOTU = votu_names,
  Domain = "Viruses",
  Phylum = sample(c("Caudovirales", "Microviridae", "Inoviridae"), n_votu, replace = TRUE),
  Class = sample(c("Class1", "Class2", "Class3"), n_votu, replace = TRUE),
  Order = sample(c("Order1", "Order2", "Order3"), n_votu, replace = TRUE),
  Family = sample(c("Siphoviridae", "Myoviridae", "Podoviridae"), n_votu, replace = TRUE),
  Genus = paste0("Genus_", sample(1:20, n_votu, replace = TRUE)),
  votu_matrix,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
colnames(votu_df)[8:ncol(votu_df)] <- metadata$sample_id

votu_dir <- file.path(outdir, "result/virus/votu/table")
dir.create(votu_dir, recursive = TRUE, showWarnings = FALSE)
votu_path <- file.path(votu_dir, "vOTU_table_ann.txt")
write.table(votu_df, votu_path, sep = "\t", quote = FALSE, row.names = FALSE)
cat("[INFO] Generated vOTU table:", n_votu, "vOTUs x", n_samples, "samples\n")

# Virus PHAROKKA gff (dummy)
pharokka_dir <- file.path(outdir, "result/virus/pharokka")
dir.create(pharokka_dir, recursive = TRUE, showWarnings = FALSE)
writeLines("##gff-version 3\n# PHAROKKA placeholder", file.path(pharokka_dir, "pharokka.gff"))

# ==============================================================================
# 7. Fungi: MetaPhlAn4 per-sample profiles
# ==============================================================================
n_fungi_species <- 50
fungi_species_names <- paste0("k__Fungi|p__Phylum", 1:n_fungi_species, "|s__Species", 1:n_fungi_species)

for (sid in metadata$sample_id) {
  fungi_dir <- file.path(outdir, "result/fungi/metaphlan4", sid)
  dir.create(fungi_dir, recursive = TRUE, showWarnings = FALSE)

  fungi_abund <- rexp(n_fungi_species, rate = 1)
  fungi_abund <- (fungi_abund / sum(fungi_abund)) * 100

  fungi_profile <- data.frame(
    clade_name = fungi_species_names,
    NCBI_tax_id = paste0("taxid_fungi_", 1:n_fungi_species),
    relative_abundance = fungi_abund,
    stringsAsFactors = FALSE
  )

  write.table(fungi_profile, file.path(fungi_dir, paste0(sid, "_profile.txt")),
              sep = "\t", quote = FALSE, row.names = FALSE)
}
cat("[INFO] Generated Fungi MetaPhlAn4 profiles:", n_samples, "samples x", n_fungi_species, "species\n")

# Fungi FunOMIC aggregate table
funomic_matrix <- matrix(rpois(n_fungi_species * n_samples, lambda = 10), nrow = n_fungi_species, ncol = n_samples)
funomic_df <- data.frame(
  species = paste0("Fungi_species_", 1:n_fungi_species),
  funomic_matrix,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
colnames(funomic_df)[2:ncol(funomic_df)] <- metadata$sample_id

funomic_dir <- file.path(outdir, "result/integration/fungi")
dir.create(funomic_dir, recursive = TRUE, showWarnings = FALSE)
funomic_path <- file.path(funomic_dir, "funomic_species_count.tsv")
write.table(funomic_df, funomic_path, sep = "\t", quote = FALSE, row.names = FALSE)
cat("[INFO] Generated FunOMIC species count table:", n_fungi_species, "species x", n_samples, "samples\n")

# ==============================================================================
# 8. Generate samplesheet.csv
# ==============================================================================
data_dir <- file.path(outdir, "data")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

samplesheet <- data.frame(
  sample_id = metadata$sample_id,
  r1 = file.path(data_dir, paste0(metadata$sample_id, "_1.fq.gz")),
  r2 = file.path(data_dir, paste0(metadata$sample_id, "_2.fq.gz")),
  stringsAsFactors = FALSE
)
write.csv(samplesheet, file.path(outdir, "samplesheet.csv"), row.names = FALSE, quote = FALSE)
cat("[INFO] Generated samplesheet.csv\n")

# Create dummy fastq.gz files (empty but present for directory structure)
for (sid in metadata$sample_id) {
  writeLines("", file.path(data_dir, paste0(sid, "_1.fq.gz")))
  writeLines("", file.path(data_dir, paste0(sid, "_2.fq.gz")))
}
cat("[INFO] Created dummy fastq.gz placeholders in data/\n")

# ==============================================================================
# Summary
# ==============================================================================
cat("\n=== Test dataset generation complete ===\n")
cat("Output directory:", outdir, "\n")
cat("Samples:", n_samples, "(case:", n_case, ", control:", n_ctrl, ")\n")
cat("Bacteria species:", n_species, "\n")
cat("Bacteria genes:", n_genes, "\n")
cat("HUMAnN3 pathways:", n_pathways, "\n")
cat("vOTUs:", n_votu, "\n")
cat("Fungi species:", n_fungi_species, "\n")
cat("\nReady for downstream analysis (scripts 91-98).\n")
