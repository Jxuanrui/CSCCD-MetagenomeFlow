#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 68_vir_iphop.sh
# 功  能: 病毒-宿主关联预测（iPHoP）
#         工具版本：iPHoP 3+（conda env: iphop）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/iphop/
#           Host_prediction_to_genus_m90.csv — 宿主预测表（属级汇总）
#           Host_prediction_to_genome_m90.csv — 宿主预测表（基因组级）
#
# ── 数据库 ────────────────────────────────────────────────────────────────────
#   iPHoP 数据库需预下载至 ${REPO}/db/iphop/
#   下载: iphop download --db_dir ${REPO}/db/iphop/
#
# 参  考: Roux et al. 2024 (iPHoP); Virus_Apptainer_pipline
# 用  法: bash 68_vir_iphop.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 68_vir_iphop.sh -t CPUS -w WORKDIR -r REPO
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
OUTDIR="${WORKDIR}/result/virus/iphop"
SENTINEL="${OUTDIR}/Host_prediction_to_genus_m90.csv"
IPHOP_DB="${REPO}/db/iphop/Jun_2025_pub_rw"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
# R-task 审计 P0-1：DB 缺失原为「WARN+写假哨兵+exit 0」静默降级——宿主预测空结果与
# 真无宿主不可区分（违背 R-26 语义铁律），且 Fig3-e 断供无感知。改为显式失败：
# 写 iphop_db_missing.flag 供区分「基建缺失」与其它错误，跑通时自动清除该旗标。
if [ ! -d "${IPHOP_DB}" ]; then
    echo "[ERROR] iPHoP 数据库不存在（R-task P0-1，基建缺失非数据事实）: ${IPHOP_DB}"
    mkdir -p "${OUTDIR}"
    touch "${OUTDIR}/iphop_db_missing.flag"
    exit 1
fi
rm -f "${OUTDIR}/iphop_db_missing.flag"
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[iphop] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[iphop] 病毒-宿主关联预测 ..."
EXIT_CODE=0
mgx_try mgx_conda iphop \
    iphop predict \
        --fa_file "${VOTU_FA}" \
        --db_dir "${IPHOP_DB}" \
        --out_dir "${OUTDIR}" \
        --num_threads "${CPUS}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[WARN] iphop 失败（exit: ${EXIT_CODE}）"; touch "${SENTINEL}"; fi

mgx_end "iphop"
