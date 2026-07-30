#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 71_fun_kraken2_fungi.sh
# 功  能: Kraken2 + Bracken 真菌物种分类（k-mer 比对，PlusPF 数据库同时覆盖细菌/真菌）
#         工具版本：Kraken2 v2.1.3 + Bracken v2.x（conda env: kraken2）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/kraken2/${SAMPLE}/
#           ${SAMPLE}.report             — Kraken2 标准报告（下游 Bracken 输入）
#           ${SAMPLE}.output.gz          — 每条 read 分类结果（压缩）
#           bracken/${SAMPLE}_S.bracken  — 种级丰度估计（主要结果）
#           bracken/${SAMPLE}_G.bracken  — 属级丰度估计
#           bracken/${SAMPLE}_P.bracken  — 门级丰度估计
#
# ── 数据库说明 ────────────────────────────────────────────────────────────────
#   PlusPF 数据库覆盖 Bacteria+Archaea+Viruses+Fungi+Protozoa
#   ${REPO}/db/kraken2/pluspf/ (~77G)
#
# 参  考: Wood et al. Genome Biology 2019; Lu et al. PeerJ 2017
# 用  法: bash 71_fun_kraken2_fungi.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--confidence 0.1] [--read-len 150]
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 71_fun_kraken2_fungi.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16）
  -w  工作目录（Project 路径）
  -r  MaxMetagenome 项目根目录

可选参数:
  --confidence  Kraken2 置信度阈值（默认 0.1，范围 0.0-1.0）
  --read-len    测序读长，用于 Bracken（默认 150，可选 100/250）

示例:
  bash 71_fun_kraken2_fungi.sh -s SRR28210342 -t 16 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
CONFIDENCE="0.1"; READ_LEN="150"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";       shift 2 ;;
        -t) CPUS="$2";         shift 2 ;;
        -w) WORKDIR="$2";      shift 2 ;;
        -r) REPO="$2";         shift 2 ;;
        --confidence) CONFIDENCE="$2"; shift 2 ;;
        --read-len)   READ_LEN="$2";   shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-s/-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/fungi/kraken2/${SAMPLE}"
BRACKEN_DIR="${RESULT_DIR}/bracken"
DB_KRAKEN="${REPO}/db/kraken2/pluspf"
REPORT="${RESULT_DIR}/${SAMPLE}.report"
OUTPUT_GZ="${RESULT_DIR}/${SAMPLE}.output.gz"

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] R1 不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] R2 不存在: ${INPUT_R2}"; exit 1; fi
if [ ! -d "${DB_KRAKEN}" ] || [ -z "$(ls -A "${DB_KRAKEN}" 2>/dev/null)" ]; then
    echo "[ERROR] 数据库目录为空: ${DB_KRAKEN}"; exit 1
fi

BRACKEN_S="${BRACKEN_DIR}/${SAMPLE}_S.bracken"
if [ ${FORCE} -eq 0 ] && [ -f "${BRACKEN_S}" ] && [ -s "${BRACKEN_S}" ]; then
    echo "[INFO] 结果已存在，跳过: ${SAMPLE}"; exit 0
fi

mkdir -p "${RESULT_DIR}" "${BRACKEN_DIR}"

echo "[fun_kraken2] 开始真菌物种分类: ${SAMPLE}"
echo "[fun_kraken2] 线程: ${CPUS}，置信度: ${CONFIDENCE}，读长: ${READ_LEN}"

set +e
conda run --prefix "${REPO}/envs/kraken2" --no-capture-output \
    kraken2 \
        --db "${DB_KRAKEN}" \
        --threads "${CPUS}" \
        --paired "${INPUT_R1}" "${INPUT_R2}" \
        --use-names \
        --report-zero-counts \
        --confidence "${CONFIDENCE}" \
        --report "${REPORT}" \
        --output - \
    | gzip -c > "${OUTPUT_GZ}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] Kraken2 失败（exit: ${EXIT_CODE}）"; exit ${EXIT_CODE}; fi
if [ ! -f "${REPORT}" ] || [ ! -s "${REPORT}" ]; then echo "[ERROR] Report 未生成"; exit 1; fi

echo "[fun_kraken2] Kraken2 完成，运行 Bracken 丰度重估..."

for LEVEL in S G P; do
    conda run --prefix "${REPO}/envs/kraken2" --no-capture-output \
        bracken \
            -d "${DB_KRAKEN}" \
            -i "${REPORT}" \
            -r "${READ_LEN}" \
            -l "${LEVEL}" \
            -t 10 \
            -o "${BRACKEN_DIR}/${SAMPLE}_${LEVEL}.bracken" \
            -w "${BRACKEN_DIR}/${SAMPLE}_${LEVEL}.report" || \
        echo "[WARN] Bracken ${LEVEL} 失败，跳过"
done

echo "[fun_kraken2] ${SAMPLE} 完成，耗时 ${SECONDS}s | 结果: ${RESULT_DIR}/"
echo "[提示] 使用 Bracken 分类结果提取真菌 reads 供 78_fun_megahit.sh 组装"
