#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 55_vir_prodigal_gv.sh
# 功  能: 病毒蛋白编码基因预测（Prodigal -p meta 模式；标题中的 gv 为历史命名，实际未用密码表 15，meta_gv 属未来候选）
#         工具版本：Prodigal 2.6.3（conda env: assembly），运行参数 -p meta
# 依  赖: 54_vir_checkv_contig.sh 的病毒 contigs
# 输  入: ${WORKDIR}/result/virus/checkv/{sample}/viruses.fna
# 输  出: ${WORKDIR}/result/virus/prodigal/{sample}/
#           {sample}.faa  — 蛋白序列
#           {sample}.fna  — 基因核酸序列
#           {sample}.gff  — 基因坐标
#
# 参  考: Prodigal (Hyatt et al. 2010)；Prodigal-gv/meta_gv (code 15) 记录于未来候选清单，未经 benchmark 不得切换
# 用  法: bash 55_vir_prodigal_gv.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 55_vir_prodigal_gv.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
# T-15: gene prediction runs on the MIUVIG-filtered set, same universe as 56.
INPUT_FA="${WORKDIR}/result/virus/checkv/${SAMPLE}/viruses_filtered.fna"
OUTDIR="${WORKDIR}/result/virus/prodigal/${SAMPLE}"
FAA="${OUTDIR}/${SAMPLE}.faa"
FNA="${OUTDIR}/${SAMPLE}.fna"
GFF="${OUTDIR}/${SAMPLE}.gff"

if [ ! -f "${INPUT_FA}" ]; then echo "[ERROR] 病毒序列不存在: ${INPUT_FA}"; exit 1; fi
# T-15: a sample with 0 MIUVIG-passed contigs is a legal empty state -
# emit empty sentinels instead of failing prodigal on an empty FASTA.
if [ ! -s "${INPUT_FA}" ]; then
    OUTDIR="${WORKDIR}/result/virus/prodigal/${SAMPLE}"
    mkdir -p "${OUTDIR}"
    : > "${OUTDIR}/${SAMPLE}.faa"; : > "${OUTDIR}/${SAMPLE}.fna"; : > "${OUTDIR}/${SAMPLE}.gff"
    echo "[prodigal_gv] ${SAMPLE}: 0 条 MIUVIG 通过 contig，写空哨兵"
    exit 0
fi
if [ ${FORCE} -eq 0 ] && [ -f "${FAA}" ] && [ -s "${FAA}" ]; then echo "[prodigal_gv] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[prodigal_gv] ${SAMPLE} | 病毒基因预测（遗传密码 11 + -p meta）..."
EXIT_CODE=0
mgx_try mgx_conda assembly \
    prodigal \
        -i "${INPUT_FA}" \
        -a "${FAA}" \
        -d "${FNA}" \
        -f gff \
        -o "${GFF}" \
        -p meta \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] prodigal 失败"; exit ${EXIT_CODE}; fi

N_GENES=$(grep -c '^>' "${FAA}" 2>/dev/null || echo 0)
echo "[prodigal_gv] 预测基因: ${N_GENES}"
mgx_end "prodigal_gv"
