#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 52_vir_genomad.sh
# 功  能: 病毒/质粒鉴定 + 生活方式预测（geNomad 端到端）
#         工具版本：geNomad 1.11+（conda env: genomad）
# 依  赖: 51_vir_megahit.sh 的 contigs
# 输  入: ${WORKDIR}/result/virus/assembly/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/virus/genomad/{sample}/
#           *.contigs_summary/*virus_summary.tsv  — 病毒鉴定汇总
#           *.contigs_annotate/*taxonomy.tsv      — 分类注释
#
# ── 关键参数 ──────────────────────────────────────────────────────────────────
#   --sensitivity 7.5    搜索灵敏度（越高越灵敏，推荐 4.2-7.5）
#   --splits 4           分块数以降低内存
#   --cleanup            删除中间临时文件
#
# 参  考: Camargo et al. 2024 Nature Biotechnol (geNomad)
# 用  法: bash 52_vir_genomad.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 52_vir_genomad.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

FORCE=0
SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
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
CONTIGS="${WORKDIR}/result/virus/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/virus/genomad/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}.contigs_summary/${SAMPLE}.contigs_virus_summary.tsv"
GENOMAD_DB="${REPO}/db/genomad/genomad/genomad_db"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing: ${CONTIGS}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[genomad] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

set +e
echo "[genomad] ${SAMPLE} | geNomad 病毒鉴定 ..."
conda run --prefix "${REPO}/envs/genomad" --no-capture-output \
    genomad end-to-end \
        --cleanup \
        --threads "${CPUS}" \
        --sensitivity 7.5 \
        --splits 4 \
        "${CONTIGS}" \
        "${OUTDIR}" \
        "${GENOMAD_DB}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] genomad 失败"; exit ${EXIT_CODE}; fi

echo "[genomad] 完成，耗时 ${SECONDS}s"
