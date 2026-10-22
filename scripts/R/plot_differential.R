#!/usr/bin/env Rscript
# ==============================================================================
# Differential Abundance Visualization Functions
# Nature-style plots for microbiome differential abundance analysis
# ==============================================================================

library(ggplot2)
library(ggrepel)
library(ggtext)
library(dplyr)
library(stringr)

# ==============================================================================
# Function 1: Nature-style volcano plot
# ==============================================================================
#' Create Nature-style volcano plot for differential abundance
#'
#' @param df Data frame with columns: feature, log2FoldChange, pvalue, padj
#' @param method Method name for title
#' @param fdr FDR threshold (default: 0.05)
#' @param lfc Log2 fold change threshold (default: 1.0)
#' @param top_n Number of top features to label (default: 10 per direction)
#' @param label_column Column name for feature labels (default: "feature")
#' @return ggplot object
plot_volcano_nature <- function(df, method = "Differential Abundance",
                                fdr = 0.05, lfc = 1.0, top_n = 10,
                                label_column = "feature") {

  # Extract species names from metaphlan4 clade names if needed
  if (all(grepl("\\|", df[[label_column]]))) {
    df$feature_name <- sapply(df[[label_column]], function(x) {
      parts <- strsplit(x, "\\|")[[1]]
      species_part <- grep("^s__", parts, value = TRUE)
      if (length(species_part) > 0) {
        return(sub("^s__", "", species_part[1]))
      } else {
        return(tail(parts, 1))
      }
    })
  } else {
    df$feature_name <- df[[label_column]]
  }

  # Clean feature names (remove underscores, truncate long names)
  df$feature_name <- gsub("_", " ", df$feature_name)
  df$feature_name <- ifelse(nchar(df$feature_name) > 30,
                            paste0(substr(df$feature_name, 1, 27), "..."),
                            df$feature_name)

  # Classify features into three categories
  df <- df %>%
    mutate(
      neg_log10_padj = -log10(padj),
      change = case_when(
        padj < fdr & log2FoldChange > lfc ~ "up",
        padj < fdr & log2FoldChange < -lfc ~ "down",
        TRUE ~ "non-sig"
      )
    )

  # Select top N features to label
  top_features <- df %>%
    filter(change != "non-sig") %>%
    group_by(change) %>%
    arrange(desc(abs(log2FoldChange))) %>%
    slice_head(n = top_n) %>%
    ungroup()

  # Define colors (Nature-style)
  colors <- c(
    "up" = "#C6295C",      # Wine red for upregulated
    "down" = "#2C6DB2",    # Deep blue for downregulated
    "non-sig" = "grey70"   # Grey for non-significant
  )

  # Create plot
  p <- ggplot(df, aes(x = log2FoldChange, y = neg_log10_padj, color = change)) +
    # Points with size mapped to significance
    geom_point(aes(size = neg_log10_padj), alpha = 0.7) +

    # Threshold lines
    geom_vline(xintercept = c(-lfc, lfc), linetype = "dashed", color = "grey40", linewidth = 0.5) +
    geom_hline(yintercept = -log10(fdr), linetype = "dashed", color = "grey40", linewidth = 0.5) +

    # Labels for top features
    geom_text_repel(
      data = top_features,
      aes(label = feature_name),
      size = 3,
      segment.size = 0.3,
      max.overlaps = 20,
      box.padding = 0.5,
      color = "black"  # Black text for readability
    ) +

    # Color and size scales
    scale_color_manual(
      values = colors,
      labels = c("up" = "Upregulated", "down" = "Downregulated", "non-sig" = "Non-significant")
    ) +
    scale_size_continuous(range = c(1, 3), guide = "none") +

    # Labels with HTML formatting
    labs(
      title = sprintf("%s Volcano Plot", method),
      x = "log<sub>2</sub>(Fold Change)",
      y = "-log<sub>10</sub>(FDR)",
      color = "Change"
    ) +

    # Theme
    theme_test(base_size = 12) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
      axis.text = element_text(color = "black", size = 11),
      axis.title.x = element_markdown(size = 12),
      axis.title.y = element_markdown(size = 12),
      legend.position = "right",
      legend.justification = "top",
      legend.background = element_rect(fill = "white", color = "grey80", linewidth = 0.5),
      legend.title = element_text(size = 11, face = "bold"),
      legend.text = element_text(size = 10),
      legend.key.size = unit(0.8, "lines"),
      legend.spacing.y = unit(0.2, "lines"),
      panel.grid.major = element_line(color = "grey95", linewidth = 0.3),
      panel.grid.minor = element_blank()
    )

  return(p)
}

