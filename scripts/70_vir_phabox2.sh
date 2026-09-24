#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 70_vir_phabox2.sh
# 功  能: 病毒端到端分析与分类预测（PhaBox2）
#         工具版本：PhaBox2 2.1.12（conda env: phabox2）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/phabox2/
#           phabox2_summary.tsv         — PhaBox2 汇总结果
#           predict/                    — PhaBox2 原始输出目录
#
# ── 数据库 ────────────────────────────────────────────────────────────────────
#   PhaBox2 数据库需预放置于 ${REPO}/db/phabox2_db
#
# 参  考: Shang et al. 2024 Briefings in Bioinformatics (PhaBox2)
# 用  法: bash 70_vir_phabox2.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 70_vir_phabox2.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/phabox2"
SENTINEL="${OUTDIR}/phabox2_summary.tsv"
PHABOX_DB="${REPO}/db/phabox2_db"
PREDICT_DIR="${OUTDIR}/predict"
PREDICT_SUMMARY="${PREDICT_DIR}/final_prediction/final_prediction_summary.tsv"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ ! -d "${PHABOX_DB}" ]; then echo "[ERROR] PhaBox2 数据库不存在: ${PHABOX_DB}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[phabox2] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[phabox2] 病毒端到端分析 ..."
mgx_conda phabox2 \
    phabox2 --task end_to_end \
        --dbdir "${PHABOX_DB}" \
        --outpth "${PREDICT_DIR}" \
        --contigs "${VOTU_FA}" \
        --len 500 \
        --threads "${CPUS}"

if [ ! -f "${PREDICT_SUMMARY}" ] || [ ! -s "${PREDICT_SUMMARY}" ]; then
    echo "[ERROR] PhaBox2 输出不存在: ${PREDICT_SUMMARY}"
    exit 1
fi

cp "${PREDICT_SUMMARY}" "${SENTINEL}"

echo "[phabox2] 输出: ${SENTINEL}"
mgx_end "phabox2"
