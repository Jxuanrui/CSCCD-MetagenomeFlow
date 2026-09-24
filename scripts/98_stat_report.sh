#!/usr/bin/env bash
# ==============================================================================
# Script: 98_stat_report.sh
# Purpose: Generate a markdown snapshot report from result/stat outputs
# Usage:   bash 98_stat_report.sh -w WORKDIR -r REPO [-o OUTPUT_DIR] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 98_stat_report.sh -w WORKDIR -r REPO [-o OUTPUT_DIR] [--force]

Required:
  -w  Project work directory
  -r  Repository root

Optional:
  -o  Output directory (default: result/stat/report)
  --force  Re-run and create a fresh timestamped report
  -h, --help  Show this help message
EOF
}

OUTPUT_DIR=""

# MGX_* tables are consumed by mgx_parse (libcommon.sh)
export MGX_OPTS_STRING="w:WORKDIR r:REPO o:OUTPUT_DIR"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

# Ensure absolute paths so R sub-processes receive them correctly
WORKDIR="$(cd "${WORKDIR}" && pwd)"

mgx_begin

if [ -z "${OUTPUT_DIR}" ]; then
    OUTPUT_DIR="${WORKDIR}/result/stat/report"
fi

STAT_DIR="${WORKDIR}/result/stat"
LOG_DIR="${WORKDIR}/logs/stat/report"
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
REPORT_FILE="${OUTPUT_DIR}/report_${TIMESTAMP}.md"

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/98_stat_report.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

LATEST_REPORT="$(ls -1 "${OUTPUT_DIR}"/report_*.md 2>/dev/null | tail -n 1 || true)"
if [ ${FORCE} -eq 0 ] && [ -n "${LATEST_REPORT}" ] && [ -s "${LATEST_REPORT}" ]; then
    echo "[INFO] Existing report found; creating a new timestamped report anyway is only gated by --force in spirit, but report generation is non-destructive."
fi

echo "[INFO] Building markdown report"

relpath() {
    python3 - "$1" "$2" <<'PY'
import os, sys
print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
}

extract_table_preview() {
    local file="$1"
    local max_lines="${2:-5}"
    if [ -f "${file}" ]; then
        awk -v max_lines="${max_lines}" 'NR<=max_lines {print}' "${file}"
    fi
}

{
    echo "# CSCCD-MetagenomeFlow Statistical Snapshot"
    echo
    echo "- Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "- Workdir: ${WORKDIR}"
    echo "- Repo: ${REPO}"
    echo

    echo "## QC Summary"
    echo
    echo "- Statistical output root: \`${STAT_DIR}\`"
    echo "- Failed sentinels detected: $(find "${STAT_DIR}" -type f -name '*.FAILED' | wc -l | awk '{print $1}')"
    echo

    echo "## Diversity"
    echo
    if [ -f "${STAT_DIR}/diversity_alpha_summary.tsv" ]; then
        echo '```tsv'
        extract_table_preview "${STAT_DIR}/diversity_alpha_summary.tsv" 6
        echo '```'
    else
        echo "- Missing: \`result/stat/diversity_alpha_summary.tsv\`"
    fi
    echo

    echo "## Differential Abundance"
    echo
    if [ -f "${STAT_DIR}/differential_summary.tsv" ]; then
        echo '```tsv'
        extract_table_preview "${STAT_DIR}/differential_summary.tsv" 6
        echo '```'
    else
        echo "- Missing: \`result/stat/differential_summary.tsv\`"
    fi
    echo

    echo "## Networks"
    echo
    if [ -f "${STAT_DIR}/network/network_summary.tsv" ]; then
        echo '```tsv'
        extract_table_preview "${STAT_DIR}/network/network_summary.tsv" 6
        echo '```'
    elif [ -f "${STAT_DIR}/network/network_summary.txt" ]; then
        echo '```text'
        sed -n '1,20p' "${STAT_DIR}/network/network_summary.txt"
        echo '```'
    else
        echo "- Missing network summary outputs"
    fi
    echo

    echo "## Batch"
    echo
    if [ -f "${STAT_DIR}/bacteria/batch/evaluation_report.tsv" ]; then
        echo '```tsv'
        extract_table_preview "${STAT_DIR}/bacteria/batch/evaluation_report.tsv" 8
        echo '```'
    else
        echo "- Missing: \`result/stat/bacteria/batch/evaluation_report.tsv\`"
    fi
    echo

    echo "## ML"
    echo
    echo "<!-- Default preview shows bacteria ML. Virus/fungi ML live under their dimension ml/ folders; all-dimension ML lives under result/stat/ml/. -->"
    if [ -f "${STAT_DIR}/bacteria/ml/siamcat_auc_summary.tsv" ]; then
        echo '```tsv'
        extract_table_preview "${STAT_DIR}/bacteria/ml/siamcat_auc_summary.tsv" 8
        echo '```'
    elif [ -f "${STAT_DIR}/bacteria/ml/siamcat_done.txt" ]; then
        echo '```text'
        sed -n '1,20p' "${STAT_DIR}/bacteria/ml/siamcat_done.txt"
        echo '```'
    else
        echo "- Missing ML summary outputs"
    fi
    echo

    echo "## Cross-cohort"
    echo
    if [ -f "${WORKDIR}/result/viz_crosscohort/auc_summary.tsv" ]; then
        echo '```tsv'
        extract_table_preview "${WORKDIR}/result/viz_crosscohort/auc_summary.tsv" 8
        echo '```'
    elif [ -f "${WORKDIR}/result/viz_crosscohort/crosscohort_done.txt" ]; then
        echo '```text'
        sed -n '1,20p' "${WORKDIR}/result/viz_crosscohort/crosscohort_done.txt"
        echo '```'
    else
        echo "- Missing cross-cohort outputs"
    fi
    echo

    echo "## Figures"
    echo
    find "${STAT_DIR}" -type f \( -name '*.pdf' -o -name '*.png' -o -name '*.jpg' \) | sort | while read -r fig; do
        rel="$(relpath "${fig}" "${OUTPUT_DIR}")"
        echo "- ![](${rel})"
    done
    echo

    echo "## Warnings"
    echo
    FAILED_FILES="$(find "${STAT_DIR}" -type f -name '*.FAILED' | sort || true)"
    if [ -n "${FAILED_FILES}" ]; then
        while read -r ff; do
            [ -z "${ff}" ] && continue
            rel="$(relpath "${ff}" "${OUTPUT_DIR}")"
            echo "- ${rel}: $(head -n 1 "${ff}" 2>/dev/null)"
        done <<< "${FAILED_FILES}"
    else
        echo "- No .FAILED sentinels found"
    fi
} > "${REPORT_FILE}"

if [ ! -s "${REPORT_FILE}" ]; then
    echo "[ERROR] Report file was not generated: ${REPORT_FILE}"
    exit 1
fi

echo "[INFO] Report generated: ${REPORT_FILE}"
mgx_end "report"
