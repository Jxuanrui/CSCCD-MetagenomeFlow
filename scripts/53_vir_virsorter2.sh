#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 53_vir_virsorter2.sh
# 功  能: 病毒序列预测（VirSorter2，与 geNomad 取交集）
#         工具版本：VirSorter2 2.2+（conda env: virsorter2）
# 依  赖: 51_vir_megahit.sh 的 contigs
# 输  入: ${WORKDIR}/result/virus/assembly/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/virus/virsorter2/{sample}/
#           final-viral-boundary.tsv  — 病毒边界预测
#           final-viral-score.tsv     — 病毒评分
#
# 参  考: Guo et al. 2021 Nat Biotechnol (VirSorter2)
# 用  法: bash 53_vir_virsorter2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 53_vir_virsorter2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
CONTIGS="${WORKDIR}/result/virus/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/virus/virsorter2/${SAMPLE}"
SENTINEL="${OUTDIR}/final-viral-combined.fa"
VS2_DB="${REPO}/db/virsorter2"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing: ${CONTIGS}"; exit 1; fi
if [ ! -d "${VS2_DB}" ]; then echo "[ERROR] VirSorter2 数据库不存在: ${VS2_DB}"; exit 1; fi
if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[virsorter2] 结果已存在，跳过"; exit 0; fi

echo "[virsorter2] ${SAMPLE} | VirSorter2 病毒预测 ..."
# virsorter2 内部会调用 conda info --json 检测 conda 环境
# 需显式传入 CONDA_EXE 确保找到 conda 可执行文件
CONDA_EXE="${REPO}/miniforge3/bin/conda" \
conda run --prefix "${REPO}/envs/virsorter2" --no-capture-output \
    virsorter run --use-conda-off \
        -w "${OUTDIR}" \
        -i "${CONTIGS}" \
        --db-dir "${VS2_DB}" \
        --min-length 1000 \
        --include-groups "dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae" \
        -j "${CPUS}" \
        --verbose 2>&1

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] virsorter2 失败"; exit ${EXIT_CODE}; fi

echo "[virsorter2] 完成，耗时 ${SECONDS}s"
