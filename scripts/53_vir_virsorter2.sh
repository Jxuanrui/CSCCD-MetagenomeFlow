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

# --- 运行 VirSorter2（SIF 容器，需隔离宿主机 Python 环境） ---
# activate.sh 把 miniforge3/bin 加入 PATH，SIF 容器继承后会拾取宿主机的
# pkg_resources（Python 版本不匹配），导致 DistributionNotFound。
# 解决：用 env -i 清空环境后只传必要变量，在子 shell 中运行。
set +e
echo "[virsorter2] ${SAMPLE} | VirSorter2 病毒预测 ..."
(env -i \
    HOME="${HOME}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
    APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${HOME}/.apptainer}" \
    "${REPO}/envs/virsorter2/bin/virsorter" run --use-conda-off \
    -w "${OUTDIR}" \
    -i "${CONTIGS}" \
    --db-dir "${VS2_DB}" \
    --min-length 1000 \
    --include-groups "dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae" \
    -j "${CPUS}" \
    --verbose) 2>&1

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] virsorter2 失败"; exit ${EXIT_CODE}; fi

mgx_end "virsorter2"
