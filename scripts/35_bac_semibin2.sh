#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 35_bac_semibin2.sh
# 功  能: SemiBin2 分箱（肠道样本预训练模型，human_gut）
#         工具版本：SemiBin 2.5.0（conda env: semibin2x；1.5.0 旧环境 semibin 冻结保留）
# 依  赖: 32_bac_coverm_depth.sh 的输出（depth.txt）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/depth.txt
# 输  出: ${WORKDIR}/result/binning/semibin2/{sample}/
#           output/bin/  — SemiBin2 输出目录
#           ${SAMPLE}.semibin2.tsv  — contig2bin 表
#
# 说  明: SemiBin 2.5.0 已修复 1.5.0 的 BAM coverage 失败 bug（2026-09-19 实测
#         self-supervised + BAM 通过），且 0-bin 时优雅退出（1.5.0 崩在 hmmsearch）。
#         生产默认仍用 --depth-metabat2 + --environment human_gut 预训练模型，
#         保持与历史结果可比；如需自监督模式可改用 -b BAM。
#
# 参  考: Pan et al. 2023 Nature Comms (SemiBin2)
# 用  法: bash 35_bac_semibin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 35_bac_semibin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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

EXIT_CODE=0
echo "[semibin2] ${SAMPLE} | 预训练模型分箱（human_gut）..."
mgx_try mgx_conda semibin2x \
    SemiBin2 single_easy_bin \
        -t "${CPUS}" \
        --environment human_gut \
        --input-fasta "${CONTIGS}" \
        --depth-metabat2 "${DEPTH}" \
        -o "${OUTDIR}" || EXIT_CODE=$?

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
