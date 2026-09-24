#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 84_fun_vfdb.sh
# 功  能: 真菌毒力因子注释（diamond blastp 比对 VFDB，覆盖念珠菌/曲霉等真菌毒力因子）
#         工具版本：DIAMOND 2.x（conda env: assembly）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/vfdb/vfdb_hits.tsv
# 用  法: bash 84_fun_vfdb.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 84_fun_vfdb.sh -t CPUS -w WORKDIR -r REPO

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

RESULT_DIR="${WORKDIR}/result/fungi/vfdb"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
OUTPUT="${RESULT_DIR}/vfdb_hits.tsv"

DB_FILE=$(find "${REPO}/db/vfdb" -name "*.dmnd" 2>/dev/null | head -1)
if [ -z "${DB_FILE}" ]; then echo "[ERROR] VFDB DB 未找到: ${REPO}/db/vfdb/*.dmnd"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then echo "[INFO] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

mapfile -t FAA_FILES < <(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null)
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

echo "[fun_vfdb] 开始真菌毒力因子注释 | DB: ${DB_FILE} | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    diamond blastp \
        --db     "${DB_FILE}" \
        --query  "${COMBINED_FAA}" \
        --out    "${OUTPUT}" \
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
        --evalue 1e-5 \
        --max-target-seqs 1 \
        --sensitive \
        --threads "${CPUS}" \
        --quiet \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] diamond blastp 失败"; rm -f "${OUTPUT}"; exit ${EXIT_CODE}; fi

N_HITS=$(wc -l < "${OUTPUT}" 2>/dev/null || echo "0")
echo "[fun_vfdb] 完成 | 毒力因子: ${N_HITS} | 输出: ${OUTPUT}"
mgx_end "fun_vfdb"
