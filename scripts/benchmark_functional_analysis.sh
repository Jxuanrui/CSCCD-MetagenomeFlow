#!/usr/bin/env bash
# ==============================================================================
# Script: benchmark_functional_analysis.sh
# Purpose: Record wall-clock, CPU time, peak RSS, and disk I/O for each of the
#          20 dimension x func_type pairs in 96_stat_functional.sh, to quantify
#          the speedup from the Task 4.1 parallel-optimization fix (per-pair
#          maaslin_cores=1 + Snakemake-layer xargs -P N process parallelism).
# Usage:   bash benchmark_functional_analysis.sh -w WORKDIR -r REPO
#                                                [-m METADATA_CSV] [-o OUTPUT_DIR]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash benchmark_functional_analysis.sh -w WORKDIR -r REPO [-m METADATA_CSV] [-o OUTPUT_DIR]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV (default: WORKDIR/metadata.csv)
  -o  Output directory for logs + summary (default: WORKDIR/result/stat/benchmark)
  -h, --help  Show this help message

Notes:
  - Every pair is re-run with --force so the recorded time/memory reflect a
    real computation, not a sentinel-skip no-op.
  - Pairs run sequentially (not through the xargs -P N pool used in
    production) so /usr/bin/time -v measures each pair in isolation, without
    contention from sibling processes skewing CPU/memory numbers.
EOF
}

WORKDIR=""
REPO=""
METADATA_CSV=""
OUTPUT_DIR=""

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO m:METADATA_CSV o:OUTPUT_DIR"
mgx_parse "$@"
mgx_require WORKDIR REPO

WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"
METADATA_CSV="${METADATA_CSV:-${WORKDIR}/metadata.csv}"

if [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "[ERROR] /usr/bin/time not found; install the 'time' package (e.g. apt-get install time)"
    exit 1
fi

OUTPUT_DIR="${OUTPUT_DIR:-${WORKDIR}/result/stat/benchmark}"
LOG_DIR="${OUTPUT_DIR}/logs"
SUMMARY_TSV="${OUTPUT_DIR}/benchmark_summary.tsv"
mkdir -p "${LOG_DIR}"

echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Repo: ${REPO}"
echo "[INFO] Metadata: ${METADATA_CSV}"
echo "[INFO] Output: ${OUTPUT_DIR}"

PAIRS=(
    bacteria:pathway bacteria:cog bacteria:cazyme bacteria:arg bacteria:vfdb
    bacteria:defense bacteria:ncyc bacteria:pcyc bacteria:kegg_ko
    fungi:cog fungi:cazyme fungi:vfdb fungi:amr fungi:merops fungi:kegg_ko
    virus:phrog virus:vog virus:lifestyle virus:host_genus virus:viral_family
)

for pair in "${PAIRS[@]}"; do
    dimension="${pair%%:*}"
    func_type="${pair#*:}"
    log_file="${LOG_DIR}/benchmark_${dimension}_${func_type}.log"

    echo "[INFO] Benchmarking ${dimension}:${func_type}"
    exit_code=0
    mgx_try /usr/bin/time -v bash "${REPO}/scripts/96_stat_functional.sh" \
        -w "${WORKDIR}" -r "${REPO}" -m "${METADATA_CSV}" \
        -d "${dimension}" -t "${func_type}" --force \
        > "${log_file}" 2>&1 || exit_code=$?
    echo "  Exit code: ${exit_code} (log: ${log_file})"
done

echo "[INFO] Parsing benchmark logs into summary table"
python3 "${REPO}/scripts/parse_benchmark_logs.py" "${LOG_DIR}"/benchmark_*.log \
    > "${SUMMARY_TSV}"

echo "[INFO] Benchmark completed"
echo "[INFO] Summary: ${SUMMARY_TSV}"
