# Deprecated 2026-07-16: superseded by the Snakemake downstream_summary aggregation rule.
#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 99c_batch_downstream.sh
# 功能:   自动检测可用维度并批量运行核心微生物组、LEfSe、功能冗余和通路活性分析
# 依赖:   99a_core_microbiome.sh、99b_lefse.sh、96c_functional_redundancy.sh、96b_pathway_activity.sh
# 输入:   MaxMetagenome 工作目录、元数据文件和仓库根目录
# 输出:   ${WORKDIR}/result/stat/{bacteria,virus,fungi}/ 下游分析结果及终端汇总表
# 用法:   bash 99c_batch_downstream.sh -w WORKDIR -r REPO [-m METADATA_FILE] [-t THREADS]
# ==============================================================================

set -euo pipefail

show_help() {
cat <<'EOF'
Usage: bash 99c_batch_downstream.sh -w WORKDIR -r REPO [options]

Required:
  -w, --workdir        Project work directory containing result/
  -r, --repo           Path to the MaxMetagenome repository root

Optional:
  -m, --metadata-file  Metadata CSV/TSV (default: WORKDIR/metadata.csv)
  -t, --threads        Reserved thread count for future use (default: 8)
  -h, --help           Show this help message
EOF
}

WORKDIR=""
METADATA_FILE=""
REPO=""
THREADS="8"

normalized_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir) normalized_args+=("-w") ;;
        --metadata-file) normalized_args+=("-m") ;;
        --repo) normalized_args+=("-r") ;;
        --threads) normalized_args+=("-t") ;;
        --help) normalized_args+=("-h") ;;
        --) shift; normalized_args+=("$@"); break ;;
        *) normalized_args+=("$1") ;;
    esac
    shift
done
set -- "${normalized_args[@]}"

OPTIND=1
while getopts ":w:m:r:t:h" option; do
    case "${option}" in
        w) WORKDIR="${OPTARG}" ;;
        m) METADATA_FILE="${OPTARG}" ;;
        r) REPO="${OPTARG}" ;;
        t) THREADS="${OPTARG}" ;;
        h) show_help; exit 0 ;;
        :) echo "[ERROR] Missing value for -${OPTARG}" >&2; show_help >&2; exit 1 ;;
        \?) echo "[ERROR] Unknown option: -${OPTARG}" >&2; show_help >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -gt 0 ]]; then
    echo "[ERROR] Unexpected argument: $1" >&2
    show_help >&2
    exit 1
fi
if [[ -z "${WORKDIR}" || -z "${REPO}" ]]; then
    echo "[ERROR] -w/--workdir and -r/--repo are required" >&2
    show_help >&2
    exit 1
fi
[[ -d "${WORKDIR}" ]] || { echo "[ERROR] Work directory not found: ${WORKDIR}" >&2; exit 1; }
[[ -d "${REPO}" ]] || { echo "[ERROR] Repository directory not found: ${REPO}" >&2; exit 1; }
[[ "${THREADS}" =~ ^[1-9][0-9]*$ ]] || { echo "[ERROR] Threads must be a positive integer: ${THREADS}" >&2; exit 1; }

WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"
if [[ -z "${METADATA_FILE}" ]]; then
    METADATA_FILE="${WORKDIR}/metadata.csv"
fi
[[ -f "${METADATA_FILE}" ]] || { echo "[ERROR] Metadata file not found: ${METADATA_FILE}" >&2; exit 1; }
METADATA_FILE="$(cd "$(dirname "${METADATA_FILE}")" && pwd)/$(basename "${METADATA_FILE}")"

CORE_SCRIPT="${REPO}/scripts/99a_core_microbiome.sh"
LEFSE_SCRIPT="${REPO}/scripts/99b_lefse.sh"
REDUNDANCY_SCRIPT="${REPO}/scripts/96c_functional_redundancy.sh"
PATHWAY_SCRIPT="${REPO}/scripts/96b_pathway_activity.sh"
for script in "${CORE_SCRIPT}" "${LEFSE_SCRIPT}" "${REDUNDANCY_SCRIPT}" "${PATHWAY_SCRIPT}"; do
    [[ -f "${script}" ]] || { echo "[ERROR] Downstream script not found: ${script}" >&2; exit 1; }
done

export R_SCRIPT_BIN="${R_SCRIPT_BIN:-${REPO}/envs/r_stat/bin/Rscript}"

declare -A TAXONOMY_FILE
declare -A DIMENSION_AVAILABLE
declare -A MODULE_STATUS

for dimension in bacteria virus fungi; do
    DIMENSION_AVAILABLE["${dimension}"]="no"
    for module in core_microbiome lefse functional_redundancy pathway_activity; do
        MODULE_STATUS["${dimension}:${module}"]="skipped"
    done
done

BAC_FUNC="${WORKDIR}/result/integration/bacteria/kegg_ko_abundance.tsv"
BAC_TAX="${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"
VIR_FUNC="${WORKDIR}/result/integration/virus/vog_abundance.tsv"
VIR_TAX="${WORKDIR}/result/integration/virus/viral_family_abundance.tsv"
FUN_TAX="${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy.tsv"

