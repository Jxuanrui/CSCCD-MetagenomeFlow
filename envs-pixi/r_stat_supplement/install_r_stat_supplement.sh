#!/usr/bin/env bash
# =============================================================================
# install_r_stat_supplement.sh
# AUTO-GENERATED from envs/r_stat live state on 2026-10-03 (pixi adoption P1-2).
# Source of truth: DESCRIPTION metadata of every directory under
#   envs/r_stat/lib/R/library/ + cross-check vs envs/r_stat/conda-meta/*.json.
#
# PURPOSE: install the 180 non-conda R packages that exist in the live env but
#   are installed by NEITHER the conda layer NOR envs/install_r_stat.sh.
#
# RUN ORDER (strict):
#   1. pixi install                    (conda layer, from pixi.lock)
#   2. bash envs/install_r_stat.sh     (original script: BiocManager 4 pkgs + GitHub 3)
#   3. bash install_r_stat_supplement.sh <prefix>   <-- THIS SCRIPT
#
# This script does NOT install (or touch) any conda-managed package; the 180
# entries below were each verified absent from conda-meta (r-*/bioconductor-*
# name matching). 14 further dirs (base/compiler/datasets/... ) ship with
# r-base 4.4.3 itself and need nothing.
#
# Install order = topological layers L0..L6 of Depends/Imports/LinkingTo edges
# among the 180 packages themselves (202 edges, no cycles): dependencies first.
#
# Pins: CRAN -> remotes::install_version (exact version; CRAN Archive fallback)
#       GitHub -> install_github @ commit SHA (content-level pin)
#       Bioconductor -> BiocManager 3.20 frozen repo (12/13 exact) + 1 exception
# ==============================================================================
set -euo pipefail
PREFIX="${1:?usage: install_r_stat_supplement.sh <r_stat-env-prefix>}"; shift || true
echo "[supplement] target prefix: ${PREFIX}"
if [ ! -x "${PREFIX}/bin/Rscript" ]; then echo "[supplement] ERROR: ${PREFIX}/bin/Rscript not found (run pixi install first)" >&2; exit 1; fi
# R_LIBS_USER must stay unset: Rlib/ is an unrelated R-4.5 layer (P0-2 lesson)
env -u R_LIBS_USER "${PREFIX}/bin/Rscript" --vanilla - <<'RSCRIPT'

## ---- guards & helpers -------------------------------------------------------
if (!requireNamespace("BiocManager", quietly = TRUE))
  stop("BiocManager missing: conda layer / install_r_stat.sh not run yet")
if (getRversion() < "4.4.0" || getRversion() >= "4.5.0")
  stop(sprintf("R %s found; this env was built on R 4.4.x", getRversion()))
if (!requireNamespace("remotes", quietly = TRUE) || packageVersion("remotes") != "2.5.0")
  install.packages("remotes", repos = c(CRAN = "https://cloud.r-project.org"))
.norm <- function(v) gsub("-", ".", as.character(v))
.have <- function(pkg, ver)
  requireNamespace(pkg, quietly = TRUE) &&
    identical(.norm(packageVersion(pkg)), .norm(ver))
ins_ver <- function(pkg, ver) {
  if (.have(pkg, ver)) { message(sprintf("  [skip]  %-22s %s", pkg, ver)); return(invisible(NULL)) }
  message(sprintf("  [cran]  %-22s == %s", pkg, ver))
  remotes::install_version(pkg, version = ver,
    repos = c(CRAN = "https://cloud.r-project.org"),
    upgrade = "never", dependencies = FALSE)
}
ins_gh <- function(repo_ref, pkg, ver) {
  if (.have(pkg, ver)) { message(sprintf("  [skip]  %-22s %s", pkg, ver)); return(invisible(NULL)) }
  message(sprintf("  [gh]    %-22s %s @ %s", pkg, ver, repo_ref))
  remotes::install_github(repo_ref, dependencies = FALSE, upgrade = "never", force = TRUE)
}
ins_bioc <- function(pkg, ver) {
  if (.have(pkg, ver)) { message(sprintf("  [skip]  %-22s %s", pkg, ver)); return(invisible(NULL)) }
  message(sprintf("  [bioc]  %-22s %s", pkg, ver))
  BiocManager::install(pkg, ask = FALSE, update = FALSE, force = TRUE)
}
options(repos = c(CRAN = "https://cloud.r-project.org"))
# Bioconductor 3.20 frozen repos (matches live env; BiocManager itself is conda-managed 1.30.27)
BiocManager::install(version = "3.20", ask = FALSE, update = FALSE)

