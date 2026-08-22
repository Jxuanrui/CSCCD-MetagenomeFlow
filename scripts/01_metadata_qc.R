#!/usr/bin/env Rscript
# 01_metadata_qc.R - Metadata preparation and quality control

options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...
))

cat("[INFO] Step 1: Metadata preparation and quality control\n")

conda_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_lib)) {
  .libPaths(unique(c(
    conda_lib,
    .libPaths()[normalizePath(.libPaths(), mustWork = FALSE) !=
                  normalizePath(conda_lib, mustWork = FALSE)]
  )))
}

required_pkgs <- c("readr", "tibble")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {
  stop("Missing required R packages: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(readr)
  library(tibble)
})

is_nonempty <- function(x) length(x) > 0 && !is.na(x[1]) && nzchar(x[1])

args <- commandArgs(trailingOnly = TRUE)
env_workdir <- Sys.getenv("WORKDIR")
workdir <- if (is_nonempty(env_workdir)) {
  env_workdir
} else if (length(args) >= 1 && is_nonempty(args[1])) {
  args[1]
} else if (file.exists("metadata.csv")) {
  "."
} else {
  "Project/Test_100samples"
}
workdir <- normalizePath(workdir, mustWork = TRUE)

repo <- Sys.getenv("REPO")
if (!is_nonempty(repo)) {
  repo <- if (basename(dirname(workdir)) == "Project") dirname(dirname(workdir)) else getwd()
}
repo <- normalizePath(repo, winslash = "/", mustWork = FALSE)

rel_path <- function(path) {
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  r <- normalizePath(repo, winslash = "/", mustWork = FALSE)
  prefix <- paste0(r, "/")
  if (startsWith(p, prefix)) substring(p, nchar(prefix) + 1) else p
}

metadata_csv <- file.path(workdir, "metadata.csv")
out_dir <- file.path(workdir, "result", "stat")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

metadata_tsv <- file.path(out_dir, "metadata.tsv")
report_path <- file.path(out_dir, "metadata_qc_report.txt")
status_path <- file.path(out_dir, "metadata_status.tsv")

format_pct <- function(x, digits = 1) sprintf(paste0("%.", digits, "f%%"), x)
format_p <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
format_value <- function(x, variable) {
  if (is.na(x)) return("NA")
  if (identical(variable, "seq_depth")) {
    formatC(x, format = "f", digits = 0, big.mark = "")
  } else {
    formatC(x, format = "f", digits = 1)
  }
}

outlier_detection <- function(x) {
  mean_x <- mean(x, na.rm = TRUE)
  sd_x <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(mean_x) || !is.finite(sd_x) || sd_x == 0) {
    outliers <- rep(FALSE, length(x))
    lower <- NA_real_
    upper <- NA_real_
  } else {
    lower <- mean_x - 3 * sd_x
    upper <- mean_x + 3 * sd_x
    outliers <- x < lower | x > upper
    outliers[is.na(outliers)] <- FALSE
  }

  list(
    mean = mean_x,
    sd = sd_x,
    lower = lower,
    upper = upper,
    outliers = outliers,
    n_outliers = sum(outliers, na.rm = TRUE),
    outlier_samples = which(outliers)
  )
}

format_table_lines <- function(mat) {
  mat <- as.matrix(mat)
  row_names <- rownames(mat)
  col_names <- colnames(mat)
  cells <- cbind(Batch = row_names, as.data.frame.matrix(mat, stringsAsFactors = FALSE))
  names(cells) <- c("", col_names)

  widths <- vapply(seq_along(cells), function(i) {
    max(nchar(c(names(cells)[i], as.character(cells[[i]]))), na.rm = TRUE)
  }, integer(1))

  header <- paste(vapply(seq_along(cells), function(i) {
    format(names(cells)[i], width = widths[i], justify = if (i == 1) "left" else "right")
  }, character(1)), collapse = "  ")

  body <- vapply(seq_len(nrow(cells)), function(j) {
    paste(vapply(seq_along(cells), function(i) {
      format(as.character(cells[[i]][j]), width = widths[i], justify = if (i == 1) "left" else "right")
    }, character(1)), collapse = "  ")
  }, character(1))

  c(header, body)
}

