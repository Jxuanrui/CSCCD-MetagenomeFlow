#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 15_bac_centrifuger.sh
# 功  能: Centrifuger 蛋白级精确物种分类（GTDB R226 + RefSeq，FM-index + 无损压缩）
#         工具版本：Centrifuger v1.0.5（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/centrifuger/${SAMPLE}/
#           ${SAMPLE}.classifications.tsv.gz  — 每条 read 分类结果（压缩，大文件）
#           ${SAMPLE}.kreport.tsv             — Kraken2 兼容格式报告（主要结果）
#
# ── 工具对比定位 ─────────────────────────────────────────────────────────────
#
#   与同流程中其他分类工具的差异：
#   - MetaPhlAn4（脚本 11）：基于 Marker gene，精度高，仅覆盖已知物种
#   - Kraken2（脚本 14）：k-mer 索引，速度最快，精度中等
#   - Centrifuger（本脚本）：FM-index + 蛋白级比对，精度最高（尤其种/属级），
#     但速度慢 2-3×（比 Kraken2 慢约 2.3×），适合需要精确分类的正式分析
#
# ── 数据库说明 ────────────────────────────────────────────────────────────────
#
#   数据库：GTDB R226 + RefSeq HVFC（166 GB）
#     ${REPO}/db/centrifuger/cfr_gtdb_r226+refseq_hvfc.*
#   包含 7 个索引文件（.1.cfr, .2.cfr, .3.cfr, .4.cfr 等）
#   涵盖 GTDB 所有细菌/古菌 + RefSeq 病毒/真菌/人类序列
#
# ── 输出格式说明 ──────────────────────────────────────────────────────────────
#
#   classifications.tsv（制表符分隔，压缩为 .gz）：
#     readID  seqID  taxID  score  ...
#   kreport.tsv（Kraken2 兼容格式，供下游统计分析使用）：
#     %_covered  num_reads  num_unique  rank  taxID  name
#
# 参  考: Song & Langmead, Genome Biology 2024 (Centrifuger)
#         https://github.com/mourisl/centrifuger
# 用  法: bash 15_bac_centrifuger.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 15_bac_centrifuger.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16，内存需求 ≥100G）
  -w  工作目录（Project 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash 15_bac_centrifuger.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/centrifuger/${SAMPLE}"

DB_INDEX="${REPO}/db/centrifuger/cfr_gtdb_r226+refseq_hvfc"

CLASSIF_GZ="${RESULT_DIR}/${SAMPLE}.classifications.tsv.gz"
KREPORT="${RESULT_DIR}/${SAMPLE}.kreport.tsv"

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
# 检查数据库第一个分块文件是否存在
if [ ! -f "${DB_INDEX}.1.cfr" ]; then
    echo "[ERROR] Centrifuger 数据库索引不存在: ${DB_INDEX}.1.cfr"
    echo "        请先下载数据库（参考 0Install.sh §4）"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${KREPORT}" ] && [ -s "${KREPORT}" ]; then
    echo "[INFO] Centrifuger 结果已存在，跳过: ${SAMPLE}"
    echo "       ${RESULT_DIR}/"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[centrifuger] 开始蛋白级物种分类: ${SAMPLE}"
echo "[centrifuger] 线程: ${CPUS}"
echo "[centrifuger] 数据库: ${DB_INDEX} (GTDB R226 + RefSeq, ~166G)"
echo "[centrifuger] 预计耗时 30-90 分钟（取决于样本大小），请耐心等待"

# --- 运行 Centrifuger ---
# 输出通过管道直接压缩，避免大文件占用磁盘（.tsv 原始输出体积可达 fastq 大小）
# 分类结果先写入临时文件，然后传给 centrifuger-kreport 生成报告

CLASSIF_TMP="${RESULT_DIR}/${SAMPLE}.classifications.tsv"

echo "[centrifuger] Step 1/2: 运行 centrifuger 分类..."

EXIT_CODE=0
mgx_try mgx_conda assembly \
    bash -c "centrifuger \
        -x    '${DB_INDEX}' \
        -1    '${INPUT_R1}' \
        -2    '${INPUT_R2}' \
        -t    '${CPUS}' \
        > '${CLASSIF_TMP}'" \
    || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] centrifuger 运行失败（exit code: ${EXIT_CODE}）"
    rm -f "${CLASSIF_TMP}"
    exit ${EXIT_CODE}
fi

if [ ! -f "${CLASSIF_TMP}" ] || [ ! -s "${CLASSIF_TMP}" ]; then
    echo "[ERROR] centrifuger 输出文件未生成或为空: ${CLASSIF_TMP}"
    exit 1
fi

echo "[centrifuger] Step 2/2: 生成 Kraken2 格式报告..."

EXIT_CODE=0
mgx_try mgx_conda assembly \
    centrifuger-kreport \
        -x "${DB_INDEX}" \
        "${CLASSIF_TMP}" \
        > "${KREPORT}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] centrifuger-kreport 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# 压缩大文件（通常 500M-2G）
echo "[centrifuger] 压缩原始分类文件..."
gzip -c "${CLASSIF_TMP}" > "${CLASSIF_GZ}" && rm -f "${CLASSIF_TMP}"

# --- 统计摘要 ---

N_SPECIES=$(awk '$4 == "S" && $2 > 0' "${KREPORT}" 2>/dev/null | wc -l || echo "N/A")
N_GENUS=$(awk '$4 == "G" && $2 > 0' "${KREPORT}" 2>/dev/null | wc -l || echo "N/A")

echo ""
echo "[centrifuger] ${SAMPLE} 完成"
echo "[centrifuger] 结果目录: ${RESULT_DIR}/"
echo "    检测到种数: ${N_SPECIES}"
echo "    检测到属数: ${N_GENUS}"
echo "    关键输出:"
echo "    ├── ${SAMPLE}.kreport.tsv              (Kraken 格式报告，主要结果)"
echo "    └── ${SAMPLE}.classifications.tsv.gz   (每条 read 分类，压缩存储)"
mgx_end "centrifuger"