## ---- topologically ordered installs (L0 -> L6) ------------------------------
## L0 (106 pkgs)
ins_ver("BWStest", "0.2.3")
ins_ver("CompQuadForm", "1.4.4")
ins_bioc("DESeq2", "1.46.0")
ins_bioc("GO.db", "3.20.0")
ins_ver("GPArotation", "2026.4-1")  # current CRAN differs: archive fallback
ins_ver("LaplacesDemon", "16.1.8")
ins_ver("Metrics", "0.1.4")
ins_ver("SuppDists", "1.1-9.9")
ins_ver("TMB", "1.9.21")  # current CRAN differs: archive fallback
ins_ver("TSP", "1.2.7")
ins_bioc("Wrench", "1.24.0")
ins_ver("afex", "1.5-1")
ins_ver("biglm", "0.9-3")
ins_ver("bitops", "1.0-9")  # current CRAN differs: archive fallback
ins_ver("bookdown", "0.46")  # current CRAN differs: archive fallback
ins_ver("brio", "1.1.5")
ins_ver("ca", "0.71.1")  # current CRAN differs: archive fallback
ins_ver("cccd", "1.6")
ins_ver("coda", "0.19-4.1")
ins_ver("collapse", "2.1.7")  # current CRAN differs: archive fallback
ins_ver("contfrac", "1.1-12")
ins_ver("corpcor", "1.6.10")
ins_ver("cqrReg", "1.2.1")
ins_ver("crosstalk", "1.2.2")
ins_ver("cubature", "2.1.4-1")
ins_ver("deSolve", "1.42")
ins_ver("dendextend", "1.19.1")
ins_ver("desc", "1.4.3")
ins_ver("diffobj", "0.3.6")  # current CRAN differs: archive fallback
ins_ver("diptest", "0.77-2")
ins_ver("dirmult", "0.1.3-5")
ins_ver("doFuture", "1.2.2")  # current CRAN differs: archive fallback
ins_ver("doSNOW", "1.0.20")
ins_ver("dynamicTreeCut", "1.63-1")
ins_ver("egg", "0.4.5")
ins_ver("elliptic", "1.5-1")
ins_ver("fastDummies", "1.7.6")
ins_ver("fastcluster", "1.3.0")
ins_ver("fdrtool", "1.2.18")
ins_ver("filematrix", "1.3")
ins_ver("forestplot", "3.2.0")
ins_ver("furrr", "0.4.0")
ins_ver("gclus", "1.3.3")
ins_ver("ggcorrplot", "0.1.4.1")  # current CRAN differs: archive fallback
ins_ver("ggh4x", "0.3.1")
ins_gh("erocoar/gghalves@0ba901f0f93485112ca2d1307211ed2ce6133324", "gghalves", "0.1.3")
ins_ver("ggpp", "0.6.0")  # current CRAN differs: archive fallback
ins_ver("ggside", "0.4.1")
ins_ver("ggstar", "1.0.6")
ins_ver("ggstats", "0.13.0")  # current CRAN differs: archive fallback
ins_ver("ggtangle", "0.1.2")  # current CRAN differs: archive fallback
ins_gh("YuLab-SMU/ggtreeExtra@b353b67109d84f344f63b5607567357a5c1a58e2", "ggtreeExtra", "1.23.1")
ins_ver("glasso", "1.11")
ins_ver("gridBezier", "1.1-1")
ins_ver("gridSVG", "1.7-7")
ins_ver("gson", "0.2.0")  # current CRAN differs: archive fallback
ins_ver("hash", "2.2.6.4")
ins_ver("iBreakDown", "2.1.2")
ins_bioc("impute", "1.80.0")
ins_ver("indicspecies", "1.8.0")
ins_ver("ingredients", "2.3.0")
ins_ver("inline", "0.3.21")
ins_ver("insight", "1.5.1")  # current CRAN differs: archive fallback
ins_ver("kernlab", "0.9-33")
ins_ver("lars", "1.3")
ins_ver("libcoin", "1.0-13")
ins_ver("linprog", "0.9-6")
ins_ver("logging", "0.10-111")
ins_ver("magic", "1.6-1")  # current CRAN differs: archive fallback
ins_ver("mathjaxr", "2.0-0")
ins_ver("mclust", "6.1.2")  # current CRAN differs: archive fallback
ins_ver("metabook", "0.2-0")
ins_ver("microeco", "2.2.0")  # current CRAN differs: archive fallback
ins_ver("miniUI", "0.1.2")
ins_ver("mlr3filters", "0.9.1")
ins_ver("mlr3pipelines", "0.11.0")  # current CRAN differs: archive fallback
ins_ver("mlr3viz", "0.11.0")  # current CRAN differs: archive fallback
ins_ver("mnormt", "2.1.2")
ins_ver("modeltools", "0.2-24")  # current CRAN differs: archive fallback
ins_ver("multcompView", "0.1-11")  # current CRAN differs: archive fallback
ins_ver("orca", "1.1-3")
ins_ver("packcircles", "0.3.7")
ins_ver("pbapply", "1.7-4")  # current CRAN differs: archive fallback
ins_ver("pbivnorm", "0.6.0")
ins_ver("pcaPP", "2.0-5")
ins_ver("pcutils", "0.2.8")
ins_ver("pls", "2.9-0")
ins_ver("ppcor", "1.1")
ins_ver("praise", "1.0.0")
ins_bioc("preprocessCore", "1.68.0")
ins_ver("prismatic", "1.1.2")
ins_ver("pscl", "1.5.9")
ins_ver("qap", "0.1-2")  # current CRAN differs: archive fallback
ins_bioc("qvalue", "2.38.0")
ins_ver("remotes", "2.5.0")
ins_ver("reshape", "0.8.10")
ins_ver("rprojroot", "2.1.1")
ins_ver("ruv", "0.9.7.1")  # current CRAN differs: archive fallback
ins_ver("scatterpie", "0.2.6")
ins_ver("shades", "1.5.0")
ins_ver("shinyjs", "2.1.1")
ins_ver("som", "0.3-5.2")
ins_ver("svglite", "2.2.2")
ins_ver("tweedie", "3.1.0")
ins_ver("webshot", "0.5.5")
ins_ver("xgboost", "3.2.1.1")

