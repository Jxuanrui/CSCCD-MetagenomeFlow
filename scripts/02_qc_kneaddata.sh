#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 02_qc_kneaddata.sh
# 功  能: 宏基因组双端测序数据去宿主（人/鼠/大鼠参考基因组去污染）
# 依  赖: 01_qc_fastp.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/fastp/${SAMPLE}/${SAMPLE}_1.fastq.gz
#         ${WORKDIR}/result/fastp/${SAMPLE}/${SAMPLE}_2.fastq.gz
# 输  出: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/stats.txt
# 用  法: bash 02_qc_kneaddata.sh -s SAMPLE -t THREADS -w WORKDIR -r REPO
# ==============================================================================

set -e

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# ===== 参数解析 =====
show_help() {
cat << EOF
用法: bash $(basename "$0") -s SAMPLE -t THREADS -w WORKDIR -r REPO

必需参数:
  -s SAMPLE    样本名称（不含 _1/_2 后缀）
  -t THREADS   线程数
  -w WORKDIR   工作目录（Project/xxx）
  -r REPO      仓库根目录

示例:
  bash scripts/02_qc_kneaddata.sh -s S1 -t 16 -w Project/Project_example -r /path/to/CSCCD-MetagenomeFlow

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:THREADS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE THREADS WORKDIR REPO

# ===== 路径和环境 =====
FASTP_OUT="${WORKDIR}/result/fastp/${SAMPLE}"
INPUT_R1="${FASTP_OUT}/${SAMPLE}_1.fastq.gz"
INPUT_R2="${FASTP_OUT}/${SAMPLE}_2.fastq.gz"

OUTDIR="${WORKDIR}/result/kneaddata/${SAMPLE}"
LOGFILE="${OUTDIR}/kneaddata.log"

# kneaddata 宿主数据库（人类基因组）
DB_HOST="${REPO}/db/kneaddata/human"

# 检查输入文件
if [ ! -f "$INPUT_R1" ] || [ ! -f "$INPUT_R2" ]; then
  echo "[ERROR] 输入文件不存在，请先运行 01_qc_fastp.sh"
  echo "  期望: $INPUT_R1"
  echo "  期望: $INPUT_R2"
  exit 1
fi

# 检查宿主数据库
if [ ! -d "$DB_HOST" ]; then
  echo "[ERROR] 宿主数据库不存在: $DB_HOST"
  echo "  请先运行数据库安装脚本（§8.1 kneaddata database）"
  exit 1
fi

# 检查是否已存在结果
# 注: 本脚本输出为中间产物（.kneaddata_raw），最终路径由 02b_qc_pair_repair.sh
# 严格重新配对后产出，供下游全部引用（详见 02b 脚本头注释）
FINAL_R1="${OUTDIR}/${SAMPLE}_1.kneaddata_raw.fastq.gz"
FINAL_R2="${OUTDIR}/${SAMPLE}_2.kneaddata_raw.fastq.gz"
if [ ${FORCE} -eq 0 ] && [ -f "$FINAL_R1" ] && [ -f "$FINAL_R2" ]; then
  echo "[INFO] 输出文件已存在，跳过: ${SAMPLE}"
  exit 0
fi

# 创建输出目录
mkdir -p "${OUTDIR}"

# ===== 运行 kneaddata =====
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始去宿主污染: ${SAMPLE}"
echo "[INFO] 线程数: ${THREADS}"
echo "[INFO] 输入: ${INPUT_R1}, ${INPUT_R2}"
echo "[INFO] 输出: ${OUTDIR}"

# kneaddata 生成临时文件较多，在 temp/ 下运行
TEMP_WORKDIR="${WORKDIR}/temp/kneaddata/${SAMPLE}"
mkdir -p "${TEMP_WORKDIR}"

# 运行 kneaddata
mgx_conda kneaddata \
    kneaddata \
    --input1 "${INPUT_R1}" \
    --input2 "${INPUT_R2}" \
    --output "${TEMP_WORKDIR}" \
    --reference-db "${DB_HOST}" \
    --threads "${THREADS}" \
    --bypass-trim \
    --remove-intermediate-output \
    --log-level INFO \
    --log "${LOGFILE}" \
    --output-prefix "${SAMPLE}" \
  2>&1 | tee -a "${LOGFILE}"

# 检查 kneaddata 输出
KNEADDATA_R1="${TEMP_WORKDIR}/${SAMPLE}_paired_1.fastq"
KNEADDATA_R2="${TEMP_WORKDIR}/${SAMPLE}_paired_2.fastq"

if [ ! -f "$KNEADDATA_R1" ] || [ ! -f "$KNEADDATA_R2" ]; then
  echo "[ERROR] kneaddata 运行失败，未生成预期输出文件"
  echo "  期望: $KNEADDATA_R1"
  echo "  期望: $KNEADDATA_R2"
  exit 1
fi

# ===== 压缩并移动结果 =====
echo "[INFO] 压缩结果文件..."
gzip -c "${KNEADDATA_R1}" > "${FINAL_R1}"
gzip -c "${KNEADDATA_R2}" > "${FINAL_R2}"

# 移动日志文件
mv "${TEMP_WORKDIR}/${SAMPLE}.log" "${LOGFILE}" 2>/dev/null || true

# 清理临时文件
rm -rf "${TEMP_WORKDIR}"

# ===== 提取统计信息 =====
echo "[INFO] 提取统计信息..."

# kneaddata 日志中包含统计信息（格式: "Total reads: XXX"）
STATS_FILE="${OUTDIR}/stats.txt"

if [ -f "${LOGFILE}" ]; then
  grep -E "reads|pairs|contaminated|retained" "${LOGFILE}" > "${STATS_FILE}" || echo "无统计信息" > "${STATS_FILE}"
else
  echo "[WARN] 日志文件不存在，无法提取统计信息"
fi

# ===== 完成 =====
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 完成去宿主污染: ${SAMPLE}"
echo "[INFO] 输出文件:"
echo "  R1: ${FINAL_R1} ($(du -h ${FINAL_R1} | cut -f1))"
echo "  R2: ${FINAL_R2} ($(du -h ${FINAL_R2} | cut -f1))"
echo "  日志: ${LOGFILE}"
echo "  统计: ${STATS_FILE}"

exit 0
