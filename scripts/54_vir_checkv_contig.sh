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

if $HAS_GENOMAD && $HAS_VS2; then
    # 用户approve 2026-10-11：交集做主结果（严格，减少假阳性），并集作为敏感性分析
    mkdir -p "${CONTIGS_DIR}"
    # 提取两个工具共同判定的 contig ID（交集）
    comm -12 \
        <(grep '^>' "${GENOMAD_VIRUS}" | sed 's/^>//' | cut -d' ' -f1 | cut -d'|' -f1 | sort -u) \
        <(grep '^>' "${VS2_VIRUS}" | sed 's/^>//' | cut -d'||/' -f1 | cut -d' ' -f1 | sort -u) \
        > "${CONTIGS_DIR}/common_ids.txt"
    COMMON_COUNT=$(wc -l < "${CONTIGS_DIR}/common_ids.txt")
    echo "[checkv] 交集 contigs: ${COMMON_COUNT} (geNomad: $(grep -c '^>' "${GENOMAD_VIRUS}"), VirSorter2: $(grep -c '^>' "${VS2_VIRUS}"))"
    if [ "${COMMON_COUNT}" -gt 0 ]; then
        # 从 geNomad 输出中提取交集序列（保留原始序列，不截断）
        mgx_conda assembly \
            seqkit grep -f "${CONTIGS_DIR}/common_ids.txt" \
            -o "${VIRAL_CONTIGS}" "${GENOMAD_VIRUS}"
    else
        echo "[WARN] 交集为空，回退到仅 geNomad 结果"
        cp "${GENOMAD_VIRUS}" "${VIRAL_CONTIGS}"
    fi
    rm -f "${CONTIGS_DIR}/common_ids.txt" "${CONTIGS_DIR}/_merged.fasta"
elif $HAS_GENOMAD || $HAS_VS2; then
    # 只有一个工具有结果时，直接使用该结果
    mkdir -p "${CONTIGS_DIR}"
    if $HAS_GENOMAD; then
        cp "${GENOMAD_VIRUS}" "${VIRAL_CONTIGS}"
    else
        cp "${VS2_VIRUS}" "${VIRAL_CONTIGS}"
    fi
else
    echo "[WARN] S01 中未检测到病毒序列: geNomad 和 VirSorter2 均无有效输出"
    mkdir -p "${OUTDIR}"
    # T-15: empty result must still match the real per-contig quality_summary
    # schema so 54b can parse it (previously a fabricated summary header).
    echo -e "contig_id\tcontig_length\tprovirus\tproviral_length\tgene_count\tviral_genes\thost_genes\tcheckv_quality\tmiuvig_quality\tcompleteness\tcompleteness_method\tcontamination\tkmer_freq\twarnings" > "${SENTINEL}"
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