## L1 (37 pkgs)
ins_gh("Bioconductor/BiocStyle@RELEASE_3_18", "BiocStyle", "2.30.0")  # exception: Bioc 3.18 version
ins_ver("GGally", "2.4.0")
ins_ver("GUniFrac", "1.9")
ins_bioc("MBECS", "1.10.0")
ins_ver("MetaNet", "0.3.2")
ins_ver("WGCNA", "1.74")
ins_ver("WRS2", "1.1-7")
ins_ver("caTools", "1.18.3")  # current CRAN differs: archive fallback
ins_ver("chemometrics", "1.4.4")
ins_ver("coin", "1.4-3")  # current CRAN differs: archive fallback
ins_ver("colourpicker", "1.3.0")
ins_ver("cplm", "0.7-12.1")
ins_ver("datawizard", "1.3.1")  # current CRAN differs: archive fallback
ins_ver("file2meco", "0.9.1")
ins_ver("flexmix", "2.3-20")  # current CRAN differs: archive fallback
ins_ver("geometry", "0.5.2")
ins_ver("ggfittext", "0.10.4")
ins_ver("glmmTMB", "1.1.14")  # current CRAN differs: archive fallback
ins_ver("hypergeo", "1.2-14")
ins_ver("iml", "0.11.4")
ins_ver("kSamples", "1.2-12")
ins_ver("kernelshap", "0.9.1")
ins_ver("lavaan", "0.6-21")  # current CRAN differs: archive fallback
ins_gh("biobakery/Maaslin3@3a194ece449ef249354df394b58bfe3e6f951ca3", "maaslin3", "1.5.3")
ins_ver("metadat", "1.6-0")
ins_ver("paletteer", "1.7.0")
ins_ver("pkgbuild", "1.4.8")
ins_ver("plotROC", "2.3.3")
ins_ver("plotly", "4.12.0")  # current CRAN differs: archive fallback
ins_ver("prabclus", "2.3-5")
ins_ver("psych", "2.6.5")  # current CRAN differs: archive fallback
ins_ver("rstantools", "2.6.0")  # current CRAN differs: archive fallback
ins_ver("seriation", "1.5.8")
ins_ver("sn", "2.1.3")
ins_ver("statnet.common", "4.13.0")
ins_ver("vwline", "0.2-4")
ins_ver("waldo", "0.6.2")

