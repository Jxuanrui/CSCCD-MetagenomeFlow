#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 16b_bac_filter_contigs.sh
# 功  能: 分箱专用 contig 过滤（≥1000 bp）
#         依据 R-20261116-27/30：分箱输入统一 ≥1000 bp；功能注释轨保留 500 bp 全集，
#         两套并行不混用（注释轨读原始 contigs.fa，分箱轨读 contigs_ge1000.fa）。
# 工具: seqkit（conda env: assembly）
# 输  入: ${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs_ge1000.fa
# 用  法: bash 16b_bac_filter_contigs.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

CPUS=8; FORCE=0   # 其余 SAMPLE/WORKDIR/REPO 由 mgx_parse 赋值（与 kneaddata 同款惯例）
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE WORKDIR REPO

mgx_begin
DIR="${WORKDIR}/result/assembly/megahit/${SAMPLE}"
CONTIGS="${DIR}/${SAMPLE}.contigs.fa"
OUT="${DIR}/${SAMPLE}.contigs_ge1000.fa"

if [ ! -s "${CONTIGS}" ]; then echo "[ERROR] contigs 不存在: ${CONTIGS}"; exit 1; fi

if [ "${FORCE:-0}" -eq 0 ] && [ -s "${OUT}" ] && [ "${OUT}" -nt "${CONTIGS}" ]; then
    echo "[filter_ge1000] 结果已存在且新于输入，跳过"
    mgx_end "filter_ge1000"; exit 0
fi

echo "[filter_ge1000] ${SAMPLE} | 过滤 ≥1000 bp ..."
mgx_try mgx_conda assembly \
    seqkit seq -j "${CPUS}" -m 1000 -w 0 "${CONTIGS}" > "${OUT}.tmp" || {
        RC=$?; echo "[ERROR] seqkit 过滤失败（exit ${RC}）"; rm -f "${OUT}.tmp"; exit ${RC};
    }
mv -f "${OUT}.tmp" "${OUT}"

N_IN=$(grep -c '^>' "${CONTIGS}" || true)
N_OUT=$(grep -c '^>' "${OUT}" || true)
echo "[filter_ge1000] 完成 | 输入 ${N_IN} 条 → 输出 ${N_OUT} 条（≥1000 bp，保留 $(awk "BEGIN{printf \"%.1f\", ${N_OUT}*100/(${N_IN}>0?${N_IN}:1)}")%）"
mgx_end "filter_ge1000"