# ==============================================================================
# Function 2: Enhanced differential species barplot
# ==============================================================================
#' Create enhanced barplot for top differential species
#'
#' @param df Data frame with columns: feature, log2FoldChange, padj
#' @param method Method name for title
#' @param top_n Number of top species to show (default: 20)
#' @return ggplot object
plot_barplot_enhanced <- function(df, method = "Differential Abundance",
                                  top_n = 20) {

  # Extract species names
  if (all(grepl("\\|", df$feature))) {
    df$feature_name <- sapply(df$feature, function(x) {
      parts <- strsplit(x, "\\|")[[1]]
      species_part <- grep("^s__", parts, value = TRUE)
      if (length(species_part) > 0) {
        return(sub("^s__", "", species_part[1]))
      } else {
        return(tail(parts, 1))
      }
    })
  } else {
    df$feature_name <- df$feature
  }

  # Clean names
  df$feature_name <- gsub("_", " ", df$feature_name)
  df$feature_name <- ifelse(nchar(df$feature_name) > 40,
                            paste0(substr(df$feature_name, 1, 37), "..."),
                            df$feature_name)

  # Select top N by absolute LFC
  df_top <- df %>%
    filter(sig) %>%
    arrange(desc(abs(log2FoldChange))) %>%
    slice_head(n = top_n) %>%
    mutate(
      direction = ifelse(log2FoldChange > 0, "up", "down"),
      feature_name = factor(feature_name, levels = rev(feature_name))
    )

  # Colors
  colors <- c("up" = "#C6295C", "down" = "#2C6DB2")

  # Create plot
  p <- ggplot(df_top, aes(x = log2FoldChange, y = feature_name, fill = direction)) +
    geom_col(width = 0.7, alpha = 0.8) +
    geom_vline(xintercept = 0, linetype = "solid", color = "grey30", size = 0.5) +
    scale_fill_manual(values = colors, guide = "none") +
    labs(
      title = sprintf("%s - Top %d Differential Species", method, top_n),
      x = "log<sub>2</sub>(Fold Change)",
      y = NULL
    ) +
    theme_test(base_size = 11) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
      axis.text.y = element_text(color = "black", size = 9),
      axis.text.x = element_text(color = "black", size = 10),
      axis.title.x = element_markdown(size = 11),
      panel.grid.major.x = element_line(color = "grey95", size = 0.3),
      panel.grid.major.y = element_blank()
    )

  return(p)
}

