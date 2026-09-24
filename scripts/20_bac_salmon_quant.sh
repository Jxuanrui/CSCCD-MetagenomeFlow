#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 20_bac_salmon_quant.sh
# 功  能: Salmon 基因丰度定量（TPM + Read count），基于 NR 基因集索引
#         工具版本：Salmon v1.2.0（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh（clean reads）+ 19_bac_salmon_build.sh（Salmon 索引）
# 输  入: kneaddata clean reads R1/R2 + Salmon 索引目录
# 输  出: ${WORKDIR}/result/assembly/salmon/${SAMPLE}/
#           quant.sf    — 基因 TPM + Read count（主要结果）
#           aux_info/   — Salmon 辅助统计信息
#
# ── 参数说明 ─────────────────────────────────────────────────────────────────
#
#   -l A：文库类型自动推断（适合 PE stranded/unstranded 宏基因组）
#   --meta：宏基因组模式（使用 EM 而非 VBEM 优化，避免 RNA-seq 专用参数干扰）
#   --validateMappings：启用选择性比对（Salmon v1.2.0 推荐；v1.9+ 中已为默认行为）
#
# ── 合并多样本结果 ─────────────────────────────────────────────────────────────
#
#   所有样本 quant 完成后，使用 salmon quantmerge 合并：
#     salmon quantmerge --quants result/assembly/salmon/*.quant -o gene.TPM
#     salmon quantmerge --quants result/assembly/salmon/*.quant --column NumReads -o gene.count
#
# 参  考: Patro et al. Nature Methods 2017; EasyMetagenome 1Pipeline.sh
#         https://salmon.readthedocs.io/en/latest/salmon.html
# 用  法: bash 20_bac_salmon_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 20_bac_salmon_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名（如 SRR28210342）
  -t  线程数（推荐 8-16）
  -w  工作目录（Project 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash 20_bac_salmon_quant.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

INDEX_DIR="${WORKDIR}/result/assembly/salmon/index"
INDEX_INFO="${INDEX_DIR}/info.json"

RESULT_DIR="${WORKDIR}/result/assembly/salmon/${SAMPLE}"
QUANT_SF="${RESULT_DIR}/quant.sf"

# --- 输入检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
if [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    exit 1
fi
if [ ! -f "${INDEX_INFO}" ]; then
    echo "[ERROR] Salmon 索引不存在: ${INDEX_DIR}/info.json"
    echo "        请先运行 19_bac_salmon_build.sh"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${QUANT_SF}" ] && [ -s "${QUANT_SF}" ]; then
    echo "[INFO] Salmon 定量结果已存在，跳过: ${SAMPLE}"
    echo "       ${QUANT_SF}"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[salmon-quant] 开始基因丰度定量: ${SAMPLE}"
echo "[salmon-quant] 线程: ${CPUS}"
echo "[salmon-quant] 索引: ${INDEX_DIR}/"

# --- 运行 salmon quant ---
# -i:                  索引目录（由 19_bac_salmon_build 构建）
# -l A:                文库类型自动推断（宏基因组一般为 IU 或 ISF，A 自动检测）
# -p:                  线程数
# --meta:              宏基因组模式（EM 优化，避免 RNA-seq 专用先验干扰）
# --validateMappings:  选择性比对（Salmon v1.2.0 推荐；新版已为默认行为）
# -1/-2:               双端 reads
# -o:                  输出目录

EXIT_CODE=0
mgx_try mgx_conda assembly \
    salmon quant \
        -i "${INDEX_DIR}" \
        -l A \
        -p "${CPUS}" \
        --meta \
        --validateMappings \
        -1 "${INPUT_R1}" \
        -2 "${INPUT_R2}" \
        -o "${RESULT_DIR}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] salmon quant 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${QUANT_SF}" ] || [ ! -s "${QUANT_SF}" ]; then
    echo "[ERROR] quant.sf 未生成或为空: ${QUANT_SF}"
    exit 1
fi

# --- 统计摘要 ---

N_GENES=$(tail -n+2 "${QUANT_SF}" | wc -l 2>/dev/null || echo "N/A")
N_MAPPED=$(awk 'NR>1 && $5>0 {sum+=$5} END{print sum+0}' "${QUANT_SF}" 2>/dev/null || echo "N/A")

echo ""
echo "[salmon-quant] ${SAMPLE} 定量完成"
echo "[salmon-quant] 结果: ${QUANT_SF}"
echo "    定量基因数:    ${N_GENES}"
echo "    有 reads 基因: ${N_MAPPED}"
echo ""
echo "[提示] 所有样本完成后运行: salmon quantmerge 合并 TPM 和 Count 矩阵"
mgx_end "salmon-quant"
