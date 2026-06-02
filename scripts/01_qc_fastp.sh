#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 01_qc_fastp.sh
# 功  能: 宏基因组双端测序数据质量控制（接头去除、低质量修剪、统计报告）
# 输  入: ${WORKDIR}/data/${SAMPLE}_1.fastq.gz
#         ${WORKDIR}/data/${SAMPLE}_2.fastq.gz
# 输  出: ${WORKDIR}/result/qc/fastp/${SAMPLE}/${SAMPLE}_1.fastq.gz  (clean reads)
#         ${WORKDIR}/result/qc/fastp/${SAMPLE}/${SAMPLE}_2.fastq.gz
#         ${WORKDIR}/result/qc/fastp/${SAMPLE}/${SAMPLE}.json
#         ${WORKDIR}/result/qc/fastp/${SAMPLE}/${SAMPLE}.html
# 临时文件: ${WORKDIR}/temp/fastp/${SAMPLE}/
# 用  法: bash 01_qc_fastp.sh -s SRR28210342 -t 16 -w /path/to/Project_example -r /path/to/MaxMetagenome
# ==============================================================================

# --- 参数解析 ---

if [ $# -ge 8 ]; then
    while getopts s:t:w:r: option; do
        case "${option}" in
            s) SAMPLE=${OPTARG} ;;
            t) CPUS=${OPTARG} ;;
            w) WORKDIR=${OPTARG} ;;
            r) REPO=${OPTARG} ;;
        esac
    done
else
    echo ""
    echo "用法: bash 01_qc_fastp.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO"
    echo ""
    echo "参数说明:"
    echo "  -s  样本名（不含后缀，如 SRR28210342）"
    echo "  -t  线程数（推荐 8-16）"
    echo "  -w  工作目录（Project_example 路径）"
    echo "  -r  MaxMetagenome 项目根目录"
    echo ""
    echo "示例:"
    echo "  bash 01_qc_fastp.sh -s SRR28210342 -t 16 \\"
    echo "       -w ~/Course/Maxmetagenome/Project/Project_example \\"
    echo "       -r ~/Course/Maxmetagenome"
    exit 1
fi

SECONDS=0

# --- 路径设置 ---

INPUT_DIR=${WORKDIR}/data
TEMP_DIR=${WORKDIR}/temp/fastp/${SAMPLE}
RESULT_DIR=${WORKDIR}/result/qc/fastp/${SAMPLE}

INPUT_R1=${INPUT_DIR}/${SAMPLE}_1.fastq.gz
INPUT_R2=${INPUT_DIR}/${SAMPLE}_2.fastq.gz
OUT_R1=${RESULT_DIR}/${SAMPLE}_1.fastq.gz
OUT_R2=${RESULT_DIR}/${SAMPLE}_2.fastq.gz
OUT_JSON=${RESULT_DIR}/${SAMPLE}.json
OUT_HTML=${RESULT_DIR}/${SAMPLE}.html
FASTP_LOG=${TEMP_DIR}/${SAMPLE}.log

# --- 输入文件检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    exit 1
fi
if [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    exit 1
fi

# --- 创建输出目录 ---

mkdir -p "${TEMP_DIR}" "${RESULT_DIR}"

echo "[fastp] 开始质控: ${SAMPLE}"
echo "[fastp] 输入: ${INPUT_DIR}/${SAMPLE}_*.fastq.gz"
echo "[fastp] 线程: ${CPUS}"

# --- 运行 fastp ---

conda run --prefix "${REPO}/envs/fastp" fastp \
    --in1  "${INPUT_R1}" \
    --in2  "${INPUT_R2}" \
    --out1 "${OUT_R1}" \
    --out2 "${OUT_R2}" \
    --json "${OUT_JSON}" \
    --html "${OUT_HTML}" \
    --detect_adapter_for_pe \
    --qualified_quality_phred 20 \
    --length_required 50 \
    --correction \
    -w "${CPUS}" \
    2> "${FASTP_LOG}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] fastp 运行失败（exit code: ${EXIT_CODE}），查看日志: ${FASTP_LOG}"
    exit ${EXIT_CODE}
fi

# --- 提取关键统计信息 ---

if [ -f "${OUT_JSON}" ] && command -v python3 &>/dev/null; then
    python3 - <<PYEOF
import json, sys
with open("${OUT_JSON}") as f:
    d = json.load(f)
s = d.get("summary", {})
bf = s.get("before_filtering", {})
af = s.get("after_filtering", {})
total_reads   = bf.get("total_reads", "N/A")
passed_reads  = af.get("total_reads", "N/A")
pass_rate     = round(int(passed_reads)/int(total_reads)*100, 2) if str(total_reads).isdigit() else "N/A"
total_bases   = bf.get("total_bases", "N/A")
q20_rate      = round(af.get("q20_rate", 0)*100, 2)
q30_rate      = round(af.get("q30_rate", 0)*100, 2)
print(f"[fastp] 统计: 输入reads={total_reads:,}  通过={passed_reads:,}  通过率={pass_rate}%  Q20={q20_rate}%  Q30={q30_rate}%")
PYEOF
fi

echo "[fastp] ${SAMPLE} 完成，耗时 ${SECONDS}s，结果: ${RESULT_DIR}"