if [[ -f "${BAC_FUNC}" && -f "${BAC_TAX}" ]]; then
    DIMENSION_AVAILABLE[bacteria]="yes"
    TAXONOMY_FILE[bacteria]="${BAC_TAX}"
else
    echo "[INFO] Bacteria functional or taxonomy data not available, skipping bacteria dimension"
fi

if [[ -f "${VIR_FUNC}" && -f "${VIR_TAX}" ]]; then
    DIMENSION_AVAILABLE[virus]="yes"
    TAXONOMY_FILE[virus]="${VIR_TAX}"
else
    echo "[INFO] Virus functional or taxonomy data not available, skipping virus dimension"
fi

if [[ -f "${FUN_TAX}" ]]; then
    DIMENSION_AVAILABLE[fungi]="yes"
    TAXONOMY_FILE[fungi]="${FUN_TAX}"
else
    echo "[INFO] Fungi taxonomy not available, skipping fungi dimension"
fi

run_core_microbiome() {
    local dimension="$1"
    local output_dir="${WORKDIR}/result/stat/${dimension}/core_microbiome"
    local module_ok=1

    echo "[INFO] Running Core Microbiome for ${dimension}"
    bash "${CORE_SCRIPT}" \
        -i "${TAXONOMY_FILE[${dimension}]}" \
        -m "${METADATA_FILE}" \
        -o "${output_dir}" \
        -d "${dimension}" \
        --prevalence-threshold 0.5 \
        --min-abundance 0.0001 || {
            echo "[WARN] Core Microbiome failed for ${dimension}, continuing"
            module_ok=0
        }
    if [[ "${module_ok}" -eq 1 ]]; then
        MODULE_STATUS["${dimension}:core_microbiome"]="ran"
    else
        MODULE_STATUS["${dimension}:core_microbiome"]="failed"
    fi
}

