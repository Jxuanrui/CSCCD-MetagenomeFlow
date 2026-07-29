#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 17_bac_prodigal.sh
# 功  能: Prodigal v2.6.3 宏基因组蛋白编码基因预测（-p meta 模式）
#         工具版本：Prodigal v2.6.3（conda env: assembly）
# 依  赖: 16_bac_megahit.sh 的输出（${SAMPLE}.contigs.fa）
# 输  入: ${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/assembly/prodigal/${SAMPLE}/
#           ${SAMPLE}.faa   — 蛋白序列（下游 eggNOG/CARD/dbCAN/VFDB 注释输入）
#           ${SAMPLE}.fna   — 核苷酸序列（下游 CD-HIT 去冗余 / Salmon 定量输入）
#           ${SAMPLE}.gff   — 基因坐标（GFF3 格式，含 partial/complete 标记）
#
# ── 参数说明 ─────────────────────────────────────────────────────────────────
#
#   -p meta（宏基因组模式，固定）
#     使用预训练参数集，适合 contig 太短、无法自训练的宏基因组数据。
#     -p single 仅适合高质量完整基因组（≥500kb）。
#
#   基因完整性标记（GFF/FASTA header 中）：
#     partial=00 — 完整基因（有起始 + 终止密码子），推荐用于下游分析
#     partial=10 — 5' 不完整（contig 左侧截断）
#     partial=01 — 3' 不完整（contig 右侧截断）
#     partial=11 — 两端均截断
#
#   注意：Prodigal 是单线程工具（无 -t 参数）。
#         大样本（>5G contigs）可拆分后并行，但通常 contigs <1G，无需拆分。
#
# 参  考: Hyatt et al. BMC Bioinformatics 2010; Prodigal v2.6.3
#         https://github.com/hyattpd/Prodigal
# 用  法: bash 17_bac_prodigal.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 17_bac_prodigal.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名（如 SRR28210342）
  -t  线程数（Prodigal 单线程，此参数保留供 pipeline 调用一致性）
  -w  工作目录（Project 路径）
  -r  MaxMetagenome 项目根目录

示例:
  bash 17_bac_prodigal.sh -s SRR28210342 -t 1 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome
EOF
}

SAMPLE=""
CPUS="1"
WORKDIR=""
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-s/-w/-r）"
    show_help; exit 1
fi

SECONDS=0

# --- 路径设置 ---

INPUT_CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"

RESULT_DIR="${WORKDIR}/result/assembly/prodigal/${SAMPLE}"
FAA="${RESULT_DIR}/${SAMPLE}.faa"
FNA="${RESULT_DIR}/${SAMPLE}.fna"
GFF="${RESULT_DIR}/${SAMPLE}.gff"

# --- 输入检查 ---

if [ ! -f "${INPUT_CONTIGS}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_CONTIGS}"
    echo "        请先运行 16_bac_megahit.sh"
    exit 1
fi
if [ ! -s "${INPUT_CONTIGS}" ]; then
    echo "[ERROR] contig 文件为空: ${INPUT_CONTIGS}"
    exit 1
fi

# --- 幂等性检查 ---

if [ -f "${FAA}" ] && [ -s "${FAA}" ]; then
    echo "[INFO] Prodigal 预测结果已存在，跳过: ${SAMPLE}"
    echo "       ${RESULT_DIR}/"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[prodigal] 开始基因预测: ${SAMPLE}"
echo "[prodigal] 模式: -p meta（宏基因组），输入: ${INPUT_CONTIGS}"

# --- 运行 Prodigal ---
# -p meta:  宏基因组匿名模式（使用预训练参数，适合短 contig 数据）
# -a ${FAA}: 蛋白序列输出（功能注释主要输入）
# -d ${FNA}: 核苷酸序列输出（CD-HIT 去冗余 / Salmon 定量输入）
# -f gff:   GFF3 格式输出（基因坐标，含 partial/complete 标记）
# -o ${GFF}: GFF 文件路径

set +e
conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    prodigal \
        -i "${INPUT_CONTIGS}" \
        -a "${FAA}" \
        -d "${FNA}" \
        -f gff \
        -o "${GFF}" \
        -p meta

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] Prodigal 运行失败（exit code: ${EXIT_CODE}）"
    rm -f "${FAA}" "${FNA}" "${GFF}"
    exit ${EXIT_CODE}
fi

if [ ! -f "${FAA}" ] || [ ! -s "${FAA}" ]; then
    echo "[ERROR] 蛋白序列文件未生成或为空: ${FAA}"
    exit 1
fi

# --- 统计摘要 ---

N_TOTAL=$(grep -c "^>" "${FAA}" 2>/dev/null || echo "N/A")
N_COMPLETE=$(grep -c "partial=00" "${FAA}" 2>/dev/null || echo "N/A")

if [ "${N_TOTAL}" != "N/A" ] && [ "${N_COMPLETE}" != "N/A" ] && [ "${N_TOTAL}" -gt 0 ]; then
    PCT_COMPLETE=$(awk "BEGIN{printf \"%.1f\", ${N_COMPLETE}/${N_TOTAL}*100}")
else
    PCT_COMPLETE="N/A"
fi

echo ""
echo "[prodigal] ${SAMPLE} 预测完成，耗时 ${SECONDS}s"
echo "[prodigal] 结果目录: ${RESULT_DIR}/"
echo "    预测基因总数:  ${N_TOTAL}"
echo "    完整基因数:    ${N_COMPLETE} (${PCT_COMPLETE}%，partial=00)"
echo "    关键输出:"
echo "    ├── ${SAMPLE}.faa  (蛋白序列，→ eggNOG/CARD/dbCAN/VFDB 注释)"
echo "    ├── ${SAMPLE}.fna  (核苷酸序列，→ CD-HIT 去冗余 → Salmon 定量)"
echo "    └── ${SAMPLE}.gff  (基因坐标，GFF3 格式)"
echo ""
echo "[提示] 下一步: 运行 18_bac_cdhit.sh 对全部样本基因集进行去冗余"
