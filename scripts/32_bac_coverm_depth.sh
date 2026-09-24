#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 32_bac_coverm_depth.sh
# 功  能: 计算 contig 覆盖度深度（CoverM + minimap2）
#         输出 MetaBAT2/SemiBin2 所需的深度表和 BAM
#         工具版本：CoverM 0.7+（conda env: coverm）
# 依  赖: 01_qc_fastp.sh → 02_qc_kneaddata.sh（clean reads）
#         16_bac_megahit.sh（contigs）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/binning/coverm/{sample}/
#           {sample}.bam        — 排序后的 BAM（SemiBin2 输入）
#           depth.txt            — MetaBAT2/MaxBin2 格式深度表
#
# 参  考: CoverM docs; Woodcroft et al. (CoverM)
# 用  法: bash 32_bac_coverm_depth.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 32_bac_coverm_depth.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
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
CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/binning/coverm/${SAMPLE}"
BAM="${OUTDIR}/${SAMPLE}.bam"
DEPTH="${OUTDIR}/depth.txt"
R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing: ${CONTIGS}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${DEPTH}" ] && [ -s "${DEPTH}" ] && [ -f "${BAM}" ] && [ -s "${BAM}" ]; then
    echo "[coverm] depth 和 BAM 已存在，跳过"; exit 0
fi

mkdir -p "${OUTDIR}"

    set +e
if [ ! -f "${BAM}" ] || [ ! -s "${BAM}" ]; then
    echo "[coverm] 步骤 1/2: minimap2 比对生成 BAM ..."
    mgx_conda coverm \
        coverm make \
            -p minimap2-sr \
            -t "${CPUS}" \
            -r "${CONTIGS}" \
            -1 "${R1}" -2 "${R2}" \
            -o "${OUTDIR}"
    # coverm make 输出 BAM 文件名包含 contig/read 信息，重命名为标准格式
    GENERATED_BAM=$(ls "${OUTDIR}"/*.bam 2>/dev/null | head -1)
    if [ -n "${GENERATED_BAM}" ] && [ "${GENERATED_BAM}" != "${BAM}" ]; then
        mv "${GENERATED_BAM}" "${BAM}"
    fi
    EXIT_CODE=$?
    set -e
    if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm make 失败"; exit ${EXIT_CODE}; fi
fi

    set +e
if [ ! -f "${DEPTH}" ] || [ ! -s "${DEPTH}" ]; then
    echo "[coverm] 步骤 2/2: 生成深度表 ..."
    mgx_conda coverm \
        coverm contig \
            -t "${CPUS}" \
            --methods metabat \
            --bam-files "${BAM}" \
            -o "${DEPTH}"
    EXIT_CODE=$?
    set -e
    if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm contig 失败"; exit ${EXIT_CODE}; fi
fi

echo "[coverm] 输出: ${OUTDIR}/"
mgx_end "coverm"
