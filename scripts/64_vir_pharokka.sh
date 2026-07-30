#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 64_vir_pharokka.sh
# 功  能: 病毒基因组端到端注释（PHAROKKA + PHROG，含 ARG）
#         工具版本：PHAROKKA 1.7+（conda env: pharokka）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 代表序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/pharokka/
#           pharokka.gff          — GFF 注释
#           prodigal-gv.faa       — 预测蛋白（vOTU）
#           pharokka_cds_final_merged_output.tsv — CDS 汇总
#
# 参  考: Terzian et al. 2023 Microb Genom (PHAROKKA)
# 用  法: bash 64_vir_pharokka.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 64_vir_pharokka.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/pharokka"
SENTINEL="${OUTDIR}/pharokka_cds_final_merged_output.tsv"
PHAROKKA_DB="${REPO}/db/pharokka"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[pharokka] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

set +e
echo "[pharokka] vOTU 病毒基因组注释 ..."
conda run --prefix "${REPO}/envs/pharokka" --no-capture-output \
    pharokka.py \
        -i "${VOTU_FA}" \
        -o "${OUTDIR}" \
        -d "${PHAROKKA_DB}" \
        -t "${CPUS}" \
        -f \
        --skip_extra_annotations \
        --skip_mash

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] pharokka 失败"; exit ${EXIT_CODE}; fi

echo "[pharokka] 完成，耗时 ${SECONDS}s"
