#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 21_bac_eggnog.sh
# 功  能: eggNOG-mapper v2 综合功能注释（COG / KEGG KO / GO / EC / CAZy）
#         工具版本：eggNOG-mapper 2.1.13（conda env: eggnog）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/eggnog/
#           eggnog.emapper.annotations      — 主注释表（COG/KO/GO/EC/CAZy）
#           eggnog.emapper.seed_orthologs   — 同源 OG 命中
#
# ── 参数说明 ─────────────────────────────────────────────────────────────────
#
#   -m diamond：使用 DIAMOND 进行同源搜索（速度最快，推荐宏基因组）
#   --itype proteins：输入为蛋白序列（预测已完成，不重新调用 Prodigal）
#   --override：覆盖已有输出文件（确保重新运行时正常）
#   --dbmem：将 eggNOG 注释数据库加载到内存（加速注释步骤）
#
#   两步工作流（适合大数据 HPC）：
#     步骤1: emapper.py ... --no_annot  → 先跑 diamond 搜索
#     步骤2: emapper.py -m no_search --annotate_hits_table  → 再做注释
#
# 参  考: Cantalapiedra et al. 2021 Mol Biol Evol; https://github.com/eggnogdb/eggnog-mapper
# 用  法: bash 21_bac_eggnog.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 21_bac_eggnog.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 16-32）
  -w  工作目录（Project 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash 21_bac_eggnog.sh -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
EGGNOG_DB="${REPO}/db/eggnog"
RESULT_DIR="${WORKDIR}/result/annotation/eggnog"
OUTPUT_PREFIX="eggnog"
ANNOTATIONS="${RESULT_DIR}/${OUTPUT_PREFIX}.emapper.annotations"
TEMP_DIR="${RESULT_DIR}/tmp"

# --- 输入检查 ---

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"
    echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi
if [ ! -d "${EGGNOG_DB}" ]; then
    echo "[ERROR] eggNOG 数据库目录不存在: ${EGGNOG_DB}"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${ANNOTATIONS}" ] && [ -s "${ANNOTATIONS}" ]; then
    echo "[INFO] eggNOG 注释结果已存在，跳过"
    echo "       ${ANNOTATIONS}"
    exit 0
fi

mkdir -p "${RESULT_DIR}" "${TEMP_DIR}"

echo "[eggnog] 开始 eggNOG-mapper 综合功能注释"
echo "[eggnog] 输入: ${PROTEIN_NR}"
echo "[eggnog] 数据库: ${EGGNOG_DB}"
echo "[eggnog] 线程: ${CPUS}，预计耗时 30-120 分钟（取决于基因规模）"

# --- 运行 eggNOG-mapper ---
# -m diamond:    使用 DIAMOND 同源搜索（速度最快，宏基因组标准）
# --itype proteins: 输入类型（不重新运行 Prodigal）
# --override:    覆盖已有结果文件
# --dbmem:       内存加载注释数据库（加快注释步骤，需要 ~30G RAM）
# --temp_dir:    临时文件目录（建议本地 SSD）

EXIT_CODE=0
mgx_try mgx_conda eggnog emapper.py \
    -m diamond \
    --itype proteins \
    --data_dir "${EGGNOG_DB}" \
    --dbmem \
    -i "${PROTEIN_NR}" \
    --cpu "${CPUS}" \
    -o "${OUTPUT_PREFIX}" \
    --output_dir "${RESULT_DIR}" \
    --temp_dir "${TEMP_DIR}" \
    --override || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] emapper.py 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${ANNOTATIONS}" ] || [ ! -s "${ANNOTATIONS}" ]; then
    echo "[ERROR] 注释文件未生成: ${ANNOTATIONS}"
    exit 1
fi

rm -rf "${TEMP_DIR}"

# --- 统计摘要 ---

N_ANNOTATED=$(grep -v "^#" "${ANNOTATIONS}" | wc -l 2>/dev/null || echo "N/A")
N_KO=$(grep -v "^#" "${ANNOTATIONS}" | awk -F'\t' '$12!=""&&$12!="-"' | wc -l 2>/dev/null || echo "N/A")
N_COG=$(grep -v "^#" "${ANNOTATIONS}" | awk -F'\t' '$7!=""&&$7!="-"' | wc -l 2>/dev/null || echo "N/A")

echo ""
echo "[eggnog] 功能注释完成"
echo "[eggnog] 结果: ${RESULT_DIR}/"
echo "    注释基因数:  ${N_ANNOTATED}"
echo "    有 KO 注释:  ${N_KO}"
echo "    有 COG 注释: ${N_COG}"
echo "    主要输出: eggnog.emapper.annotations（COG/KO/GO/EC/CAZy）"
mgx_end "eggnog"
