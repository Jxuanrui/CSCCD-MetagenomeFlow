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

show_help() { cat << EOF
用法: bash 67_vir_bacphlip.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
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
conda run --prefix "${REPO}/envs/bacphlip" --no-capture-output \
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

echo "[bacphlip] 完成，耗时 ${SECONDS}s"
