#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 53_vir_virsorter2.sh
# 功  能: 病毒序列预测（VirSorter2，与 geNomad 取交集）
#         工具版本：VirSorter2 2.2+（conda env: virsorter2）
# 依  赖: 51_vir_megahit.sh 的 contigs
# 输  入: ${WORKDIR}/result/virus/assembly/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/virus/virsorter2/{sample}/
#           final-viral-boundary.tsv  — 病毒边界预测
#           final-viral-score.tsv     — 病毒评分
#
# 参  考: Guo et al. 2021 Nat Biotechnol (VirSorter2)
# 用  法: bash 53_vir_virsorter2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 53_vir_virsorter2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
CONTIGS="${WORKDIR}/result/virus/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/virus/virsorter2/${SAMPLE}"
SENTINEL="${OUTDIR}/final-viral-boundary.tsv"
COMBINED="${OUTDIR}/final-viral-combined.fa"
VS2_DB="${REPO}/db/virsorter2"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing: ${CONTIGS}"; exit 1; fi
if [ ! -d "${VS2_DB}" ]; then echo "[ERROR] VirSorter2 数据库不存在: ${VS2_DB}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[virsorter2] 结果已存在，跳过"; exit 0; fi
if [ ${FORCE} -eq 0 ] && [ -f "${COMBINED}" ] && [ ! -f "${SENTINEL}" ]; then
    echo "[WARN] final-viral-combined.fa 存在但 final-viral-boundary.tsv 缺失，删除不完整输出后重建"
    rm -rf "${OUTDIR}"
fi

# --- 运行 VirSorter2（保留原始 set +e 形式：命令带 CONDA_EXE 环境前缀与 2>&1，不套 mgx_conda/mgx_try）---
set +e
echo "[virsorter2] ${SAMPLE} | VirSorter2 病毒预测 ..."
# virsorter2 内部会调用 conda info --json 检测 conda 环境
# 需显式传入 CONDA_EXE 确保找到 conda 可执行文件
CONDA_EXE="${REPO}/miniforge3/bin/conda" \
conda run --prefix "${REPO}/envs/virsorter2" --no-capture-output \
    virsorter run --use-conda-off \
        -w "${OUTDIR}" \
        -i "${CONTIGS}" \
        --db-dir "${VS2_DB}" \
        --min-length 1000 \
        --include-groups "dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae" \
        -j "${CPUS}" \
        --verbose 2>&1

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] virsorter2 失败"; exit ${EXIT_CODE}; fi

mgx_end "virsorter2"
