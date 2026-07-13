#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE, warn=1)

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
  library(KEGGREST)
})

option_list <- list(
  make_option(c("-w", "--workdir"), type="character", help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character", help="Dimension: bacteria/fungi"),
  make_option(c("-t", "--type"), type="character", default="kegg_ko",
              help="Functional type [default: kegg_ko]"),
  make_option(c("--source"), type="character",
              help="Feature source: ml_top50/deseq2_sig"),
  make_option(c("-o", "--outdir"), type="character", help="Output directory")
)

opt <- parse_args(OptionParser(option_list=option_list))
required <- c("workdir", "dimension", "source", "outdir")
missing <- required[vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}
if(!opt$dimension %in% c("bacteria", "fungi")) {
  stop("--dimension must be bacteria or fungi")
}
if(opt$type != "kegg_ko") {
  stop("--type is currently fixed to kegg_ko")
}
if(!opt$source %in% c("ml_top50", "deseq2_sig")) {
  stop("--source must be ml_top50 or deseq2_sig")
}

normalize_ko <- function(values) {
  values <- toupper(trimws(as.character(values)))
  values <- sub("^KO:", "", values)
  values <- ifelse(grepl("^[0-9]{5}$", values), paste0("K", values), values)
  unique(values[grepl("^K[0-9]{5}$", values)])
}

read_inputs <- function() {
  stat_dir <- file.path(opt$workdir, "result", "stat", opt$dimension)
  ml_dir <- file.path(stat_dir, "ml_mlr3_functional", opt$type)
  processed_file <- file.path(ml_dir, paste0("processed_", opt$type, ".rds"))
  if(!file.exists(processed_file)) stop("Processed RDS not found: ", processed_file)

  processed <- readRDS(processed_file)
  if(is.null(processed$features) || is.null(colnames(processed$features))) {
    stop("processed RDS does not contain feature column names: ", processed_file)
  }
  universe <- normalize_ko(colnames(processed$features))

  if(opt$source == "ml_top50") {
    input_file <- file.path(ml_dir, paste0("shap_importance_", opt$dimension, ".csv"))
    if(!file.exists(input_file)) stop("SHAP importance file not found: ", input_file)
    input <- read.csv(input_file, check.names=FALSE)
    needed <- c("feature", "mean_abs_shap")
    if(!all(needed %in% names(input))) stop("SHAP file missing required columns")
    input$mean_abs_shap <- suppressWarnings(as.numeric(input$mean_abs_shap))
    input <- input[is.finite(input$mean_abs_shap), , drop=FALSE]
    input <- input[order(input$mean_abs_shap, decreasing=TRUE), , drop=FALSE]
    genes <- normalize_ko(head(input$feature, 50))
  } else {
    input_file <- file.path(stat_dir, "functional_differential", opt$type,
                            "deseq2_results.tsv")
    if(!file.exists(input_file)) stop("DESeq2 result file not found: ", input_file)
    input <- read.delim(input_file, check.names=FALSE)
    if(!all(c("feature", "padj") %in% names(input))) {
      stop("DESeq2 file missing feature or padj column")
    }
    genes <- normalize_ko(input$feature[!is.na(input$padj) & input$padj < 0.05])
  }

  genes <- intersect(genes, universe)
  list(genes=genes, universe=universe, input_file=input_file,
       processed_file=processed_file)
}

standardize_clusterprofiler <- function(result) {
  result <- as.data.frame(result)
  if(nrow(result) == 0) return(result)
  gene_ratio <- vapply(strsplit(result$GeneRatio, "/", fixed=TRUE), function(parts) {
    as.numeric(parts[[1]]) / as.numeric(parts[[2]])
  }, numeric(1))
  data.frame(
    pathway_id=sub("^ko", "map", result$ID),
    description=result$Description,
    pvalue=result$pvalue,
    p.adjust=result$p.adjust,
    qvalue=result$qvalue,
    gene_count=result$Count,
    gene_ratio=gene_ratio,
    gene_ratio_text=result$GeneRatio,
    background_count=vapply(strsplit(result$BgRatio, "/", fixed=TRUE),
                            function(parts) as.numeric(parts[[1]]), numeric(1)),
    background_ratio=result$BgRatio,
    genes=gsub("/", ";", result$geneID, fixed=TRUE),
    method="clusterProfiler::enrichKEGG",
    stringsAsFactors=FALSE
  )
}

run_clusterprofiler <- function(genes, universe) {
  if(!requireNamespace("clusterProfiler", quietly=TRUE)) {
    stop("clusterProfiler is not installed")
  }
  formats <- list(
    prefixed=list(gene=genes, universe=universe),
    numeric=list(gene=sub("^K", "", genes), universe=sub("^K", "", universe))
  )
  errors <- character()
  for(format_name in names(formats)) {
    attempt <- tryCatch(
      clusterProfiler::enrichKEGG(
        gene=formats[[format_name]]$gene,
        organism="ko",
        universe=formats[[format_name]]$universe,
        pvalueCutoff=0.05,
        qvalueCutoff=0.2
      ),
      error=function(error) error
    )
    if(!inherits(attempt, "error")) {
      result <- standardize_clusterprofiler(attempt)
      attr(result, "ko_format") <- format_name
      return(result)
    }
    errors <- c(errors, paste0(format_name, ": ", conditionMessage(attempt)))
  }
  stop(paste(errors, collapse="; "))
}

fetch_pathway_links <- function(kos, batch_size=100) {
  batches <- split(kos, ceiling(seq_along(kos) / batch_size))
  links <- lapply(seq_along(batches), function(index) {
    query <- paste0("ko:", batches[[index]])
    result <- tryCatch(KEGGREST::keggLink("pathway", query), error=function(error) error)
    if(inherits(result, "error")) {
      stop("KEGG pathway link query failed for batch ", index, ": ",
           conditionMessage(result))
    }
    if(length(result) == 0) return(NULL)
    data.frame(
      ko=sub("^ko:", "", names(result)),
      pathway_id=sub("^path:ko", "map", unname(result)),
      stringsAsFactors=FALSE
    )
  })
  links <- do.call(rbind, links)
  if(is.null(links)) return(data.frame(ko=character(), pathway_id=character()))
  unique(links[grepl("^map[0-9]{5}$", links$pathway_id), , drop=FALSE])
}

fetch_pathway_names <- function(pathway_ids) {
  listing <- KEGGREST::keggList("pathway", "ko")
  names_by_id <- setNames(unname(listing), sub("^ko", "map", names(listing)))
  descriptions <- unname(names_by_id[pathway_ids])
  descriptions <- sub(" - Reference pathway$", "", descriptions)
  descriptions[is.na(descriptions)] <- pathway_ids[is.na(descriptions)]
  descriptions
}

run_manual_enrichment <- function(genes, universe) {
  links <- fetch_pathway_links(universe)
  mapped_universe <- intersect(universe, unique(links$ko))
  mapped_genes <- intersect(genes, mapped_universe)
  if(length(mapped_genes) == 0 || nrow(links) == 0) return(data.frame())

  pathway_sets <- split(links$ko, links$pathway_id)
  pathway_sets <- lapply(pathway_sets, unique)
  total_universe <- length(mapped_universe)
  total_genes <- length(mapped_genes)
  result <- lapply(names(pathway_sets), function(pathway_id) {
    members <- intersect(pathway_sets[[pathway_id]], mapped_universe)
    hits <- intersect(mapped_genes, members)
    background_count <- length(members)
    gene_count <- length(hits)
    if(gene_count == 0) return(NULL)
    pvalue <- phyper(gene_count - 1, background_count,
                     total_universe - background_count, total_genes,
                     lower.tail=FALSE)
    data.frame(
      pathway_id=pathway_id,
      pvalue=pvalue,
      gene_count=gene_count,
      gene_ratio=gene_count / total_genes,
      gene_ratio_text=paste0(gene_count, "/", total_genes),
      background_count=background_count,
      background_ratio=paste0(background_count, "/", total_universe),
      genes=paste(sort(hits), collapse=";"),
      stringsAsFactors=FALSE
    )
  })
  result <- do.call(rbind, result)
  if(is.null(result) || nrow(result) == 0) return(data.frame())
  result$p.adjust <- p.adjust(result$pvalue, method="BH")
  result$qvalue <- result$p.adjust
  result$description <- fetch_pathway_names(result$pathway_id)
  result$method <- "KEGGREST hypergeometric"
  result <- result[, c("pathway_id", "description", "pvalue", "p.adjust", "qvalue",
                       "gene_count", "gene_ratio", "gene_ratio_text",
                       "background_count", "background_ratio", "genes", "method")]
  result[order(result$p.adjust, result$pvalue, -result$gene_count), , drop=FALSE]
}

empty_result <- function(status, method, input_count, universe_count) {
  data.frame(
    pathway_id=NA_character_, description=status, pvalue=NA_real_,
    p.adjust=NA_real_, qvalue=NA_real_, gene_count=NA_integer_,
    gene_ratio=NA_real_, gene_ratio_text=NA_character_,
    background_count=NA_integer_, background_ratio=NA_character_,
    genes=NA_character_, method=method, input_ko_count=input_count,
    universe_ko_count=universe_count, stringsAsFactors=FALSE
  )
}

save_empty_plot <- function(path, title, message) {
  plot <- ggplot() +
    annotate("text", x=0.5, y=0.5, label=message, size=4) +
    xlim(0, 1) + ylim(0, 1) +
    labs(title=title) +
    theme_void(base_size=11) +
    theme(plot.title=element_text(face="bold", hjust=0.5))
  ggsave(path, plot, width=8, height=5, units="in")
}

save_plots <- function(result, barplot_file, dotplot_file) {
  significant <- result[!is.na(result$p.adjust) & result$p.adjust < 0.05, , drop=FALSE]
  if(nrow(significant) == 0) {
    title <- paste(opt$dimension, opt$source, "KEGG enrichment")
    save_empty_plot(barplot_file, title, "No significant enrichment")
    save_empty_plot(dotplot_file, title, "No significant enrichment")
    return(invisible(NULL))
  }

  top <- head(significant[order(significant$p.adjust, significant$pvalue), , drop=FALSE], 20)
  top$description <- factor(top$description, levels=rev(top$description))
  top$minus_log10_padj <- -log10(pmax(top$p.adjust, .Machine$double.xmin))

  barplot <- ggplot(top, aes(x=gene_ratio, y=description, fill=minus_log10_padj)) +
    geom_col(width=0.75) +
    scale_fill_gradient(low="#74ADD1", high="#D73027") +
    labs(title=paste(opt$dimension, opt$source, "KEGG pathway enrichment"),
         x="Gene ratio", y=NULL, fill=expression(-log[10](adjusted~P))) +
    theme_bw(base_size=10) +
    theme(plot.title=element_text(face="bold", hjust=0.5),
          panel.grid.major.y=element_blank())

  dotplot <- ggplot(top, aes(x=gene_ratio, y=description,
                            size=gene_count, color=p.adjust)) +
    geom_point(alpha=0.9) +
    scale_color_gradient(low="#D73027", high="#4575B4", trans="reverse") +
    scale_size_continuous(range=c(3, 10)) +
    labs(title=paste(opt$dimension, opt$source, "KEGG pathway enrichment"),
         x="Gene ratio", y=NULL, size="KO count", color="Adjusted P") +
    theme_bw(base_size=10) +
    theme(plot.title=element_text(face="bold", hjust=0.5),
          panel.grid.major.y=element_blank())

  plot_height <- max(5, 0.3 * nrow(top) + 2)
  ggsave(barplot_file, barplot, width=9, height=plot_height, units="in")
  ggsave(dotplot_file, dotplot, width=9, height=plot_height, units="in")
}

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)
prefix <- paste(opt$source, opt$dimension, opt$type, sep="_")
csv_file <- file.path(opt$outdir, paste0("enrichment_", prefix, ".csv"))
barplot_file <- file.path(opt$outdir, paste0("enrichment_barplot_", prefix, ".pdf"))
dotplot_file <- file.path(opt$outdir, paste0("enrichment_dotplot_", prefix, ".pdf"))

