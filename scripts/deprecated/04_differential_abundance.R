# Deprecated 2026-07-16: superseded by 92_differential.R due to directory-convention duplication.
#!/usr/bin/env Rscript
# Step 4: Differential Abundance Analysis
# Methods: DESeq2, ANCOM-BC, MaAsLin2, Wilcoxon, LEfSe
# Visualizations: Volcano plots + Barplots

suppressPackageStartupMessages({
  library(optparse)
  library(phyloseq)
  library(DESeq2)
  library(ANCOMBC)
  library(Maaslin2)
  library(compositions)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(ggsci)
})

# Parse arguments
option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Working directory"),
  make_option(c("-r", "--repo"), type="character", help="Repository root"),
  make_option(c("-m", "--metadata"), type="character", help="Metadata file path"),
  make_option(c("-d", "--dimension"), type="character", help="Dimension: bacteria/fungi/virus"),
  make_option(c("-g", "--group"), type="character", help="Group column name"),
  make_option(c("--fdr"), type="double", default=0.05, help="FDR threshold [default: 0.05]"),
  make_option(c("--lfc"), type="double", default=1.0, help="Log2 fold-change threshold [default: 1.0]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate inputs
required <- c("workdir", "repo", "metadata", "dimension", "group")
missing <- required[!required %in% names(opt) | sapply(opt[required], is.null)]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}

cat(sprintf("[INFO] Starting differential abundance analysis\n"))
cat(sprintf("  Workdir: %s\n", opt$workdir))
cat(sprintf("  Metadata: %s\n", opt$metadata))
cat(sprintf("  Dimension: %s\n", opt$dimension))

# Setup paths
stat_dir <- file.path(opt$workdir, "result", "stat", opt$dimension)
ps_dir <- file.path(stat_dir, "phyloseq")
ps_rds <- file.path(ps_dir, sprintf("%s_phyloseq.rds", opt$dimension))
output_dir <- file.path(stat_dir, "differential")
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

