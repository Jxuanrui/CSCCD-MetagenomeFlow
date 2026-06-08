#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 83_fun_dbcan.sh
# 功  能: 真菌 CAZyme 注释（run_dbcan, HMMER+DIAMOND+eCAMI 三方法）
#         工具版本：run_dbcan 4.x（conda env: dbcan）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/dbcan/overview.txt
# 用  法: bash 83_fun_dbcan.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 83_fun_dbcan.sh -t CPUS -w WORKDIR -r REPO

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

RESULT_DIR="${WORKDIR}/result/fungi/dbcan"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
DBCAN_DB="${REPO}/db/dbcan3"
SENTINEL="${RESULT_DIR}/overview.txt"

if [ ! -d "${DBCAN_DB}" ]; then echo "[ERROR] dbCAN DB 不存在: ${DBCAN_DB}"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在"; exit 1; fi
if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[INFO] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

FAA_FILES=($(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null))
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

echo "[fun_dbcan] 开始真菌 CAZyme 注释 | 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/dbcan" --no-capture-output \
    run_dbcan \
        "${COMBINED_FAA}" \
        protein \
        --tools all \
        --db_dir "${DBCAN_DB}" \
        --out_dir "${RESULT_DIR}" \
        --cpu "${CPUS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] run_dbcan 失败"; exit ${EXIT_CODE}; fi

N_CAZYMES=$(awk 'NR>1' "${SENTINEL}" 2>/dev/null | wc -l || echo "0")
echo "[fun_dbcan] 完成，耗时 ${SECONDS}s | CAZyme: ${N_CAZYMES} | 输出: ${RESULT_DIR}/"