inputs <- read_inputs()
cat(sprintf("[INFO] Dimension: %s; source: %s\n", opt$dimension, opt$source))
cat(sprintf("[INFO] Input KOs: %d; universe KOs: %d\n",
            length(inputs$genes), length(inputs$universe)))

if(length(inputs$genes) < 10) {
  result <- empty_result("No significant enrichment: fewer than 10 input KOs",
                         "not run", length(inputs$genes), length(inputs$universe))
} else {
  result <- tryCatch(
    {
      cat("[INFO] Trying clusterProfiler::enrichKEGG\n")
      run_clusterprofiler(inputs$genes, inputs$universe)
    },
    error=function(error) {
      cat("[WARN] clusterProfiler unavailable or failed: ", conditionMessage(error), "\n",
          "[INFO] Switching to KEGGREST hypergeometric enrichment\n", sep="")
      run_manual_enrichment(inputs$genes, inputs$universe)
    }
  )
  if(nrow(result) == 0) {
    result <- empty_result("No significant enrichment", "KEGG enrichment",
                           length(inputs$genes), length(inputs$universe))
  } else {
    result$input_ko_count <- length(inputs$genes)
    result$universe_ko_count <- length(inputs$universe)
    result <- result[!is.na(result$p.adjust) & result$p.adjust < 0.05, , drop=FALSE]
    if(nrow(result) == 0) {
      result <- empty_result("No significant enrichment", "KEGG enrichment",
                             length(inputs$genes), length(inputs$universe))
    }
  }
}

write.csv(result, csv_file, row.names=FALSE, na="")
save_plots(result, barplot_file, dotplot_file)

significant <- result[!is.na(result$p.adjust) & result$p.adjust < 0.05, , drop=FALSE]
cat(sprintf("[RESULT] Significant pathways (p.adjust < 0.05): %d\n", nrow(significant)))
if(nrow(significant) > 0) {
  cat("[RESULT] Top pathways: ",
      paste(head(significant$description[order(significant$p.adjust)], 3), collapse=" | "),
      "\n", sep="")
}
cat("[INFO] Saved: ", csv_file, "\n", sep="")
cat("[INFO] Saved: ", barplot_file, "\n", sep="")
cat("[INFO] Saved: ", dotplot_file, "\n", sep="")
