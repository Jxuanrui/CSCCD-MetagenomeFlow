#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 35_bac_semibin2.sh
# 功  能: SemiBin2 自监督 ML 分箱（基于 BAM + contig 特征）
#         工具版本：SemiBin2 2.x（conda env: semibin）
# 依  赖: 32_bac_coverm_depth.sh 的输出（BAM）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/{sample}.bam
# 输  出: ${WORKDIR}/result/binning/semibin2/{sample}/
#           output/bin/  — SemiBin2 输出目录
#           ${SAMPLE}.semibin2.tsv  — contig2bin 表
#
# 特  点: 自监督学习，无需参考基因组；需要原始 BAM（非深度表）
#
# 参  考: Pan et al. 2023 Nature Comms (SemiBin2)
# 用  法: bash 35_bac_semibin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 35_bac_semibin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
BAM="${WORKDIR}/result/binning/coverm/${SAMPLE}/${SAMPLE}.bam"
OUTDIR="${WORKDIR}/result/binning/semibin2/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}.semibin2.tsv"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi
if [ ! -f "${BAM}" ]; then echo "[ERROR] BAM missing: ${BAM}"; exit 1; fi

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[semibin2] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[semibin2] ${SAMPLE} | 自监督分箱 ..."
conda run --prefix "${REPO}/envs/semibin" --no-capture-output \
    SemiBin2 single_easy_bin \
        -t "${CPUS}" \
        --self-supervised \
        --input-fasta "${CONTIGS}" \
        --input-bam "${BAM}" \
        -o "${OUTDIR}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] SemiBin2 失败"; exit ${EXIT_CODE}; fi

# 构建 contig2bin 表
BIN_TSV="${OUTDIR}/output_bins.tsv"
if [ -f "${OUTDIR}/output/contig_bins.tsv" ]; then
    cp "${OUTDIR}/output/contig_bins.tsv" "${SENTINEL}"
elif [ -f "${BIN_TSV}" ]; then
    cp "${BIN_TSV}" "${SENTINEL}"
else
    echo "[semibin2] WARNING: contig_bins.tsv not found, check ${OUTDIR}/"
    touch "${SENTINEL}"
fi

N_BINS=$(find "${OUTDIR}" -name "*.fa" 2>/dev/null | wc -l || echo 0)
echo "[semibin2] 完成，耗时 ${SECONDS}s | bins: ${N_BINS}"
