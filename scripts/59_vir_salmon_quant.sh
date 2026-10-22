#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 59_vir_salmon_quant.sh
# 功  能: vOTU 样本间丰度定量（Salmon quant）
#         工具版本：Salmon 1.10+（conda env: assembly）
# 依  赖: 58_vir_salmon_build.sh 的索引
# 输  入: Salmon index + kneaddata clean reads
# 输  出: ${WORKDIR}/result/virus/salmon/{sample}/quant.sf
#         ${WORKDIR}/result/virus/salmon/{sample}/report.tsv
#
# 参  考: Patro et al. 2017; Virus_Apptainer_pipline vOTU-quant.sh
# 用  法: bash 59_vir_salmon_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 59_vir_salmon_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin
INDEX_DIR="${WORKDIR}/result/virus/salmon/index"
R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
QUANT_DIR="${WORKDIR}/result/virus/salmon/${SAMPLE}"
REPORT="${QUANT_DIR}/report.tsv"

if [ ! -d "${INDEX_DIR}" ]; then echo "[ERROR] Salmon 索引不存在: ${INDEX_DIR}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${REPORT}" ]; then echo "[salmon_quant] 结果已存在，跳过"; exit 0; fi

mkdir -p "${QUANT_DIR}" "$(dirname "${REPORT}")"

echo "[salmon_quant] ${SAMPLE} | Salmon vOTU 定量 ..."
EXIT_CODE=0
mgx_try mgx_conda assembly \
    salmon quant \
        -i "${INDEX_DIR}" \
        -l A \
        -p "${CPUS}" \
        -1 "${R1}" -2 "${R2}" \
        -o "${QUANT_DIR}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] salmon quant 失败"; exit ${EXIT_CODE}; fi

# 生成简化报告（TPM + counts）
tail -n +2 "${QUANT_DIR}/quant.sf" | \
    awk '{print $1"\t"$2"\t"$4"\t"$5}' > "${REPORT}"

mgx_end "salmon_quant"
