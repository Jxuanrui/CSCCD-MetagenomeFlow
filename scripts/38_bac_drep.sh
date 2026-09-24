#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 38_bac_drep.sh
# 功  能: MAG 去冗余（dRep，默认 95% ANI / 物种级）
#         工具版本：dRep 3.6+（conda env: drep；二级聚类默认 skani 0.3.2）
# 依  赖: 37_bac_checkm2.sh 的过滤输出
# 输  入: ${WORKDIR}/result/binning/checkm2/drep_input/*.fa
# 输  出: ${WORKDIR}/result/binning/drep/
#           dereplicated_genomes/*.fa     — 去冗余后 MAGs
#           data_tables/Cdb.csv           — 比较表
#           data_tables/Widb.csv          — 基因组信息表
#
# ── 阈值说明 ─────────────────────────────────────────────────────────────────
#   -sa 0.95：物种级去冗余（推荐用于大多数分析）
#   -sa 0.97：菌株级去冗余（更严格）
#   -sa 0.99：亚菌株级（容易过度分割）
#   -A skani：二级聚类算法，默认 skani（比 fastANI 更快；ANI 估计略有差异）
#
# 参  考: Olm et al. 2017 ISME J (dRep)
# 用  法: bash 38_bac_drep.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 38_bac_drep.sh -t CPUS -w WORKDIR -r REPO
可选参数:
  -a ANI_THRESHOLD    去冗余 ANI 阈值（默认 0.95，0.97=菌株级）
  -A S_ALGORITHM      二级聚类算法（默认 skani；可选 fastANI/ANImf）
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="a:ANI A:S_ALGO t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
ANI="0.95"; S_ALGO="skani"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
INPUT_DIR="${WORKDIR}/result/binning/checkm2/drep_input"
FILTERED_REPORT="${WORKDIR}/result/binning/checkm2/checkm2_filtered/filtered_report.tsv"
OUTDIR="${WORKDIR}/result/binning/drep"
SENTINEL="${OUTDIR}/dereplicated_genomes"
SENTINEL_FILE="${OUTDIR}/drep_done.txt"
GENOME_INFO="${OUTDIR}/checkm2_genomeInfo.csv"

N_INPUT_MAGS=0
if [ -d "${INPUT_DIR}" ]; then
    N_INPUT_MAGS=$(find "${INPUT_DIR}" -maxdepth 1 -type f -name "*.fa" | wc -l)
fi
if [ "${N_INPUT_MAGS}" -eq 0 ]; then
    echo "[drep] WARNING: dRep 输入 MAGs 为 0，创建空结果哨兵: ${SENTINEL_FILE}"
    mkdir -p "${OUTDIR}" "${SENTINEL}"
    touch "${SENTINEL_FILE}"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL_FILE}" ]; then echo "[drep] 结果已存在，跳过"; exit 0; fi

# dRep refuses to run into a populated work directory ("Both Bdb and a genome list are
# found- either don't include a genome list or start a new work directory"). Without
# this the script aborts after 7 s and then reports the STALE MAG count as success —
# the same error is present three times in the Project01 log (08-12, 08-20, 09-16).
rm -rf "${OUTDIR}"

mkdir -p "${OUTDIR}"

# 复用 CheckM2（37）已算好的 completeness/contamination，避免 dRep 内部重跑 checkm1 lineage_wf
GENOME_INFO_ARGS=()
if [ -f "${FILTERED_REPORT}" ]; then
    echo "genome,completeness,contamination" > "${GENOME_INFO}"
    awk -F'\t' 'NR>1 {print $1".fa,"$2","$3}' "${FILTERED_REPORT}" >> "${GENOME_INFO}"
    GENOME_INFO_ARGS=(--genomeInfo "${GENOME_INFO}")
fi

echo "[drep] 去冗余 | ANI: ${ANI} | 二级聚类: ${S_ALGO} | 线程: ${CPUS}"
EXIT_CODE=0
mgx_try mgx_conda drep dRep dereplicate \
        "${OUTDIR}" \
        -g "${INPUT_DIR}"/*.fa \
        -sa "${ANI}" \
        --S_algorithm "${S_ALGO}" \
        -pa 0.9 \
        -nc 0.30 \
        -p "${CPUS}" \
        "${GENOME_INFO_ARGS[@]}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] dRep 失败"; exit ${EXIT_CODE}; fi

N_MAGS=$(ls "${SENTINEL}"/*.fa 2>/dev/null | wc -l || echo 0)
touch "${SENTINEL_FILE}"
echo "[drep] 去冗余后 MAGs: ${N_MAGS}"
mgx_end "drep"