# Load or construct phyloseq object
if(file.exists(ps_rds)) {
  ps <- readRDS(ps_rds)
  cat(sprintf("[INFO] Loaded phyloseq from RDS: %d taxa, %d samples\n", ntaxa(ps), nsamples(ps)))
} else {
  cat(sprintf("[INFO] Phyloseq RDS not found, constructing from raw data...\n"))

  # Check dimension and load appropriate data format
  if(opt$dimension == "virus") {
    # ========================================================================
    # Virus dimension: use vOTU table format
    # ========================================================================
    votu_file <- file.path(opt$workdir, "result", "virus", "votu", "votu_table.tsv")
    tax_file <- file.path(opt$workdir, "result", "virus", "votu", "genomad", "virus_taxonomy.tsv")

    if(!file.exists(votu_file)) {
      stop("vOTU table not found: ", votu_file)
    }

    # Read vOTU table (vOTU_ID × samples, counts)
    votu_df <- read.table(votu_file, sep="\t", header=TRUE, row.names=1,
                          check.names=FALSE, comment.char="", quote="")
    cat(sprintf("  Loaded vOTU table: %d vOTUs, %d samples\n", nrow(votu_df), ncol(votu_df)))

    # Read virus taxonomy if available
    if(file.exists(tax_file)) {
      tax_raw <- read.table(tax_file, sep="\t", header=TRUE, stringsAsFactors=FALSE)

      # Parse lineage into separate columns
      # Format: Viruses;Realm;Kingdom;Phylum;Class;Order;Family;Genus
      tax_df <- data.frame(
        row.names = tax_raw$seq_name,
        stringsAsFactors = FALSE
      )

      for(rank_idx in 1:8) {
        rank_name <- c("Domain", "Realm", "Kingdom", "Phylum", "Class", "Order", "Family", "Genus")[rank_idx]
        tax_df[[rank_name]] <- sapply(tax_raw$lineage, function(lineage) {
          parts <- strsplit(lineage, ";")[[1]]
          if(length(parts) >= rank_idx) {
            return(parts[rank_idx])
          } else {
            return(NA_character_)
          }
        })
      }

      # Add vOTU_ID as "Species" for consistency
      tax_df$Species <- rownames(tax_df)

      # Match taxonomy to vOTU table
      common_votus <- intersect(rownames(votu_df), rownames(tax_df))
      votu_df <- votu_df[common_votus, , drop=FALSE]
      tax_df <- tax_df[common_votus, , drop=FALSE]

      cat(sprintf("  Parsed virus taxonomy: %d vOTUs with lineage\n", nrow(tax_df)))
    } else {
      # No taxonomy available, create minimal taxonomy with vOTU IDs
      cat("  [WARN] No virus taxonomy file found, using vOTU IDs only\n")
      tax_df <- data.frame(
        row.names = rownames(votu_df),
        Domain = "Viruses",
        Species = rownames(votu_df),
        stringsAsFactors = FALSE
      )
    }

    abund_df <- votu_df

  } else {
    # ========================================================================
    # Bacteria/Fungi dimensions: use metaphlan4 format
    # ========================================================================
    # Load abundance table (metaphlan4 format)
    abund_file <- file.path(opt$workdir, "result", opt$dimension, "metaphlan4",
                            "merged_abundance_table.txt")
    if(!file.exists(abund_file)) {
      stop("Abundance file not found: ", abund_file)
    }

    # Read metaphlan4 output (skip first comment line)
    abund_df <- read.table(abund_file, sep="\t", header=TRUE, row.names=1,
                           check.names=FALSE, comment.char="#", quote="")

    # Filter to species-level only (rows containing "s__")
    species_rows <- grep("\\|s__", rownames(abund_df), value=TRUE)
    if(length(species_rows) > 0) {
      abund_df <- abund_df[species_rows, , drop=FALSE]
      cat(sprintf("  Filtered to %d species-level features\n", nrow(abund_df)))
    }

    # Convert relative abundance (0-100) to pseudo-counts for count-based methods
    # Multiply by 1e4 to get reasonable scale
    abund_df <- abund_df * 1e4

    cat(sprintf("  Loaded abundance: %d features, %d samples\n", nrow(abund_df), ncol(abund_df)))

    # Parse taxonomy from metaphlan4 clade names
    # Format: k__Bacteria|p__Proteobacteria|c__Gammaproteobacteria|...|s__Escherichia_coli
    tax_df <- data.frame(
      row.names = rownames(abund_df),
      stringsAsFactors = FALSE
    )

    for(rank in c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")) {
      prefix <- switch(rank,
                       "Kingdom" = "k__",
                       "Phylum" = "p__",
                       "Class" = "c__",
                       "Order" = "o__",
                       "Family" = "f__",
                       "Genus" = "g__",
                       "Species" = "s__")

      tax_df[[rank]] <- sapply(rownames(abund_df), function(clade) {
        parts <- strsplit(clade, "\\|")[[1]]
        match_part <- grep(paste0("^", prefix), parts, value=TRUE)
        if(length(match_part) > 0) {
          return(sub(paste0("^", prefix), "", match_part[1]))
        } else {
          return(NA_character_)
        }
      })
    }

    cat(sprintf("  Parsed taxonomy from clade names: %d features\n", nrow(tax_df)))
  }

  # Common processing for all dimensions
  # Load metadata
  meta_df <- read.table(opt$metadata, sep="\t", header=TRUE, row.names=1,
                        check.names=FALSE, comment.char="", quote="")
  cat(sprintf("  Loaded metadata: %d samples\n", nrow(meta_df)))

  # Match samples
  common_samples <- intersect(colnames(abund_df), rownames(meta_df))
  if(length(common_samples) == 0) {
    stop("No common samples between abundance and metadata")
  }

  abund_df <- abund_df[, common_samples, drop=FALSE]
  meta_df <- meta_df[common_samples, , drop=FALSE]

  # Ensure taxonomy matches abundance features
  tax_df <- tax_df[rownames(abund_df), , drop=FALSE]

  cat(sprintf("  Final dimensions: %d features × %d samples\n", nrow(abund_df), ncol(abund_df)))

  # Construct phyloseq
  otu_mat_obj <- otu_table(as.matrix(abund_df), taxa_are_rows=TRUE)
  sample_data_obj <- sample_data(meta_df)
  tax_mat_obj <- tax_table(as.matrix(tax_df))
  ps <- phyloseq(otu_mat_obj, sample_data_obj, tax_mat_obj)

  cat(sprintf("[INFO] Constructed phyloseq: %d taxa, %d samples\n", ntaxa(ps), nsamples(ps)))
}

