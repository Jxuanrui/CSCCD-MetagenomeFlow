#!/usr/bin/env bash
# ==============================================================================
# Script: run_functional_analysis.sh
# Purpose: One-shot runner for the full 96_stat_functional pipeline (20
#          dimension x func_type pairs) plus the three downstream summary
#          steps (permanova / integrated / cross_dimension), mirroring the
#          Snakemake wiring in pipeline/rules/statistics.smk without needing
#          Snakemake itself. Useful for manual re-runs or debugging a single
#          layer without invoking the full pipeline DAG.
#
# Usage:   bash run_functional_analysis.sh -w WORKDIR -r REPO [-m METADATA_CSV]
#                                          [-g GROUP_COL] [-c CPUS] [-p PARALLEL] [--force]
# ==============================================================================
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash run_functional_analysis.sh -w WORKDIR -r REPO [-m METADATA_CSV]
                                       [-g GROUP_COL] [-c CPUS] [-p PARALLEL] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV (default: WORKDIR/metadata.csv)
  -g  Group column (default: group)
  -c  CPUs passed to 96_functional_integrated.sh (default: 4)
  -p  Parallel pair count for the 20-pair functional analysis batch (default: 6)
  --force  Re-run even if sentinels exist
  -h, --help  Show this help message
EOF
}

METADATA_CSV=""
GROUP_COL="group"
CPUS="4"
PARALLEL="6"
FORCE_FLAG=""

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV g:GROUP_COL c:CPUS p:PARALLEL"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO
[ ${FORCE} -eq 1 ] && FORCE_FLAG="--force"

WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"
METADATA_CSV="${METADATA_CSV:-${WORKDIR}/metadata.csv}"
METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Repo: ${REPO}"
echo "[INFO] Metadata: ${METADATA_CSV}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Parallel pairs: ${PARALLEL}"

mgx_begin

# ---- Stage 1: 20 dimension x func_type pairs -------------------------------
# maaslin3's mirai/nanonext-based internal parallelization (cores>1) is
# unreliable at this feature scale (see scripts/96_stat_functional.R comment
# and docs/visualization_workflow_specification.md); every pair now runs
# maaslin_cores=1 internally, so pair-level concurrency here is safe and is
# where all the speedup comes from.
run_pair() {
    local dimension="${1%%:*}"
    local func_type="${1#*:}"
    bash "${REPO}/scripts/96_stat_functional.sh" \
        -w "${WORKDIR}" -r "${REPO}" -m "${METADATA_CSV}" \
        -d "${dimension}" -t "${func_type}" ${FORCE_FLAG}
}
export -f run_pair
export WORKDIR REPO METADATA_CSV FORCE_FLAG

echo "[INFO] === Stage 1/4: functional differential analysis (20 pairs) ==="
printf '%s\n' \
    bacteria:pathway bacteria:cog bacteria:cazyme bacteria:arg bacteria:vfdb bacteria:defense bacteria:ncyc bacteria:pcyc bacteria:kegg_ko \
    fungi:cog fungi:cazyme fungi:vfdb fungi:amr fungi:merops fungi:kegg_ko \
    virus:phrog virus:vog virus:lifestyle virus:host_genus virus:viral_family \
    | xargs -P "${PARALLEL}" -I{} bash -c 'run_pair "$1"' _ {}

# ---- Stage 2: per-dimension PERMANOVA ---------------------------------------
echo "[INFO] === Stage 2/4: functional PERMANOVA ==="
bash "${REPO}/scripts/96_functional_permanova.sh" \
    -w "${WORKDIR}" -r "${REPO}" -m "${METADATA_CSV}" -g "${GROUP_COL}"

# ---- Stage 3: per-dimension integrated summaries ----------------------------
echo "[INFO] === Stage 3/4: per-dimension integrated summaries ==="
for dimension in bacteria fungi virus; do
    bash "${REPO}/scripts/96_functional_integrated.sh" \
        -w "${WORKDIR}" -r "${REPO}" -m "${METADATA_CSV}" \
        -g "${GROUP_COL}" -d "${dimension}" -c "${CPUS}"
done

# ---- Stage 4: cross-dimension comparison ------------------------------------
echo "[INFO] === Stage 4/4: cross-dimension comparison ==="
bash "${REPO}/scripts/96_functional_cross_dimension.sh" \
    -w "${WORKDIR}" -r "${REPO}"

echo "[INFO] All functional analyses completed in ${SECONDS}s"
