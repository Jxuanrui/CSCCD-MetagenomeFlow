#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 33b_bac_quickbin.sh
# 功  能: QuickBin 高保真宏基因组分箱（GC-覆盖度空间索引 + Oracle 相似度级联，
#         仅对模糊合并用小型神经网络裁决；CPU-only、marker-free）
#         工具版本：QuickBin（BBTools 39.81，Java；随 envs/busco 提供）
# 依  赖: 16_bac_megahit.sh（contigs）
#         32_bac_coverm_depth.sh（contig 排序 BAM，直接复用，无需重复映射）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/{sample}.bam
# 输  出: ${WORKDIR}/result/binning/quickbin/{sample}/
#           QUICKBIN_BIN*.fa          — 每个 bin 的 fasta
#           ${SAMPLE}.quickbin.tsv    — contig2bin 表（从 bin fasta 派生，供 DAS_Tool）
#
# ── 定位说明 ──────────────────────────────────────────────────────────────────
#
#   作为第 4 个成员加入 DAS_Tool 集成（与 MetaBAT2/MaxBin2/SemiBin2 并列）：
#   QuickBin 论文（Bushnell & Villada, Commun Biol 2026）在 297 个真实宏基因组
#   基准中，高保真 MAG（≥95% 完整、≤1% 污染）产出优于 MetaBAT2/SemiBin2/VAMB/
#   COMEBin，且全部跑完（竞品在同等资源限制下常失败），内存需求低、仅需 Java。
#   marker-free 设计亦利于真核 MAG 恢复。
#
#   已知取舍：官方推荐用 BBMap（ambig=random mateqtag）映射以最大化配对边证据；
#   本脚本复用 CoverM(minimap2) 的 BAM 以避免重复映射，边证据可能略少。
#
# 参  考: Bushnell & Villada 2026 Communications Biology (QuickBin)
#         https://github.com/bbushnell/BBTools ; https://bbmap.org/tools/quickbin
# 用  法: bash 33b_bac_quickbin.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force] [--mem-gb 32]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 33b_bac_quickbin.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（不含后缀）
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --mem-gb  JVM 堆上限 GB（默认 32）
  --force   强制重新运行
  -h        显示帮助
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
FORCE=0
MEM_GB=32
# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_LONG="mem-gb:MEM_GB"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

# QuickBin (Java/BBTools) cannot resolve relative paths: the tool is invoked after
# `cd "${OUTDIR}"`, so a relative -w would break in=/reads=. Absolutise both roots.
WORKDIR="$(realpath -m "${WORKDIR}")"
REPO="$(realpath -m "${REPO}")"

mgx_begin

CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
BAM="${WORKDIR}/result/binning/coverm/${SAMPLE}/${SAMPLE}.bam"
OUTDIR="${WORKDIR}/result/binning/quickbin/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}.quickbin.tsv"

BBTOOLS_BIN="${REPO}/envs/busco/bin"
QUICKBIN="${BBTOOLS_BIN}/quickbin.sh"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs 缺失: ${CONTIGS}"; exit 1; fi
if [ ! -f "${BAM}" ]; then echo "[ERROR] BAM 缺失（需先运行 32_bac_coverm_depth.sh）: ${BAM}"; exit 1; fi
if [ ! -x "${QUICKBIN}" ]; then echo "[ERROR] QuickBin 未找到: ${QUICKBIN}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[quickbin] 结果已存在，跳过: ${SENTINEL}（--force 可强制重跑）"
    exit 0
fi

mkdir -p "${OUTDIR}"

echo "[quickbin] 样本: ${SAMPLE}"
echo "[quickbin] contigs: ${CONTIGS}"
echo "[quickbin] bam: ${BAM}"
echo "[quickbin] 线程: ${CPUS} | JVM 堆: ${MEM_GB}g"

EXIT_CODE=0
( cd "${OUTDIR}" && mgx_conda busco quickbin.sh \
    "in=${CONTIGS}" \
    "reads=${BAM}" \
    "out=QUICKBIN_BIN%.fa" \
    mincontig=1500 \
    mincluster=100000 \
    normal \
    simd \
    threads="${CPUS}" \
    -Xmx"${MEM_GB}"g \
    -eoom ) || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] quickbin 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

N_BINS=$(find "${OUTDIR}" -maxdepth 1 -name 'QUICKBIN_BIN*.fa' 2>/dev/null | wc -l)
if [ "${N_BINS}" -eq 0 ]; then
    echo "[WARNING] 未生成任何 bin，写空 sentinel"
    : > "${SENTINEL}"
    exit 0
fi

for f in "${OUTDIR}"/QUICKBIN_BIN*.fa; do
    bin="$(basename "${f}" .fa)"
    grep '^>' "${f}" | sed 's/^>//;s/[[:space:]].*//' | awk -v b="${bin}" 'BEGIN{FS=OFS="\t"} {print $1, b}'
done | sort -u > "${SENTINEL}"

echo ""
echo "[quickbin] ${SAMPLE} 完成 | bins: ${N_BINS}"
echo "[quickbin] contig2bin: ${SENTINEL}"
mgx_end "quickbin"
