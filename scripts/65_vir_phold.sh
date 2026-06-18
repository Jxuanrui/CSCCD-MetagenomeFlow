#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 65_vir_phold.sh
# 功  能: 结构暗物质 ORF 注释（PHOLD，PHAROKKA 补充）
#         工具版本：PHOLD 1.0+（conda env: phold）
# 依  赖: 64_vir_pharokka.sh 的输出
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/phold/
#           vOTU_phold.tsv     — PHOLD 注释表
#
# 参  考: PHOLD (manual); Virus_Apptainer_pipline phold.sh
# 用  法: bash 65_vir_phold.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 65_vir_phold.sh -t CPUS -w WORKDIR -r REPO
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
OUTDIR="${WORKDIR}/result/virus/phold"
SENTINEL="${OUTDIR}/vOTU_phold.tsv"
PHOLD_DB="${REPO}/db/phold"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ -f "${SENTINEL}" ]; then echo "[phold] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[phold] 结构暗物质 ORF 注释 ..."
conda run --prefix "${REPO}/envs/phold" --no-capture-output \
    phold run \
        -i "${VOTU_FA}" \
        -o "${OUTDIR}" \
        -d "${PHOLD_DB}" \
        -t "${CPUS}" \
        -p vOTU \
        -f \
        --cpu

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] phold 失败"; exit ${EXIT_CODE}; fi

# 汇总输出（phold 直接输出到 OUTDIR，不创建 results/ 子目录）
if [ -f "${OUTDIR}/vOTU_all_cds_functions.tsv" ]; then
    cp "${OUTDIR}/vOTU_all_cds_functions.tsv" "${SENTINEL}"
elif [ -d "${OUTDIR}/results" ]; then
    cat "${OUTDIR}/results/"*.tsv 2>/dev/null > "${SENTINEL}" || true
fi

echo "[phold] 完成，耗时 ${SECONDS}s"
