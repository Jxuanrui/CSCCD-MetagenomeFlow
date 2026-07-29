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

show_help() { cat << EOF
用法: bash 63_vir_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
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
conda run --prefix "${REPO}/envs/coverm" --no-capture-output \
    coverm genome \
        -p minimap2-sr \
        -t "${CPUS}" \
        -x fasta \
        --min-covered-fraction 0 \
        -m relative_abundance rpkm tpm count covered_bases \
        -d "${VMAGS_DIR}" \
        -1 "${R1}" -2 "${R2}" \
        -o "${OUTFILE}"

echo "[coverm_quant] 完成，耗时 ${SECONDS}s"
