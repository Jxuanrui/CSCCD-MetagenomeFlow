#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 73_fun_humann4_fungi.sh
# 功  能: 从已计算的 HUMAnN3 stratified 通路结果中提取真菌相关通路丰度
#
#   背景：ChocoPhlAn v201901_v31 含有真菌物种基因组（Candida/Aspergillus/
#         Saccharomyces/Malassezia/Cryptococcus/Pichia 等）。HUMAnN3 stratified
#         文件中真菌物种以 "g__Candida.s__Candida_albicans" 形式出现，而非
#         "|k__Eukaryota"（原始过滤条件错误，现已修正）。
#
#   注意：ChocoPhlAn 覆盖约 70+ 种肠道真菌，主要为临床常见菌（Candida/
#         Aspergillus）。若需全谱真菌定量，请使用 Script 75 (FunOMIC)。
#
# 工具版本：grep/awk（无需额外 conda env）
# 依  赖: 13_bac_humann3.sh 的输出（HUMAnN3 stratified pathabundance）
# 输  入: ${WORKDIR}/result/humann3/${SAMPLE}/stratified/${SAMPLE}_pathabundance_relab_stratified.tsv
# 输  出: ${WORKDIR}/result/fungi/humann4/${SAMPLE}/${SAMPLE}_fungi_pathabundance.tsv
# 用  法: bash 73_fun_humann4_fungi.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 73_fun_humann4_fungi.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数（本步骤为后处理，固定单线程；保留供 pipeline 统一调用）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

INPUT_STRATIFIED="${WORKDIR}/result/humann3/${SAMPLE}/stratified/${SAMPLE}_pathabundance_relab_stratified.tsv"
OUTDIR="${WORKDIR}/result/fungi/humann4/${SAMPLE}"
OUTPUT_TSV="${OUTDIR}/${SAMPLE}_fungi_pathabundance.tsv"

if [ ! -f "${INPUT_STRATIFIED}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_STRATIFIED}"
    echo "        请先运行 13_bac_humann3.sh"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
else

mkdir -p "${OUTDIR}"

# ChocoPhlAn 中真菌属名列表（基于 v201901_v31 数据库实际内容验证）
# 主要临床肠道真菌：Candida / Aspergillus / Saccharomyces / Malassezia /
#   Cryptococcus / Pichia / Nakaseomyces / Pneumocystis / Clavispora /
#   Lodderomyces / Yarrowia / Cutaneotrichosporon / Trichosporon
FUNGI_PATTERN="g__(Candida|Aspergillus|Saccharomyces|Malassezia|Cryptococcus|Pichia|Nakaseomyces|Pneumocystis|Clavispora|Lodderomyces|Yarrowia|Cutaneotrichosporon|Trichosporon|Debaryomyces|Kluyveromyces|Rhodotorula|Fusarium|Penicillium|Cladosporium|Alternaria|Mucor|Rhizopus)"

# 提取 header + 真菌物种分层通路行
set +e
{
    head -1 "${INPUT_STRATIFIED}"
    grep -E "\|${FUNGI_PATTERN}\." "${INPUT_STRATIFIED}" || true
} > "${OUTPUT_TSV}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 真菌 HUMAnN3 后处理失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

# 如果只有 header 行（无真菌命中），写入空结果并软退出
N_ROWS=$(awk 'NR>1' "${OUTPUT_TSV}" 2>/dev/null | wc -l || echo "0")
if [ "${N_ROWS}" -eq 0 ]; then
    echo "[fun_humann3_fungi] 样本 ${SAMPLE}: ChocoPhlAn 无真菌命中（样本中可能无检出真菌，或真菌丰度极低）"
    echo "[fun_humann3_fungi] 提示: 如需全谱真菌定量，请使用 Script 75 (FunOMIC DIAMOND)"
else
    echo "[fun_humann3_fungi] 样本 ${SAMPLE}: 提取到 ${N_ROWS} 条真菌分层通路"
fi

echo "[fun_humann3_fungi] 完成 | 输出: ${OUTPUT_TSV}"
fi

FUNOMIC_CLASSIFICATION="${WORKDIR}/result/fungi/funomic/${SAMPLE}/${SAMPLE}_classification.tsv"
FUNOMIC_ANN="${REPO}/db/funomic/P/jgi_ann_05-2022_reordered.tab"
FUNOMIC_OUTPUT="${OUTDIR}/${SAMPLE}_fungi_funomic_pathway.tsv"

if [ -f "${FUNOMIC_OUTPUT}" ] && [ -s "${FUNOMIC_OUTPUT}" ]; then
    echo "[INFO] FunOMIC pathway 结果已存在，跳过: ${FUNOMIC_OUTPUT}"
elif [ ! -f "${FUNOMIC_CLASSIFICATION}" ]; then
    echo "[WARN] FunOMIC classification 文件不存在，跳过: ${FUNOMIC_CLASSIFICATION}"
else
    mkdir -p "${OUTDIR}"
    EXIT_CODE=0
    mgx_try mgx_conda assembly \
        python3 - "${FUNOMIC_ANN}" "${FUNOMIC_CLASSIFICATION}" "${FUNOMIC_OUTPUT}" <<'PY' || EXIT_CODE=$?
import sys
from collections import Counter

ann_path, classification_path, output_path = sys.argv[1:4]

pathway_by_id = {}
with open(ann_path, "r", encoding="utf-8", errors="replace") as ann:
    for line in ann:
        fields = line.rstrip("\n").split("\t")
        if len(fields) < 6:
            continue
        short_id = fields[0]
        pathway = fields[5]
        if not short_id or not pathway or pathway == r"\N":
            continue
        if short_id not in pathway_by_id:
            pathway_by_id[short_id] = pathway

counts = Counter()
with open(classification_path, "r", encoding="utf-8", errors="replace") as classification:
    for line in classification:
        fields = line.rstrip("\n").split("\t")
        if len(fields) < 2:
            continue
        tokens = fields[1].split("_")
        if len(tokens) < 3:
            continue
        short_id = "_".join(tokens[:3])
        pathway = pathway_by_id.get(short_id)
        if pathway:
            counts[pathway] += 1

with open(output_path, "w", encoding="utf-8") as out:
    out.write("pathway\tcount\n")
    for pathway, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        out.write(f"{pathway}\t{count}\n")
PY

    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] FunOMIC pathway 提取失败（exit: ${EXIT_CODE}）"
        rm -f "${FUNOMIC_OUTPUT}"
        exit ${EXIT_CODE}
    fi

    FUNOMIC_ROWS=$(awk 'NR>1' "${FUNOMIC_OUTPUT}" 2>/dev/null | wc -l || echo "0")
    echo "[fun_funomic_fungi] 样本 ${SAMPLE}: 提取到 ${FUNOMIC_ROWS} 条 FunOMIC pathway"
    echo "[fun_funomic_fungi] 完成 | 输出: ${FUNOMIC_OUTPUT}"
fi
mgx_end "fun_humann4_fungi"
