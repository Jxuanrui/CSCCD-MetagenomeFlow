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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 52_vir_genomad.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
CONTIGS="${WORKDIR}/result/virus/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/virus/genomad/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}.contigs_summary/${SAMPLE}.contigs_virus_summary.tsv"
GENOMAD_DB="${REPO}/db/genomad/genomad/genomad_db"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing: ${CONTIGS}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[genomad] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[genomad] ${SAMPLE} | geNomad 病毒鉴定 ..."
EXIT_CODE=0
mgx_try mgx_conda genomad \
    genomad end-to-end \
        --cleanup \
        --threads "${CPUS}" \
        --sensitivity 7.5 \
        --splits 4 \
        "${CONTIGS}" \
        "${OUTDIR}" \
        "${GENOMAD_DB}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] genomad 失败"; exit ${EXIT_CODE}; fi

mgx_end "genomad"
