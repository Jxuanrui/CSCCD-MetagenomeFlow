#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 31_bac_pcyc.sh
# 功  能: 磷循环功能基因注释（diamond blastp 比对 PCyc 数据库）
#         工具版本：DIAMOND 2.x（conda env: assembly）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/pcyc/pcyc_hits.tsv
#
# 参  考: PCyc database; DIAMOND (Buchfink et al. 2015)
# 用  法: bash 31_bac_pcyc.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 31_bac_pcyc.sh -t CPUS -w WORKDIR -r REPO

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
RESULT_DIR="${WORKDIR}/result/annotation/pcyc"
OUTPUT="${RESULT_DIR}/pcyc_hits.tsv"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"; exit 1
fi

DB_FILE=$(find "${REPO}/db/pcyc" -name "*.dmnd" 2>/dev/null | head -1)
if [ -z "${DB_FILE}" ]; then
    echo "[ERROR] PCyc diamond 数据库未找到: ${REPO}/db/pcyc/*.dmnd"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then
    echo "[31_bac_pcyc] 结果已存在，跳过: ${OUTPUT}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[pcyc] 开始磷循环基因注释 | DB: ${DB_FILE} | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda assembly diamond blastp \
    --db     "${DB_FILE}" \
    --query  "${PROTEIN_NR}" \
    --out    "${OUTPUT}" \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --max-target-seqs 1 \
    --sensitive \
    --threads "${CPUS}" \
    --quiet || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] diamond blastp 失败（exit code: ${EXIT_CODE}）"; rm -f "${OUTPUT}"; exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT}" 2>/dev/null || echo "N/A")
echo "[pcyc] 磷循环基因命中: ${N_HITS} | 输出: ${OUTPUT}"
mgx_end "pcyc"