# Extract data
otu_mat <- as.data.frame(otu_table(ps))
metadata <- as.data.frame(sample_data(ps))
tax_table_df <- as.data.frame(tax_table(ps))

# Ensure group column exists
if(!opt$group %in% colnames(metadata)) {
  stop("Group column not found in metadata: ", opt$group)
}

# Filter to two-group comparison
group_counts <- table(metadata[[opt$group]])
if(length(group_counts) != 2) {
  stop("Group column must have exactly 2 levels for pairwise comparison")
}
cat(sprintf("[INFO] Comparing groups: %s (n=%d) vs %s (n=%d)\n",
            names(group_counts)[1], group_counts[1],
            names(group_counts)[2], group_counts[2]))

# Prepare results storage
results_list <- list()
timing <- list()

# ==============================================================================
# Method 1: DESeq2
# ==============================================================================
cat("\n[INFO] Running DESeq2...\n")
t_start <- Sys.time()
tryCatch({
  # DESeq2 requires integer counts
  otu_int <- round(otu_mat)
  dds <- DESeqDataSetFromMatrix(
    countData = otu_int,
    colData = metadata,
    design = as.formula(paste0("~ ", opt$group))
  )
  dds <- DESeq(dds, sfType="poscounts", quiet=TRUE)
  res_deseq2 <- results(dds, contrast=c(opt$group, names(group_counts)[1], names(group_counts)[2]))

  results_list$DESeq2 <- as.data.frame(res_deseq2) %>%
    tibble::rownames_to_column("feature") %>%
    mutate(method="DESeq2", sig=padj < opt$fdr & abs(log2FoldChange) > opt$lfc)

  cat(sprintf("  DESeq2: %d significant features (FDR < %.2f, |LFC| > %.2f)\n",
              sum(results_list$DESeq2$sig, na.rm=TRUE), opt$fdr, opt$lfc))
}, error=function(e) {
  cat(sprintf("  [ERROR] DESeq2 failed: %s\n", e$message))
  results_list$DESeq2 <<- NULL
})
timing$DESeq2 <- as.numeric(difftime(Sys.time(), t_start, units="secs"))

# ==============================================================================
# Method 2: ANCOM-BC2 (updated version)
# ==============================================================================
cat("\n[INFO] Running ANCOM-BC2...\n")
t_start <- Sys.time()
tryCatch({
  ancom_out <- ancombc2(
    data = ps,
    fix_formula = opt$group,
    p_adj_method = "fdr",
    prv_cut = 0.10,
    lib_cut = 1000,
    group = opt$group,
    struc_zero = FALSE,  # Disable for two-group comparison
    neg_lb = FALSE,
    alpha = opt$fdr,
    global = FALSE
  )

  # Extract results from ANCOM-BC2
  # ancom_out$res is a data.frame with columns: taxon, lfc_*, se_*, W_*, p_*, q_*, diff_*
  res_df <- ancom_out$res

  # Find the group comparison column (format: lfc_groupX, p_groupX, q_groupX)
  lfc_cols <- grep("^lfc_", colnames(res_df), value = TRUE)
  group_col <- setdiff(lfc_cols, "lfc_(Intercept)")[1]
  group_suffix <- sub("^lfc_", "", group_col)

  p_col <- paste0("p_", group_suffix)
  q_col <- paste0("q_", group_suffix)

  results_list$ANCOMBC <- data.frame(
    feature = res_df$taxon,
    log2FoldChange = res_df[[group_col]] / log(2),  # Convert natural log to log2
    pvalue = res_df[[p_col]],
    padj = res_df[[q_col]],
    method = "ANCOMBC2",
    stringsAsFactors = FALSE
  ) %>%
    mutate(sig = padj < opt$fdr & abs(log2FoldChange) > opt$lfc)

  cat(sprintf("  ANCOM-BC2: %d significant features\n",
              sum(results_list$ANCOMBC$sig, na.rm=TRUE)))
}, error=function(e) {
  cat(sprintf("  [ERROR] ANCOM-BC2 failed: %s\n", e$message))
  results_list$ANCOMBC <<- NULL
})
timing$ANCOMBC2 <- as.numeric(difftime(Sys.time(), t_start, units="secs"))