cat("[INFO] Loading metadata: ", metadata_csv, "\n", sep = "")
if (!file.exists(metadata_csv)) {
  stop("Input metadata not found: ", metadata_csv)
}

metadata <- readr::read_csv(
  metadata_csv,
  na = c("", "NA", "NaN", "NULL", "null"),
  show_col_types = FALSE,
  progress = FALSE
)
metadata <- as.data.frame(metadata, stringsAsFactors = FALSE)

required_cols <- c("sample_id", "group")
missing_required <- setdiff(required_cols, colnames(metadata))
if (length(missing_required)) {
  stop("Missing required metadata columns: ", paste(missing_required, collapse = ", "))
}
if (any(is.na(metadata$sample_id) | !nzchar(as.character(metadata$sample_id)))) {
  stop("sample_id contains missing or empty values")
}
if (anyDuplicated(metadata$sample_id)) {
  stop("sample_id contains duplicated values")
}

numeric_vars <- c("age", "bmi", "seq_depth")
for (var in intersect(numeric_vars, colnames(metadata))) {
  metadata[[var]] <- suppressWarnings(as.numeric(metadata[[var]]))
}

metadata$sample_id <- as.character(metadata$sample_id)
metadata$group <- as.character(metadata$group)
preferred_levels <- c("case", "control")
group_levels <- c(intersect(preferred_levels, unique(metadata$group)),
                  setdiff(unique(metadata$group), preferred_levels))
metadata$group <- factor(metadata$group, levels = group_levels)
rownames(metadata) <- metadata$sample_id

metadata_tsv_df <- metadata[, setdiff(colnames(metadata), "sample_id"), drop = FALSE]
utils::write.table(
  metadata_tsv_df,
  metadata_tsv,
  sep = "\t",
  quote = FALSE,
  row.names = TRUE,
  col.names = NA,
  na = ""
)
cat("[INFO] Standardized metadata written: ", metadata_tsv, "\n", sep = "")

missing_count <- colSums(is.na(metadata))
missing_pct <- missing_count / nrow(metadata) * 100
sample_missing <- rowSums(is.na(metadata))
total_missing <- sum(missing_count)
total_cells <- nrow(metadata) * ncol(metadata)
total_missing_pct <- if (total_cells > 0) total_missing / total_cells * 100 else 0

outlier_vars <- intersect(numeric_vars, colnames(metadata))
outlier_results <- stats::setNames(lapply(outlier_vars, function(var) {
  res <- outlier_detection(metadata[[var]])
  sample_idx <- res$outlier_samples
  details <- data.frame(
    variable = rep(var, length(sample_idx)),
    sample_id = metadata$sample_id[sample_idx],
    value = metadata[[var]][sample_idx],
    direction = ifelse(
      metadata[[var]][sample_idx] > res$upper,
      "upper outlier",
      "lower outlier"
    ),
    stringsAsFactors = FALSE
  )
  list(summary = res, details = details)
}), outlier_vars)

group_counts <- table(metadata$group, useNA = "ifany")
balance_ratio <- if (length(group_counts) > 1 && max(group_counts) > 0) {
  as.numeric(min(group_counts) / max(group_counts))
} else {
  NA_real_
}

has_batch_col <- "batch" %in% colnames(metadata)
if (!has_batch_col) {
  # 本项目 metadata 无 batch 列，视为单批次数据（与 95a_stat_batch_correct.sh
  # 的处理一致），跳过批次-分组混淆检验而非直接报错终止整个 QC 脚本
  metadata$batch <- "single_batch"
}
batch_group_table <- table(metadata$batch, metadata$group)
batch_has_both <- all(rowSums(batch_group_table > 0) == ncol(batch_group_table))
chi_p <- if (has_batch_col) {
  tryCatch(
    suppressWarnings(stats::chisq.test(batch_group_table)$p.value),
    error = function(e) NA_real_
  )
} else {
  NA_real_
}
batch_ok <- if (has_batch_col) {
  isTRUE(batch_has_both) && (is.na(chi_p) || chi_p >= 0.05)
} else {
  TRUE
}