## L2 (16 pkgs)
ins_ver("BayesFactor", "0.9.12-4.8")
ins_ver("DALEX", "2.5.3")  # current CRAN differs: archive fallback
ins_bioc("MicrobiotaProcess", "1.18.0")
ins_ver("PMCMRplus", "1.9.12")
ins_ver("bayestestR", "0.18.1")  # current CRAN differs: archive fallback
ins_ver("fMultivar", "4031.84")
ins_ver("fpc", "2.2-14")  # current CRAN differs: archive fallback
ins_ver("ggExtra", "0.11.0")
ins_ver("gggenes", "0.7.0")
ins_ver("ggsankeyfier", "0.1.8")
ins_ver("gplots", "3.3.0")
ins_ver("heatmaply", "1.6.0")
ins_ver("metafor", "5.0-1")  # current CRAN differs: archive fallback
ins_ver("network", "1.20.0")
ins_ver("pkgload", "1.5.2")  # current CRAN differs: archive fallback
ins_ver("qgraph", "1.9.8")  # current CRAN differs: archive fallback

## L3 (9 pkgs)
ins_ver("ROCR", "1.0-12")
ins_ver("latentcor", "2.0.2")
ins_ver("meta", "8.5-0")
ins_bioc("metagenomeSeq", "1.48.1")
ins_ver("parameters", "0.29.1")  # current CRAN differs: archive fallback
ins_ver("performance", "0.17.0")  # current CRAN differs: archive fallback
ins_ver("shapviz", "0.10.3")  # current CRAN differs: archive fallback
ins_ver("sna", "2.8")
ins_ver("testthat", "3.3.2")

## L4 (8 pkgs)
ins_gh("wdl2459/ConQuR@c7a88794efd4ecfe4d96988dceeec3b410222e48", "ConQuR", "2.0")
ins_bioc("Maaslin2", "1.20.0")
ins_gh("IrinaStatsLab/SPRING@11ddf3597a6c5d24a55395ef28b8215192491dce", "SPRING", "0.99.0")
ins_ver("correlation", "0.8.8")
ins_ver("effectsize", "1.0.2")  # current CRAN differs: archive fallback
ins_gh("taowenmicro/ggClusterNet@a70510f9f1d7f896dddfce57f8217bb8de59cf72", "ggClusterNet", "2.00")
ins_bioc("microbiomeMarker", "1.12.2")
ins_ver("mixedCCA", "1.6.3")

## L5 (3 pkgs)
ins_bioc("MMUPHin", "1.20.0")
ins_gh("stefpeschel/NetCoMi@d891a81c6c4a63dfeaac17875eb4b81e6b600017", "NetCoMi", "1.1.0")
ins_ver("statsExpressions", "2.0.0")  # current CRAN differs: archive fallback

## L6 (1 pkgs)
ins_ver("ggstatsplot", "1.0.0")  # current CRAN differs: archive fallback

