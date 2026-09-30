#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74_fun_blast_gutdb.sh
# 功  能: DIAMOND blastx 比对肠道真菌参考基因组数据库（gut fungi DB）
#         工具版本：DIAMOND 2.x（conda env: assembly）
#     注: combined.fasta 为核苷酸基因组序列 (WGS)，使用 DIAMOND blastx 按
#          6-框翻译比对。DMND 数据库通过 diamond makedb --ignore-warnings 构建。
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/blast_gutdb/${SAMPLE}/${SAMPLE}_blast.tsv
# 用  法: bash 74_fun_blast_gutdb.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 74_fun_blast_gutdb.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/fungi/blast_gutdb/${SAMPLE}"
OUTPUT_TSV="${OUTDIR}/${SAMPLE}_blast.tsv"
TMP_FASTQ="${OUTDIR}/${SAMPLE}_merged.fastq.gz"
DB_FILE=""

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi

# 自动搜索 DIAMOND 数据库
if [ -f "${REPO}/db/fungi/gut_fungi.dmnd" ]; then
    DB_FILE="${REPO}/db/fungi/gut_fungi.dmnd"
else
    DB_FILE=$(find "${REPO}/db/fungi" -maxdepth 1 -name "*.dmnd" 2>/dev/null | head -1)
fi
if [ -z "${DB_FILE}" ]; then
    echo "[ERROR] 未找到真菌 DIAMOND 数据库: ${REPO}/db/fungi/"
    echo "        期望文件: ${REPO}/db/fungi/gut_fungi.dmnd"
    echo "        构建示例: diamond makedb --in combined.fasta -d ${REPO}/db/fungi/gut_fungi --ignore-warnings"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"
zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${TMP_FASTQ}"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    diamond blastx \
        --db "${DB_FILE}" \
        --query "${TMP_FASTQ}" \
        --out "${OUTPUT_TSV}" \
        --outfmt 6 qseqid sseqid pident length evalue bitscore \
        --evalue 1e-5 \
        --max-target-seqs 5 \
        --threads "${CPUS}" \
        --sensitive \
        || EXIT_CODE=$?
rm -f "${TMP_FASTQ}"
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] diamond blastx 失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT_TSV}" 2>/dev/null || echo "0")
echo "[fun_blast_gutdb] 完成 | 命中: ${N_HITS}"
mgx_end "fun_blast_gutdb"
