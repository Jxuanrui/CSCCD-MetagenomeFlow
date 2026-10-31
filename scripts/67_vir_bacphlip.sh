#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 67_vir_bacphlip.sh
# 功  能: 噬菌体生活方式预测（裂解/溶原）
#         工具版本：BACPHLIP 0.9+（conda env: bacphlip）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/bacphlip/
#           bacphlip_results.tsv  — 生活方式预测结果
#           *.bacphlip            — 逐序列预测
#
# 参  考: Hockenberry et al. 2021 BMC Genomics (BACPHLIP)
# 用  法: bash 67_vir_bacphlip.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 67_vir_bacphlip.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/bacphlip"
SENTINEL="${OUTDIR}/bacphlip_results.tsv"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[bacphlip] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[bacphlip] 噬菌体生活方式预测 ..."

if command -v bacphlip &>/dev/null; then
    BACPHLIP="bacphlip"
else
    BACPHLIP="python -m bacphlip"
fi

# 多序列模式：对每条序列预测生活方式
mgx_conda bacphlip \
    ${BACPHLIP} \
        -i "${VOTU_FA}" \
        --multi_fasta \
        -f

# 收集结果
: > "${SENTINEL}"
for f in "${VOTU_FA}"*.bacphlip; do
    [ -f "$f" ] && cat "$f" >> "${SENTINEL}"
done 2>/dev/null

# 如果没找到输出文件，尝试其他命名模式
if [ ! -s "${SENTINEL}" ]; then
    find "$(dirname "${VOTU_FA}")" -name "*.bacphlip" -exec cat {} \; > "${SENTINEL}" 2>/dev/null
fi

mgx_end "bacphlip"
