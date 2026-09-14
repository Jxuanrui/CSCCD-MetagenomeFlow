#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
})

# Parse arguments
option_list <- list(
  make_option(c("-w", "--workdir"), type="character",
              help="Project work directory"),
  make_option(c("-d", "--dimension"), type="character",
              help="Dimension: bacteria/virus/fungi"),
  make_option(c("-i", "--input-dir"), dest="input_dir", type="character", default=NULL,
              help="Input directory [default: workdir/result/stat/dimension/ml_mlr3]"),
  make_option(c("-o", "--outdir"), type="character", default=NULL,
              help="Output directory [default: workdir/result/stat/dimension/ml_mlr3]"),
  make_option(c("--n-top-shap"), dest="n_top_shap", type="integer", default=20,
              help="Top SHAP features shown [default: 20]"),
  make_option(c("--n-top-boruta"), dest="n_top_boruta", type="integer", default=30,
              help="Maximum confirmed Boruta features shown [default: 30]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate inputs
required <- c("workdir", "dimension")
missing <- required[!required %in% names(opt) | vapply(opt[required], is.null, logical(1))]
if(length(missing) > 0) {
  stop("Missing required arguments: ", paste(missing, collapse=", "))
}

valid_dimensions <- c("bacteria", "virus", "fungi")
if(!opt$dimension %in% valid_dimensions) {
  stop("Invalid dimension: ", opt$dimension,
       ". Expected one of: ", paste(valid_dimensions, collapse=", "))
}

integer_options <- c("n_top_shap", "n_top_boruta")
for(option_name in integer_options) {
  option_value <- opt[[option_name]]
  if(is.null(option_value) || length(option_value) != 1 || is.na(option_value) ||
     !is.finite(option_value) || option_value < 1) {
    stop("--", gsub("_", "-", option_name), " must be a positive integer")
  }
}

if(is.null(opt$input_dir)) {
  opt$input_dir <- file.path(
    opt$workdir, "result", "stat", opt$dimension, "ml_mlr3"
  )
}
if(is.null(opt$outdir)) {
  opt$outdir <- opt$input_dir
}

shap_file <- file.path(
  opt$input_dir, sprintf("shap_importance_%s.csv", opt$dimension)
)
boruta_file <- file.path(
  opt$input_dir, sprintf("boruta_importance_%s.csv", opt$dimension)
)

shorten_taxon_label <- function(feature_strings) {
  shorten_one <- function(feature_string) {
    if(is.na(feature_string)) {
      return("NA")
    }

    feature_string <- as.character(feature_string)
    if(!grepl("|", feature_string, fixed=TRUE)) {
      if(nchar(feature_string) > 60) {
        return(paste0(substr(feature_string, 1, 57), "..."))
      }
      return(feature_string)
    }

    taxon_levels <- strsplit(feature_string, "|", fixed=TRUE)[[1]]
    taxon_levels <- tail(taxon_levels, min(2L, length(taxon_levels)))
    taxon_levels <- vapply(taxon_levels, function(taxon_level) {
      prefix_match <- regexpr("^[^_]+__", taxon_level)
      if(prefix_match[[1]] == 1) {
        prefix_length <- attr(prefix_match, "match.length")
        prefix <- substr(taxon_level, 1, prefix_length)
        value <- substr(taxon_level, prefix_length + 1, nchar(taxon_level))
        return(paste0(prefix, gsub("_", " ", value, fixed=TRUE)))
      }
      gsub("_", " ", taxon_level, fixed=TRUE)
    }, character(1))

    paste(taxon_levels, collapse=" | ")
  }

  shortened <- vapply(feature_strings, shorten_one, character(1))
  make.unique(shortened, sep=" #")
}

read_importance_csv <- function(path, required_columns) {
  importance <- utils::read.csv(path, stringsAsFactors=FALSE, check.names=FALSE)
  missing_columns <- setdiff(required_columns, names(importance))
  if(length(missing_columns) > 0) {
    stop("Input file ", path, " is missing columns: ",
         paste(missing_columns, collapse=", "))
  }
  importance
}

start_time <- proc.time()[["elapsed"]]

cat(sprintf("[INFO] Starting diagnostic importance plotting\n"))
cat(sprintf("[INFO] Workdir: %s\n", opt$workdir))
cat(sprintf("[INFO] Dimension: %s\n", opt$dimension))
cat(sprintf("[INFO] Input directory: %s\n", opt$input_dir))
cat(sprintf("[INFO] Output directory: %s\n", opt$outdir))
cat(sprintf("[INFO] Top features: SHAP=%d; Boruta confirmed=%d\n",
            opt$n_top_shap, opt$n_top_boruta))

dir.create(opt$outdir, recursive=TRUE, showWarnings=FALSE)

if(!file.exists(shap_file)) {
  cat(sprintf("[WARN] SHAP importance file not found; skipping SHAP plot: %s\n",
              shap_file))
} else {
  shap_importance <- read_importance_csv(
    shap_file, c("feature", "mean_abs_shap")
  )

  if(nrow(shap_importance) == 0) {
    cat(sprintf("[WARN] SHAP importance file has 0 rows; skipping SHAP plot: %s\n",
                shap_file))
  } else {
    shap_importance$mean_abs_shap <- as.numeric(shap_importance$mean_abs_shap)
    valid_rows <- is.finite(shap_importance$mean_abs_shap) &
      !is.na(shap_importance$feature) & shap_importance$feature != ""
    if(any(!valid_rows)) {
      cat(sprintf("[WARN] Excluding %d invalid SHAP importance rows\n",
                  sum(!valid_rows)))
    }
    shap_importance <- shap_importance[valid_rows, , drop=FALSE]

    if(nrow(shap_importance) == 0) {
      cat(sprintf("[WARN] No valid SHAP importance rows; skipping SHAP plot\n"))
    } else {
      shap_importance <- shap_importance[
        order(shap_importance$mean_abs_shap, decreasing=TRUE), , drop=FALSE
      ]
      n_plotted <- min(opt$n_top_shap, nrow(shap_importance))
      shap_plot_data <- shap_importance[seq_len(n_plotted), , drop=FALSE]
      shap_plot_data$short_label <- shorten_taxon_label(shap_plot_data$feature)

      shap_plot <- ggplot(
        shap_plot_data,
        aes(
          x=mean_abs_shap,
          y=stats::reorder(short_label, mean_abs_shap),
          fill=mean_abs_shap
        )
      ) +
        geom_col(width=0.78) +
        scale_fill_gradient(low="#2C7FB8", high="#D7191C") +
        labs(
          title=sprintf("Top %d diagnostic features (SHAP): %s",
                        n_plotted, opt$dimension),
          x="Mean |SHAP value|",
          y=NULL
        ) +
        theme_classic(base_size=11) +
        theme(
          legend.position="none",
          axis.ticks.y=element_blank(),
          plot.title=element_text(face="bold", hjust=0.5),
          plot.margin=margin(8, 12, 8, 8)
        )

      shap_plot_file <- file.path(
        opt$outdir, sprintf("importance_shap_%s.pdf", opt$dimension)
      )
      ggsave(
        shap_plot_file, shap_plot, width=8,
        height=max(4, 0.28 * n_plotted + 1.5), units="in"
      )
      cat(sprintf("[INFO] Saved SHAP importance plot: %s\n", shap_plot_file))
    }
  }
}

if(!file.exists(boruta_file)) {
  cat(sprintf("[WARN] Boruta importance file not found; skipping Boruta plot: %s\n",
              boruta_file))
} else {
  boruta_importance <- read_importance_csv(
    boruta_file, c("feature", "meanImp", "medianImp", "decision")
  )
  boruta_importance <- boruta_importance[
    boruta_importance$decision == "Confirmed", , drop=FALSE
  ]

  if(nrow(boruta_importance) == 0) {
    cat(sprintf("[WARN] No confirmed Boruta features; skipping Boruta plot: %s\n",
                boruta_file))
  } else {
    boruta_importance$meanImp <- as.numeric(boruta_importance$meanImp)
    valid_rows <- is.finite(boruta_importance$meanImp) &
      !is.na(boruta_importance$feature) & boruta_importance$feature != ""
    if(any(!valid_rows)) {
      cat(sprintf("[WARN] Excluding %d invalid confirmed Boruta rows\n",
                  sum(!valid_rows)))
    }
    boruta_importance <- boruta_importance[valid_rows, , drop=FALSE]

    if(nrow(boruta_importance) == 0) {
      cat(sprintf("[WARN] No valid confirmed Boruta rows; skipping Boruta plot\n"))
    } else {
      boruta_importance <- boruta_importance[
        order(boruta_importance$meanImp, decreasing=TRUE), , drop=FALSE
      ]
      n_plotted <- min(opt$n_top_boruta, nrow(boruta_importance))
      boruta_plot_data <- boruta_importance[seq_len(n_plotted), , drop=FALSE]
      boruta_plot_data$short_label <- shorten_taxon_label(boruta_plot_data$feature)

      boruta_plot <- ggplot(
        boruta_plot_data,
        aes(
          x=meanImp,
          y=stats::reorder(short_label, meanImp),
          fill=meanImp
        )
      ) +
        geom_col(width=0.78) +
        scale_fill_gradient(low="#41AB5D", high="#00441B") +
        labs(
          title=sprintf("Confirmed diagnostic features (Boruta): %s",
                        opt$dimension),
          x="Mean importance (Boruta)",
          y=NULL
        ) +
        theme_classic(base_size=11) +
        theme(
          legend.position="none",
          axis.ticks.y=element_blank(),
          plot.title=element_text(face="bold", hjust=0.5),
          plot.margin=margin(8, 12, 8, 8)
        )

      boruta_plot_file <- file.path(
        opt$outdir, sprintf("importance_boruta_%s.pdf", opt$dimension)
      )
      ggsave(
        boruta_plot_file, boruta_plot, width=8,
        height=max(4, 0.28 * n_plotted + 1.5), units="in"
      )
      cat(sprintf("[INFO] Saved Boruta importance plot: %s\n", boruta_plot_file))
    }
  }
}

total_runtime <- proc.time()[["elapsed"]] - start_time
cat(sprintf("[INFO] Total runtime: %.1f seconds\n", total_runtime))
cat(sprintf("[INFO] Diagnostic importance plotting completed successfully\n"))
