#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 31b_bac_scyc.sh
# 功  能: 硫循环功能基因注释（diamond blastp 比对 SCyc 数据库）
#         工具版本：DIAMOND 2.x（conda env: assembly）
#         与 30_bac_ncyc.sh / 31_bac_pcyc.sh 完全对称，补全 S 循环维度
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/annotation/scyc/scyc_hits.tsv
#
# ── 参数说明 ──────────────────────────────────────────────────────────────────
#   --evalue 1e-5  : 标准期望值阈值（与 NCyc/PCyc 一致）
#   --id 60        : 60% 序列相似度（SCyc 数据库推荐，保守过滤）
#   --min-score 30 : 最小比特分（过滤低质量比对）
#   --max-target-seqs 1 : 每条 query 保留最佳命中
#
# 参  考: SCyc 数据库（硫循环功能基因 HMM + DIAMOND 索引）
#         https://github.com/ZengJiaxiong/SCyc
#         DIAMOND: Buchfink et al. 2015 Nature Methods
# 用  法: bash 31b_bac_scyc.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 31b_bac_scyc.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

示例:
  bash scripts/31b_bac_scyc.sh -t 16 \\
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

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/scyc"
OUTPUT="${RESULT_DIR}/scyc_hits.tsv"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"
    echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi

DB_FILE="${REPO}/db/scyc/scyc-db/scyc.dmnd"
if [ ! -f "${DB_FILE}" ]; then
    echo "[ERROR] SCyc diamond 数据库未找到: ${DB_FILE}"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then
    echo "[31b_bac_scyc] 结果已存在，跳过: ${OUTPUT}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[scyc] 开始硫循环基因注释 | DB: ${DB_FILE} | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda assembly diamond blastp \
    --db     "${DB_FILE}" \
    --query  "${PROTEIN_NR}" \
    --out    "${OUTPUT}" \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --id 60 \
    --min-score 30 \
    --max-target-seqs 1 \
    --more-sensitive \
    --threads "${CPUS}" \
    --quiet || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] diamond blastp 失败（exit code: ${EXIT_CODE}）"
    rm -f "${OUTPUT}"; exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT}" 2>/dev/null || echo "N/A")
echo "[scyc] 硫循环基因命中: ${N_HITS} | 输出: ${OUTPUT}"
echo "[提示] 下一步可结合 Salmon TPM 矩阵（result/salmon/）计算硫循环基因丰度"
mgx_end "scyc"
