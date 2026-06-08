#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 85_fun_amr.sh
# 功  能: 抗真菌药物耐药基因检测（AMRFinderPlus，覆盖 CYP51/FKS 等）
#         工具版本：AMRFinderPlus 3.12+（conda env: amr）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/amr/amrfinder_results.tsv
# 用  法: bash 85_fun_amr.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 85_fun_amr.sh -t CPUS -w WORKDIR -r REPO

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

if [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数"; show_help; exit 1
fi

SECONDS=0

RESULT_DIR="${WORKDIR}/result/fungi/amr"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
OUTPUT="${RESULT_DIR}/amrfinder_results.tsv"
AMR_DB="${REPO}/db/amrfinder/latest"

if [ ! -d "${AMR_DB}" ]; then echo "[ERROR] AMR DB 不存在: ${AMR_DB}"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在"; exit 1; fi
if [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then echo "[INFO] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

FAA_FILES=($(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null))
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

echo "[fun_amr] 开始耐药基因检测 | 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/amr" --no-capture-output \
    amrfinder \
        --protein "${COMBINED_FAA}" \
        --database "${AMR_DB}" \
        --output "${OUTPUT}" \
        --threads "${CPUS}" \
        --ident_min 0.9 \
        --coverage_min 0.6 \
        --plus

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] amrfinder 失败"; rm -f "${OUTPUT}"; exit ${EXIT_CODE}; fi

N_HITS=$(awk 'NR>1' "${OUTPUT}" 2>/dev/null | wc -l || echo "0")
echo "[fun_amr] 完成，耗时 ${SECONDS}s | 耐药基因: ${N_HITS} | 输出: ${OUTPUT}"
