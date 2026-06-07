#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 30_bac_ncyc.sh
# 功  能: 氮循环功能基因注释（diamond blastp 比对 NCyc 数据库）
#         工具版本：DIAMOND 2.x（conda env: assembly）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/ncyc/ncyc_hits.tsv
#
# 参  考: Tu et al. 2019 mBio (NCyc); DIAMOND (Buchfink et al. 2015)
# 用  法: bash 30_bac_ncyc.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 30_bac_ncyc.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""
WORKDIR=""
REPO=""

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
    echo "[ERROR] 缺少必需参数（-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/ncyc"
OUTPUT="${RESULT_DIR}/ncyc_hits.tsv"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"; exit 1
fi

DB_FILE=$(find "${REPO}/db/ncyc" -name "*.dmnd" 2>/dev/null | head -1)
if [ -z "${DB_FILE}" ]; then
    echo "[ERROR] NCyc diamond 数据库未找到: ${REPO}/db/ncyc/*.dmnd"; exit 1
fi

if [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then
    echo "[INFO] NCyc 注释结果已存在，跳过: ${OUTPUT}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[ncyc] 开始氮循环基因注释 | DB: ${DB_FILE} | 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    diamond blastp \
        --db     "${DB_FILE}" \
        --query  "${PROTEIN_NR}" \
        --out    "${OUTPUT}" \
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
        --evalue 1e-5 \
        --max-target-seqs 1 \
        --sensitive \
        --threads "${CPUS}" \
        --quiet

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] diamond blastp 失败（exit code: ${EXIT_CODE}）"; rm -f "${OUTPUT}"; exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT}" 2>/dev/null || echo "N/A")
echo "[ncyc] 完成，耗时 ${SECONDS}s | 氮循环基因命中: ${N_HITS} | 输出: ${OUTPUT}"
