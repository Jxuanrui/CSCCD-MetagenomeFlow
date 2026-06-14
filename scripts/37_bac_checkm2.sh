#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 37_bac_checkm2.sh
# 功  能: MAG 质量评估（CheckM2 ML 模型，预测完整度和污染度）
#         工具版本：CheckM2 1.1+（conda env: checkm2）
# 依  赖: 36_bac_dastool.sh 的 bins
# 输  入: ${WORKDIR}/result/binning/dastool/*/bins/*.fa
# 输  出: ${WORKDIR}/result/binning/checkm2/quality_report.tsv
#         ${WORKDIR}/result/binning/checkm2/checkm2_filtered/
#           — 完整度 ≥50% 且 污染度 ≤10% 的 MAGs（软链或复制）
#
# 参  考: Chklovski et al. 2022 Nature Methods (CheckM2)
# 用  法: bash 37_bac_checkm2.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 37_bac_checkm2.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
BINS_DIR="${WORKDIR}/result/binning/dastool"
REPORT="${WORKDIR}/result/binning/checkm2/quality_report.tsv"
FILTERED_DIR="${WORKDIR}/result/binning/checkm2/checkm2_filtered"
DREP_IN="${WORKDIR}/result/binning/checkm2/drep_input"
DB="${REPO}/db/checkm2"

# 收集所有 dastool bins（跨样本）
BIN_FILES=()
for d in "${BINS_DIR}"/*/bins; do
    [ -d "$d" ] && for f in "$d"/*.fa; do [ -f "$f" ] && BIN_FILES+=("$f"); done
done

if [ ${#BIN_FILES[@]} -eq 0 ]; then
    echo "[checkm2] WARNING: No bins found. Creating empty quality report."
    mkdir -p "${WORKDIR}/result/binning/checkm2" "${FILTERED_DIR}" "${DREP_IN}"
    echo -e "Name\tCompleteness\tContamination" > "${REPORT}"
    echo -e "Name\tCompleteness\tContamination" > "${FILTERED_DIR}/filtered_report.tsv"
    exit 0
fi

# 为 CheckM2 创建输入目录（符号链）
INPUT_DIR="${WORKDIR}/result/binning/checkm2/input"
if [ ! -f "${INPUT_DIR}/.done" ]; then
    mkdir -p "${INPUT_DIR}"
    for f in "${BIN_FILES[@]}"; do
        ln -sf "$(realpath "$f")" "${INPUT_DIR}/"
    done
    touch "${INPUT_DIR}/.done"
fi

if [ -f "${REPORT}" ] && [ -s "${REPORT}" ]; then
    echo "[checkm2] 结果已存在，跳过"; exit 0
fi

mkdir -p "${WORKDIR}/result/binning/checkm2"

echo "[checkm2] MAG 质量评估 | bins: ${#BIN_FILES[@]} | 线程: ${CPUS}"
conda run --prefix "${REPO}/envs/checkm2" --no-capture-output \
    checkm2 predict \
        --threads "${CPUS}" \
        --force \
        --input "${INPUT_DIR}" \
        -x fa \
        --output-directory "${WORKDIR}/result/binning/checkm2" \
        --database_path "${DB}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] checkm2 失败"; exit ${EXIT_CODE}; fi

# 过滤：完整度 ≥50% 且 污染度 ≤10%
mkdir -p "${FILTERED_DIR}" "${DREP_IN}"
awk -F'\t' 'NR==1 || ($2>=50 && $3<=10)' "${REPORT}" > "${FILTERED_DIR}/filtered_report.tsv"

# 复制高质量 MAGs
N_FILTERED=0
while IFS=$'\t' read -r name comp cont _; do
    [ "$name" == "Name" ] && continue
    src="${INPUT_DIR}/${name}.fa"
    if [ -f "$src" ]; then
        cp "$src" "${DREP_IN}/"
        ((N_FILTERED++))
    fi
done < "${FILTERED_DIR}/filtered_report.tsv"

echo "[checkm2] 完成，耗时 ${SECONDS}s | 输入 bins: ${#BIN_FILES[@]} | 高质量: ${N_FILTERED}"
