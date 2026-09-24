#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 28_bac_antismash.sh
# 功  能: 次级代谢产物生物合成基因簇（BGC）预测（antiSMASH）
#         工具版本：antiSMASH 8.0.4（conda env: antismash8；Blin et al. 2025，101 cluster types；
#                   旧 7.1.0 env/db 冻结保留可回滚）
# 依  赖: 16_bac_megahit.sh 的输出（{sample}.contigs.fa，≥1000bp）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/antismash/{sample}/
#           {sample}.gbk           — 结果 GenBank 文件
#           {sample}.json          — 结果 JSON（API用）
#           index.html             — 可视化报告
#
# ── 注意 ─────────────────────────────────────────────────────────────────────
#   antiSMASH 按样本运行（per-sample），宏基因组模式下不使用全基因组注释步骤
#   --minimal 可跳过 NCBI taxonomy 查询，但会损失部分注释
#   --taxon bacteria 是宏基因组细菌最常用设置
#
# 参  考: Blin et al. 2025 NAR (antiSMASH 8)
# 用  法: bash 28_bac_antismash.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 28_bac_antismash.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
RESULT_DIR="${WORKDIR}/result/annotation/antismash/${SAMPLE}"
SENTINEL="${RESULT_DIR}/antismash_done.txt"
ANTISMASH_DB="${REPO}/db/antismash8"

if [ ! -f "${CONTIGS}" ] || [ ! -s "${CONTIGS}" ]; then
    echo "[ERROR] 组装文件不存在: ${CONTIGS}"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then
    echo "[INFO] antiSMASH 结果已存在，跳过: ${RESULT_DIR}/"; exit 0
fi

# antiSMASH 不允许写入已存在目录
[ -d "${RESULT_DIR}" ] && rm -rf "${RESULT_DIR}"
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[28_bac_antismash] 结果已存在，跳过: ${SENTINEL}"; exit 0
fi

mkdir -p "$(dirname "${RESULT_DIR}")"

echo "[antismash] 样本: ${SAMPLE} | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda antismash8 \
    antismash \
        "${CONTIGS}" \
        --taxon bacteria \
        --output-dir "${RESULT_DIR}" \
        --cpus "${CPUS}" \
        --databases "${ANTISMASH_DB}" \
        --genefinding-tool prodigal-m \
        --minimal \
        --enable-nrps-pks || EXIT_CODE=$?

if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[antismash] WARNING: antismash 失败（exit: ${EXIT_CODE}），创建空 sentinel"
    mkdir -p "${RESULT_DIR}"
    touch "${SENTINEL}"
    exit 0
fi

N_BGC=$(grep -c '"cluster_blast_hit"' "${RESULT_DIR}"/*.json 2>/dev/null || \
        find "${RESULT_DIR}" -name "*.gbk" | wc -l)
touch "${SENTINEL}"
echo "[antismash] 完成，耗时 ${SECONDS}s | BGC: ${N_BGC} | 输出: ${RESULT_DIR}/"
