#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_96_stat_ml_label_alignment.sh
# Purpose: Regression test for the W-C1(1) label-alignment fix in
#          96_stat_ml_siamcat.sh (A6 pseudo-label defect): the metrics panel
#          (siamcat_metrics.tsv) must be computed against labels aligned BY
#          SAMPLE NAME from SIAMCAT::label(sc)$label, never against the
#          periodic pseudo-label sequence the old
#          as.integer(as.character(lbl)==...) + rep(length.out=) code produced.
#
#          Strategy: run 96 on a deterministic 12-sample fixture, then
#          independently recompute auc_pr/sensitivity/specificity from the
#          saved siamcat_<model>.rds (name-aligned) and assert exact equality
#          with the TSV. The known-bad old-style values are recomputed too;
#          the fixture must keep at least one model where old != aligned so
#          the assertion actually discriminates (a revert would fail it).
#
#          Fixture is built in mktemp -d (Test_CI_fixture untouched); the
#          file was ratified by the W-C1 change order ("回归固化" approval).
# Usage:   bash scripts/tests/level2/test_96_stat_ml_label_alignment.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="$(mktemp -d /tmp/test_96_label_alignment.XXXXXX)"

cleanup() {
    rm -rf "${FIXTURE}"
}
trap cleanup EXIT

echo "[INFO] Building deterministic 12-sample fixture in ${FIXTURE}..."
mkdir -p "${FIXTURE}/Project/result/metaphlan4/merged"

# metadata: H1-H6 / D1-D6; SIAMCAT convention case=levels()[2] -> with these
#          values the sorted factor levels are c(D,H), so H is the CASE class
{
    echo "sample_id,group"
    for i in 1 2 3 4 5 6; do echo "H${i},control"; done
    for i in 1 2 3 4 5 6; do echo "D${i},case"; done
} > "${FIXTURE}/Project/metadata.csv"

# deterministic abundance table: taxa 1-8 class-shifted markers, 9-24 noise.
# Arithmetic (no RNG) so every environment reproduces the same matrix.
{
    header="ID"
    for i in 1 2 3 4 5 6; do header="${header}	H${i}"; done
    for i in 1 2 3 4 5 6; do header="${header}	D${i}"; done
    echo "${header}"
    for i in $(seq 1 24); do
        row="k__Bacteria|p__P|c__C|o__O|f__F|g__G${i}|s__species${i}"
        j=0
        for s in H1 H2 H3 H4 H5 H6 D1 D2 D3 D4 D5 D6; do
            j=$((j + 1))
            if [ "${i}" -le 8 ]; then
                case "${s}" in H*) v=$(( 10 + (i * 3 + j * 5) % 7 ));;
                                *) v=$(( 40 + (i * 7 + j * 3) % 11 ));;
                esac
            else
                v=$(( 5 + (i * 11 + j * 7) % 13 ))
            fi
            row="${row}	${v}"
        done
        echo "${row}"
    done
} > "${FIXTURE}/Project/result/metaphlan4/merged/taxonomy.tsv"

echo "[INFO] Running 96_stat_ml_siamcat.sh (bacteria, --skip-shap)..."
bash "${REPO_ROOT}/scripts/96_stat_ml_siamcat.sh" \
    -w "${FIXTURE}/Project" -r "${REPO_ROOT}" -t 2 \
    -m "${FIXTURE}/Project/metadata.csv" -g group --force --skip-shap

ML_DIR="${FIXTURE}/Project/result/stat/bacteria/ml"
for f in siamcat_metrics.tsv siamcat_auc_summary.tsv; do
    if [ ! -s "${ML_DIR}/${f}" ]; then
        echo "[FAIL] Expected output missing: ${ML_DIR}/${f}"
        exit 1
    fi
done

echo "[INFO] Asserting name-aligned panel metrics against rds recomputation..."
conda run --prefix "${REPO_ROOT}/envs/r_stat" --no-capture-output \
    Rscript - "${ML_DIR}" <<'RHARNESS'
options(stringsAsFactors = FALSE, warn = 1)
options(device = function(...) grDevices::pdf(
  file = file.path(tempdir(), paste0("Rplots_", Sys.getpid(), ".pdf")), ...))
conda_r_lib <- file.path(R.home("home"), "library")
if (dir.exists(conda_r_lib)) .libPaths(unique(c(conda_r_lib, .libPaths())))
suppressPackageStartupMessages({ library(SIAMCAT); library(PRROC) })

ml_dir <- commandArgs(trailingOnly = TRUE)[1]
tsv <- read.delim(file.path(ml_dir, "siamcat_metrics.tsv"), check.names = FALSE)

fail <- function(...) { cat("[FAIL]", ..., "\n"); quit(save = "no", status = 1) }
if (nrow(tsv) == 0) fail("siamcat_metrics.tsv has no model rows")

if (!identical("sample_id", unique(tsv$aligned_by))) {
  fail("aligned_by column missing or wrong: ", paste(unique(tsv$aligned_by), collapse = ","))
}