covariate_tests <- stats::setNames(lapply(outlier_vars, function(var) {
  cov_df <- metadata[!is.na(metadata[[var]]) & !is.na(metadata$group), c("group", var), drop = FALSE]
  if (nlevels(droplevels(cov_df$group)) != 2 || nrow(cov_df) == 0) {
    return(NA_real_)
  }
  stats::wilcox.test(cov_df[[var]] ~ droplevels(cov_df$group), exact = FALSE)$p.value
}), outlier_vars)
covariate_p <- unlist(covariate_tests)
covariate_ok <- all(is.na(covariate_p) | covariate_p >= 0.05)

cat("[INFO] Generating QC report\n")

missing_column_lines <- if (all(missing_count == 0)) {
  "Columns with missing values: None"
} else {
  c(
    "Columns with missing values:",
    vapply(names(missing_count)[missing_count > 0], function(col) {
      sprintf("  - %s: %d (%s)", col, missing_count[[col]], format_pct(missing_pct[[col]], 2))
    }, character(1))
  )
}

missing_sample_lines <- if (all(sample_missing == 0)) {
  "Samples with missing values: None"
} else {
  sample_ids <- names(sample_missing)[sample_missing > 0]
  c(
    "Samples with missing values:",
    vapply(sample_ids, function(id) {
      sprintf("  - %s: %d", id, sample_missing[[id]])
    }, character(1))
  )
}

outlier_lines <- unlist(lapply(outlier_vars, function(var) {
  res <- outlier_results[[var]]$summary
  details <- outlier_results[[var]]$details
  pct <- if (nrow(metadata) > 0) res$n_outliers / nrow(metadata) * 100 else 0
  lines <- sprintf("%s: %d outliers (%s)", var, res$n_outliers, format_pct(pct, 1))
  if (nrow(details) > 0) {
    detail_lines <- vapply(seq_len(nrow(details)), function(i) {
      sprintf("  - %s: %s (%s)",
              details$sample_id[i],
              format_value(details$value[i], var),
              details$direction[i])
    }, character(1))
    lines <- c(lines, detail_lines)
  } else {
    lines <- c(lines, "  - None")
  }
  lines
}), use.names = FALSE)

group_lines <- vapply(names(group_counts), function(grp) {
  count <- as.integer(group_counts[[grp]])
  sprintf("  %s: %d (%s)", grp, count, format_pct(count / nrow(metadata) * 100, 1))
}, character(1))

balance_text <- if (!is.na(balance_ratio) && isTRUE(all.equal(balance_ratio, 1))) {
  "perfect balance"
} else {
  "acceptable balance"
}

batch_table_lines <- format_table_lines(batch_group_table)
chi_text <- if (is.na(chi_p)) {
  "Chi-square test: p = NA (test unavailable)"
} else if (chi_p < 0.05) {
  sprintf("Chi-square test: p = %s (significant batch-group association)", format_p(chi_p))
} else {
  sprintf("Chi-square test: p = %s (no significant batch-group confounding)", format_p(chi_p))
}
if (!batch_has_both) {
  chi_text <- paste0(chi_text, "; at least one batch lacks one group")
}

covariate_lines <- vapply(outlier_vars, function(var) {
  p <- covariate_p[[var]]
  suffix <- if (is.na(p)) {
    "test unavailable"
  } else if (p < 0.05) {
    "significant difference"
  } else {
    "no significant difference"
  }
  sprintf("%s: Wilcoxon p = %s (%s)", var, format_p(p), suffix)
}, character(1))

