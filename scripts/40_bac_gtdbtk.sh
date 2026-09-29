#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 40_bac_gtdbtk.sh
# 功  能: MAG 系统发育分类（GTDB-Tk classify_wf，GTDB R214）
#         工具版本：GTDB-Tk 2.4+（conda env: gtdbtk）
#         数  据：db/gtdb/（GTDB R214 + Mash 草图）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
# 输  出: ${WORKDIR}/result/binning/gtdbtk/
#           classify/gtdbtk.bac120.summary.tsv   — 细菌分类汇总
#           classify/gtdbtk.ar53.summary.tsv     — 古菌分类汇总
#           align/gtdbtk.bac120.user_msa.fasta.gz — 多序列比对
#
# ── 环境变量 ──────────────────────────────────────────────────────────────────
#   GTDBTK_DATA_PATH 必须在 conda 环境中已设置，指向 db/gtdtbtk/
#   如未设置，脚本自动设为 ${REPO}/db/gtdbtk/
#
# 参  考: Chaumeil et al. 2022 NAR (GTDB-Tk v2)
# 用  法: bash 40_bac_gtdbtk.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 40_bac_gtdbtk.sh -t CPUS -w WORKDIR -r REPO
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
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/binning/gtdbtk"
SENTINEL="${OUTDIR}/classify/gtdbtk.bac120.summary.tsv"

N_MAGS=0
if [ -d "${MAGS_DIR}" ]; then
    N_MAGS=$(find "${MAGS_DIR}" -maxdepth 1 -type f -name "*.fa" | wc -l)
fi
if [ "${N_MAGS}" -eq 0 ]; then
    echo "[gtdbtk] WARNING: 去冗余 MAGs 为 0，创建空结果哨兵: ${SENTINEL}"
    mkdir -p "$(dirname "${SENTINEL}")"
    : > "${SENTINEL}"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[gtdbtk] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# 清理残留的悬空符号链接：gtdbtk 的 symlink_f() 用 os.path.isfile() 判断是否
# 需要先删除旧链接，但该调用对悬空链接（目标不存在）返回 False，导致清理被跳过，
# 随后 os.symlink() 因链接已存在而抛出 FileExistsError（gtdbtk 2.5.2 已知边界情况）
find "${OUTDIR}" -maxdepth 1 -xtype l -delete 2>/dev/null || true

# 确保 GTDBTK_DATA_PATH 指向正确
GTDB_PATH="${REPO}/db/gtdbtk"
if [ -z "${GTDBTK_DATA_PATH:-}" ]; then
    export GTDBTK_DATA_PATH="${GTDB_PATH}"
elif [ "${GTDBTK_DATA_PATH}" != "${GTDB_PATH}" ]; then
    echo "[gtdbtk] NOTE: 当前 GTDBTK_DATA_PATH=${GTDBTK_DATA_PATH}"
fi

echo "[gtdbtk] MAG 分类（分步执行，避开 classify_wf 的 skani 依赖）| 线程: ${CPUS}"
# Step 1: identify markers
EXIT_CODE=0
mgx_try mgx_conda gtdbtk gtdbtk identify \
        --genome_dir "${MAGS_DIR}" \
        --out_dir "${OUTDIR}" \
        -x fa \
        --cpus "${CPUS}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] gtdbtk identify 失败"; exit ${EXIT_CODE}; fi

# Step 2: align
EXIT_CODE=0
mgx_try mgx_conda gtdbtk gtdbtk align \
        --identify_dir "${OUTDIR}" \
        --out_dir "${OUTDIR}" \
        --cpus "${CPUS}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] gtdbtk align 失败"; exit ${EXIT_CODE}; fi

# Step 3: classify
EXIT_CODE=0
mgx_try mgx_conda gtdbtk gtdbtk classify \
        --genome_dir "${MAGS_DIR}" \
        --align_dir "${OUTDIR}" \
        --out_dir "${OUTDIR}" \
        -x fa \
        --cpus "${CPUS}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] gtdbtk classify 失败"; exit ${EXIT_CODE}; fi

N_CLASSIFIED=$(awk 'NR>1' "${SENTINEL}" 2>/dev/null | wc -l || echo 0)
echo "[gtdbtk] 分类 MAGs: ${N_CLASSIFIED}"
mgx_end "gtdbtk"
