#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 54b_vir_checkv_filter.sh
# 功  能: CheckV 病毒 contigs 质量过滤
#         保留非零 viral gene 的 Not-determined contigs，过滤长度 < 2000 contigs
# 依  赖: 54_vir_checkv_contig.sh 的 CheckV 输出
# 输  入: ${WORKDIR}/result/virus/checkv/{sample}/quality_summary.tsv
#         ${WORKDIR}/result/virus/checkv/{sample}/virus_contigs.fasta
# 输  出: ${WORKDIR}/result/virus/checkv/{sample}/viruses_filtered.fna
#
# 用  法: bash 54b_vir_checkv_filter.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 54b_vir_checkv_filter.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
OUTDIR="${WORKDIR}/result/virus/checkv/${SAMPLE}"
SUMMARY_TSV="${OUTDIR}/quality_summary.tsv"
VIRAL_CONTIGS="${OUTDIR}/virus_contigs.fasta"
PASS_IDS="${OUTDIR}/viruses_filtered.ids"
FILTERED_FASTA="${OUTDIR}/viruses_filtered.fna"

if [ ! -f "${SUMMARY_TSV}" ] || [ ! -s "${SUMMARY_TSV}" ]; then echo "[ERROR] 缺少输入文件: ${SUMMARY_TSV}"; exit 1; fi
if [ ! -f "${VIRAL_CONTIGS}" ] || [ ! -s "${VIRAL_CONTIGS}" ]; then echo "[ERROR] 缺少输入文件: ${VIRAL_CONTIGS}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${FILTERED_FASTA}" ] && [ -s "${FILTERED_FASTA}" ]; then
    echo "[54b_checkv_filter] 结果已存在，跳过: ${SAMPLE}"; exit 0
fi

echo "[54b_checkv_filter] ${SAMPLE} | CheckV 质量过滤 ..."

awk -F '\t' '
NR == 1 {
    for (i = 1; i <= NF; i++) idx[$i] = i
    next
}
{
    total++
    q = $(idx["checkv_quality"])
    vg = $(idx["viral_genes"]) + 0
    len = $(idx["contig_length"]) + 0
    keep_quality = (q == "Complete" || q == "High-quality" || q == "Medium-quality" || q == "Low-quality")
    keep_not_determined = (q == "Not-determined" && vg > 0)
    keep_len = (len >= 2000)
    if ((keep_quality || keep_not_determined) && keep_len) {
        print $(idx["contig_id"])
        passed++
    }
}
END {
    excluded = total - passed
    printf("TOTAL=%d\nPASSED=%d\nEXCLUDED=%d\n", total, passed, excluded) > stats
}
' stats="${OUTDIR}/viruses_filtered.stats" "${SUMMARY_TSV}" > "${PASS_IDS}"

if [ ! -s "${PASS_IDS}" ]; then
    : > "${FILTERED_FASTA}"
else
    mgx_conda assembly \
        seqkit --quiet grep -f "${PASS_IDS}" "${VIRAL_CONTIGS}" -o "${FILTERED_FASTA}"
fi

TOTAL=$(awk -F '=' '$1=="TOTAL"{print $2}' "${OUTDIR}/viruses_filtered.stats")
PASSED=$(awk -F '=' '$1=="PASSED"{print $2}' "${OUTDIR}/viruses_filtered.stats")
EXCLUDED=$(awk -F '=' '$1=="EXCLUDED"{print $2}' "${OUTDIR}/viruses_filtered.stats")

echo "[54b_checkv_filter] ${SAMPLE} | total=${TOTAL}, passed=${PASSED}, excluded=${EXCLUDED}"
echo "[54b_checkv_filter] 输出: ${FILTERED_FASTA}"
mgx_end "54b_checkv_filter"
