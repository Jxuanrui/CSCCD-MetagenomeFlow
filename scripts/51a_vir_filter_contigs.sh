#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 51a_vir_filter_contigs.sh
# 功  能: 病毒轨输入 = 细菌组装 contigs 过滤 ≥1500 bp（R-20261116-27 第 2 项：
#         取消独立 vir_megahit——实测 54,990 条中 54,980 条与细菌组装序列相同）
# 工具: seqkit（conda env: assembly）
# 输  入: ${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa（细菌轨）
# 输  出: ${WORKDIR}/result/virus/assembly/${SAMPLE}/${SAMPLE}.contigs.fa
#         （**路径保持不变** → 下游 geNomad/VirSorter2/CheckV/provenance 零改动；
#          注意：contig 命名沿用细菌轨命名空间，ASSEMBLY_STRATEGY v3 已声明）
# 用  法: bash 51a_vir_filter_contigs.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 51a_vir_filter_contigs.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]

必选参数:
  -s SAMPLE   样本 ID
  -t CPUS     线程数
  -w WORKDIR  工作目录
  -r REPO     管线仓库路径

可选参数:
  --force     忽略产物新旧，强制重跑
EOF
}

export MGX_OPTS_STRING="s:SAMPLE t:THREADS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE THREADS WORKDIR REPO

BAC_CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/virus/assembly/${SAMPLE}"
CONTIGS="${OUTDIR}/${SAMPLE}.contigs.fa"

if [ ! -s "${BAC_CONTIGS}" ]; then
    echo "[ERROR] 细菌组装 contigs 不存在（需先完成细菌轨组装）: ${BAC_CONTIGS}"
    exit 1
fi

mgx_begin

# 原子发布登记：中断时清掉发布中的临时文件
mgx_cleanup_register_file "${CONTIGS}.tmp"

if [ "${FORCE:-0}" -eq 0 ] && [ -s "${CONTIGS}" ] && [ "${CONTIGS}" -nt "${BAC_CONTIGS}" ]; then
    echo "[vir_filter] 结果已存在且新于细菌 contigs，跳过"
    mgx_end "vir_filter"; exit 0
fi

echo "[vir_filter] ${SAMPLE} | 过滤 ≥1500 bp（源自细菌组装 contigs）..."
mgx_try mgx_conda assembly \
    seqkit seq -j "${THREADS}" -m 1500 -w 0 "${BAC_CONTIGS}" > "${CONTIGS}.tmp" || {
        RC=$?; echo "[ERROR] seqkit 过滤失败（exit ${RC}）"; rm -f "${CONTIGS}.tmp"; exit ${RC};
    }
mv -f "${CONTIGS}.tmp" "${CONTIGS}"

N_IN=$(grep -c '^>' "${BAC_CONTIGS}" || true)
N_OUT=$(grep -c '^>' "${CONTIGS}" || true)
echo "[vir_filter] 完成 | 细菌 ${N_IN} 条 → 病毒输入 ${N_OUT} 条（≥1500 bp，保留 $(awk "BEGIN{printf \"%.1f\", ${N_OUT}*100/(${N_IN}>0?${N_IN}:1)}")%）"
mgx_end "vir_filter"