# ==============================================================================
# Method 3: MaAsLin2
# ==============================================================================
cat("\n[INFO] Running MaAsLin2...\n")
t_start <- Sys.time()
tryCatch({
  maaslin_dir <- file.path(output_dir, "maaslin2_output")
  dir.create(maaslin_dir, showWarnings=FALSE, recursive=TRUE)

  # MaAsLin2 requires transposed data (samples × features)
  otu_t <- as.data.frame(t(otu_mat))

  # Ensure metadata has correct types
  # MaAsLin2 is sensitive to data.frame columns - all must be atomic vectors
  metadata_maaslin <- data.frame(
    row.names = rownames(metadata),
    stringsAsFactors = FALSE
  )

  # Add only the group column, ensuring it's a simple character vector
  metadata_maaslin[[opt$group]] <- as.character(metadata[[opt$group]])

  maaslin_out <- Maaslin2(
    input_data = otu_t,
    input_metadata = metadata_maaslin,
    output = maaslin_dir,
    fixed_effects = opt$group,
    transform = "AST",  # Arcsine square root transformation
    normalization = "TSS",
    standardize = FALSE,
    plot_heatmap = FALSE,
    plot_scatter = FALSE,
    min_abundance = 0.0,
    min_prevalence = 0.1
  )

  if(!is.null(maaslin_out$results) && nrow(maaslin_out$results) > 0) {
    results_list$MaAsLin2 <- maaslin_out$results %>%
      rename(feature = feature, log2FoldChange = coef, pvalue = pval, padj = qval) %>%
      mutate(
        method = "MaAsLin2",
        sig = padj < opt$fdr & abs(log2FoldChange) > opt$lfc
      ) %>%
      select(feature, log2FoldChange, pvalue, padj, method, sig)

    cat(sprintf("  MaAsLin2: %d significant features\n",
                sum(results_list$MaAsLin2$sig, na.rm=TRUE)))
  } else {
    cat("  MaAsLin2: No results returned\n")
    results_list$MaAsLin2 <- NULL
  }
}, error=function(e) {
  cat(sprintf("  [ERROR] MaAsLin2 failed: %s\n", e$message))
  results_list$MaAsLin2 <<- NULL
})
timing$MaAsLin2 <- as.numeric(difftime(Sys.time(), t_start, units="secs"))

