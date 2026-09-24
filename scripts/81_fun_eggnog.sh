#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 81_fun_eggnog.sh
# 功  能: eggNOG-mapper v2 真菌功能注释（COG / KEGG KO / GO / EC / CAZy）
#         工具版本：eggNOG-mapper 2.1.13（conda env: eggnog）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/eggnog/
#           eggnog.emapper.annotations      — 主注释表（COG/KO/GO/EC/CAZy）
#           eggnog.emapper.seed_orthologs   — 同源 OG 命中
# 用  法: bash 81_fun_eggnog.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 81_fun_eggnog.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 16-32）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin

RESULT_DIR="${WORKDIR}/result/fungi/eggnog"
EGGNOG_DB="${REPO}/db/eggnog"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
ANNOTATIONS="${RESULT_DIR}/eggnog.emapper.annotations"
TEMP_DIR="${RESULT_DIR}/tmp"

if [ ! -d "${EGGNOG_DB}" ]; then echo "[ERROR] eggNOG 数据库不存在: ${EGGNOG_DB}"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在: ${PRODIGAL_DIR}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${ANNOTATIONS}" ] && [ -s "${ANNOTATIONS}" ]; then
    echo "[INFO] 结果已存在，跳过"; exit 0
fi

mkdir -p "${RESULT_DIR}" "${TEMP_DIR}"

echo "[fun_eggnog] 合并各样本 FAA 文件..."
mapfile -t FAA_FILES < <(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null)
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

N_PROTEINS=$(grep -c "^>" "${COMBINED_FAA}")
echo "[fun_eggnog] 合并完成: ${#FAA_FILES[@]} 个样本, ${N_PROTEINS} 条蛋白序列"
echo "[fun_eggnog] 开始 eggNOG-mapper 注释 | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda eggnog \
    emapper.py \
        -m diamond \
        --itype proteins \
        --data_dir "${EGGNOG_DB}" \
        --dbmem \
        -i "${COMBINED_FAA}" \
        --cpu "${CPUS}" \
        -o eggnog \
        --output_dir "${RESULT_DIR}" \
        --temp_dir "${TEMP_DIR}" \
        --override \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] emapper.py 失败（exit: ${EXIT_CODE}）"; exit ${EXIT_CODE}; fi
rm -rf "${TEMP_DIR}"

N_ANNOTATED=$(grep -v "^#" "${ANNOTATIONS}" 2>/dev/null | wc -l || echo "0")
echo "[fun_eggnog] 完成 | 注释: ${N_ANNOTATED} | 输出: ${RESULT_DIR}/"
mgx_end "fun_eggnog"
