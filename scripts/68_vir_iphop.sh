#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 68_vir_iphop.sh
# 功  能: 病毒-宿主关联预测（iPHoP）
#         工具版本：iPHoP 3+（conda env: iphop）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/iphop/
#           iphop_host_prediction.tsv  — 宿主预测表
#
# ── 数据库 ────────────────────────────────────────────────────────────────────
#   iPHoP 数据库需预下载至 ${REPO}/db/iphop/
#   下载: iphop download --db_dir ${REPO}/db/iphop/
#
# 参  考: Roux et al. 2024 (iPHoP); Virus_Apptainer_pipline
# 用  法: bash 68_vir_iphop.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 68_vir_iphop.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/iphop"
SENTINEL="${OUTDIR}/iphop_host_prediction.tsv"
IPHOP_DB="${REPO}/db/iphop"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ ! -d "${IPHOP_DB}" ]; then echo "[WARN] iPHoP 数据库不存在: ${IPHOP_DB}，跳过"; mkdir -p "${OUTDIR}"; touch "${SENTINEL}"; exit 0; fi
if [ -f "${SENTINEL}" ]; then echo "[iphop] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[iphop] 病毒-宿主关联预测 ..."
conda run --prefix "${REPO}/envs/iphop" --no-capture-output \
    iphop predict \
        --fa_file "${VOTU_FA}" \
        --db_dir "${IPHOP_DB}" \
        --out_dir "${OUTDIR}" \
        --num_threads "${CPUS}" \
        --min_length 1000

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[WARN] iphop 失败（exit: ${EXIT_CODE}）"; touch "${SENTINEL}"; fi

echo "[iphop] 完成，耗时 ${SECONDS}s"
