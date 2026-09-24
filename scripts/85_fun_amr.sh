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

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 85_fun_amr.sh -t CPUS -w WORKDIR -r REPO

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

RESULT_DIR="${WORKDIR}/result/fungi/amr"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${RESULT_DIR}/combined_fungi.faa"
OUTPUT="${RESULT_DIR}/amrfinder_results.tsv"
AMR_DB="${REPO}/db/amrfinder/latest"

if [ ! -d "${AMR_DB}" ]; then echo "[ERROR] AMR DB 不存在: ${AMR_DB}"; exit 1; fi
if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then echo "[INFO] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

mapfile -t FAA_FILES < <(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null)
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

# 去除重复 ID（不同样本 Prodigal 会生成相同序列 ID，AMRFinder 不容忍重复）
# 用 `>` 后的第一个 token 作为唯一 key（而非完整 header 行）
awk '/^>/{split(substr($0,2),a," "); key=a[1]; if(key in seen){skip=1}else{seen[key]=1; skip=0; print; next}} !skip{print}' \
    "${COMBINED_FAA}" > "${COMBINED_FAA}.dedup" && mv "${COMBINED_FAA}.dedup" "${COMBINED_FAA}"
N_PROTEINS=$(grep -c "^>" "${COMBINED_FAA}" 2>/dev/null || echo 0)
echo "[fun_amr] 合并去重完成: ${#FAA_FILES[@]} 个样本, ${N_PROTEINS} 条蛋白序列"

echo "[fun_amr] 开始耐药基因检测 | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda amr \
    amrfinder \
        --protein "${COMBINED_FAA}" \
        --database "${AMR_DB}" \
        --output "${OUTPUT}" \
        --threads "${CPUS}" \
        --ident_min 0.9 \
        --coverage_min 0.6 \
        --plus \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[fun_amr] WARNING: amrfinder 失败（exit: ${EXIT_CODE}），创建空结果文件"
    echo -e "Protein identifier\tContig id\tStart\tStop\tStrand\tElement symbol\tElement name\tScope\tElement type\tElement subtype\tClass\tSubclass\tMethod\tTarget length\tReference sequence length\t% Coverage of reference sequence\t% Identity to reference sequence\tAlignment length\tAccession of closest sequence\tName of closest sequence\tHMM id\tHMM description" > "${OUTPUT}"
    exit 0
fi

N_HITS=$(awk 'NR>1' "${OUTPUT}" 2>/dev/null | wc -l || echo "0")
echo "[fun_amr] 完成 | 耐药基因: ${N_HITS} | 输出: ${OUTPUT}"
mgx_end "fun_amr"
