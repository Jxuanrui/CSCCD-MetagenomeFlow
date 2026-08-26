#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 29_bac_defense_finder.sh
# 功  能: 细菌防御系统检测（CRISPR/Restriction/其他免疫系统）
#         工具版本：DefenseFinder 1.x + MacSyFinder 2.x（conda env: defense-finder）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/defense_finder/
#           defense_finder_systems.tsv  — 检出防御系统汇总
#           defense_finder_genes.tsv    — 基因级别注释
#
# ── 关键参数 ──────────────────────────────────────────────────────────────────
#   --db-type ordered-replicon → 对宏基因组用 unordered（NR蛋白没有连续基因组座标）
#   使用 unordered 模式绕过基因组上下文依赖，适合 NR 蛋白集
#
# 参  考: Tesson et al. 2022 Nature Comm (DefenseFinder)
# 用  法: bash 29_bac_defense_finder.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 29_bac_defense_finder.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

CPUS=""
WORKDIR=""
REPO=""
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

if [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/defense_finder"
SENTINEL="${RESULT_DIR}/defense_finder_systems.tsv"
RAW_SYSTEMS="${RESULT_DIR}/protein_nr_defense_finder_systems.tsv"
RAW_GENES="${RESULT_DIR}/protein_nr_defense_finder_genes.tsv"
RAW_HMMER="${RESULT_DIR}/protein_nr_defense_finder_hmmer.tsv"
RENAMED_GENES="${RESULT_DIR}/defense_finder_genes.tsv"
RENAMED_HMMER="${RESULT_DIR}/defense_finder_hmmer.tsv"
DF_DB="${REPO}/db/defense-finder/defense-finder-db/models"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] DefenseFinder 结果已存在，跳过: ${SENTINEL}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[defense_finder] 开始防御系统检测 | 线程: ${CPUS}"

set +e
conda run --prefix "${REPO}/envs/defense-finder" --no-capture-output \
    defense-finder run \
        --models-dir "${DF_DB}" \
        --db-type unordered \
        --workers "${CPUS}" \
        --out-dir "${RESULT_DIR}" \
        "${PROTEIN_NR}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] defense-finder 失败（exit code: ${EXIT_CODE}）"; exit ${EXIT_CODE}
fi

if [ -f "${RAW_SYSTEMS}" ] && [ ! -f "${SENTINEL}" ]; then
    mv "${RAW_SYSTEMS}" "${SENTINEL}"
fi
if [ -f "${RAW_GENES}" ] && [ ! -f "${RENAMED_GENES}" ]; then
    mv "${RAW_GENES}" "${RENAMED_GENES}"
fi
if [ -f "${RAW_HMMER}" ] && [ ! -f "${RENAMED_HMMER}" ]; then
    mv "${RAW_HMMER}" "${RENAMED_HMMER}"
fi

if [ ! -f "${SENTINEL}" ]; then
    # DefenseFinder 未检出任何防御系统时不生成 *_defense_finder_systems.tsv
    # （非报错场景，genes.tsv/hmmer.tsv 仍会正常产出），写空表头文件作为 sentinel
    echo "[defense_finder] 未检出防御系统，写入空结果表: ${SENTINEL}"
    echo -e "sys_id\ttype\tsubtype\tprotein_in_syst\tgenes_count\tname_of_profiles_in_sys" > "${SENTINEL}"
fi

N_SYSTEMS=$(awk 'NR>1' "${SENTINEL}" 2>/dev/null | wc -l || echo "N/A")
echo "[defense_finder] 完成，耗时 ${SECONDS}s | 防御系统: ${N_SYSTEMS} | 输出: ${RESULT_DIR}/"
