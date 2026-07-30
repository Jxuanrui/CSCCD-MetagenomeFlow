#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 35_bac_semibin2.sh
# 功  能: SemiBin2 分箱（肠道样本预训练模型，human_gut）
#         工具版本：SemiBin2 1.5.0（conda env: semibin）
# 依  赖: 32_bac_coverm_depth.sh 的输出（depth.txt）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/depth.txt
# 输  出: ${WORKDIR}/result/binning/semibin2/{sample}/
#           output/bin/  — SemiBin2 输出目录
#           ${SAMPLE}.semibin2.tsv  — contig2bin 表
#
# 说  明: SemiBin2 1.5.0 --self-supervised 模式需要直接访问 BAM 进行 coverage 计算，
#         在某些 BAM 格式下会失败（"Generating coverage file fail"）。
#         改用 --depth-metabat2 + --environment human_gut 预训练模型，
#         肠道菌群样本效果更好且无 BAM 依赖。
#
# 参  考: Pan et al. 2023 Nature Comms (SemiBin2)
# 用  法: bash 35_bac_semibin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 35_bac_semibin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

FORCE=0
SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
DEPTH="${WORKDIR}/result/binning/coverm/${SAMPLE}/depth.txt"
OUTDIR="${WORKDIR}/result/binning/semibin2/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}.semibin2.tsv"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi
if [ ! -f "${DEPTH}" ]; then echo "[ERROR] depth.txt missing: ${DEPTH}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[semibin2] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# Guard: SemiBin2 requires contigs >=2500 bp
LONG_CONTIGS=$(awk '
    /^>/ {
        if (seen && len >= 2500) count++
        len = 0
        seen = 1
        next
    }
    { len += length($0) }
    END {
        if (seen && len >= 2500) count++
        print count + 0
    }
' "${CONTIGS}" 2>/dev/null || echo "0")
if [ "${LONG_CONTIGS}" -lt 2 ]; then
    echo "[semibin2] WARNING: ${LONG_CONTIGS} contigs >=2500 bp (need >=2). Creating empty output sentinel."
    : > "${SENTINEL}"
    exit 0
fi

set +e
echo "[semibin2] ${SAMPLE} | 预训练模型分箱（human_gut）..."
conda run --prefix "${REPO}/envs/semibin" --no-capture-output \
    SemiBin2 single_easy_bin \
        -t "${CPUS}" \
        --environment human_gut \
        --input-fasta "${CONTIGS}" \
        --depth-metabat2 "${DEPTH}" \
        -o "${OUTDIR}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[semibin2] WARNING: SemiBin2 失败，创建空 sentinel: ${SENTINEL}"
    : > "${SENTINEL}"
    exit 0
fi

# 构建 contig2bin 表
# 注: SemiBin2 1.5.0 将 contig_bins.tsv 直接输出到 OUTDIR 根目录，
#     bin FASTA（.fa.gz）位于 OUTDIR/output_bins/
if [ -f "${OUTDIR}/contig_bins.tsv" ]; then
    cp "${OUTDIR}/contig_bins.tsv" "${SENTINEL}"
elif [ -f "${OUTDIR}/output/contig_bins.tsv" ]; then
    cp "${OUTDIR}/output/contig_bins.tsv" "${SENTINEL}"
else
    echo "[semibin2] WARNING: contig_bins.tsv not found, check ${OUTDIR}/"
    touch "${SENTINEL}"
fi

N_BINS=$(find "${OUTDIR}/output_bins" -name "*.fa*" 2>/dev/null | wc -l || echo 0)
echo "[semibin2] 完成，耗时 ${SECONDS}s | bins: ${N_BINS}"
