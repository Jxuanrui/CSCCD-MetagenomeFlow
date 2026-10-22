#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 80_fun_prodigal.sh
# 功  能: Prodigal v2.6.3 真菌蛋白编码基因预测（-p meta 模式）
#         真菌使用标准遗传密码（与细菌相同，-p meta 即可）
# 依  赖: 78_fun_megahit.sh 的输出（${SAMPLE}.contigs.fa）
# 输  入: ${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/fungi/prodigal/${SAMPLE}/
#           ${SAMPLE}.faa   — 蛋白序列（下游 eggNOG/KEGG/dbCAN/VFDB/AMR 注释输入）
#           ${SAMPLE}.fna   — 核苷酸序列
#           ${SAMPLE}.gff   — 基因坐标（GFF3 格式）
# 用  法: bash 80_fun_prodigal.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 80_fun_prodigal.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数（Prodigal 单线程，保留供 pipeline 调用一致性）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash 80_fun_prodigal.sh -s SRR28210342 -t 1 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# 注：-t 仅占位（Prodigal 单线程），CPUS 不在脚本内使用，故不设默认值
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE WORKDIR REPO

mgx_begin

INPUT_CONTIGS="${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
RESULT_DIR="${WORKDIR}/result/fungi/prodigal/${SAMPLE}"
FAA="${RESULT_DIR}/${SAMPLE}.faa"
FNA="${RESULT_DIR}/${SAMPLE}.fna"
GFF="${RESULT_DIR}/${SAMPLE}.gff"

if [ ! -f "${INPUT_CONTIGS}" ]; then echo "[ERROR] 输入不存在: ${INPUT_CONTIGS}"; exit 1; fi
if [ ! -s "${INPUT_CONTIGS}" ]; then echo "[ERROR] 文件为空"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${FAA}" ] && [ -s "${FAA}" ]; then
    echo "[INFO] 结果已存在，跳过: ${SAMPLE}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[fun_prodigal] 开始真菌基因预测: ${SAMPLE} | 输入: ${INPUT_CONTIGS}"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    prodigal \
        -i "${INPUT_CONTIGS}" \
        -a "${FAA}" \
        -d "${FNA}" \
        -f gff \
        -o "${GFF}" \
        -p meta \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] Prodigal 失败（exit: ${EXIT_CODE}）"
    rm -f "${FAA}" "${FNA}" "${GFF}"; exit ${EXIT_CODE}
fi

N_TOTAL=$(grep -c "^>" "${FAA}" 2>/dev/null || echo "0")
echo "[fun_prodigal] ${SAMPLE} 完成 | 预测基因: ${N_TOTAL} | 输出: ${RESULT_DIR}/"
mgx_end "fun_prodigal"
