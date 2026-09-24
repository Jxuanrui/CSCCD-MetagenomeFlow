#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 54_vir_checkv_contig.sh
# 功  能: 病毒 contig 质量评估（CheckV end-to-end）
#         合并完整病毒 + 原前病毒序列
#         工具版本：CheckV 1.0.3（conda env: checkv）
# 依  赖: 52_vir_genomad.sh + 53_vir_virsorter2.sh 的病毒预测
# 输  入: 去重后的病毒 contigs（genomad + virsorter2 交集）
# 输  出: ${WORKDIR}/result/virus/checkv/{sample}/
#           quality_summary.tsv     — CheckV 质量汇总
#           viruses.fna             — 去重病毒 contigs
#           provirus.fna + .bed     — 原前病毒区域
#
# 参  考: Nayfach et al. 2021 Nat Biotechnol (CheckV)
# 用  法: bash 54_vir_checkv_contig.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 54_vir_checkv_contig.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
GENOMAD_DIR="${WORKDIR}/result/virus/genomad/${SAMPLE}"
VS2_DIR="${WORKDIR}/result/virus/virsorter2/${SAMPLE}"
CONTIGS_DIR="${WORKDIR}/result/virus/checkv/${SAMPLE}"
OUTDIR="${WORKDIR}/result/virus/checkv/${SAMPLE}"

VIRAL_CONTIGS="${CONTIGS_DIR}/virus_contigs.fasta"
SENTINEL="${OUTDIR}/quality_summary.tsv"
CHK_DB="${REPO}/db/checkv"

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[checkv] 结果已存在，跳过"; exit 0; fi

# Step 1: 合并 geNomad + VirSorter2 病毒序列后去重
GENOMAD_VIRUS="${GENOMAD_DIR}/${SAMPLE}.contigs_summary/${SAMPLE}.contigs_virus.fna"
# VirSorter2 2.2.4 输出 final-viral-combined.fa（非 .fasta）
VS2_VIRUS="${VS2_DIR}/final-viral-combined.fa"
if [ ! -f "${VS2_VIRUS}" ]; then
    VS2_VIRUS="${VS2_DIR}/final-viral-combined.fasta"
fi

# 检查输入文件是否存在且非空
HAS_GENOMAD=false; HAS_VS2=false
[ -f "${GENOMAD_VIRUS}" ] && [ -s "${GENOMAD_VIRUS}" ] && HAS_GENOMAD=true
[ -f "${VS2_VIRUS}" ] && [ -s "${VS2_VIRUS}" ] && HAS_VS2=true

if $HAS_GENOMAD || $HAS_VS2; then
    mkdir -p "${CONTIGS_DIR}"
    : > "${CONTIGS_DIR}/_merged.fasta"
    $HAS_GENOMAD && cat "${GENOMAD_VIRUS}" >> "${CONTIGS_DIR}/_merged.fasta"
    $HAS_VS2 && cat "${VS2_VIRUS}" >> "${CONTIGS_DIR}/_merged.fasta"
    mgx_conda assembly \
        seqkit rmdup -s -o "${VIRAL_CONTIGS}" "${CONTIGS_DIR}/_merged.fasta"
    rm -f "${CONTIGS_DIR}/_merged.fasta"
else
    echo "[WARN] S01 中未检测到病毒序列: geNomad 和 VirSorter2 均无有效输出"
    mkdir -p "${OUTDIR}"
    echo -e "sample_id\tnum_viral\tnuc_contam\tcompleteness\tcompleteness_method\tcontamination\tcontamination_method\tkmer_freq\tn50\tlength_max\ttotal_length\tgene_count\tviral_genes\thost_genes\tprovirus" > "${SENTINEL}"
    echo "0\t0\t0\t0.0\tN/A\t0.0\tN/A\tNA\t0\t0\t0\t0\t0\t0\tN/A" >> "${SENTINEL}"
    echo "[checkv] 生成空摘要（sentinel），下游步骤可正常感知"
    exit 0
fi

# CheckV 内部按 tmp/ 目录里已有的中间结果（gene_features.tsv/diamond.tsv 等）
# 做断点续跑，但不会校验这些结果是否对应当前的 VIRAL_CONTIGS；若 VIRAL_CONTIGS
# 是重新生成的（如本次 genomad/virsorter2 重跑后 contig 集合变化），旧 tmp/
# 会与新 fasta 不一致，导致 contamination.py 里按 contig ID 查 gene 时 KeyError。
# 因此这里比较 mtime，VIRAL_CONTIGS 更新则视为输入已变化，清空 tmp/ 强制全量重跑。
if [ -d "${OUTDIR}/tmp" ] && [ "${VIRAL_CONTIGS}" -nt "${OUTDIR}/tmp" ]; then
    echo "[checkv] 检测到 virus_contigs.fasta 比缓存的 tmp/ 更新，清空旧中间结果重新计算"
    rm -rf "${OUTDIR}/tmp"
fi

# Step 2: CheckV
echo "[checkv] ${SAMPLE} | CheckV 质量评估 ..."
EXIT_CODE=0
mgx_try mgx_conda checkv \
    checkv end_to_end \
        "${VIRAL_CONTIGS}" \
        "${OUTDIR}" \
        -d "${CHK_DB}" \
        -t "${CPUS}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] checkv 失败"; exit ${EXIT_CODE}; fi

echo "[checkv] 输出: ${OUTDIR}/quality_summary.tsv"
mgx_end "checkv"
