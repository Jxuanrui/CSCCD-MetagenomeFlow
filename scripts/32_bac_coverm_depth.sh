#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 32_bac_coverm_depth.sh
# 功  能: 计算 contig 覆盖度深度（CoverM + minimap2）
#         输出 MetaBAT2/SemiBin2 所需的深度表和 BAM
#         工具版本：CoverM 0.7+（conda env: coverm）
# 依  赖: 01_qc_fastp.sh → 02_qc_kneaddata.sh（clean reads）
#         16_bac_megahit.sh（contigs）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/temp/qc/kneaddata/{sample}/{sample}_1/2.kneaddata.clean.fastq.gz
# 输  出: ${WORKDIR}/result/binning/coverm/{sample}/
#           {sample}.bam        — 排序后的 BAM（SemiBin2 输入）
#           depth.txt            — MetaBAT2/MaxBin2 格式深度表
#
# 参  考: CoverM docs; Woodcroft et al. (CoverM)
# 用  法: bash 32_bac_coverm_depth.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 32_bac_coverm_depth.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
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
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数 -$(echo ${v:0:1} | tr '[:upper:]' '[:lower:]')"; show_help; exit 1; fi
done

SECONDS=0
CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/binning/coverm/${SAMPLE}"
BAM="${OUTDIR}/${SAMPLE}.bam"
DEPTH="${OUTDIR}/depth.txt"
R1="${WORKDIR}/temp/qc/kneaddata/${SAMPLE}/${SAMPLE}_1_kneaddata.fastq.gz"
R2="${WORKDIR}/temp/qc/kneaddata/${SAMPLE}/${SAMPLE}_2_kneaddata.fastq.gz"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing: ${CONTIGS}"; exit 1; fi

if [ -f "${DEPTH}" ] && [ -s "${DEPTH}" ] && [ -f "${BAM}" ] && [ -s "${BAM}" ]; then
    echo "[coverm] depth 和 BAM 已存在，跳过"; exit 0
fi

mkdir -p "${OUTDIR}"

if [ ! -f "${BAM}" ] || [ ! -s "${BAM}" ]; then
    echo "[coverm] 步骤 1/2: minimap2 比对生成 BAM ..."
    conda run --prefix "${REPO}/envs/coverm" --no-capture-output \
        coverm make \
            -p minimap2-sr \
            -t "${CPUS}" \
            -r "${CONTIGS}" \
            -1 "${R1}" -2 "${R2}" \
            -o "${OUTDIR}"
    # coverm make 默认输出 ${SAMPLE}.bam 到 -o 目录
    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm make 失败"; exit ${EXIT_CODE}; fi
fi

if [ ! -f "${DEPTH}" ] || [ ! -s "${DEPTH}" ]; then
    echo "[coverm] 步骤 2/2: 生成深度表 ..."
    conda run --prefix "${REPO}/envs/coverm" --no-capture-output \
        coverm contig \
            -t "${CPUS}" \
            --methods metabat \
            --bam-files "${BAM}" \
            -o "${DEPTH}"
    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm contig 失败"; exit ${EXIT_CODE}; fi
fi

echo "[coverm] 完成，耗时 ${SECONDS}s | 输出: ${OUTDIR}/"
