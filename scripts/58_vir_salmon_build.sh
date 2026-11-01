#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 58_vir_salmon_build.sh
# 功  能: 构建 vOTU 定量索引（Salmon 标准索引，仅 vOTU contigs）
#         工具版本：Salmon 0.14.1（conda env: assembly）
# 依  赖: 56_vir_votu_gen.sh（vOTU 成员序列，即 54b MIUVIG 过滤后全集）
# 输  入: result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/salmon/index/
#
# ── 索引策略 ─────────────────────────────────────────────────────
#   索引只放 vOTU contigs（拍板 D + 质量审核 2026-10-13 复审 P0-1）。
#   旧策略把 CDS 与 contig 同放索引（gentrome），Salmon EM 会把落在
#   基因区的 reads 分摊给基因和 contig 两条 target；60 号按拍板 D 丢
#   基因行时这部分 reads 一并丢失，单条 vOTU 实测损失 35-77%。
#   基因级病毒定量无下游消费方，故索引不再包含 CDS。
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
if [ ${FORCE} -eq 0 ] && [ -f "${SALMON_VERSION_INFO}" ]; then
    cp "${SALMON_VERSION_INFO}" "${SENTINEL}"
    echo "[salmon_build] 检测到已有 Salmon 索引，已补全 info.json 哨兵文件"
    exit 0
fi

mkdir -p "${INDEX_DIR}"

# 索引只含 vOTU contigs（拍板 D 落实到定量层，质量审核 P0-1）。
# 移除旧的 CDS 收集与 gentrome 拼接；基因 ID 样本前缀逻辑随之移除
# （索引中已无基因行，58→59 不再产生基因级定量）。
grep '^>' "${VOTU_FA}" | sed 's/^>//' > "${INDEX_DIR}/decoys.txt"  # 保留：phase1_tierA_golden.sha256 引用此文件；标准索引不消费它

if [ ! -s "${INDEX_DIR}/decoys.txt" ]; then
    echo "[salmon_build] WARN: 索引序列为空（可能是测试数据无病毒序列）"
fi
# Salmon 0.14.1 与 decoy-aware 索引在 quant 时存在 segfault 兼容性问题
# 统一使用标准索引（不传 -d）
echo "[salmon_build] 构建标准索引（仅 vOTU contigs，兼容 Salmon 0.14.1）..."
mgx_conda assembly \
    salmon index \
        -t "${VOTU_FA}" \
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