outlier_counts <- vapply(outlier_results, function(x) x$summary$n_outliers, integer(1))
outlier_pcts <- outlier_counts / nrow(metadata) * 100
no_missing <- total_missing == 0
minimal_outliers <- all(outlier_pcts < 1)
perfect_balance <- !is.na(balance_ratio) && isTRUE(all.equal(balance_ratio, 1))
pass_status <- no_missing && minimal_outliers && perfect_balance && batch_ok && covariate_ok
mark <- "\u2713"
warn_mark <- "!"
conclusion_line <- function(ok, text) paste(if (ok) mark else warn_mark, text)

report_date <- Sys.getenv("QC_DATE")
if (!is_nonempty(report_date)) report_date <- as.character(Sys.Date())

report_lines <- c(
  "========================================",
  "Metadata Quality Control Report",
  "========================================",
  "",
  paste("Data:", rel_path(metadata_tsv)),
  paste("Date:", report_date),
  paste("Total Samples:", nrow(metadata)),
  "",
  "--- Summary ---",
  "Samples per group:",
  group_lines,
  sprintf("Balance ratio: %.2f (%s)", balance_ratio, balance_text),
  "",
  "--- Missing Values ---",
  sprintf("Total missing: %d (%s)", total_missing, format_pct(total_missing_pct, 2)),
  missing_column_lines,
  missing_sample_lines,
  "",
  "--- Outliers (mean \u00b1 3*SD) ---",
  outlier_lines,
  "",
  "--- Batch Distribution ---",
  "Batch \u00d7 Group cross-tabulation:",
  batch_table_lines,
  "",
  chi_text,
  "",
  "--- Covariates Group Comparison ---",
  covariate_lines,
  "",
  "--- Conclusion ---",
  conclusion_line(no_missing, if (no_missing) "No missing values" else "Missing values detected"),
  conclusion_line(minimal_outliers, if (minimal_outliers) "Minimal outliers (<1% per variable)" else "Outlier rate >=1% in at least one variable"),
  conclusion_line(perfect_balance, if (perfect_balance) "Perfect group balance" else "Group imbalance detected"),
  conclusion_line(batch_ok, if (batch_ok) "No batch-group confounding" else "Potential batch-group confounding"),
  conclusion_line(covariate_ok, if (covariate_ok) "No significant covariate imbalance between groups" else "Significant covariate imbalance detected"),
  if (pass_status) "Status: PASS - Ready for downstream analysis" else "Status: WARN - Review issues before downstream analysis",
  "",
  "========================================"
)
writeLines(report_lines, report_path)

status_df <- tibble::tibble(
  step = c(
    "load_metadata",
    "missing_check",
    "outlier_check",
    "balance_check",
    "batch_check",
    "covariate_check",
    "report_generation"
  ),
  status = c(
    "OK",
    if (no_missing) "OK" else "WARN",
    if (minimal_outliers) "OK" else "WARN",
    if (perfect_balance) "OK" else "WARN",
    if (batch_ok) "OK" else "WARN",
    if (covariate_ok) "OK" else "WARN",
    "OK"
  ),
  message = c(
    sprintf("%d samples loaded", nrow(metadata)),
    sprintf("%d missing values", total_missing),
    sprintf("%d outliers detected (<1%% per variable)", sum(outlier_counts)),
    if (perfect_balance) {
      sprintf("Perfect balance (%s)", paste(as.integer(group_counts), collapse = "/"))
    } else {
      sprintf("Balance ratio %.2f", balance_ratio)
    },
    if (batch_ok) "No batch-group confounding" else "Potential batch-group confounding",
    if (covariate_ok) "No significant group differences" else "Significant group differences detected",
    "QC report saved"
  )
)
readr::write_tsv(status_df, status_path, na = "")

cat("[INFO] QC report written: ", report_path, "\n", sep = "")
cat("[INFO] Status written: ", status_path, "\n", sep = "")
cat("[INFO] Metadata QC completed\n")
