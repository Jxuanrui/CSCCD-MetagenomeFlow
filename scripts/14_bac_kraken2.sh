#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 14_bac_kraken2.sh
# 功  能: Kraken2 + Bracken 快速物种分类与丰度估计（k-mer 比对，覆盖细菌/古菌/病毒/真菌）
#         工具版本：Kraken2 v2.1.3 + Bracken v2.x（conda env: kraken2）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/kraken2/${SAMPLE}/
#           ${SAMPLE}.report             — Kraken2 标准报告（下游 Bracken 输入）
#           ${SAMPLE}.output.gz          — 每条 read 分类结果（压缩存储，大文件）
#           bracken/${SAMPLE}_S.bracken  — 种级丰度估计（主要结果）
#           bracken/${SAMPLE}_G.bracken  — 属级丰度估计
#           bracken/${SAMPLE}_P.bracken  — 门级丰度估计
#           bracken/${SAMPLE}_S.report   — Kraken 格式种级报告（可视化用）
#           bracken/${SAMPLE}_G.report
#           bracken/${SAMPLE}_P.report
#
# ── 参数说明 ──────────────────────────────────────────────────────────────────
#
#   --confidence 0.1（默认）
#     Kraken2 置信度阈值：分类某条 read 时，命中 k-mer 比例需超过此阈值。
#     0.0  = 最宽松（最多分类，FPR 高）
#     0.1  = 推荐（肠道宏基因组平衡精度与灵敏度）
#     0.3+ = 高置信度（临床/低生物量样本）
#     参考：Wood et al. Genome Biology 2019; Ye et al. PMC10979606 2024
#
#   --read-len 150（默认）
#     Bracken 读长参数，需与测序数据一致（PE150 填 150，PE100 填 100）。
#     若数据库中无对应读长的 Bracken 索引，需提前运行 bracken-build。
#
#   Bracken -t 10（固定）
#     物种最低 read 数阈值，低于此数的物种不进行丰度重估，避免噪声。
#     参考：Lu et al. PeerJ 2017
#
# ── 数据库说明 ────────────────────────────────────────────────────────────────
#
#   默认使用 PlusPF 数据库（细菌+古菌+病毒+真菌+原生生物）：
#     ${REPO}/db/kraken2/pluspf/   (~77G)
#   如需更快速（内存受限）可改用 Standard 8G 版本，但覆盖度下降。
#
# 参  考: Wood et al. Genome Biology 2019 (Kraken2); Lu et al. PeerJ 2017 (Bracken)
#         Metagenomics Workshop QIB: https://corebio.info/metagenomics-workshop/
#         Nature Protocols 2022: Metagenome analysis using Kraken software suite
# 用  法: bash 14_bac_kraken2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--confidence 0.1] [--read-len 150]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 14_bac_kraken2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16）
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  --confidence  Kraken2 置信度阈值（默认 0.1，范围 0.0-1.0）
  --read-len    测序读长，用于 Bracken（默认 150，可选 100/250）

示例:
  bash 14_bac_kraken2.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

  # 高置信度模式（临床样本）
  bash 14_bac_kraken2.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow --confidence 0.3
EOF
}

CONFIDENCE="0.1"
READ_LEN="150"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="confidence:CONFIDENCE read-len:READ_LEN"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/kraken2/${SAMPLE}"
BRACKEN_DIR="${RESULT_DIR}/bracken"

DB_KRAKEN="${REPO}/db/kraken2/pluspf"

REPORT="${RESULT_DIR}/${SAMPLE}.report"
OUTPUT_GZ="${RESULT_DIR}/${SAMPLE}.output.gz"

