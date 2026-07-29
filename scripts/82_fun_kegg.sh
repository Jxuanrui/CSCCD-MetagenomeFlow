#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 82_fun_kegg.sh
# 功  能: KEGG KO 通路注释（diamond blastp 比对 KEGG 蛋白数据库）
#         工具版本：DIAMOND 2.x（conda env: assembly）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/kegg/kegg_diamond.tsv
# 用  法: bash 82_fun_kegg.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 82_fun_kegg.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数"; show_help; exit 1
fi

SECONDS=0

RESULT_DIR="${WORKDIR}/result/fungi/kegg"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
OUTPUT="${RESULT_DIR}/kegg_diamond.tsv"

DB_FILE=$(find "${REPO}/db/kegg" -name "*.dmnd" 2>/dev/null | head -1)
if [ -z "${DB_FILE}" ]; then echo "[ERROR] KEGG DB 未找到: ${REPO}/db/kegg/*.dmnd"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在"; exit 1; fi

if [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then echo "[INFO] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

FAA_FILES=($(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null))
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

echo "[fun_kegg] 开始 KEGG KO 注释 | DB: ${DB_FILE} | 线程: ${CPUS}"

set +e
conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    diamond blastp \
        --db     "${DB_FILE}" \
        --query  "${COMBINED_FAA}" \
        --out    "${OUTPUT}" \
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
        --evalue 1e-5 \
        --max-target-seqs 1 \
        --sensitive \
        --threads "${CPUS}" \
        --quiet

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] diamond blastp 失败"; rm -f "${OUTPUT}"; exit ${EXIT_CODE}; fi

N_HITS=$(wc -l < "${OUTPUT}" 2>/dev/null || echo "0")
echo "[fun_kegg] 完成，耗时 ${SECONDS}s | 命中: ${N_HITS} | 输出: ${OUTPUT}"
