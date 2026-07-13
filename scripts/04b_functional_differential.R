#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(DESeq2)
  library(Maaslin2)
})

option_list <- list(
  make_option(c("-i", "--input"), type="character", help="Feature-by-sample TSV"),
  make_option(c("-m", "--metadata"), type="character", help="Metadata CSV"),
  make_option(c("-g", "--group"), type="character", help="Two-level group column"),
  make_option(c("-o", "--output-dir"), dest="output_dir", type="character", help="Output directory"),
  make_option(c("--fdr"), type="double", default=0.05),
  make_option(c("--lfc"), type="double", default=1.0)
)
opt <- parse_args(OptionParser(option_list=option_list))

required <- c("input", "metadata", "group", "output_dir")
missing <- required[vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) stop("Missing required arguments: ", paste(missing, collapse=", "))

dir.create(opt$output_dir, recursive=TRUE, showWarnings=FALSE)
otu_mat <- read.table(opt$input, sep="\t", header=TRUE, row.names=1,
                      check.names=FALSE, comment.char="", quote="")
metadata <- read.csv(opt$metadata, header=TRUE, row.names=1, check.names=FALSE,
                     stringsAsFactors=FALSE)
common_samples <- intersect(colnames(otu_mat), rownames(metadata))
if(length(common_samples) == 0) stop("No common samples between input and metadata")
otu_mat <- otu_mat[, common_samples, drop=FALSE]
metadata <- metadata[common_samples, , drop=FALSE]
otu_mat <- as.matrix(otu_mat)
storage.mode(otu_mat) <- "numeric"
if(any(!is.finite(otu_mat))) stop("Input contains non-finite values")
if(any(otu_mat < 0)) stop("Input contains negative values")
if(!opt$group %in% colnames(metadata)) stop("Group column not found: ", opt$group)

group_vec <- factor(metadata[[opt$group]])
if(nlevels(group_vec) != 2) stop("Group column must have exactly two levels")
metadata[[opt$group]] <- group_vec
group_levels <- levels(group_vec)
cat(sprintf("[INFO] %d features x %d samples; %s vs %s\n",
            nrow(otu_mat), ncol(otu_mat), group_levels[1], group_levels[2]))

write_result <- function(result, path) {
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  write.table(result, path, sep="\t", quote=FALSE, row.names=FALSE, na="NA")
}

summary_rows <- list()

cat("[INFO] Running DESeq2\n")
otu_int <- round(as.matrix(otu_mat))
dds <- DESeqDataSetFromMatrix(otu_int, metadata, as.formula(paste0("~ ", opt$group)))
dds <- tryCatch(
  DESeq(dds, sfType="poscounts", quiet=TRUE),
  error=function(error) {
    cat(sprintf("[WARN] DESeq2 default fit failed (%s); retrying fitType=mean\n", error$message))
    DESeq(dds, sfType="poscounts", fitType="mean", quiet=TRUE)
  }
)
deseq_result <- as.data.frame(results(
  dds, contrast=c(opt$group, group_levels[1], group_levels[2])
))
deseq_result$feature <- rownames(deseq_result)
deseq_result$method <- "DESeq2"
deseq_result$sig <- !is.na(deseq_result$padj) & deseq_result$padj < opt$fdr &
  abs(deseq_result$log2FoldChange) > opt$lfc
deseq_result <- deseq_result[, c("feature", "baseMean", "log2FoldChange", "lfcSE",
                                 "stat", "pvalue", "padj", "method", "sig")]
write_result(deseq_result, file.path(opt$output_dir, "deseq2_results.tsv"))
summary_rows$DESeq2 <- data.frame(method="DESeq2", total=nrow(deseq_result),
                                  significant=sum(deseq_result$sig, na.rm=TRUE))

cat("[INFO] Running MaAsLin2\n")
maaslin_raw_dir <- file.path(opt$output_dir, "maaslin2_raw")
metadata_maaslin <- data.frame(row.names=rownames(metadata), stringsAsFactors=FALSE)
metadata_maaslin[[opt$group]] <- as.character(metadata[[opt$group]])
maaslin_fit <- Maaslin2(
  input_data=as.data.frame(t(otu_mat)), input_metadata=metadata_maaslin,
  output=maaslin_raw_dir, fixed_effects=opt$group, transform="AST",
  normalization="TSS", standardize=FALSE, plot_heatmap=FALSE,
  plot_scatter=FALSE, min_abundance=0.0, min_prevalence=0.1
)
maaslin_result <- maaslin_fit$results
if(is.null(maaslin_result)) maaslin_result <- data.frame()
if(nrow(maaslin_result) > 0) {
  maaslin_result$log2FoldChange <- maaslin_result$coef
  maaslin_result$pvalue <- maaslin_result$pval
  maaslin_result$padj <- maaslin_result$qval
  maaslin_result$method <- "MaAsLin2"
  maaslin_result$sig <- !is.na(maaslin_result$padj) & maaslin_result$padj < opt$fdr &
    abs(maaslin_result$log2FoldChange) > opt$lfc
}
write_result(maaslin_result, file.path(opt$output_dir, "maaslin2_results", "results.tsv"))
summary_rows$MaAsLin2 <- data.frame(method="MaAsLin2", total=nrow(maaslin_result),
                                    significant=if(nrow(maaslin_result)) sum(maaslin_result$sig, na.rm=TRUE) else 0)

cat("[INFO] Running Wilcoxon CLR\n")
clr_mat <- apply(as.matrix(otu_mat) + 1, 2, function(values) log(values) - mean(log(values)))
pvalues <- apply(clr_mat, 1, function(values) wilcox.test(values ~ group_vec, exact=FALSE)$p.value)
mean_diff <- apply(clr_mat, 1, function(values) {
  mean(values[group_vec == group_levels[1]]) - mean(values[group_vec == group_levels[2]])
})
wilcoxon_result <- data.frame(
  feature=rownames(clr_mat), log2FoldChange=mean_diff / log(2), pvalue=pvalues,
  padj=p.adjust(pvalues, method="fdr"), method="Wilcoxon", stringsAsFactors=FALSE
)
wilcoxon_result$sig <- wilcoxon_result$padj < opt$fdr &
  abs(wilcoxon_result$log2FoldChange) > opt$lfc
write_result(wilcoxon_result, file.path(opt$output_dir, "wilcoxon_results.tsv"))
summary_rows$Wilcoxon <- data.frame(method="Wilcoxon", total=nrow(wilcoxon_result),
                                    significant=sum(wilcoxon_result$sig, na.rm=TRUE))

write_result(do.call(rbind, summary_rows), file.path(opt$output_dir, "differential_summary.tsv"))
writeLines(format(Sys.time()), file.path(opt$output_dir, "functional_differential_done.txt"))
cat("[INFO] Completed without visualizations\n")
