#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74_fun_blast_gutdb.sh
# 功  能: DIAMOND blastn 比对肠道真菌参考基因组数据库（gut fungi DB）
#         工具版本：DIAMOND 2.x（conda env: assembly）
#     注: combined.fasta 为核苷酸基因组序列 (WGS)，使用 blastn 而非 blastx
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/blast_gutdb/${SAMPLE}/${SAMPLE}_blast.tsv
# 用  法: bash 74_fun_blast_gutdb.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 74_fun_blast_gutdb.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; exit 1; fi; done

SECONDS=0

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/fungi/blast_gutdb/${SAMPLE}"
OUTPUT_TSV="${OUTDIR}/${SAMPLE}_blast.tsv"
TMP_FASTQ="${OUTDIR}/${SAMPLE}_merged.fastq.gz"
DB_FILE=""

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi

if [ -f "${REPO}/db/fungi/gut_fungi.dmnd" ]; then
    DB_FILE="${REPO}/db/fungi/gut_fungi.dmnd"
else
    DB_FILE=$(find "${REPO}/db/fungi" -maxdepth 1 -name "*.dmnd" 2>/dev/null | head -1)
fi
if [ -z "${DB_FILE}" ]; then
    echo "[ERROR] 未找到真菌 DIAMOND 数据库: ${REPO}/db/fungi/"
    echo "        期望文件: ${REPO}/db/fungi/gut_fungi.dmnd"
    echo "        构建示例: diamond makedb --in gut_fungi.fa -d ${REPO}/db/fungi/gut_fungi"
    exit 1
fi

if [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"
zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${TMP_FASTQ}"

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    diamond blastn \
        --db "${DB_FILE}" \
        --query "${TMP_FASTQ}" \
        --out "${OUTPUT_TSV}" \
        --outfmt 6 qseqid sseqid pident length evalue bitscore staxids \
        --evalue 1e-5 \
        --max-target-seqs 1 \
        --threads "${CPUS}" \
        --sensitive
EXIT_CODE=$?
rm -f "${TMP_FASTQ}"
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] diamond blastx 失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT_TSV}" 2>/dev/null || echo "0")
echo "[fun_blast_gutdb] 完成，耗时 ${SECONDS}s | 命中: ${N_HITS}"