# ==============================================================================
# Method 3b: MaAsLin3 (if available)
# ==============================================================================
cat("\n[INFO] Running MaAsLin3...\n")
t_start <- Sys.time()
tryCatch({
  if(requireNamespace("maaslin3", quietly = TRUE)) {
    maaslin3_dir <- file.path(output_dir, "maaslin3_output")
    dir.create(maaslin3_dir, showWarnings=FALSE, recursive=TRUE)

    # MaAsLin3 requires transposed data (samples × features)
    otu_t <- as.data.frame(t(otu_mat))

    # Prepare metadata
    metadata_maaslin3 <- data.frame(
      row.names = rownames(metadata),
      stringsAsFactors = FALSE
    )
    metadata_maaslin3[[opt$group]] <- as.character(metadata[[opt$group]])

    # Run MaAsLin3
    maaslin3_out <- maaslin3::maaslin3(
      input_data = otu_t,
      input_metadata = metadata_maaslin3,
      output = maaslin3_dir,
      fixed_effects = opt$group,
      reference = NULL,
      transform = "LOG",
      normalization = "TSS",
      standardize = "NONE",
      min_abundance = 0.0,
      min_prevalence = 0.1,
      max_significance = opt$fdr,
      cores = 1
    )

    if(!is.null(maaslin3_out$results) && nrow(maaslin3_out$results) > 0) {
      results_list$MaAsLin3 <- maaslin3_out$results %>%
        filter(metadata == opt$group) %>%
        rename(feature = feature, log2FoldChange = coef, pvalue = pval, padj = qval) %>%
        mutate(
          method = "MaAsLin3",
          sig = padj < opt$fdr & abs(log2FoldChange) > opt$lfc
        ) %>%
        select(feature, log2FoldChange, pvalue, padj, method, sig)

      cat(sprintf("  MaAsLin3: %d significant features\n",
                  sum(results_list$MaAsLin3$sig, na.rm=TRUE)))
    } else {
      cat("  MaAsLin3: No significant results\n")
      results_list$MaAsLin3 <- NULL
    }
  } else {
    cat("  [SKIP] MaAsLin3 not installed\n")
    results_list$MaAsLin3 <- NULL
  }
}, error=function(e) {
  cat(sprintf("  [ERROR] MaAsLin3 failed: %s\n", e$message))
  results_list$MaAsLin3 <<- NULL
})
timing$MaAsLin3 <- as.numeric(difftime(Sys.time(), t_start, units="secs"))

# ==============================================================================
# Method 4: Wilcoxon with CLR transformation
# ==============================================================================
cat("\n[INFO] Running Wilcoxon (CLR)...\n")
t_start <- Sys.time()
tryCatch({
  # CLR transformation with pseudocount
  clr_mat <- apply(otu_mat + 1, 2, function(x) log(x) - mean(log(x)))

  # Wilcoxon test per feature
  group_vec <- metadata[[opt$group]]
  pvals <- apply(clr_mat, 1, function(x) {
    wilcox.test(x ~ group_vec, exact=FALSE)$p.value
  })

  # Calculate effect size (mean difference in CLR space)
  group_levels <- levels(factor(group_vec))
  mean_diff <- apply(clr_mat, 1, function(x) {
    mean(x[group_vec == group_levels[1]]) - mean(x[group_vec == group_levels[2]])
  })

  results_list$Wilcoxon <- data.frame(
    feature = rownames(clr_mat),
    log2FoldChange = mean_diff / log(2),  # Convert to log2 scale
    pvalue = pvals,
    padj = p.adjust(pvals, method="fdr"),
    method = "Wilcoxon",
    stringsAsFactors = FALSE
  ) %>%
    mutate(sig = padj < opt$fdr & abs(log2FoldChange) > opt$lfc)

  cat(sprintf("  Wilcoxon: %d significant features\n",
              sum(results_list$Wilcoxon$sig, na.rm=TRUE)))
}, error=function(e) {
  cat(sprintf("  [ERROR] Wilcoxon failed: %s\n", e$message))
  results_list$Wilcoxon <<- NULL
})
timing$Wilcoxon <- as.numeric(difftime(Sys.time(), t_start, units="secs"))

