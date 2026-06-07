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

show_help() { cat << EOF
用法: bash 40_bac_gtdbtk.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/binning/gtdbtk"
SENTINEL="${OUTDIR}/classify/gtdbtk.bac120.summary.tsv"

if [ ! -d "${MAGS_DIR}" ] || [ -z "$(ls "${MAGS_DIR}"/*.fa 2>/dev/null)" ]; then
    echo "[ERROR] 去冗余 MAGs 不存在: ${MAGS_DIR}"; exit 1
fi

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[gtdbtk] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# 确保 GTDBTK_DATA_PATH 指向正确
GTDB_PATH="${REPO}/db/gtdbtk"
if [ -z "${GTDBTK_DATA_PATH}" ]; then
    export GTDBTK_DATA_PATH="${GTDB_PATH}"
elif [ "${GTDBTK_DATA_PATH}" != "${GTDB_PATH}" ]; then
    echo "[gtdbtk] NOTE: 当前 GTDBTK_DATA_PATH=${GTDBTK_DATA_PATH}"
fi

echo "[gtdbtk] MAG 分类 | 线程: ${CPUS}"
conda run --prefix "${REPO}/envs/gtdbtk" --no-capture-output \
    gtdbtk classify_wf \
        --genome_dir "${MAGS_DIR}" \
        --out_dir "${OUTDIR}" \
        -x fa \
        --cpus "${CPUS}" \
        --skip_ani_screen \
        --force

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] gtdbtk 失败"; exit ${EXIT_CODE}; fi

N_CLASSIFIED=$(awk 'NR>1' "${SENTINEL}" 2>/dev/null | wc -l || echo 0)
echo "[gtdbtk] 完成，耗时 ${SECONDS}s | 分类 MAGs: ${N_CLASSIFIED}"
