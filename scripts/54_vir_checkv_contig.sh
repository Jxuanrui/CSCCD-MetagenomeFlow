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

show_help() { cat << EOF
用法: bash 54_vir_checkv_contig.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
GENOMAD_DIR="${WORKDIR}/result/virus/genomad/${SAMPLE}"
VS2_DIR="${WORKDIR}/result/virus/virsorter2/${SAMPLE}"
CONTIGS_DIR="${WORKDIR}/result/virus/checkv/${SAMPLE}"
OUTDIR="${WORKDIR}/result/virus/checkv/${SAMPLE}"

VIRAL_CONTIGS="${CONTIGS_DIR}/virus_contigs.fasta"
SENTINEL="${OUTDIR}/quality_summary.tsv"
CHK_DB="${REPO}/db/checkv"

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[checkv] 结果已存在，跳过"; exit 0; fi

# Step 1: 合并 geNomad + VirSorter2 病毒序列后去重
GENOMAD_VIRUS="${GENOMAD_DIR}/${SAMPLE}.contigs_summary/${SAMPLE}.contigs_virus.fna"
VS2_VIRUS="${VS2_DIR}/final-viral-combined.fasta"

if [ -f "${GENOMAD_VIRUS}" ] && [ -f "${VS2_VIRUS}" ]; then
    mkdir -p "${CONTIGS_DIR}"
    cat "${GENOMAD_VIRUS}" "${VS2_VIRUS}" > "${CONTIGS_DIR}/_merged.fasta"
    conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        seqkit rmdup -s -o "${VIRAL_CONTIGS}" "${CONTIGS_DIR}/_merged.fasta"
    rm -f "${CONTIGS_DIR}/_merged.fasta"
elif [ -f "${GENOMAD_VIRUS}" ]; then
    mkdir -p "${CONTIGS_DIR}"
    cp "${GENOMAD_VIRUS}" "${VIRAL_CONTIGS}"
else
    echo "[ERROR] 无病毒预测结果（geNomad/VirSorter2）"; exit 1
fi

# Step 2: CheckV
echo "[checkv] ${SAMPLE} | CheckV 质量评估 ..."
conda run --prefix "${REPO}/envs/checkv" --no-capture-output \
    checkv end_to_end \
        "${VIRAL_CONTIGS}" \
        "${OUTDIR}" \
        -d "${CHK_DB}" \
        -t "${CPUS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] checkv 失败"; exit ${EXIT_CODE}; fi

echo "[checkv] 完成，耗时 ${SECONDS}s | 输出: ${OUTDIR}/quality_summary.tsv"
