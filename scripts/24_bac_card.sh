#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 24_bac_card.sh
# 功  能: 抗生素耐药基因综合注释（CARD/RGI）
#         工具版本：RGI 6.x + CARD 3.x（conda env: amr）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/card/
#           rgi_results.txt       — RGI 文本报告（含 Best_Hit_ARO、抗性机制等）
#           rgi_results.json      — RGI JSON 报告（下游分析用）
#
# ── 关键参数 ──────────────────────────────────────────────────────────────────
#   --alignment_tool DIAMOND      — 使用 DIAMOND 加速（比 BLAST 快 100x）
#   --local                       — 本地 CARD 数据库（离线）
#   --clean                       — 删除临时文件（节省磁盘）
#
# 参  考: Alcock et al. 2023 NAR (CARD); McArthur et al. 2013 AAC (RGI)
# 用  法: bash 24_bac_card.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 24_bac_card.sh -t CPUS -w WORKDIR -r REPO

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

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/card"
OUTPUT_PREFIX="${RESULT_DIR}/rgi_results"
CARD_DB="${REPO}/db/card/card.json"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"; exit 1
fi

if [ ! -f "${CARD_DB}" ]; then
    echo "[ERROR] CARD 数据库不存在: ${CARD_DB}"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_PREFIX}.txt" ] && [ -s "${OUTPUT_PREFIX}.txt" ]; then
    echo "[24_bac_card] 结果已存在，跳过: ${OUTPUT_PREFIX}.txt"; exit 0
fi

mkdir -p "${RESULT_DIR}"

# rgi --local reads/writes localDB/ relative to CWD; cd ensures load and main share the same localDB
cd "${RESULT_DIR}"

echo "[card] 加载 CARD 本地数据库..."
EXIT_CODE=0
mgx_try mgx_conda amr rgi load \
    --card_json "${CARD_DB}" \
    --local || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] rgi load 失败（exit code: ${EXIT_CODE}）"; exit ${EXIT_CODE}
fi

echo "[card] 开始 RGI 耐药基因注释 | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda amr rgi main \
    --input_sequence "${PROTEIN_NR}" \
    --output_file "${OUTPUT_PREFIX}" \
    --input_type protein \
    --alignment_tool DIAMOND \
    --num_threads "${CPUS}" \
    --local \
    --clean \
    --include_loose || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] rgi main 失败（exit code: ${EXIT_CODE}）"; exit ${EXIT_CODE}
fi

N_STRICT=$(awk -F'\t' 'NR>1 && $24=="Strict"' "${OUTPUT_PREFIX}.txt" 2>/dev/null | wc -l || echo "N/A")
N_PERFECT=$(awk -F'\t' 'NR>1 && $24=="Perfect"' "${OUTPUT_PREFIX}.txt" 2>/dev/null | wc -l || echo "N/A")
echo "[card] Perfect: ${N_PERFECT} | Strict: ${N_STRICT} | 输出: ${OUTPUT_PREFIX}.txt"
mgx_end "card"
