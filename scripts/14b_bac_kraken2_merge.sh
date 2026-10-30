#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 14b_bac_kraken2_merge.sh
# 功  能: 合并所有样本的 Bracken 丰度估计表，生成项目级多样本矩阵
# 依  赖: 14_bac_kraken2.sh 的输出（每个样本的 _S/_G/_P.bracken）
# 输  入: ${WORKDIR}/result/kraken2/*/bracken/  （扫描所有已完成样本）
# 输  出: ${WORKDIR}/result/kraken2/merged/bracken_S.tsv  （种级多样本丰度表）
#         ${WORKDIR}/result/kraken2/merged/bracken_G.tsv  （属级多样本丰度表）
#         ${WORKDIR}/result/kraken2/merged/bracken_P.tsv  （门级多样本丰度表）
# 用  法: bash 14b_bac_kraken2_merge.sh -w /path/to/Project_example -r /path/to/CSCCD-MetagenomeFlow
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# --- 参数解析 ---

show_help() { cat << EOF

用法: bash 14b_bac_kraken2_merge.sh -w WORKDIR -r REPO

参数说明:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

示例:
  bash 14b_bac_kraken2_merge.sh \\
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

PROFILE_DIR="${WORKDIR}/result/kraken2"
MERGED_DIR="${PROFILE_DIR}/merged"

BRACKEN_S_TSV="${MERGED_DIR}/bracken_S.tsv"
BRACKEN_G_TSV="${MERGED_DIR}/bracken_G.tsv"
BRACKEN_P_TSV="${MERGED_DIR}/bracken_P.tsv"

# --- 收集所有已完成的 Bracken 文件 ---

SAMPLE_LIST=()
for sample_dir in "${PROFILE_DIR}"/*/; do
    sample=$(basename "${sample_dir}")
    [ "${sample}" = "merged" ] && continue
    bracken_dir="${sample_dir}/bracken"
    bracken_s="${bracken_dir}/${sample}_S.bracken"
    if [ -f "${bracken_s}" ]; then
        SAMPLE_LIST+=("${sample}")
    fi
done

if [ ${#SAMPLE_LIST[@]} -eq 0 ]; then
    echo "[ERROR] 未找到任何 Bracken 结果文件"
    echo "        期望路径: ${PROFILE_DIR}/<SAMPLE>/bracken/<SAMPLE>_S.bracken"
    echo "        请先运行 14_bac_kraken2.sh"
    exit 1
fi

mapfile -t SAMPLE_LIST < <(printf '%s\n' "${SAMPLE_LIST[@]}" | sort)

echo "[kraken2_merge] 找到 ${#SAMPLE_LIST[@]} 个样本 profile:"
for sample in "${SAMPLE_LIST[@]}"; do
    echo "    ${sample}"
done

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${BRACKEN_S_TSV}" ] && [ -f "${BRACKEN_G_TSV}" ] && [ -f "${BRACKEN_P_TSV}" ]; then
    echo "[INFO] 合并结果已存在，跳过。如需重新合并请先删除 ${MERGED_DIR}"
    exit 0
fi

mkdir -p "${MERGED_DIR}"

# --- Step 1: 按分类级别合并 Bracken 丰度表 ---

for LEVEL in S G P; do
    FILE_LIST=()
    for sample in "${SAMPLE_LIST[@]}"; do
        bracken_file="${PROFILE_DIR}/${sample}/bracken/${sample}_${LEVEL}.bracken"
        if [ ! -f "${bracken_file}" ]; then
            echo "[ERROR] 缺少 Bracken ${LEVEL} 级文件: ${bracken_file}"
            exit 1
        fi
        FILE_LIST+=("${bracken_file}")
    done

    NAME_LIST=$(IFS=,; echo "${SAMPLE_LIST[*]}")
    OUTPUT_TSV="${MERGED_DIR}/bracken_${LEVEL}.tsv"

    echo "[INFO] 合并 Bracken ${LEVEL} 级丰度表..."
    mgx_conda kraken2 \
        combine_bracken_outputs.py \
            --files "${FILE_LIST[@]}" \
            --names "${NAME_LIST}" \
            -o "${OUTPUT_TSV}"

    if [ ! -f "${OUTPUT_TSV}" ] || [ ! -s "${OUTPUT_TSV}" ]; then
        echo "[ERROR] 合并失败，未生成 ${OUTPUT_TSV}"
        exit 1
    fi
done

# --- 统计摘要 ---

echo ""
echo "[kraken2_merge] 合并完成"
echo "[kraken2_merge] 输出目录: ${MERGED_DIR}"
for LEVEL in S G P; do
    OUTPUT_TSV="${MERGED_DIR}/bracken_${LEVEL}.tsv"
    NROW=$(wc -l < "${OUTPUT_TSV}")
    NCOL=$(awk -F'\t' 'NR==1{print NF}' "${OUTPUT_TSV}")
    echo "    bracken_${LEVEL}.tsv — ${NROW} 行 × ${NCOL} 列"
done
mgx_end "kraken2_merge"
