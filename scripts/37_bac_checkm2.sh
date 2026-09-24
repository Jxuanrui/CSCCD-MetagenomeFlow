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

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 37_bac_checkm2.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
REASSEMBLY_DIR="${WORKDIR}/result/binning/reassembly"
DASTOOL_DIR="${WORKDIR}/result/binning/dastool"
REPORT="${WORKDIR}/result/binning/checkm2/quality_report.tsv"
FILTERED_DIR="${WORKDIR}/result/binning/checkm2/checkm2_filtered"
DREP_IN="${WORKDIR}/result/binning/checkm2/drep_input"
DB="${REPO}/db/checkm2/CheckM2_database/uniref100.KO.1.dmnd"

# 收集所有 bins（跨样本）：优先取 36b_bac_bin_reassembly.sh 的重组装结果
# （result/binning/reassembly/{sample}/reassembled_bins/），该目录里每个 bin
# 要么是重组装成功的版本，要么是回退的原始 DAS_Tool bin，与原始 bin 集合一一对应；
# 若某样本尚未跑过 reassembly（目录不存在），回退读取该样本的原始 DAS_Tool bins
# （DAS_Tool 输出目录名为 {sample}_DASTool_bins），保证脚本对新旧项目状态均兼容
BIN_FILES=()
BIN_SAMPLES=()
for d in "${DASTOOL_DIR}"/*/*_DASTool_bins; do
    [ -d "$d" ] || continue
    SAMPLE_NAME=$(basename "$(dirname "$d")")
    SRC_DIR="${REASSEMBLY_DIR}/${SAMPLE_NAME}/reassembled_bins"
    if [ ! -d "${SRC_DIR}" ]; then
        SRC_DIR="$d"
    fi
    for f in "${SRC_DIR}"/*.fa; do
        if [ -f "$f" ]; then
            BIN_FILES+=("$f")
            BIN_SAMPLES+=("$SAMPLE_NAME")
        fi
    done
done

if [ ${#BIN_FILES[@]} -eq 0 ]; then
    echo "[checkm2] WARNING: No bins found. Creating empty quality report."
    mkdir -p "${WORKDIR}/result/binning/checkm2" "${FILTERED_DIR}" "${DREP_IN}"
    echo -e "Name\tCompleteness\tContamination" > "${REPORT}"
    echo -e "Name\tCompleteness\tContamination" > "${FILTERED_DIR}/filtered_report.tsv"
    exit 0
fi

# 为 CheckM2 创建输入目录（符号链，文件名加样本前缀避免跨样本重名冲突，如 Sample1/0.fa 与 Sample2/0.fa）
# 注: 必须放在 output-directory 之外，--force 会清空输出目录
# 幂等性检查用 .done 哨兵，但若上游 reassembled_bins/（bin_reassembly 重跑后
# 命名规则、bin 数量都可能变化）比 .done 更新，说明输入已变化，旧软链集合会
# 包含大量悬空链接（指向已不存在的旧 bin 名），必须重建整个 INPUT_DIR
INPUT_DIR="${WORKDIR}/temp/checkm2_input"
REBUILD_INPUT=0
if [ ! -f "${INPUT_DIR}/.done" ]; then
    REBUILD_INPUT=1
elif [ -n "$(find "${REASSEMBLY_DIR}" -maxdepth 2 -name reassembled_bins -newer "${INPUT_DIR}/.done" 2>/dev/null)" ]; then
    echo "[checkm2] 检测到 reassembled_bins/ 比 checkm2_input/.done 更新，重建输入目录"
    REBUILD_INPUT=1
fi
if [ ${REBUILD_INPUT} -eq 1 ]; then
    rm -rf "${INPUT_DIR}"
    mkdir -p "${INPUT_DIR}"
    for i in "${!BIN_FILES[@]}"; do
        f="${BIN_FILES[$i]}"
        s="${BIN_SAMPLES[$i]}"
        ln -sf "$(realpath "$f")" "${INPUT_DIR}/${s}__$(basename "$f")"
    done
    touch "${INPUT_DIR}/.done"
fi

if [ ${FORCE} -eq 0 ] && [ -f "${REPORT}" ] && [ -s "${REPORT}" ]; then
    echo "[checkm2] 结果已存在，跳过"; exit 0
fi

mkdir -p "${WORKDIR}/result/binning/checkm2"

echo "[checkm2] MAG 质量评估 | bins: ${#BIN_FILES[@]} | 线程: ${CPUS}"
mgx_conda checkm2 \
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
while IFS=$'\t' read -r name _ _ _; do
    [ "$name" == "Name" ] && continue
    src="${INPUT_DIR}/${name}.fa"
    if [ -f "$src" ]; then
        cp "$src" "${DREP_IN}/"
        N_FILTERED=$((N_FILTERED+1))
    fi
done < "${FILTERED_DIR}/filtered_report.tsv"

echo "[checkm2] 输入 bins: ${#BIN_FILES[@]} | 高质量: ${N_FILTERED}"
mgx_end "checkm2"
