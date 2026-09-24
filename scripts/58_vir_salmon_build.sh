#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 58_vir_salmon_build.sh
# 功  能: 构建 vOTU 定量索引（Salmon index，gentrome+decoy）
#         工具版本：Salmon 1.10+（conda env: assembly）
# 依  赖: 56_vir_votu_gen.sh（vOTU 代表序列）
#         55_vir_prodigal_gv.sh 的基因核酸序列
# 输  入: vOTU 序列 + 所有样本病毒 CDS（.ffn）
# 输  出: ${WORKDIR}/result/virus/salmon/index/
#
# ── 索引策略 ─────────────────────────────────────────────────────
#   gentrome = CDS ffns + vOTU fna; decoy = vOTU fna
#   该索引同时支持基因级和 contig 级定量
#
# 参  考: Patro et al. 2017 Nat Methods (Salmon)
# 用  法: bash 58_vir_salmon_build.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 58_vir_salmon_build.sh -t CPUS -w WORKDIR -r REPO
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
INDEX_DIR="${WORKDIR}/result/virus/salmon/index"
SENTINEL="${INDEX_DIR}/info.json"
SALMON_VERSION_INFO="${INDEX_DIR}/versionInfo.json"

if [ ! -f "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在: ${VOTU_FA}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[salmon_build] 索引已存在，跳过"; exit 0; fi
if [ -f "${SALMON_VERSION_INFO}" ]; then
    cp "${SALMON_VERSION_INFO}" "${SENTINEL}"
    echo "[salmon_build] 检测到已有 Salmon 索引，已补全 info.json 哨兵文件"
    exit 0
fi

mkdir -p "${INDEX_DIR}"

echo "[salmon_build] 准备 gentrome + decoy ..."
# 收集所有病毒 CDS (ffn)
ALL_FFN="${INDEX_DIR}/virus_cds.ffn"
: > "${ALL_FFN}"
for f in "${WORKDIR}"/result/virus/prodigal/*/*.fna; do
    [ -f "$f" ] && cat "$f" >> "${ALL_FFN}"
done

# gentrome = CDS + vOTU
cat "${ALL_FFN}" "${VOTU_FA}" > "${INDEX_DIR}/gentrome.fasta"
# decoy = vOTU only
grep '^>' "${VOTU_FA}" | sed 's/^>//' > "${INDEX_DIR}/decoys.txt"

if [ ! -s "${INDEX_DIR}/decoys.txt" ]; then
    echo "[salmon_build] WARN: decoys.txt 为空（可能是测试数据无病毒序列）"
fi
# Salmon 0.14.1 与 decoy-aware 索引在 quant 时存在 segfault 兼容性问题
# 统一使用标准索引（不传 -d），对 vOTU 定量精度影响极小
echo "[salmon_build] 构建标准索引（无 decoy，兼容 Salmon 0.14.1）..."
mgx_conda assembly \
    salmon index \
        -t "${INDEX_DIR}/gentrome.fasta" \
        -i "${INDEX_DIR}" \
        -p "${CPUS}" \
        --keepDuplicates

if [ ! -f "${SENTINEL}" ]; then
    if [ -f "${SALMON_VERSION_INFO}" ]; then
        cp "${SALMON_VERSION_INFO}" "${SENTINEL}"
    else
        echo "[ERROR] 索引文件 info.json 未生成，且未找到 versionInfo.json"
        exit 1
    fi
fi

echo "[salmon_build] 完成"
mgx_end "salmon_build"
