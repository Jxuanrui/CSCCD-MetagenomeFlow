#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 86_fun_merops.sh
# 功  能: MEROPS 蛋白酶注释（DIAMOND blastp 比对 MEROPS 数据库）
#         工具版本：DIAMOND 2.x（conda env: assembly）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/merops/merops_hits.tsv
# 用  法: bash 86_fun_merops.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 86_fun_merops.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin

OUTDIR="${WORKDIR}/result/fungi/merops"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${OUTDIR}/combined_fungi.faa"
OUTPUT_TSV="${OUTDIR}/merops_hits.tsv"
DB_FILE=$(find "${REPO}/db/merops" -name "*.dmnd" 2>/dev/null | head -1)

if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在: ${PRODIGAL_DIR}"; exit 1; fi
if [ -z "${DB_FILE}" ]; then echo "[ERROR] 未找到 MEROPS 数据库: ${REPO}/db/merops/*.dmnd"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"

mapfile -t FAA_FILES < <(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null | sort)
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    diamond blastp \
        --db "${DB_FILE}" \
        --query "${COMBINED_FAA}" \
        --out "${OUTPUT_TSV}" \
        --outfmt 6 qseqid sseqid pident length evalue bitscore \
        --evalue 1e-5 \
        --max-target-seqs 1 \
        --sensitive \
        --threads "${CPUS}" \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] diamond blastp 失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT_TSV}" 2>/dev/null || echo "0")
N_QUERY=$(grep -c "^>" "${COMBINED_FAA}" 2>/dev/null || echo "0")
echo "[fun_merops] 完成 | 查询蛋白: ${N_QUERY} | 命中: ${N_HITS}"
mgx_end "fun_merops"
