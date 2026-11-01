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
        # S-4: truncate cells >80 chars to 77 + ellipsis for readability
        awk -v max_lines="${max_lines}" 'NR<=max_lines {
            n=split($0, cells, "\t")
            for(i=1;i<=n;i++) { if(length(cells[i])>80) cells[i]=substr(cells[i],1,77)"..." }
            out=cells[1]; for(i=2;i<=n;i++) out=out"\t"cells[i]
            print out
        }' "${file}"
    fi
}

{
    echo "# CSCCD-MetagenomeFlow Statistical Snapshot"
    echo
    echo "- Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "- Workdir: ${WORKDIR}"
    echo "- Repo: ${REPO}"
    echo
    # M-1 (supervisor 19th): dynamic sample-size disclosure from metadata.csv
    META_CSV="${WORKDIR}/metadata.csv"
    if [ -f "${META_CSV}" ]; then
        N_TOTAL=$(awk -F',' 'NR>1 && NF>=2 {n++} END {print n+0}' "${META_CSV}" 2>/dev/null)
        GROUP_COL=$(head -1 "${META_CSV}" | tr ',' '\n' | grep -n "^group$\|^condition$" | head -1 | cut -d: -f1)
        if [ -n "${GROUP_COL}" ] && [ "${N_TOTAL}" -gt 0 ]; then
            N_GROUPS=$(awk -F',' -v col="${GROUP_COL}" 'NR>1 {print $col}' "${META_CSV}" | sort -u | wc -l)
            if [ "${N_GROUPS}" -eq 2 ]; then
                G1=$(awk -F',' -v col="${GROUP_COL}" 'NR>1 {print $col}' "${META_CSV}" | sort | uniq -c | head -1 | awk '{print $1}')
                G2=$((N_TOTAL - G1))
                echo "> **统计功效与口径披露（必读）**：本项目 n=${N_TOTAL}（${G1}v${G2}）——"
                echo "> 置换空间 C(${N_TOTAL},${G1}) 限制 p 值分辨率，组间结论请结合样本量评估；"
                echo "> 详见 \`docs/08_statistics/POWER_DISCLOSURE.md\`。"
            else
                echo "> **统计功效与口径披露（必读）**：本项目 n=${N_TOTAL}（${N_GROUPS} 组）——"
                echo "> 组间结论请结合样本量评估；详见 \`docs/08_statistics/POWER_DISCLOSURE.md\`。"
            fi
        fi
    else
        echo "> **统计功效披露**：未找到 metadata.csv，无法计算样本量；请参考 \`docs/08_statistics/POWER_DISCLOSURE.md\`。"
    fi
    echo
    echo

    echo "## QC Summary"
    echo
    echo "- Statistical output root: \`${STAT_DIR}\`"
    echo "- Failed sentinels detected: $(find "${STAT_DIR}" -type f -name '*.FAILED' | wc -l | awk '{print $1}')"
    echo

    echo "## Validation Coverage"
    echo
    echo "- Validation rules registered: $(grep -c '^    "' scripts/utils/validate_step.py || echo 0) step groups"
    echo "- Steps with PASS: $(find "${STAT_DIR}" -name "*.json" -exec grep -l '"PASS"' {} \; 2>/dev/null | wc -l)"
    echo "- Steps with FAIL: $(find "${STAT_DIR}" -name "*.json" -exec grep -l '"FAIL"' {} \; 2>/dev/null | wc -l)"
    echo "- Steps UNVERIFIED (no rules): see scripts/utils/VALIDATION_INTEGRATION.md"
    echo "- Full validation log: logs/validation_log.jsonl (if present)"
    echo

    echo "## Artifact Index"
    echo
    echo "| Domain | Key Files |"
    echo "|---|---|"
    for domain_dir in "${STAT_DIR}"/../*/; do
        domain=$(basename "$domain_dir")
        # Skip non-result dirs
        case "$domain" in
            logs|temp|visualization|opt_bench|report) continue ;;
        esac
        n_files=$(find "$domain_dir" -type f 2>/dev/null | wc -l)
        echo "| $domain | $n_files files |"
    done
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
    echo "## Downstream Tool Guide (S-4b)"
    echo
    echo "| Table | Format | Ready for |"
    echo "|---|---|---|"
    echo "| 98b gene TPM | counts | DESeq2, edgeR, limma |"
    echo "| 98b gene relab | relative | LEfSe, MaAsLin2 |"
    echo "| 98b gene CLR | transformed | ANCOM-BC2, ALDEx2 |"
    echo "| 98c vOTU TPM | counts | DESeq2, edgeR |"
    echo "| 98c vOTU relab | relative | LEfSe |"
    echo "| 98d MAG relab | relative | MaAsLin2, SIAMCAT (n>=10) |"
    echo "| 91 alpha diversity | per-sample | group comparison (Wilcoxon) |"
    echo "| 91 beta diversity | distance | PERMANOVA, ANOSIM |"
    echo "| 93 network summary | per-network | topology comparison |"
    echo ""
    echo "> Note: SIAMCAT requires n>=10; see POWER_DISCLOSURE.md for sample-size constraints."
    echo
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
    echo

    echo "## LEfSe Failures"
    echo
    LEFSE_LEDGER="${STAT_DIR}/lefse_failed_tables.txt"
    if [ -s "${LEFSE_LEDGER}" ]; then
        echo "The following LEfSe tables FAILED (their sentinel still got touched; results for these tables are missing):"
        echo
        echo '```'
        cat "${LEFSE_LEDGER}"
        echo '```'
    else
        echo "- None (ledger empty or absent: ${LEFSE_LEDGER})"
    fi
} > "${REPORT_FILE}"

if [ ! -s "${REPORT_FILE}" ]; then
    echo "[ERROR] Report file was not generated: ${REPORT_FILE}"
    exit 1
fi

echo "[INFO] Report generated: ${REPORT_FILE}"
mgx_end "report"