# --- 输入检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
if [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    exit 1
fi
if [ ! -d "${DB_KRAKEN}" ] || [ -z "$(ls -A "${DB_KRAKEN}" 2>/dev/null)" ]; then
    echo "[ERROR] Kraken2 数据库目录不存在或为空: ${DB_KRAKEN}"
    echo "        请先下载数据库（参考 0Install.sh §3）"
    exit 1
fi

# --- 幂等性检查 ---

BRACKEN_S="${BRACKEN_DIR}/${SAMPLE}_S.bracken"
if [ ${FORCE} -eq 0 ] && [ -f "${BRACKEN_S}" ] && [ -s "${BRACKEN_S}" ]; then
    echo "[INFO] Kraken2+Bracken 结果已存在，跳过: ${SAMPLE}"
    echo "       ${RESULT_DIR}/"
    exit 0
fi

mkdir -p "${RESULT_DIR}" "${BRACKEN_DIR}"

echo "[kraken2] 开始物种分类: ${SAMPLE}"
echo "[kraken2] 线程: ${CPUS}，置信度: ${CONFIDENCE}，读长: ${READ_LEN}"
echo "[kraken2] 数据库: ${DB_KRAKEN}"

# --- 运行 Kraken2 ---
# --use-names:         输出中包含物种名称（而非仅 taxid）
# --report-zero-counts: 报告所有分类单元（包含 0 read），确保多样本矩阵列一致
# --confidence:        k-mer 命中率阈值，>0.1 过滤低置信度分类
# output 通过管道压缩，避免大文件占用磁盘（原始 output 可达原 fastq 体积）

echo "[kraken2] 运行 Kraken2..."
EXIT_CODE=0
mgx_conda kraken2 \
    kraken2 \
        --db          "${DB_KRAKEN}" \
        --threads     "${CPUS}" \
        --paired      "${INPUT_R1}" "${INPUT_R2}" \
        --use-names \
        --report-zero-counts \
        --confidence  "${CONFIDENCE}" \
        --report      "${REPORT}" \
        --output      - \
    | gzip -c > "${OUTPUT_GZ}" || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] Kraken2 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${REPORT}" ] || [ ! -s "${REPORT}" ]; then
    echo "[ERROR] Kraken2 report 未生成或为空: ${REPORT}"
    exit 1
fi

echo "[kraken2] Kraken2 分类完成，运行 Bracken 丰度重估..."

# --- 运行 Bracken（种/属/门三个分类级别）---
# -r: 读长，需与数据库预构建索引的读长匹配
# -l: 分类级别（S=种 G=属 P=门）
# -t: 最低 read 数阈值，低于此数不进行丰度重估（默认 0，推荐 10 避免噪声）
# -w: 输出 kraken 格式报告（供可视化工具如 Krona 使用）

for LEVEL in S G P; do
    LEVEL_NAME=""
    case "${LEVEL}" in
        S) LEVEL_NAME="种(Species)" ;;
        G) LEVEL_NAME="属(Genus)" ;;
        P) LEVEL_NAME="门(Phylum)" ;;
    esac

    echo "[bracken] 运行 Bracken ${LEVEL_NAME} 级别丰度估计..."

    EXIT_CODE=0
    mgx_try mgx_conda kraken2 \
        bracken \
            -d "${DB_KRAKEN}" \
            -i "${REPORT}" \
            -r "${READ_LEN}" \
            -l "${LEVEL}" \
            -t 10 \
            -o "${BRACKEN_DIR}/${SAMPLE}_${LEVEL}.bracken" \
            -w "${BRACKEN_DIR}/${SAMPLE}_${LEVEL}.report" \
            || EXIT_CODE=$?
    if [ "${EXIT_CODE}" -ne 0 ]; then
        echo "[WARN] Bracken ${LEVEL_NAME} 级别运行失败（exit code: ${EXIT_CODE}），跳过"
    fi
done

# --- 统计摘要 ---

N_SPECIES=$([ -f "${BRACKEN_S}" ] && tail -n+2 "${BRACKEN_S}" | wc -l || echo "N/A")
N_GENUS=$([ -f "${BRACKEN_DIR}/${SAMPLE}_G.bracken" ] && tail -n+2 "${BRACKEN_DIR}/${SAMPLE}_G.bracken" | wc -l || echo "N/A")

echo ""
echo "[kraken2] ${SAMPLE} 完成，置信度: ${CONFIDENCE}"
echo "[kraken2] 结果目录: ${RESULT_DIR}/"
echo "    检测到种数: ${N_SPECIES}"
echo "    检测到属数: ${N_GENUS}"
echo "    关键输出:"
echo "    ├── ${SAMPLE}.report               (Kraken2 全分类报告)"
echo "    ├── ${SAMPLE}.output.gz            (每条 read 分类结果，压缩)"
echo "    ├── bracken/${SAMPLE}_S.bracken    (种级丰度，主要结果)"
echo "    ├── bracken/${SAMPLE}_G.bracken    (属级丰度)"
echo "    └── bracken/${SAMPLE}_P.bracken    (门级丰度)"
echo ""
echo "[提示] 所有样本完成后运行 14b_bac_kraken2_merge.sh 合并丰度矩阵"
mgx_end "kraken2"