# ==============================================================================
# Method 5: LEfSe (via external Python tool)
# ==============================================================================
cat("\n[INFO] Running LEfSe...\n")
t_start <- Sys.time()
tryCatch({
  # Format input for LEfSe: first row = class labels, rest = features
  lefse_input <- rbind(
    metadata[[opt$group]],
    otu_mat
  )
  rownames(lefse_input)[1] <- opt$group
  colnames(lefse_input) <- rownames(metadata)

  lefse_file <- file.path(output_dir, "lefse_input.tsv")
  write.table(lefse_input, lefse_file, sep="\t", quote=FALSE, col.names=FALSE)

  # Check if LEfSe is available
  lefse_format <- Sys.which("lefse-format_input.py")
  lefse_run <- Sys.which("run_lefse.py")

  if(lefse_format != "" && lefse_run != "") {
    lefse_formatted <- file.path(output_dir, "lefse_formatted.in")
    lefse_output <- file.path(output_dir, "lefse_output.res")

    # Format input
    system2(lefse_format, args=c(lefse_file, lefse_formatted,
                                  "-c", "1", "-u", "0", "-o", "1000000"),
            stdout=FALSE, stderr=FALSE)

    # Run LEfSe
    system2(lefse_run, args=c(lefse_formatted, lefse_output,
                              "-a", opt$fdr, "-l", opt$lfc),
            stdout=FALSE, stderr=FALSE)

    # Parse results
    if(file.exists(lefse_output) && file.info(lefse_output)$size > 0) {
      lefse_res <- read.table(lefse_output, sep="\t", header=FALSE, stringsAsFactors=FALSE)
      colnames(lefse_res) <- c("feature", "log_max_mean", "class", "lda_score", "pvalue")

      results_list$LEfSe <- lefse_res %>%
        mutate(
          log2FoldChange = ifelse(class == group_levels[1], lda_score, -lda_score),
          padj = pvalue,  # LEfSe doesn't provide adjusted p-values separately
          method = "LEfSe",
          sig = !is.na(lda_score) & abs(lda_score) > opt$lfc
        ) %>%
        select(feature, log2FoldChange, pvalue, padj, method, sig)

      cat(sprintf("  LEfSe: %d significant features\n",
                  sum(results_list$LEfSe$sig, na.rm=TRUE)))
    } else {
      cat("  LEfSe: No significant features found\n")
      results_list$LEfSe <- NULL
    }
  } else {
    cat("  [SKIP] LEfSe not installed (lefse-format_input.py and run_lefse.py not in PATH)\n")
    results_list$LEfSe <- NULL
  }
}, error=function(e) {
  cat(sprintf("  [ERROR] LEfSe failed: %s\n", e$message))
  results_list$LEfSe <<- NULL
})
timing$LEfSe <- as.numeric(difftime(Sys.time(), t_start, units="secs"))

# ==============================================================================
# Combine results
# ==============================================================================
cat("\n[INFO] Combining results from all methods...\n")
results_combined <- bind_rows(results_list)

# Write combined results
combined_file <- file.path(output_dir, "differential_abundance_all_methods.tsv")
write.table(results_combined, combined_file, sep="\t", quote=FALSE, row.names=FALSE)
cat(sprintf("  Combined results: %s\n", combined_file))

# Summary table
summary_df <- results_combined %>%
  group_by(method) %>%
  summarise(
    total_features = n(),
    significant = sum(sig, na.rm=TRUE),
    sig_up = sum(sig & log2FoldChange > 0, na.rm=TRUE),
    sig_down = sum(sig & log2FoldChange < 0, na.rm=TRUE),
    runtime_sec = timing[[unique(method)]]
  )

summary_file <- file.path(output_dir, "differential_abundance_summary.tsv")
write.table(summary_df, summary_file, sep="\t", quote=FALSE, row.names=FALSE)
cat(sprintf("  Summary: %s\n", summary_file))

print(summary_df)

# ==============================================================================
# Load visualization functions
# ==============================================================================
source(file.path(opt$repo, "scripts/R/plot_differential.R"))

# ==============================================================================
# Visualization 1: Nature-style Volcano Plots
# ==============================================================================
cat("\n[INFO] Generating volcano plots...\n")

