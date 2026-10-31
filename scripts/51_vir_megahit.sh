#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 51_vir_megahit.sh
# 功  能: 病毒优化宏基因组组装（MEGAHIT，≥1.5kb 最小重叠群筛选）
#         工具版本：MEGAHIT 1.2.9（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh 的 clean reads
# 输  入: ${WORKDIR}/result/kneaddata/{sample}/{sample}_{1,2}.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/virus/assembly/{sample}/{sample}.contigs.fa
#
# 参  考: Li et al. 2015 MEGAHIT; Virus_Apptainer_pipline
# 用  法: bash 51_vir_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 51_vir_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/virus/assembly/${SAMPLE}"
CONTIGS="${OUTDIR}/${SAMPLE}.contigs.fa"

if [ ! -f "${R1}" ]; then echo "[ERROR] R1 missing: ${R1}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${CONTIGS}" ]; then echo "[vir_megahit] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"
MEGA_TMP="${OUTDIR}/_megahit_tmp"

echo "[vir_megahit] ${SAMPLE} | 病毒优化组装 ..."
EXIT_CODE=0
mgx_try mgx_conda assembly \
    megahit -1 "${R1}" -2 "${R2}" \
        -o "${MEGA_TMP}" \
        --out-prefix "${SAMPLE}" \
        -t "${CPUS}" \
        --presets meta-large \
        --min-contig-len 1500 \
        --force \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] megahit 失败"; exit ${EXIT_CODE}; fi

mv "${MEGA_TMP}/${SAMPLE}.contigs.fa" "${CONTIGS}"
rm -rf "${MEGA_TMP}"  # 删中间文件，节省 ~80% 磁盘

mgx_end "vir_megahit"
