#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 23_bac_amrfinder.sh
# 功  能: 抗生素耐药基因检测（AMRFinderPlus）
#         工具版本：AMRFinderPlus 3.12+（conda env: amr）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/amrfinder/
#           amrfinder_results.tsv — 耐药基因完整报告
#
# ── 关键参数 ──────────────────────────────────────────────────────────────────
#   --ident_min 0.9 / --coverage_min 0.6  — NCBI推荐严格阈值
#   --plus                                — 开启应激耐受/毒力/点突变
#
# 参  考: Feldgarden et al. 2021 Sci Rep; NCBI AMRFinderPlus docs
# 用  法: bash 23_bac_amrfinder.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 23_bac_amrfinder.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""
WORKDIR=""
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/amrfinder"
OUTPUT="${RESULT_DIR}/amrfinder_results.tsv"
AMR_DB="${REPO}/db/amrfinder/latest"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"; exit 1
fi

if [ ! -d "${AMR_DB}" ]; then
    echo "[ERROR] AMRFinderPlus 数据库目录不存在: ${AMR_DB}"; exit 1
fi

if [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then
    echo "[INFO] AMRFinder 结果已存在，跳过: ${OUTPUT}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[amrfinder] 开始耐药基因检测 | 线程: ${CPUS}"

set +e
conda run --prefix "${REPO}/envs/amr" --no-capture-output \
    amrfinder \
        --protein "${PROTEIN_NR}" \
        --database "${AMR_DB}" \
        --output "${OUTPUT}" \
        --threads "${CPUS}" \
        --ident_min 0.9 \
        --coverage_min 0.6 \
        --plus

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] amrfinder 失败（exit code: ${EXIT_CODE}）"; rm -f "${OUTPUT}"; exit ${EXIT_CODE}
fi

N_HITS=$(awk 'NR>1' "${OUTPUT}" 2>/dev/null | wc -l || echo "N/A")
echo "[amrfinder] 完成，耗时 ${SECONDS}s | 耐药基因命中: ${N_HITS} | 输出: ${OUTPUT}"
