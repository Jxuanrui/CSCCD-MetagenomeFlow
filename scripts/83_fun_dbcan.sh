#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 83_fun_dbcan.sh
# 功  能: 真菌 CAZyme 注释（run_dbcan, HMMER+DIAMOND 双方法，eCAMI 对超大规模合并蛋白集不可行已禁用）
#         工具版本：run_dbcan 4.x（conda env: dbcan）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/dbcan/overview.txt
# 用  法: bash 83_fun_dbcan.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 83_fun_dbcan.sh -t CPUS -w WORKDIR -r REPO

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

RESULT_DIR="${WORKDIR}/result/fungi/dbcan"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
DBCAN_DB="${REPO}/db/dbcan3"
SENTINEL="${RESULT_DIR}/overview.txt"

if [ ! -d "${DBCAN_DB}" ]; then echo "[ERROR] dbCAN DB 不存在: ${DBCAN_DB}"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[INFO] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

mapfile -t FAA_FILES < <(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null)
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

echo "[fun_dbcan] 开始真菌 CAZyme 注释 | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda dbcan \
    run_dbcan \
        "${COMBINED_FAA}" \
        protein \
        --tools diamond hmmer \
        --dia_cpu "${CPUS}" \
        --hmm_cpu "${CPUS}" \
        --db_dir "${DBCAN_DB}" \
        --out_dir "${RESULT_DIR}" \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] run_dbcan 失败"; exit ${EXIT_CODE}; fi

N_CAZYMES=$(awk 'NR>1' "${SENTINEL}" 2>/dev/null | wc -l || echo "0")
echo "[fun_dbcan] 完成 | CAZyme: ${N_CAZYMES} | 输出: ${RESULT_DIR}/"
mgx_end "fun_dbcan"
