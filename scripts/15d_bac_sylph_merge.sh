#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 15d_bac_sylph_merge.sh
# 功  能: 合并所有样本的 sylph .sylphmpa 物种级 profile，生成项目级多样本矩阵
# 依  赖: 15c_bac_sylph.sh 的输出（每个样本的 .sylphmpa）
# 输  入: ${WORKDIR}/result/sylph/*/  （扫描所有已完成样本）
# 输  出: ${WORKDIR}/result/sylph/merged/sylph_profile_merged.tsv  （物种级多样本相对丰度表）
# 用  法: bash 15d_bac_sylph_merge.sh -w /path/to/Project_example -r /path/to/MaxMetagenome
# ==============================================================================

set -euo pipefail

if [ $# -lt 4 ]; then
    echo ""
    echo "用法: bash 15d_bac_sylph_merge.sh -w WORKDIR -r REPO"
    echo ""
    echo "参数说明:"
    echo "  -w  工作目录（Project_example 路径）"
    echo "  -r  MaxMetagenome 项目根目录"
    echo ""
    echo "示例:"
    echo "  bash 15d_bac_sylph_merge.sh \\"
    echo "       -w ~/Course/Maxmetagenome/Project/Project_example \\"
    echo "       -r ~/Course/Maxmetagenome"
    echo ""
    echo "可选参数:"
    echo "  --force  强制重新运行（忽略已存在的结果）"
    exit 1
fi

FORCE=0
ARGS=()
for arg in "$@"; do
    if [ "${arg}" = "--force" ]; then
        FORCE=1
    else
        ARGS+=("${arg}")
    fi
done
set -- "${ARGS[@]}"

WORKDIR=""
REPO=""
while getopts w:r: option; do
    case "${option}" in
        w) WORKDIR=${OPTARG} ;;
        r) REPO=${OPTARG} ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-w/-r）"
    exit 1
fi

SECONDS=0

# --- 路径设置 ---

PROFILE_DIR="${WORKDIR}/result/sylph"
MERGED_DIR="${PROFILE_DIR}/merged"
MERGED_TSV="${MERGED_DIR}/sylph_profile_merged.tsv"

# --- 收集所有已完成的 .sylphmpa 文件 ---

SAMPLE_LIST=()
for sample_dir in "${PROFILE_DIR}"/*/; do
    sample=$(basename "${sample_dir}")
    [ "${sample}" = "merged" ] && continue
    mpa="${sample_dir}/${sample}.sylphmpa"
    if [ -f "${mpa}" ]; then
        SAMPLE_LIST+=("${sample}")
    fi
done

if [ ${#SAMPLE_LIST[@]} -eq 0 ]; then
    echo "[ERROR] 未找到任何 sylph .sylphmpa 文件"
    echo "        期望路径: ${PROFILE_DIR}/<SAMPLE>/<SAMPLE>.sylphmpa"
    echo "        请先运行 15c_bac_sylph.sh"
    exit 1
fi

mapfile -t SAMPLE_LIST < <(printf '%s\n' "${SAMPLE_LIST[@]}" | sort)

echo "[sylph_merge] 找到 ${#SAMPLE_LIST[@]} 个样本 profile:"
for sample in "${SAMPLE_LIST[@]}"; do
    echo "    ${sample}"
done

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${MERGED_TSV}" ] && [ -s "${MERGED_TSV}" ]; then
    echo "[INFO] 合并结果已存在，跳过。如需重新合并请先删除 ${MERGED_DIR}"
    exit 0
fi

mkdir -p "${MERGED_DIR}"

# --- 用 sylph-tax merge 合并（复用官方合并工具，而非重复实现解析逻辑） ---

MPA_FILES=()
for sample in "${SAMPLE_LIST[@]}"; do
    MPA_FILES+=("${PROFILE_DIR}/${sample}/${sample}.sylphmpa")
done

echo "[INFO] 合并多样本 sylphmpa 相对丰度表..."
set +e
conda run --prefix "${REPO}/envs/sylph" --no-capture-output \
    sylph-tax merge \
        "${MPA_FILES[@]}" \
        --column relative_abundance \
        -o "${MERGED_TSV}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] sylph-tax merge 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${MERGED_TSV}" ] || [ ! -s "${MERGED_TSV}" ]; then
    echo "[ERROR] 合并失败，未生成 ${MERGED_TSV}"
    exit 1
fi

# --- 统计摘要 ---

NROW=$(wc -l < "${MERGED_TSV}")
NCOL=$(awk -F'\t' 'NR==1{print NF}' "${MERGED_TSV}")

echo ""
echo "[sylph_merge] 合并完成，耗时 ${SECONDS}s"
echo "[sylph_merge] 输出: ${MERGED_TSV} — ${NROW} 行 × ${NCOL} 列"