for(method_name in names(results_list)) {
  if(is.null(results_list[[method_name]])) next

  df <- results_list[[method_name]] %>%
    filter(!is.na(pvalue) & !is.na(log2FoldChange) & !is.na(padj))

  if(nrow(df) == 0) next

  # Generate Nature-style volcano plot
  tryCatch({
    # MaAsLin2 uses AST transformation, resulting in smaller effect sizes
    # Use a lower LFC threshold for MaAsLin2 visualization
    lfc_threshold <- if(method_name == "MaAsLin2") 0.05 else opt$lfc

    p_volcano <- plot_volcano_nature(
      df = df,
      method = sprintf("%s (%s)", toupper(opt$dimension), method_name),
      fdr = opt$fdr,
      lfc = lfc_threshold,
      top_n = 10,
      label_column = "feature"
    )

    # Save in multiple formats
    ggsave(file.path(output_dir, sprintf("volcano_%s.pdf", method_name)),
           p_volcano, width=180, height=140, units="mm")
    ggsave(file.path(output_dir, sprintf("volcano_%s.svg", method_name)),
           p_volcano, width=180, height=140, units="mm")
    ggsave(file.path(output_dir, sprintf("volcano_%s.tiff", method_name)),
           p_volcano, width=180, height=140, units="mm", dpi=300, compression="lzw")

    cat(sprintf("  %s: volcano plot saved\n", method_name))
  }, error = function(e) {
    cat(sprintf("  [WARN] %s volcano plot failed: %s\n", method_name, e$message))
  })
}

# ==============================================================================
# Visualization 2: Enhanced Differential Species Barplots
# ==============================================================================
cat("\n[INFO] Generating differential species barplots...\n")

for(method_name in names(results_list)) {
  if(is.null(results_list[[method_name]])) next

  df_sig <- results_list[[method_name]] %>%
    filter(sig == TRUE)

  if(nrow(df_sig) == 0) {
    cat(sprintf("  %s: no significant features for barplot\n", method_name))
    next
  }

  # Determine number of features to plot
  n_plot <- min(20, nrow(df_sig))

  # Generate enhanced barplot using Nature-style function
  tryCatch({
    p_bar <- plot_barplot_enhanced(
      df = results_list[[method_name]],
      method = sprintf("%s (%s)", toupper(opt$dimension), method_name),
      top_n = n_plot
    )

    # Save in multiple formats
    bar_height <- max(150, n_plot * 7)  # Dynamic height based on number of features
    ggsave(file.path(output_dir, sprintf("barplot_%s.pdf", method_name)),
           p_bar, width=180, height=bar_height, units="mm")
    ggsave(file.path(output_dir, sprintf("barplot_%s.svg", method_name)),
           p_bar, width=180, height=bar_height, units="mm")
    ggsave(file.path(output_dir, sprintf("barplot_%s.tiff", method_name)),
           p_bar, width=180, height=bar_height, units="mm", dpi=300, compression="lzw")

    cat(sprintf("  %s: barplot saved (n=%d)\n", method_name, n_plot))
  }, error = function(e) {
    cat(sprintf("  [WARN] %s barplot failed: %s\n", method_name, e$message))
  })
}

# ==============================================================================
# Write sentinel and status
# ==============================================================================
sentinel_file <- file.path(output_dir, sprintf("%s_differential_abundance_done.txt", opt$dimension))
writeLines(format(Sys.time()), sentinel_file)

status_df <- data.frame(
  step = "differential_abundance",
  dimension = opt$dimension,
  timestamp = format(Sys.time()),
  methods = paste(names(results_list), collapse=","),
  total_features = nrow(otu_mat),
  fdr_threshold = opt$fdr,
  lfc_threshold = opt$lfc,
  output_dir = output_dir,
  stringsAsFactors = FALSE
)

status_file <- file.path(output_dir, sprintf("%s_differential_abundance_status.tsv", opt$dimension))
write.table(status_df, status_file, sep="\t", quote=FALSE, row.names=FALSE)

cat("\n[INFO] Differential abundance analysis completed\n")
cat(sprintf("  Sentinel: %s\n", sentinel_file))
