#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 19_bac_salmon_build.sh
# 功  能: Salmon 基因定量索引构建（基于 CD-HIT NR 非冗余基因集）
#         工具版本：Salmon v1.2.0（conda env: assembly）
# 依  赖: 18_bac_cdhit.sh 的输出（nucleotide_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/nucleotide_nr.fa
# 输  出: ${WORKDIR}/result/assembly/salmon/index/   — Salmon 索引目录（含 info.json）
#
# ── 说明 ──────────────────────────────────────────────────────────────────────
#
#   本步骤为聚合步骤（aggregate），运行一次即可供所有样本的 quant 使用。
#   索引构建完成后运行 20_bac_salmon_quant.sh 对每个样本独立定量。
#
# 参  考: Patro et al. Nature Methods 2017; https://salmon.readthedocs.io
# 用  法: bash 19_bac_salmon_build.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 19_bac_salmon_build.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 8-16）
  -w  工作目录（Project 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash 19_bac_salmon_build.sh -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

NR_FNA="${WORKDIR}/result/assembly/cdhit/nucleotide_nr.fa"
INDEX_DIR="${WORKDIR}/result/assembly/salmon/index"
INDEX_INFO="${INDEX_DIR}/info.json"
SALMON_VERSION_INFO="${INDEX_DIR}/versionInfo.json"

# --- 输入检查 ---

if [ ! -f "${NR_FNA}" ] || [ ! -s "${NR_FNA}" ]; then
    echo "[ERROR] 非冗余基因集不存在: ${NR_FNA}"
    echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${INDEX_INFO}" ]; then
    echo "[INFO] Salmon 索引已存在，跳过"
    echo "       ${INDEX_DIR}/"
    exit 0
fi
if [ -f "${SALMON_VERSION_INFO}" ]; then
    cp "${SALMON_VERSION_INFO}" "${INDEX_INFO}"
    echo "[INFO] 检测到已有 Salmon 索引，已补全 info.json 哨兵文件"
    echo "       ${INDEX_DIR}/"
    exit 0
fi

mkdir -p "${INDEX_DIR}"

echo "[salmon-index] 构建 Salmon 索引"
echo "[salmon-index] 输入: ${NR_FNA}"
echo "[salmon-index] 索引: ${INDEX_DIR}/"
echo "[salmon-index] 线程: ${CPUS}"

# --- 运行 salmon index ---
# -t: 输入核苷酸序列（NR 基因集）
# -i: 索引输出目录
# -p: 线程数
# Salmon 自动选择最优 word size

EXIT_CODE=0
mgx_try mgx_conda assembly \
    salmon index \
        -t "${NR_FNA}" \
        -i "${INDEX_DIR}" \
        -p "${CPUS}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] salmon index 运行失败（exit code: ${EXIT_CODE}）"
    rm -rf "${INDEX_DIR}"
    exit ${EXIT_CODE}
fi

if [ ! -f "${INDEX_INFO}" ]; then
    if [ -f "${SALMON_VERSION_INFO}" ]; then
        cp "${SALMON_VERSION_INFO}" "${INDEX_INFO}"
    else
        echo "[ERROR] 索引文件 info.json 未生成，且未找到 versionInfo.json"
        exit 1
    fi
fi

echo ""
echo "[salmon-index] 索引构建完成"
echo "[salmon-index] 索引目录: ${INDEX_DIR}/"
echo ""
echo "[提示] 下一步: 对每个样本运行 20_bac_salmon_quant.sh 进行基因丰度定量"
mgx_end "salmon-index"
