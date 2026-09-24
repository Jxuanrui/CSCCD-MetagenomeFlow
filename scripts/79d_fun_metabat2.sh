#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79d_fun_metabat2.sh
# 功  能: 对真核候选 contig 做 MetaBAT2 分箱（基于 tetranucleotide + 丰度）
#         工具版本：MetaBAT2 2.18+（conda env: metawrap，与33号细菌脚本共用）
#         VEBA (https://github.com/jolespin/veba) binning-eukaryotic 模块方法参考
#         （该模块默认即用 MetaBAT2 做真核 binning），不拷贝 VEBA 源码
# 依  赖: 79c_fun_coverm_depth.sh 的输出（depth.txt + BAM）
# 输  入: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/eukarya_${SAMPLE}.euk_filtered.fasta
#         ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/coverm/depth.txt
# 输  出: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/metabat2/
#           bin.{n}.fa   — 每个 bin 的 fasta（0个bin是合法结果，非失败）
#           ${SAMPLE}.tsv — contig2bin 表（0个bin时为空表头）
# 用  法: bash 79d_fun_metabat2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 79d_fun_metabat2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin
CONTIGS="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/eukarya_${SAMPLE}.euk_filtered.fasta"
DEPTH="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/coverm/depth.txt"
COVERM_EMPTY_FLAG="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/coverm/${SAMPLE}.coverm_empty.flag"
OUTDIR="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/metabat2"
SENTINEL="${OUTDIR}/${SAMPLE}.tsv"
CONTIG2BIN="${SENTINEL}"

# 79c 可能因上游79b判空而跳过覆盖度计算（预期行为），此时无 contig/depth 可用
if [ -f "${COVERM_EMPTY_FLAG}" ] || [ ! -f "${CONTIGS}" ] || [ ! -f "${DEPTH}" ]; then
    mkdir -p "${OUTDIR}"
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    echo "[metabat2_fungi] 上游（79b/79c）无候选序列或深度表可用，跳过分箱（预期行为）"
    echo "[metabat2_fungi] ${SAMPLE} complete (0 bins, upstream empty)"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[metabat2_fungi] 结果已存在，跳过"; exit 0
fi

mkdir -p "${OUTDIR}"

echo "[metabat2_fungi] ${SAMPLE} | MetaBAT2 真核候选序列分箱 ..."
EXIT_CODE=0
mgx_try mgx_conda metawrap \
    metabat2 \
        --numThreads "${CPUS}" \
        -m 1500 \
        -i "${CONTIGS}" \
        -a "${DEPTH}" \
        -o "${OUTDIR}/bin" \
        || EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 139 ]; then
    echo "[metabat2_fungi] SEGFAULT (exit 139) — 已知 MetaBAT2 问题（见33号脚本同类记录），写空 contig2bin.tsv"
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    echo "[metabat2_fungi] ${SAMPLE} complete (0 bins, segfault)"
    exit 0
fi
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] metabat2 失败 (exit ${EXIT_CODE})"; exit ${EXIT_CODE}; fi

N_BINS=$(find "${OUTDIR}" -maxdepth 1 -name 'bin.*.fa' 2>/dev/null | wc -l || echo 0)
if [ "${N_BINS}" -eq 0 ]; then
    echo "[metabat2_fungi] WARNING: 0个bin产出（候选序列过于分散或数量不足，属可能的预期行为）"
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    echo "[metabat2_fungi] ${SAMPLE} complete (0 bins)"
    exit 0
fi

echo "[metabat2_fungi] 构建 contig2bin 表 ..."
{
    echo -e "contig_id\tbin_id"
    for bin_fa in "${OUTDIR}"/bin.*.fa; do
        bin_id=$(basename "${bin_fa}" .fa)
        grep "^>" "${bin_fa}" | sed 's/^>//' | while read -r cid; do
            echo -e "${cid}\t${bin_id}"
        done
    done
} > "${CONTIG2BIN}"

echo "[metabat2_fungi] 完成 | bins: ${N_BINS}"
mgx_end "metabat2_fungi"