run_lefse() {
    local dimension="$1"
    local integration_dir="${WORKDIR}/result/integration/${dimension}"
    local table type output_dir
    local found=0
    local failed=0
    local module_ok

    shopt -s nullglob
    local tables=("${integration_dir}"/*_abundance.tsv)
    shopt -u nullglob
    for table in "${tables[@]}"; do
        found=1
        type="$(basename "${table}" _abundance.tsv)"
        output_dir="${WORKDIR}/result/stat/${dimension}/lefse/${type}"
        module_ok=1
        echo "[INFO] Running LEfSe for ${dimension}/${type}"
        bash "${LEFSE_SCRIPT}" \
            -i "${table}" \
            -m "${METADATA_FILE}" \
            -o "${output_dir}" \
            -d "${dimension}" \
            -y "${type}" \
            --lda-threshold 2.0 \
            --min-prevalence 0.1 \
            --wilcoxon-alpha 0.05 || {
                echo "[WARN] LEfSe failed for ${dimension}/${type}, continuing"
                module_ok=0
            }
        [[ "${module_ok}" -eq 1 ]] || failed=1
    done

    if [[ "${found}" -eq 0 ]]; then
        echo "[INFO] No functional *_abundance.tsv tables for ${dimension}, skipping LEfSe"
        MODULE_STATUS["${dimension}:lefse"]="skipped"
    elif [[ "${failed}" -eq 1 ]]; then
        MODULE_STATUS["${dimension}:lefse"]="failed"
    else
        MODULE_STATUS["${dimension}:lefse"]="ran"
    fi
}

run_functional_redundancy() {
    local dimension="$1"
    local integration_dir="${WORKDIR}/result/integration/${dimension}"
    local table type output_dir
    local found=0
    local failed=0
    local module_ok

    shopt -s nullglob
    local tables=("${integration_dir}"/*_abundance.tsv)
    shopt -u nullglob
    for table in "${tables[@]}"; do
        if [[ "${table}" == "${TAXONOMY_FILE[${dimension}]}" ]]; then
            continue
        fi
        found=1
        type="$(basename "${table}" _abundance.tsv)"
        output_dir="${WORKDIR}/result/stat/${dimension}/functional_redundancy/${type}"
        module_ok=1
        echo "[INFO] Running Functional Redundancy for ${dimension}/${type}"
        bash "${REDUNDANCY_SCRIPT}" \
            -f "${table}" \
            -t "${TAXONOMY_FILE[${dimension}]}" \
            -o "${output_dir}" \
            -d "${dimension}" \
            -y "${type}" || {
                echo "[WARN] Functional Redundancy failed for ${dimension}/${type}, continuing"
                module_ok=0
            }
        [[ "${module_ok}" -eq 1 ]] || failed=1
    done

    if [[ "${found}" -eq 0 ]]; then
        echo "[INFO] No functional *_abundance.tsv tables for ${dimension}, skipping Functional Redundancy"
        MODULE_STATUS["${dimension}:functional_redundancy"]="skipped"
    elif [[ "${failed}" -eq 1 ]]; then
        MODULE_STATUS["${dimension}:functional_redundancy"]="failed"
    else
        MODULE_STATUS["${dimension}:functional_redundancy"]="ran"
    fi
}

run_pathway_activity() {
    local output_dir="${WORKDIR}/result/stat/bacteria/pathway_activity"
    local module_ok=1

    if ! find "${WORKDIR}/result/humann3" -type f -name '*_pathabundance.tsv' -print -quit 2>/dev/null | grep -q .; then
        echo "[INFO] HUMAnN3 pathabundance tables not available, skipping Pathway Activity"
        MODULE_STATUS["bacteria:pathway_activity"]="skipped"
        return
    fi

    echo "[INFO] Running Pathway Activity for bacteria"
    bash "${PATHWAY_SCRIPT}" \
        -w "${WORKDIR}" \
        -m "${METADATA_FILE}" \
        -o "${output_dir}" \
        -d bacteria \
        --min-coverage 0.5 \
        --top-n-contributors 5 || {
            echo "[WARN] Pathway Activity failed for bacteria, continuing"
            module_ok=0
        }
    if [[ "${module_ok}" -eq 1 ]]; then
        MODULE_STATUS["bacteria:pathway_activity"]="ran"
    else
        MODULE_STATUS["bacteria:pathway_activity"]="failed"
    fi
}

for dimension in bacteria virus fungi; do
    [[ "${DIMENSION_AVAILABLE[${dimension}]}" == "yes" ]] || continue
    run_core_microbiome "${dimension}"
    run_lefse "${dimension}"
    run_functional_redundancy "${dimension}"
    if [[ "${dimension}" == "bacteria" ]]; then
        run_pathway_activity
    fi
done

status_icon() {
    case "$1" in
        ran) printf '✅ ran' ;;
        failed) printf '⚠️ failed' ;;
        *) printf '⏭️ skipped' ;;
    esac
}

module_detail() {
    local dimension="$1"
    local module="$2"
    local module_dir="${WORKDIR}/result/stat/${dimension}/${module}"
    local summary_file line table rows total=0 found=0

    # Only show results for modules that actually ran in this invocation.
    # Otherwise stale output from a previous run in the same directory would
    # be misreported as belonging to a "skipped" module.
    if [[ "${MODULE_STATUS[${dimension}:${module}]}" != "ran" ]]; then
        return
    fi

    case "${module}" in
        core_microbiome)
            summary_file="${module_dir}/core_microbiome_summary.txt"
            if [[ -f "${summary_file}" ]]; then
                line="$(grep -m 1 '^Global core features:' "${summary_file}" || true)"
                [[ -n "${line}" ]] && printf '%s' "${line}"
            fi
            ;;
        lefse)
            while IFS= read -r -d '' table; do
                rows=$(wc -l < "${table}")
                if (( rows > 0 )); then
                    rows=$((rows - 1))
                fi
                total=$((total + rows))
                found=1
            done < <(find "${module_dir}" -type f -name 'lefse_results.tsv' -print0 2>/dev/null)
            [[ "${found}" -eq 1 ]] && printf 'Biomarkers: %d' "${total}"
            ;;
        functional_redundancy)
            while IFS= read -r -d '' summary_file; do
                line="$(grep -m 1 '^Mean FDI:' "${summary_file}" || true)"
                if [[ -n "${line}" ]]; then
                    [[ "${found}" -eq 0 ]] || printf '; '
                    printf '%s %s' "$(basename "$(dirname "${summary_file}")")" "${line}"
                    found=1
                fi
            done < <(find "${module_dir}" -type f -name 'functional_redundancy_summary.txt' -print0 2>/dev/null | sort -z)
            ;;
        pathway_activity)
            summary_file="${module_dir}/pathway_activity_summary.txt"
            if [[ -f "${summary_file}" ]]; then
                line="$(grep -m 1 -E '^(Pathways analyzed|Mean pathway coverage):' "${summary_file}" || true)"
                [[ -n "${line}" ]] && printf '%s' "${line}"
            fi
            ;;
    esac
}

printf '\nDownstream analysis summary\n'
printf '%-10s | %-24s | %-12s | %s\n' "Dimension" "Module" "Status" "Key result"
printf '%-10s-+-%-24s-+-%-12s-+-%s\n' "----------" "------------------------" "------------" "------------------------------"
for dimension in bacteria virus fungi; do
    for module in core_microbiome lefse functional_redundancy pathway_activity; do
        if [[ "${module}" == "pathway_activity" && "${dimension}" != "bacteria" ]]; then
            MODULE_STATUS["${dimension}:${module}"]="skipped"
        fi
        printf '%-10s | %-24s | %-12s | ' \
            "${dimension}" "${module}" "$(status_icon "${MODULE_STATUS[${dimension}:${module}]}")"
        module_detail "${dimension}" "${module}"
        printf '\n'
    done
done

echo "[INFO] Batch downstream analysis finished (threads reserved: ${THREADS})"
