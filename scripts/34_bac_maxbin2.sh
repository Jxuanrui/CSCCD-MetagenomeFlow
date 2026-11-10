#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 34_bac_maxbin2.sh
# 功  能: MaxBin2 宏基因组分箱（基于 EM 算法 + tetranucleotide）
#         工具版本：MaxBin2 2.2.7（conda env: metawrap）
# 依  赖: 32_bac_coverm_depth.sh 的输出（depth.txt）
#         MaxBin2 需要转换 depth 为 2 列格式（contig, depth）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/depth.txt
# 输  出: ${WORKDIR}/result/binning/maxbin2/{sample}/
#           bin.{n}.fasta            — 每个 bin 的 fasta
#           ${SAMPLE}.maxbin2.tsv    — contig2bin 表
#
# 参  考: Wu et al. 2014 Microbiome (MaxBin2)
# 用  法: bash 34_bac_maxbin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 34_bac_maxbin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
OUTDIR="${WORKDIR}/result/binning/maxbin2/${SAMPLE}"
ABUND="${OUTDIR}/abundance.txt"
SENTINEL="${OUTDIR}/${SAMPLE}.maxbin2.tsv"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi
if [ ! -f "${DEPTH}" ]; then echo "[ERROR] Depth missing"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[maxbin2] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# MaxBin2 需要 2 列 abundance (contig, depth)，从 coverm 深度表提取
# depth.txt 比 abundance.txt 新时（如 contigs.fa 被上游重新组装）必须重新生成，
# 否则会用旧 contig-ID 体系的丰度文件配新组装，产生错位的 bins（下游 DAS_Tool 报错）
if [ ! -f "${ABUND}" ] || [ "${DEPTH}" -nt "${ABUND}" ]; then
    tail -n +2 "${DEPTH}" | cut -f1,4 > "${ABUND}"
fi

echo "[maxbin2] ${SAMPLE} | 线程: ${CPUS}"
EXIT_CODE=0
mgx_try mgx_conda metawrap run_MaxBin.pl \
        -contig "${CONTIGS}" \
        -max_iteration 50 \
        -thread "${CPUS}" \
        -abund "${ABUND}" \
        -out "${OUTDIR}/bin" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[maxbin2] WARNING: MaxBin2 失败，创建空 sentinel: ${SENTINEL}"
    : > "${SENTINEL}"
    exit 0
fi

N_FA=$(find "${OUTDIR}" -maxdepth 1 -type f -name "bin.*.fasta" | wc -l)
if [ "${N_FA}" -eq 0 ]; then
    echo "[maxbin2] WARNING: 未产生任何 bins，创建空 sentinel: ${SENTINEL}"
    : > "${SENTINEL}"
else
    # 构建 contig2bin 表
    for f in "${OUTDIR}"/bin.*.fasta; do
        bname=$(basename "$f" .fasta)
        grep '^>' "$f" | sed "s/^>//" | awk -v bin="$bname" '{print $1"\t"bin}'
    done > "${SENTINEL}"
fi

echo "[maxbin2] bins: ${N_FA}"
mgx_end "maxbin2"
