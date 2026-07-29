#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 39d_bac_instrain_compare.sh
# 功  能: 跨样本菌株群体 ANI 比较（inStrain compare，popANI 聚类）
#         工具版本：inStrain 1.10+（conda env: instrain）
# 依  赖: 39c_bac_instrain_profile.sh 全部样本的输出（profile 目录）
# 输  入: ${WORKDIR}/result/binning/instrain_profile/*/（所有样本 profile）
#         ${WORKDIR}/result/binning/instrain_map/combined_mags.stb
# 输  出: ${WORKDIR}/result/binning/instrain_compare/output/
#           comparisonsTable.tsv            — 成对样本比较结果（popANI、覆盖重叠等）
#           *_genomeWide_compare.tsv        — 基因组级跨样本 popANI 矩阵
#
# ── 说明 ──────────────────────────────────────────────────────────────────────
#   本步骤为 aggregate，聚合所有样本的 inStrain profile，计算群体内 ANI
#   （popANI），判断跨样本/跨受试者是否为同一菌株（ANI ≥99.999% = 同株）。
#   样本数 < 2 时优雅跳过（单样本项目无需比较）。
#
# 参  考: Olm et al. 2021 Nat Biotechnol (inStrain)
# 用  法: bash 39d_bac_instrain_compare.sh -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 39d_bac_instrain_compare.sh -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

CPUS=""; WORKDIR=""; REPO=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数（-t/-w/-r）"; show_help; exit 1; fi
done

SECONDS=0
PROFILE_BASE="${WORKDIR}/result/binning/instrain_profile"
COMBINED_STB="${WORKDIR}/result/binning/instrain_map/combined_mags.stb"
OUTDIR="${WORKDIR}/result/binning/instrain_compare"
OUTPUT_COMPARISONS="${OUTDIR}/output/comparisonsTable.tsv"

if [ ! -f "${COMBINED_STB}" ]; then
    echo "[ERROR] scaffold-to-bin 文件不存在: ${COMBINED_STB}"; exit 1
fi

PROFILE_DIRS=()
if [ -d "${PROFILE_BASE}" ]; then
    for pdir in "${PROFILE_BASE}"/*; do
        if [ -d "${pdir}/output" ]; then
            GENOME_INFO="${pdir}/output/$(basename "${pdir}")_genome_info.tsv"
            if [ -f "${GENOME_INFO}" ] && [ -s "${GENOME_INFO}" ]; then
                PROFILE_DIRS+=("${pdir}")
            fi
        fi
    done
fi

N_PROFILES=${#PROFILE_DIRS[@]}
if [ "${N_PROFILES}" -lt 2 ]; then
    echo "[instrain_compare] WARNING: 样本数 < 2（共 ${N_PROFILES} 个有效 profile），跳过跨样本比较"
    mkdir -p "${OUTDIR}/output"
    : > "${OUTPUT_COMPARISONS}"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_COMPARISONS}" ] && [ -s "${OUTPUT_COMPARISONS}" ]; then
    echo "[instrain_compare] 结果已存在，跳过: ${OUTPUT_COMPARISONS}"; exit 0
fi

mkdir -p "${OUTDIR}"

set +e
echo "[instrain_compare] 跨样本 popANI 比较 | ${N_PROFILES} 个样本 | 线程: ${CPUS}"
conda run --prefix "${REPO}/envs/instrain" --no-capture-output \
    inStrain compare \
        -i "${PROFILE_DIRS[@]}" \
        -o "${OUTDIR}" \
        -s "${COMBINED_STB}" \
        -p "${CPUS}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] inStrain compare 失败"; exit ${EXIT_CODE}; fi

N_COMPARISONS=0
if [ -f "${OUTPUT_COMPARISONS}" ]; then
    N_COMPARISONS=$(($(wc -l < "${OUTPUT_COMPARISONS}") - 1))
fi

echo "[instrain_compare] 完成，耗时 ${SECONDS}s | ${N_PROFILES} 样本 → ${N_COMPARISONS} 成对比较"
echo "[提示] 查看 ${OUTDIR}/output/ 下的 comparisonsTable.tsv 和 *_genomeWide_compare.tsv 获取 popANI 结果"
