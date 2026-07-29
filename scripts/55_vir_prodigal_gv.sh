#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 55_vir_prodigal_gv.sh
# 功  能: 病毒蛋白编码基因预测（Prodigal-gv，病毒遗传密码表）
#         工具版本：Prodigal-gv / Prodigal 2.6.3（conda env: assembly）
# 依  赖: 54_vir_checkv_contig.sh 的病毒 contigs
# 输  入: ${WORKDIR}/result/virus/checkv/{sample}/viruses.fna
# 输  出: ${WORKDIR}/result/virus/prodigal/{sample}/
#           {sample}.faa  — 蛋白序列
#           {sample}.fna  — 基因核酸序列
#           {sample}.gff  — 基因坐标
#
# 参  考: Prodigal-gv (virus-specific genetic code 15); Hyatt et al. 2010
# 用  法: bash 55_vir_prodigal_gv.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 55_vir_prodigal_gv.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
INPUT_FA="${WORKDIR}/result/virus/checkv/${SAMPLE}/viruses.fna"
# fallback: 如果 viruses.fna 不存在，用完整的组合病毒 contigs
[ -f "${INPUT_FA}" ] || INPUT_FA="${WORKDIR}/result/virus/checkv/${SAMPLE}/virus_contigs.fasta"
OUTDIR="${WORKDIR}/result/virus/prodigal/${SAMPLE}"
FAA="${OUTDIR}/${SAMPLE}.faa"
FNA="${OUTDIR}/${SAMPLE}.fna"
GFF="${OUTDIR}/${SAMPLE}.gff"

if [ ! -f "${INPUT_FA}" ]; then echo "[ERROR] 病毒序列不存在: ${INPUT_FA}"; exit 1; fi
if [ -f "${FAA}" ] && [ -s "${FAA}" ]; then echo "[prodigal_gv] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[prodigal_gv] ${SAMPLE} | 病毒基因预测（遗传密码 11 + -p meta）..."
set +e
conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    prodigal \
        -i "${INPUT_FA}" \
        -a "${FAA}" \
        -d "${FNA}" \
        -f gff \
        -o "${GFF}" \
        -p meta

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] prodigal 失败"; exit ${EXIT_CODE}; fi

N_GENES=$(grep -c '^>' "${FAA}" 2>/dev/null || echo 0)
echo "[prodigal_gv] 完成，耗时 ${SECONDS}s | 预测基因: ${N_GENES}"