## ---- verification: name/version must match the live env exactly --------------
expected <- c(
  "BWStest"="0.2.3",
  "BayesFactor"="0.9.12-4.8",
  "BiocStyle"="2.30.0",
  "CompQuadForm"="1.4.4",
  "ConQuR"="2.0",
  "DALEX"="2.5.3",
  "DESeq2"="1.46.0",
  "GGally"="2.4.0",
  "GO.db"="3.20.0",
  "GPArotation"="2026.4-1",
  "GUniFrac"="1.9",
  "LaplacesDemon"="16.1.8",
  "MBECS"="1.10.0",
  "MMUPHin"="1.20.0",
  "Maaslin2"="1.20.0",
  "MetaNet"="0.3.2",
  "Metrics"="0.1.4",
  "MicrobiotaProcess"="1.18.0",
  "NetCoMi"="1.1.0",
  "PMCMRplus"="1.9.12",
  "ROCR"="1.0-12",
  "SPRING"="0.99.0",
  "SuppDists"="1.1-9.9",
  "TMB"="1.9.21",
  "TSP"="1.2.7",
  "WGCNA"="1.74",
  "WRS2"="1.1-7",
  "Wrench"="1.24.0",
  "afex"="1.5-1",
  "bayestestR"="0.18.1",
  "biglm"="0.9-3",
  "bitops"="1.0-9",
  "bookdown"="0.46",
  "brio"="1.1.5",
  "ca"="0.71.1",
  "caTools"="1.18.3",
  "cccd"="1.6",
  "chemometrics"="1.4.4",
  "coda"="0.19-4.1",
  "coin"="1.4-3",
  "collapse"="2.1.7",
  "colourpicker"="1.3.0",
  "contfrac"="1.1-12",
  "corpcor"="1.6.10",
  "correlation"="0.8.8",
  "cplm"="0.7-12.1",
  "cqrReg"="1.2.1",
  "crosstalk"="1.2.2",
  "cubature"="2.1.4-1",
  "datawizard"="1.3.1",
  "deSolve"="1.42",
  "dendextend"="1.19.1",
  "desc"="1.4.3",
  "diffobj"="0.3.6",
  "diptest"="0.77-2",
  "dirmult"="0.1.3-5",
  "doFuture"="1.2.2",
  "doSNOW"="1.0.20",
  "dynamicTreeCut"="1.63-1",
  "effectsize"="1.0.2",
  "egg"="0.4.5",
  "elliptic"="1.5-1",
  "fMultivar"="4031.84",
  "fastDummies"="1.7.6",
  "fastcluster"="1.3.0",
  "fdrtool"="1.2.18",
  "file2meco"="0.9.1",
  "filematrix"="1.3",
  "flexmix"="2.3-20",
  "forestplot"="3.2.0",
  "fpc"="2.2-14",
  "furrr"="0.4.0",
  "gclus"="1.3.3",
  "geometry"="0.5.2",
  "ggClusterNet"="2.00",
  "ggExtra"="0.11.0",
  "ggcorrplot"="0.1.4.1",
  "ggfittext"="0.10.4",
  "gggenes"="0.7.0",
  "ggh4x"="0.3.1",
  "gghalves"="0.1.3",
  "ggpp"="0.6.0",
  "ggsankeyfier"="0.1.8",
  "ggside"="0.4.1",
  "ggstar"="1.0.6",
  "ggstats"="0.13.0",
  "ggstatsplot"="1.0.0",
  "ggtangle"="0.1.2",
  "ggtreeExtra"="1.23.1",
  "glasso"="1.11",
  "glmmTMB"="1.1.14",
  "gplots"="3.3.0",
  "gridBezier"="1.1-1",
  "gridSVG"="1.7-7",
  "gson"="0.2.0",
  "hash"="2.2.6.4",
  "heatmaply"="1.6.0",
  "hypergeo"="1.2-14",
  "iBreakDown"="2.1.2",
  "iml"="0.11.4",
  "impute"="1.80.0",
  "indicspecies"="1.8.0",
  "ingredients"="2.3.0",
  "inline"="0.3.21",
  "insight"="1.5.1",
  "kSamples"="1.2-12",
  "kernelshap"="0.9.1",
  "kernlab"="0.9-33",
  "lars"="1.3",
  "latentcor"="2.0.2",
  "lavaan"="0.6-21",
  "libcoin"="1.0-13",
  "linprog"="0.9-6",
  "logging"="0.10-111",
  "maaslin3"="1.5.3",
  "magic"="1.6-1",
  "mathjaxr"="2.0-0",
  "mclust"="6.1.2",
  "meta"="8.5-0",
  "metabook"="0.2-0",
  "metadat"="1.6-0",
  "metafor"="5.0-1",
  "metagenomeSeq"="1.48.1",
  "microbiomeMarker"="1.12.2",
  "microeco"="2.2.0",
  "miniUI"="0.1.2",
  "mixedCCA"="1.6.3",
  "mlr3filters"="0.9.1",
  "mlr3pipelines"="0.11.0",
  "mlr3viz"="0.11.0",
  "mnormt"="2.1.2",
  "modeltools"="0.2-24",
  "multcompView"="0.1-11",
  "network"="1.20.0",
  "orca"="1.1-3",
  "packcircles"="0.3.7",
  "paletteer"="1.7.0",
  "parameters"="0.29.1",
  "pbapply"="1.7-4",
  "pbivnorm"="0.6.0",
  "pcaPP"="2.0-5",
  "pcutils"="0.2.8",
  "performance"="0.17.0",
  "pkgbuild"="1.4.8",
  "pkgload"="1.5.2",
  "plotROC"="2.3.3",
  "plotly"="4.12.0",
  "pls"="2.9-0",
  "ppcor"="1.1",
  "prabclus"="2.3-5",
  "praise"="1.0.0",
  "preprocessCore"="1.68.0",
  "prismatic"="1.1.2",
  "pscl"="1.5.9",
  "psych"="2.6.5",
  "qap"="0.1-2",
  "qgraph"="1.9.8",
  "qvalue"="2.38.0",
  "remotes"="2.5.0",
  "reshape"="0.8.10",
  "rprojroot"="2.1.1",
  "rstantools"="2.6.0",
  "ruv"="0.9.7.1",
  "scatterpie"="0.2.6",
  "seriation"="1.5.8",
  "shades"="1.5.0",
  "shapviz"="0.10.3",
  "shinyjs"="2.1.1",
  "sn"="2.1.3",
  "sna"="2.8",
  "som"="0.3-5.2",
  "statnet.common"="4.13.0",
  "statsExpressions"="2.0.0",
  "svglite"="2.2.2",
  "testthat"="3.3.2",
  "tweedie"="3.1.0",
  "vwline"="0.2-4",
  "waldo"="0.6.2",
  "webshot"="0.5.5",
  "xgboost"="3.2.1.1"
)
bad <- character(0); missing <- character(0)
for (p in names(expected)) {
  v <- tryCatch({
    suppressPackageStartupMessages(library(p, character.only = TRUE))
    as.character(packageVersion(p))
  }, error = function(e) NA_character_)
  if (is.na(v)) {
    missing <- c(missing, p)
    cat(sprintf("  MISSING   %-24s expected %s\n", p, expected[[p]]))
  } else if (!identical(.norm(v), .norm(expected[[p]]))) {
    bad <- c(bad, p)
    cat(sprintf("  MISMATCH  %-24s got %s, expected %s\n", p, v, expected[[p]]))
  } else {
    cat(sprintf("  ok        %-24s %s\n", p, v))
  }
}
cat(sprintf("\n[supplement] %d/%d exact; %d mismatched; %d missing\n",
  length(expected) - length(bad) - length(missing), length(expected),
  length(bad), length(missing)))
if (length(bad) + length(missing) > 0) quit(status = 1)
message("[supplement] all 180 non-conda packages verified.")
RSCRIPT
