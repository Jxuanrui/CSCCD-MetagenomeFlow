#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 38_bac_drep.sh
# 功  能: MAG 去冗余（dRep，默认 95% ANI / 物种级）
#         工具版本：dRep 3.6+（conda env: drep）
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
#
# 参  考: Olm et al. 2017 ISME J (dRep)
# 用  法: bash 38_bac_drep.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 38_bac_drep.sh -t CPUS -w WORKDIR -r REPO
可选参数:
  -a ANI_THRESHOLD    去冗余 ANI 阈值（默认 0.95，0.97=菌株级）
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

ANI="0.95"; CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a) ANI="$2";    shift 2 ;;
        -t) CPUS="$2";   shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";   shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
INPUT_DIR="${WORKDIR}/result/binning/checkm2/drep_input"
OUTDIR="${WORKDIR}/result/binning/drep"
SENTINEL="${OUTDIR}/dereplicated_genomes"
SENTINEL_FILE="${OUTDIR}/.done"

if [ ! -d "${INPUT_DIR}" ] || [ -z "$(ls "${INPUT_DIR}"/*.fa 2>/dev/null)" ]; then
    echo "[ERROR] dRep 输入目录为空: ${INPUT_DIR}"; exit 1
fi

if [ -f "${SENTINEL_FILE}" ]; then echo "[drep] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[drep] 去冗余 | ANI: ${ANI} | 线程: ${CPUS}"
conda run --prefix "${REPO}/envs/drep" --no-capture-output \
    dRep dereplicate \
        "${OUTDIR}" \
        -g "${INPUT_DIR}"/*.fa \
        -sa "${ANI}" \
        -pa 0.9 \
        -nc 0.30 \
        -p "${CPUS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] dRep 失败"; exit ${EXIT_CODE}; fi

N_MAGS=$(ls "${SENTINEL}"/*.fa 2>/dev/null | wc -l || echo 0)
touch "${SENTINEL_FILE}"
echo "[drep] 完成，耗时 ${SECONDS}s | 去冗余后 MAGs: ${N_MAGS}"