get_pred <- function(nm) {
  fp <- file.path(ml_dir, paste0("siamcat_", nm, ".rds"))
  if (!file.exists(fp)) return(NULL)
  sc <- tryCatch(readRDS(fp), error = function(e) NULL)
  if (is.null(sc)) return(NULL)
  p <- tryCatch(SIAMCAT::pred_matrix(sc), error = function(e) NULL)
  if (is.null(p) || nrow(p) == 0) return(NULL)
  p
}

n_discriminating <- 0L
for (k in seq_len(nrow(tsv))) {
  nm <- as.character(tsv$model[k])
  p <- get_pred(nm)
  if (is.null(p)) fail("no readable pred_matrix for model ", nm)
  sc <- readRDS(file.path(ml_dir, paste0("siamcat_", nm, ".rds")))
  lbl_obj <- SIAMCAT::label(sc)

  # FIXED code semantics: name-aligned labels (W-C1(1))
  lab_vec <- lbl_obj$label
  ids <- sort(intersect(rownames(p), names(lab_vec)))
  if (length(ids) == 0) fail("empty name intersection for model ", nm)
  y <- as.integer(lab_vec[ids] == 1)
  scores <- p[ids, 1]
  pc <- ifelse(scores >= 0.5, 1L, 0L)
  tp <- sum(pc == 1 & y == 1); fn <- sum(pc == 0 & y == 1)
  fp <- sum(pc == 1 & y == 0); tn <- sum(pc == 0 & y == 0)
  aligned <- list(
    auc_pr = as.numeric(PRROC::pr.curve(scores.class0 = scores, weights.class0 = y)$auc.integral),
    sens = if (tp + fn > 0) tp / (tp + fn) else NA_real_,
    spec = if (tn + fp > 0) tn / (tn + fp) else NA_real_)

  # KNOWN-BAD old code semantics (A6): pseudo-labels from deparse + recycling
  y_old <- as.integer(as.character(lbl_obj) == names(table(as.character(lbl_obj)))[2])
  y_old <- rep(y_old, length.out = nrow(p))
  pc_old <- ifelse(p[, 1] >= 0.5, 1L, 0L)
  tp <- sum(pc_old == 1 & y_old == 1); fn <- sum(pc_old == 0 & y_old == 1)
  fp <- sum(pc_old == 1 & y_old == 0); tn <- sum(pc_old == 0 & y_old == 0)
  old <- list(
    sens = if (tp + fn > 0) tp / (tp + fn) else NA_real_,
    spec = if (tn + fp > 0) tn / (tn + fp) else NA_real_)

  if (!isTRUE(all.equal(tsv$auc_pr[k], aligned$auc_pr, tolerance = 1e-9)) ||
      !isTRUE(all.equal(tsv$sensitivity[k], aligned$sens, tolerance = 1e-9)) ||
      !isTRUE(all.equal(tsv$specificity[k], aligned$spec, tolerance = 1e-9)) ||
      !identical(as.integer(tsv$n_predictions[k]), length(ids))) {
    fail(sprintf("model %s: TSV metrics do not match name-aligned recomputation (tsv auc_pr=%s sens=%s spec=%s n=%s vs aligned auc_pr=%s sens=%s spec=%s n=%d)",
                 nm, tsv$auc_pr[k], tsv$sensitivity[k], tsv$specificity[k], tsv$n_predictions[k],
                 aligned$auc_pr, aligned$sens, aligned$spec, length(ids)))
  }
  # Ground-truth assertion (supervisor P1-1): the aligned label vector must equal
  # the fixture's true labels by name-prefix rule (H* -> control/0, D* -> case/1),
  # independent of the production alignment code (breaks the self-confirming loop).
  truth <- ifelse(startsWith(ids, "H"), 1L, 0L)  # case = levels()[2] = H
  if (!identical(as.integer(y), truth)) {
    fail(sprintf("model %s: aligned labels do not match ground truth by name prefix (got %s vs truth %s)",
                 nm, paste(y, collapse = ""), paste(truth, collapse = "")))
  }
  if (!isTRUE(all.equal(old$sens, aligned$sens)) || !isTRUE(all.equal(old$spec, aligned$spec))) {
    n_discriminating <- n_discriminating + 1L
  }
  cat(sprintf("[OK] %-13s auc_pr=%.4f sens=%.4f spec=%.4f n=%d (name-aligned; matches TSV)\n",
              nm, aligned$auc_pr, aligned$sens, aligned$spec, length(ids)))
}

if (n_discriminating == 0L) {
  fail("fixture lost discriminating power: old pseudo-label metrics equal aligned metrics for every model - the anti-regression assertion cannot fire")
}
cat(sprintf("[OK] %d/%d model row(s) discriminate old-vs-aligned; TSV matches aligned everywhere\n",
            n_discriminating, nrow(tsv)))
RHARNESS

echo "[PASS] 96 label alignment regression: metrics are name-aligned (pseudo-label pattern absent)"
