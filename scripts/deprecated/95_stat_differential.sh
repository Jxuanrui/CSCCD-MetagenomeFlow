# Deprecated 2026-07-16: superseded by 92_stat_differential.sh (this is an earlier iteration, dated 2026-07-06/07). The --demo regression-test capability is not present in 92 and may be worth porting separately.
#!/usr/bin/env bash
# ==============================================================================
# Script: 95_stat_differential.sh
# Purpose: Differential abundance analysis across bacteria, virus, and fungi
# Methods: DESeq2 (primary), LEfSe (secondary), Wilcoxon (quick filter)
# Usage:   bash 95_stat_differential.sh -w WORKDIR -r REPO [-m METADATA_CSV] [--force] [--demo]
# ==============================================================================

show_help() {
cat <<'EOF'
Usage: bash 95_stat_differential.sh -w WORKDIR -r REPO [-m METADATA_CSV] [--force] [--demo]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -m  Metadata CSV
  --force  Re-run even if sentinel exists
  --demo   Run on synthetic regression-test data (result/stat/demo/), not real samples
  -h, --help  Show this help message
EOF
}

WORKDIR=""
REPO=""
METADATA_CSV=""
FORCE=0
RUN_DEMO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -m) METADATA_CSV="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --demo) RUN_DEMO=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] Missing required arguments"
    show_help
    exit 1
fi

# Ensure absolute paths
WORKDIR="$(cd "${WORKDIR}" && pwd)"
[ -n "${METADATA_CSV}" ] && METADATA_CSV="$(cd "$(dirname "${METADATA_CSV}")" && pwd)/$(basename "${METADATA_CSV}")"

SECONDS=0

GROUP_COL="${GROUP_COL:-group}"
STAT_ROOT="${WORKDIR}/result/stat"
LOG_DIR="${WORKDIR}/logs/stat/differential"
SENTINEL="${STAT_ROOT}/differential_done.txt"
if [ ${RUN_DEMO} -eq 1 ]; then
    SENTINEL="${STAT_ROOT}/demo/differential_done.txt"
fi

mkdir -p "${STAT_ROOT}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/95_stat_differential.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ -n "${METADATA_CSV}" ] && [ ! -f "${METADATA_CSV}" ]; then
    echo "[ERROR] Metadata CSV not found: ${METADATA_CSV}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"
    echo "  Sentinel: ${SENTINEL}"
    echo "[INFO] Use --force to re-run"
    exit 0
fi

echo "[INFO] Running differential abundance analysis"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Metadata: ${METADATA_CSV:-<none>}"
echo "[INFO] Group column: ${GROUP_COL}"
echo "[INFO] Stat root: ${STAT_ROOT}"
[ ${RUN_DEMO} -eq 1 ] && echo "[INFO] Mode: DEMO (synthetic regression-test data)"

export WORKDIR REPO METADATA_CSV GROUP_COL STAT_ROOT FORCE SENTINEL RUN_DEMO

(cd "${WORKDIR}" && conda run --prefix "${REPO}/envs/r_stat" --no-capture-output Rscript "${REPO}/scripts/95_differential.R")

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 95_stat_differential.sh failed with exit code ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

if [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] Expected sentinel not generated: ${SENTINEL}"
    exit 1
fi

echo "[INFO] Differential analysis completed in ${SECONDS}s"
echo "[INFO] Sentinel: ${SENTINEL}"
