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

show_help() {
cat << EOF
用法: bash 81_fun_eggnog.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 16-32）
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

RESULT_DIR="${WORKDIR}/result/fungi/eggnog"
EGGNOG_DB="${REPO}/db/eggnog"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
ANNOTATIONS="${RESULT_DIR}/eggnog.emapper.annotations"
TEMP_DIR="${RESULT_DIR}/tmp"

if [ ! -d "${EGGNOG_DB}" ]; then echo "[ERROR] eggNOG 数据库不存在: ${EGGNOG_DB}"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在: ${PRODIGAL_DIR}"; exit 1; fi

if [ -f "${ANNOTATIONS}" ] && [ -s "${ANNOTATIONS}" ]; then
    echo "[INFO] 结果已存在，跳过"; exit 0
fi

mkdir -p "${RESULT_DIR}" "${TEMP_DIR}"

echo "[fun_eggnog] 合并各样本 FAA 文件..."
FAA_FILES=($(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null))
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

N_PROTEINS=$(grep -c "^>" "${COMBINED_FAA}")
echo "[fun_eggnog] 合并完成: ${#FAA_FILES[@]} 个样本, ${N_PROTEINS} 条蛋白序列"
echo "[fun_eggnog] 开始 eggNOG-mapper 注释 | 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/eggnog" --no-capture-output \
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
        --override

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] emapper.py 失败（exit: ${EXIT_CODE}）"; exit ${EXIT_CODE}; fi
rm -rf "${TEMP_DIR}"

N_ANNOTATED=$(grep -v "^#" "${ANNOTATIONS}" 2>/dev/null | wc -l || echo "0")
echo "[fun_eggnog] 完成，耗时 ${SECONDS}s | 注释: ${N_ANNOTATED} | 输出: ${RESULT_DIR}/"
