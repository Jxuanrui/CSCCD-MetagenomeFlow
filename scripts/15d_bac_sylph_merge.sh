#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 15d_bac_sylph_merge.sh
# 功  能: 合并所有样本的 sylph .sylphmpa 物种级 profile，生成项目级多样本矩阵
# 依  赖: 15c_bac_sylph.sh 的输出（每个样本的 .sylphmpa）
# 输  入: ${WORKDIR}/result/sylph/*/  （扫描所有已完成样本）
# 输  出: ${WORKDIR}/result/sylph/merged/sylph_profile_merged.tsv  （物种级多样本相对丰度表）
# 用  法: bash 15d_bac_sylph_merge.sh -w /path/to/Project_example -r /path/to/CSCCD-MetagenomeFlow
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF

用法: bash 15d_bac_sylph_merge.sh -w WORKDIR -r REPO

参数说明:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

示例:
  bash 15d_bac_sylph_merge.sh \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

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
EXIT_CODE=0
mgx_try mgx_conda sylph \
    sylph-tax merge \
        "${MPA_FILES[@]}" \
        --column relative_abundance \
        -o "${MERGED_TSV}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
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
echo "[sylph_merge] 合并完成"
echo "[sylph_merge] 输出: ${MERGED_TSV} — ${NROW} 行 × ${NCOL} 列"
mgx_end "sylph_merge"
