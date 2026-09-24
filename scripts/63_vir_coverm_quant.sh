#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 63_vir_coverm_quant.sh
# 功  能: vMAG 样本间丰度定量（CoverM genome）
#         工具版本：CoverM 0.7+（conda env: coverm）
# 依  赖: 62_vir_checkv_mag.sh 的过滤 vMAGs
# 输  入: 过滤 vMAGs + kneaddata clean reads
# 输  出: ${WORKDIR}/result/virus/coverm_quant/{sample}.tsv
#
# 参  考: CoverM docs; Virus_Apptainer_pipline vmag-quant.sh
# 用  法: bash 63_vir_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 63_vir_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
VMAGS_DIR="${WORKDIR}/result/virus/vmag/vmag_filtered"
[ -d "${VMAGS_DIR}" ] || VMAGS_DIR="${WORKDIR}/result/virus/vmag/bins/vMAG"
OUTFILE="${WORKDIR}/result/virus/coverm_quant/${SAMPLE}.tsv"
R1="${WORKDIR}/temp/qc/kneaddata/${SAMPLE}/${SAMPLE}_1_kneaddata.fastq.gz"
R2="${WORKDIR}/temp/qc/kneaddata/${SAMPLE}/${SAMPLE}_2_kneaddata.fastq.gz"

if [ ! -d "${VMAGS_DIR}" ] || [ -z "$(ls "${VMAGS_DIR}"/*.fasta 2>/dev/null)" ]; then
    echo "[WARN] 无 vMAGs 可定量，创建空输出文件"
    mkdir -p "$(dirname "${OUTFILE}")"
    printf "Genome\tRelative Abundance (%%)\tRPKM\tTPM\tRead Count\tCovered Bases\n" > "${OUTFILE}"
    exit 0
fi
if [ ${FORCE} -eq 0 ] && [ -f "${OUTFILE}" ] && [ -s "${OUTFILE}" ]; then echo "[coverm_quant] 结果已存在，跳过"; exit 0; fi

mkdir -p "$(dirname "${OUTFILE}")"

echo "[coverm_quant] ${SAMPLE} | vMAG 定量 ..."
mgx_conda coverm \
    coverm genome \
        -p minimap2-sr \
        -t "${CPUS}" \
        -x fasta \
        --min-covered-fraction 0 \
        -m relative_abundance rpkm tpm count covered_bases \
        -d "${VMAGS_DIR}" \
        -1 "${R1}" -2 "${R2}" \
        -o "${OUTFILE}"

mgx_end "coverm_quant"
