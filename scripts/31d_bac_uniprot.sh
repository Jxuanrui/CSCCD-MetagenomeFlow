#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 31d_bac_uniprot.sh
# 功  能: UniProt Swiss-Prot 高精度蛋白功能注释（MMseqs2 easy-search）
#         补充 eggNOG/KEGG 未命中条目的功能描述（人工审核蛋白库，高置信度）
#         工具版本：MMseqs2 13.x（conda env: assembly）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/annotation/uniprot_sprot/
#           sprot_hits.tsv       — MMseqs2 比对结果（13 列）
#
# ── 参数说明 ──────────────────────────────────────────────────────────────────
#   --max-accept 1   : 每条 query 保留最佳命中（等效 diamond --max-target-seqs 1）
#   --evalue 1e-5    : 期望值阈值
#   format-output    : query,target,fident,alnlen,mismatch,gapopen,qstart,qend,
#                      tstart,tend,evalue,bits,qcov（与参考 pipeline 一致）
#   DB 索引路径      : db/uniprot_sprot/mmseqs/uniprot_sprot（MMseqs2 格式）
#
# 参  考: UniProt Consortium 2023 NAR; Steinegger & Söding 2017 Nature Comms
#         https://www.uniprot.org/
#         https://github.com/soedinglab/MMseqs2
# 用  法: bash 31d_bac_uniprot.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 31d_bac_uniprot.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 16+）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash scripts/31d_bac_uniprot.sh -t 16 \\
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
RESULT_DIR="${WORKDIR}/result/annotation/uniprot_sprot"
OUTPUT="${RESULT_DIR}/sprot_hits.tsv"
TMP_DIR="${WORKDIR}/temp/uniprot_sprot"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"
    echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi

MMSEQS_DB="${REPO}/db/uniprot_sprot/mmseqs/uniprot_sprot"
if [ ! -f "${MMSEQS_DB}.dbtype" ] && [ ! -d "${REPO}/db/uniprot_sprot/mmseqs" ]; then
    echo "[ERROR] MMseqs2 索引未找到: ${MMSEQS_DB}"
    echo "        请检查 db/uniprot_sprot/mmseqs/ 目录"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then
    echo "[INFO] UniProt Swiss-Prot 注释结果已存在，跳过: ${OUTPUT}"; exit 0
fi

mkdir -p "${RESULT_DIR}" "${TMP_DIR}"

echo "[uniprot] 开始 Swiss-Prot 注释 | 线程: ${CPUS}"
echo "[uniprot] DB: ${MMSEQS_DB}"

EXIT_CODE=0
mgx_try mgx_conda assembly mmseqs easy-search \
    --threads    "${CPUS}" \
    --max-accept 1 \
    -e           1e-5 \
    --format-output "query,target,fident,alnlen,mismatch,gapopen,qstart,qend,tstart,tend,evalue,bits,qcov" \
    -v           1 \
    "${PROTEIN_NR}" \
    "${MMSEQS_DB}" \
    "${OUTPUT}" \
    "${TMP_DIR}" || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] MMseqs2 easy-search 失败（exit code: ${EXIT_CODE}）"
    rm -f "${OUTPUT}"; exit ${EXIT_CODE}
fi

# 清理 MMseqs2 临时文件
rm -rf "${TMP_DIR}"

N_HITS=$(wc -l < "${OUTPUT}" 2>/dev/null || echo "N/A")
N_QUERY=$(grep -c "^>" "${PROTEIN_NR}" 2>/dev/null || echo "N/A")
echo ""
echo "    查询蛋白数: ${N_QUERY}"
echo "    Swiss-Prot 命中: ${N_HITS}"
echo "    输出: ${OUTPUT}"
echo "[提示] 结合 21_bac_eggnog.sh 输出，可识别 eggNOG 未命中但 Swiss-Prot 有功能描述的基因"
mgx_end "uniprot"
