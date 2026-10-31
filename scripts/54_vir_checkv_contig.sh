#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 54_vir_checkv_contig.sh
# 功  能: 病毒 contig 质量评估（CheckV end-to-end）
#         geNomad ∩ VirSorter2 交集判定病毒 contig（严格，减少假阳性）；
#         geNomad 前病毒条目（k127_x|provirus_a_b）按 base ID 匹配交集，
#         保留其 provirus 区域序列（P0-2：seqkit grep 曾静默丢弃全部 provirus）
#         工具版本：CheckV 1.0.3（conda env: checkv）
# 依  赖: 52_vir_genomad.sh + 53_vir_virsorter2.sh 的病毒预测
# 输  入: 双工具共同判定（交集）的病毒 contigs
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
if [ ${FORCE} -eq 1 ]; then mgx_force_backup "${WORKDIR}/result/virus/checkv/${SAMPLE}"; fi
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
    # 用户拍板 2026-10-11：交集做主结果；前病毒按基础 contig ID 匹配（质量审核 P0-1 方案 A）
    mkdir -p "${CONTIGS_DIR}"
    # 交集（按基础 ID）：sed 不用 cut（GNU cut 不接受多字符分隔符）
    comm -12 \
        <(grep '^>' "${GENOMAD_VIRUS}" | sed 's/^>//; s/ .*//; s/|.*//' | sort -u) \
        <(grep '^>' "${VS2_VIRUS}" | sed 's/^>//; s/||.*//' | sort -u) \
        > "${CONTIGS_DIR}/common_ids.txt"
    COMMON_COUNT=$(wc -l < "${CONTIGS_DIR}/common_ids.txt")
    echo "[checkv] 交集 contigs: ${COMMON_COUNT} (geNomad: $(grep -c '^>' "${GENOMAD_VIRUS}"), VirSorter2: $(grep -c '^>' "${VS2_VIRUS}"))"
    if [ "${COMMON_COUNT}" -gt 0 ]; then
        # awk 按基础 ID 抽取（seqkit grep 匹配完整 ID 会丢 |provirus 条目）
        awk 'NR==FNR{k[$1];next} /^>/{id=substr($1,2);sub(/\|.*/,"",id);p=(id in k)} p' \
            "${CONTIGS_DIR}/common_ids.txt" "${GENOMAD_VIRUS}" > "${VIRAL_CONTIGS}"
    else
        echo "[checkv] 交集为空，写出空摘要 + 空 FASTA"
        mkdir -p "${OUTDIR}" "${CONTIGS_DIR}"
        # 空结果也须生成空 FASTA（54b 和 Snakemake 都依赖此文件存在）
        : > "${VIRAL_CONTIGS}"
        : > "${OUTDIR}/viruses.fna"
        echo -e "contig_id\tcontig_length\tprovirus\tproviral_length\tgene_count\tviral_genes\thost_genes\tcheckv_quality\tmiuvig_quality\tcompleteness\tcompleteness_method\tcontamination\tkmer_freq\twarnings" > "${SENTINEL}"
        # 空结果的 call_stats
        printf "metric\tvalue\nn_genomad\t%s\nn_vs2\t%s\nn_intersection\t0\nn_provirus_kept\t0\ncall_mode\tintersection_empty\n" \
            "$(grep -c '^>' "${GENOMAD_VIRUS}")" \
            "$(grep -c '^>' "${VS2_VIRUS}")" \
            > "${OUTDIR}/call_stats.tsv"
        exit 0
    fi
    # 审计记录
    PROVIRUS_KEPT=$(grep -c '|provirus' "${VIRAL_CONTIGS}" 2>/dev/null) || PROVIRUS_KEPT=0
    printf "metric\tvalue\nn_genomad\t%s\nn_vs2\t%s\nn_intersection\t%s\nn_provirus_kept\t%s\ncall_mode\tintersection\n" \
        "$(grep -c '^>' "${GENOMAD_VIRUS}")" \
        "$(grep -c '^>' "${VS2_VIRUS}")" \
        "${COMMON_COUNT}" \
        "${PROVIRUS_KEPT}" \
        > "${OUTDIR}/call_stats.tsv"
    # 并集敏感性分析（用户 10-11 批准；2026-10-13 修复）：去重键与交集一致
    # （基础 contig ID，剥 |provirus 后缀）；重复记录连同其序列行一起丢弃，
    # 不再只丢表头保留序列行（旧实现会把两条序列拼进同一条记录）。
    # 质量审核 2026-10-13 P1：若交集里存在同一 contig 带 ≥2 段 provirus，基础 ID
    # 去重会使并集不再 ⊇ 交集，此时改用完整 ID 去重并在 call_stats 记录
    N_MULTI_PROV=$(grep '^>' "${VIRAL_CONTIGS}" | sed 's/^>//; s/ .*//; s/|.*//' | sort | uniq -d | wc -l)
    if [ "${N_MULTI_PROV}" -gt 0 ]; then
        cat "${GENOMAD_VIRUS}" "${VS2_VIRUS}" | awk '/^>/{key=substr($1,2); keep=!(key in seen); seen[key]=1; if(keep) print; next} keep{print}' > "${OUTDIR}/viruses_union_sensitivity.fna"
        printf "union_dedup_key\tfull\n" >> "${OUTDIR}/call_stats.tsv"
    else
        cat "${GENOMAD_VIRUS}" "${VS2_VIRUS}" | awk '/^>/{key=substr($1,2); sub(/\|.*/,"",key); keep=!(key in seen); seen[key]=1; if(keep) print; next} keep{print}' > "${OUTDIR}/viruses_union_sensitivity.fna"
        printf "union_dedup_key\tbase\n" >> "${OUTDIR}/call_stats.tsv"
    fi
    printf "union_multi_provirus_contigs\t%s\n" "${N_MULTI_PROV}" >> "${OUTDIR}/call_stats.tsv"
    UNION_COUNT=$(grep -c '^>' "${OUTDIR}/viruses_union_sensitivity.fna" 2>/dev/null) || UNION_COUNT=0
    printf "union_count\t%s\n" "${UNION_COUNT}" >> "${OUTDIR}/call_stats.tsv"
    rm -f "${CONTIGS_DIR}/common_ids.txt" "${CONTIGS_DIR}/_merged.fasta"
elif $HAS_GENOMAD || $HAS_VS2; then
    # 只有一个工具有结果时，使用该结果但标记 fallback（不再静默）
    mkdir -p "${CONTIGS_DIR}" "${OUTDIR}"
    if $HAS_GENOMAD; then
        cp "${GENOMAD_VIRUS}" "${VIRAL_CONTIGS}"
        printf "metric\tvalue\nn_genomad\t%s\nn_vs2\t0\nn_intersection\t0\nn_provirus_kept\t0\ncall_mode\tfallback_genomad_only\n" \
            "$(grep -c '^>' "${GENOMAD_VIRUS}")" > "${OUTDIR}/call_stats.tsv"
    else
        cp "${VS2_VIRUS}" "${VIRAL_CONTIGS}"
        printf "metric\tvalue\nn_genomad\t0\nn_vs2\t%s\nn_intersection\t0\nn_provirus_kept\t0\ncall_mode\tfallback_vs2_only\n" \
            "$(grep -c '^>' "${VS2_VIRUS}")" > "${OUTDIR}/call_stats.tsv"
    fi
    echo "[WARN] 单工具回退模式：${OUTDIR}/call_stats.tsv 已标记 call_mode=fallback"
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