# ==============================================================================
# Function 3: Multi-dimensional volcano plot (for bacteria/fungi/virus)
# ==============================================================================
#' Create multi-dimensional volcano plot
#'
#' @param df_list Named list of data frames (one per dimension)
#' @param fdr FDR threshold
#' @param lfc Log2 fold change threshold
#' @return ggplot object
plot_volcano_multi <- function(df_list, fdr = 0.05, lfc = 1.0) {

  # Combine all dimensions
  df_combined <- bind_rows(lapply(names(df_list), function(dim) {
    df_list[[dim]] %>%
      mutate(dimension = dim,
             change = case_when(
               padj < fdr & log2FoldChange > lfc ~ "up",
               padj < fdr & log2FoldChange < -lfc ~ "down",
               TRUE ~ "non-sig"
             ))
  }))

  # Dimension colors
  dim_colors <- c(
    "bacteria" = "#3B9AB2",
    "fungi" = "#EBCC2A",
    "virus" = "#F21A00"
  )

  # Create background rectangles
  dim_levels <- unique(df_combined$dimension)
  bg_df <- tibble(
    dimension = factor(dim_levels, levels = dim_levels),
    xmin = seq_along(dim_levels) - 0.48,
    xmax = seq_along(dim_levels) + 0.48
  )

  # Plot
  p <- ggplot(df_combined, aes(x = dimension, y = log2FoldChange, color = change)) +
    geom_rect(
      data = bg_df,
      aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = dimension),
      inherit.aes = FALSE, alpha = 0.2
    ) +
    geom_jitter(alpha = 0.6, width = 0.2, size = 1) +
    scale_fill_manual(values = dim_colors, guide = "none") +
    scale_color_manual(values = c("up" = "#C6295C", "down" = "#2C6DB2", "non-sig" = "grey70")) +
    labs(
      title = "Multi-Dimensional Differential Abundance",
      x = "Dimension",
      y = "log<sub>2</sub>(Fold Change)",
      color = "Change"
    ) +
    theme_test() +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold"),
      axis.title.y = element_markdown(),
      legend.position = "top"
    )

  return(p)
}

# ==============================================================================
# Function 4: Lollipop plot for differential species
# ==============================================================================
#' Create lollipop plot for top differential species
#'
#' @param df Data frame with columns: feature, log2FoldChange, padj
#' @param top_n Number of top species to show
#' @return ggplot object
plot_lollipop <- function(df, top_n = 20) {

  # Extract and clean names
  if (all(grepl("\\|", df$feature))) {
    df$feature_name <- sapply(df$feature, function(x) {
      parts <- strsplit(x, "\\|")[[1]]
      species_part <- grep("^s__", parts, value = TRUE)
      if (length(species_part) > 0) {
        return(sub("^s__", "", species_part[1]))
      } else {
        return(tail(parts, 1))
      }
    })
  } else {
    df$feature_name <- df$feature
  }

  df$feature_name <- gsub("_", " ", df$feature_name)

  # Select top N
  df_top <- df %>%
    filter(sig) %>%
    arrange(log2FoldChange) %>%
    slice(c(1:min(top_n/2, n()), max(1, n()-top_n/2+1):n())) %>%
    mutate(
      direction = ifelse(log2FoldChange > 0, "up", "down"),
      feature_name = factor(feature_name, levels = feature_name)
    )

  # Colors
  colors <- c("up" = "#C6295C", "down" = "#2C6DB2")

  # Plot
  p <- ggplot(df_top, aes(x = log2FoldChange, y = feature_name, color = direction)) +
    geom_segment(aes(x = 0, xend = log2FoldChange, y = feature_name, yend = feature_name),
                 size = 1, alpha = 0.7) +
    geom_point(size = 3, alpha = 0.9) +
    geom_vline(xintercept = 0, linetype = "solid", color = "grey30", size = 0.5) +
    scale_color_manual(values = colors, guide = "none") +
    labs(
      title = sprintf("Top %d Differential Species", nrow(df_top)),
      x = "log<sub>2</sub>(Fold Change)",
      y = NULL
    ) +
    theme_test(base_size = 11) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
      axis.text.y = element_text(color = "black", size = 9),
      axis.text.x = element_text(color = "black", size = 10),
      axis.title.x = element_markdown(size = 11),
      panel.grid.major.x = element_line(color = "grey95", size = 0.3),
      panel.grid.major.y = element_blank()
    )

  return(p)
}

# ==============================================================================
# Export message
# ==============================================================================
message("[INFO] Differential abundance visualization functions loaded")
message("  - plot_volcano_nature(): Nature-style volcano plot")
message("  - plot_barplot_enhanced(): Enhanced differential species barplot")
message("  - plot_volcano_multi(): Multi-dimensional volcano plot")
message("  - plot_lollipop(): Lollipop plot for differential species")
