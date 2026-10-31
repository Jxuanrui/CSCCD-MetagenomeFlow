#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 13_bac_humann3.sh
# 功  能: HUMAnN3 功能通路定量分析（MetaCyc/KEGG/GO/COG 通路丰度）
#         工具版本：HUMAnN v3.9（conda env: humann4）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
#         可选：11_bac_metaphlan4.sh 的输出（_profile.txt，避免重复 MetaPhlAn4 分析）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/
#         ${WORKDIR}/result/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt（可选）
# 输  出: ${WORKDIR}/result/humann3/${SAMPLE}/
#           ${SAMPLE}_pathabundance.tsv          — MetaCyc 通路丰度（raw）
#           ${SAMPLE}_pathcoverage.tsv           — 通路覆盖度
#           ${SAMPLE}_genefamilies.tsv           — 基因家族丰度（UniRef90）
#           ${SAMPLE}_pathabundance_relab.tsv    — 通路相对丰度（normalized）
#           ${SAMPLE}_genefamilies_relab.tsv     — 基因家族相对丰度（normalized）
#           unstratified/ / stratified/          — 分层/非分层拆分结果
# 临时文件: ${WORKDIR}/temp/humann3/${SAMPLE}/  （balanced/fast 模式自动清理）
#
# ── 速度模式（--speed-mode 参数）──────────────────────────────────────────────
#
#   standard  精确模式（默认）
#             双端 R1+R2 全量输入，物种阈值 1%，最小内存
#             适合：<20M reads 低深度样本，或发表级最终分析
#             预期耗时（62M reads）：8-15h/样本
#
#   balanced  平衡模式（>20M reads 样本推荐）
#             双端 R1+R2 全量输入，物种阈值 1%，最大内存，自动清理 temp
#             原理：prescreen-threshold 1.0 将入库物种从 ~126 降至 ~21，
#                   custom ChocoPhlAn DB 从 ~60G 降至 ~2-5G，bowtie2-build 从
#                   20h 降至 30-60min（最大性能收益点）
#             预期耗时：1-2h/样本（速度约 5-10× standard）
#             精度损失：unstratified 社区通路 <5%；<1% 丰度物种的 stratified 通路丢失
#
#   fast      快速模式（探索性/大规模队列）
#             只用 R1（输入减半），物种阈值 3%，最大内存，大 block，自动清理 temp
#             原理：threshold 3.0 仅保留高丰度物种（~5 SGBs，custom DB ~0.5G），
#                   R1-only 使 DIAMOND 翻译搜索输入减半
#             预期耗时：0.5-1h/样本（速度约 15-20× standard）
#             精度损失：低丰度物种通路可能丢失；core 肠道通路影响 <10%
#             不适用于：发表级分析、稀有物种研究
#
# ── prescreen-threshold 单位说明（关键！）────────────────────────────────────
#
#   HUMAnN3 的 prescreen.py 将阈值直接与 MetaPhlAn4 输出的 relative_abundance
#   列（0-100 百分比尺度）比较：
#     if read_percent >= config.prescreen_threshold:  # prescreen.py 第159行
#
#   因此：
#     threshold=0.01 → ≥0.01% 的物种 → 几乎所有物种（~126 SGBs, 60G）
#     threshold=1.0  → ≥1.0% 的物种 → ~21 SGBs, 较小 DB（balanced 推荐）
#     threshold=3.0  → ≥3.0% 的物种 → ~5 SGBs, 极小 DB（fast 推荐）
#
#   错误示例：threshold=0.05（误以为是5%）→ 实际是0.05%，等同于threshold=0.01
#
# ── 兼容性修复（已在 0Install.sh §5.4 记录）────────────────────────────────────
#   1. config.py vOct22：HUMAnN3.9 默认只接受 vJun23，已修改为 vOct22
#      （prescreen.py 会检查 profile 头部 "#mpa_vOct22_..." 中的版本标识）
#   2. 不需要 --bypass-prescreen：提供 --taxonomic-profile 时 HUMAnN3 不调用 MetaPhlAn4，
#      且 bypass=False 才能正确触发按物种过滤的 ChocoPhlAn 小数据库构建
#
# 参  考: HUMAnN 官方文档 https://github.com/biobakery/humann
#         Beghini et al. eLife 2021; PMID 33944776
#         bioBakery forum: prescreen threshold best practice
# 用  法: bash 13_bac_humann3.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--speed-mode MODE]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 13_bac_humann3.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--speed-mode MODE]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16）
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  --speed-mode  速度模式（默认 standard）
                standard  精确，物种阈值 0.01%，双端，8-15h（62M reads）
                balanced  推荐，物种阈值 1%，双端，1-2h（62M reads）
                fast      快速，物种阈值 3%，只用 R1，0.5-1h（62M reads）

示例:
  bash 13_bac_humann3.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow --speed-mode balanced
EOF
}

SPEED_MODE="standard"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="speed-mode:SPEED_MODE"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

if [[ ! "${SPEED_MODE}" =~ ^(standard|balanced|fast)$ ]]; then
    echo "[ERROR] --speed-mode 必须为 standard / balanced / fast"
    exit 1
fi

mgx_begin

# --- 速度模式配置 ---
# 注意：threshold 值对应 MetaPhlAn4 的百分比尺度（0-100），非分数（0-1）
# balanced 核心优化：threshold 1.0（1%）将 SGB 从 ~126 降至 ~21，custom DB 从 60G 降至 ~2-5G
# fast 核心优化：threshold 3.0（3%）降至 ~5 SGBs + R1-only，custom DB ~0.5G

case "${SPEED_MODE}" in
    standard)
        PRESCREEN_THRESHOLD="0.01"
        MEMORY_MODE="minimum"
        REMOVE_TEMP=""
        USE_R1_ONLY=false
        DIAMOND_EXTRA_OPTS=""
        ;;
    balanced)
        # 1.0 = 1% abundance threshold → ~20 SGBs → ~2-5G custom DB (vs 60G in standard)
        # HUMAnN3 compares threshold directly against MetaPhlAn4 percentage values (0-100 scale)
        PRESCREEN_THRESHOLD="1.0"
        MEMORY_MODE="maximum"
        REMOVE_TEMP="--remove-temp-output"
        USE_R1_ONLY=false
        DIAMOND_EXTRA_OPTS=""
        ;;
    fast)
        # 3.0 = 3% abundance threshold → ~5 SGBs → ~0.5G custom DB
        PRESCREEN_THRESHOLD="3.0"
        MEMORY_MODE="maximum"
        REMOVE_TEMP="--remove-temp-output"
        USE_R1_ONLY=true
        DIAMOND_EXTRA_OPTS="--block-size 6.0 --top 1 --outfmt 6"
        ;;
esac

# --- 路径设置（输出到 humann3 目录）---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
METAPHLAN_PROFILE="${WORKDIR}/result/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt"

TEMP_DIR="${WORKDIR}/temp/humann3/${SAMPLE}"
RESULT_DIR="${WORKDIR}/result/humann3/${SAMPLE}"

DB_CHOCOPHLAN="${REPO}/db/humann4/chocophlan"
DB_UNIREF="${REPO}/db/humann4/uniref"

# --- 输入检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
if [ "${USE_R1_ONLY}" = false ] && [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
for db in "${DB_CHOCOPHLAN}" "${DB_UNIREF}"; do
    if [ ! -d "${db}" ] || [ -z "$(ls -A "${db}" 2>/dev/null)" ]; then
        echo "[ERROR] HUMAnN3 数据库目录不存在或为空: ${db}"
        echo "        请先配置数据库（参考 0Install.sh §2.2）"
        exit 1
    fi
done

# --- 幂等性检查 ---

PATHABUNDANCE="${RESULT_DIR}/${SAMPLE}_pathabundance.tsv"
PATHABUNDANCE_RELAB="${RESULT_DIR}/${SAMPLE}_pathabundance_relab.tsv"
if [ ${FORCE} -eq 0 ] && [ -f "${PATHABUNDANCE}" ] && [ -f "${PATHABUNDANCE_RELAB}" ]; then
    echo "[INFO] HUMAnN3 结果已存在，跳过: ${SAMPLE}"
    echo "       ${RESULT_DIR}/"
    exit 0
fi

mkdir -p "${TEMP_DIR}" "${RESULT_DIR}"

# --- 准备输入文件 ---

MERGED_FQ="${TEMP_DIR}/${SAMPLE}_input.fq.gz"

if [ "${USE_R1_ONLY}" = true ]; then
    echo "[humann3] 速度模式: fast（只用 R1，减半 DIAMOND 搜索时间）"
    cp "${INPUT_R1}" "${MERGED_FQ}"
else
    echo "[humann3] 速度模式: ${SPEED_MODE}（合并 R1+R2）"
    zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${MERGED_FQ}"
fi

echo "[humann3] 开始功能通路定量: ${SAMPLE}"
echo "[humann3] 线程: ${CPUS}，物种阈值: ${PRESCREEN_THRESHOLD}，内存模式: ${MEMORY_MODE}"

# --- MetaPhlAn4 profile 参数 ---
# 传入步骤 11 的预计算 profile，跳过 HUMAnN 内部重复运行 MetaPhlAn4

if [ -f "${METAPHLAN_PROFILE}" ]; then
    echo "[humann3] 使用步骤 11 的 MetaPhlAn4 profile，跳过重复分析"
    TAXONOMIC_PROFILE_ARG="--taxonomic-profile ${METAPHLAN_PROFILE}"
else
    echo "[humann3] 未找到 MetaPhlAn4 profile，将内部运行 MetaPhlAn4"
    TAXONOMIC_PROFILE_ARG=""
fi

# --- 真核生物 profile 合并（如果 script 72 已运行）---
# 若 result/fungi/metaphlan4/${SAMPLE}_profile.txt 存在且含真核生物条目，
# 将其合并到细菌 profile，使 HUMAnN3 stratified 输出包含 k__Eukaryota
EUK_PROFILE="${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt"
MERGED_PROFILE=""
if [ -f "${EUK_PROFILE}" ] && grep -q "k__Eukaryota" "${EUK_PROFILE}" 2>/dev/null; then
    echo "[humann3] 检测到真核生物 profile，合并细菌+真核 profile"
    MERGED_PROFILE="${TEMP_DIR}/${SAMPLE}_merged_profile.txt"
    # 保留细菌 profile 的注释头
    grep "^#" "${METAPHLAN_PROFILE}" > "${MERGED_PROFILE}"
    # 添加细菌 profile 的数据行
    grep -v "^#" "${METAPHLAN_PROFILE}" >> "${MERGED_PROFILE}"
    # 追加真核生物行（去掉重复注释头和 UNCLASSIFIED 行）
    grep -v "^#\|^UNCLASSIFIED" "${EUK_PROFILE}" | grep "k__Eukaryota" >> "${MERGED_PROFILE}"
    EUK_LINE_COUNT=$(grep -c "k__Eukaryota" "${MERGED_PROFILE}" 2>/dev/null || echo "0")
    echo "[humann3] 合并完成，真核生物行数: ${EUK_LINE_COUNT}"
    TAXONOMIC_PROFILE_ARG="--taxonomic-profile ${MERGED_PROFILE}"
fi

# --- 构建 diamond 额外参数（fast 模式，避免引号嵌套问题）---

DIAMOND_CMD_ARGS=()
if [ -n "${DIAMOND_EXTRA_OPTS}" ]; then
    DIAMOND_CMD_ARGS=(--diamond-options "${DIAMOND_EXTRA_OPTS}")
fi

# --- 运行 HUMAnN3 ---
# 注意：不使用 --bypass-prescreen。
#   理由：当提供 --taxonomic-profile 时，HUMAnN3 不会调用 MetaPhlAn4（源码 humann.py:960-970），
#         因此不存在版本检测失败的问题。
#         而 --bypass-prescreen=True 会导致 create_custom_database() 中走 else 分支，
#         将 ChocoPhlAn 目录中的所有文件（~60G）都加入自定义数据库，完全跳过基于
#         prescreen_threshold 的物种过滤（prescreen.py:246-256）。
# --prescreen-threshold：在 bypass_prescreen=False 的情况下，create_custom_database()
#   会按 threshold 过滤 profile 中的物种，只包含丰度 >= threshold 的物种对应的 ChocoPhlAn 文件。

# cd to TEMP_DIR so MetaPhlAn4's hardcoded fifo_map.mapout.txt lands here, not in PROJ_DIR
cd "${TEMP_DIR}"

EXIT_CODE=0
mgx_try mgx_conda humann4 \
    humann \
        --input                   "${MERGED_FQ}" \
        --output                  "${TEMP_DIR}" \
        --output-basename         "${SAMPLE}" \
        --threads                 "${CPUS}" \
        --nucleotide-database     "${DB_CHOCOPHLAN}" \
        --protein-database        "${DB_UNIREF}" \
        --o-log                   "${TEMP_DIR}/${SAMPLE}.log" \
        --prescreen-threshold     "${PRESCREEN_THRESHOLD}" \
        --memory-use              "${MEMORY_MODE}" \
        --metaphlan-options       "-t rel_ab --tmp_dir ${TEMP_DIR}" \
        ${REMOVE_TEMP} \
        ${TAXONOMIC_PROFILE_ARG} \
        "${DIAMOND_CMD_ARGS[@]}" \
        || EXIT_CODE=$?
rm -f "${MERGED_FQ}"
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] HUMAnN3 运行失败（exit code: ${EXIT_CODE}）"
    echo "        查看日志: ${TEMP_DIR}/${SAMPLE}.log"
    exit ${EXIT_CODE}
fi

# 清理合并的临时 profile
[ -n "${MERGED_PROFILE}" ] && rm -f "${MERGED_PROFILE}"

# --- 验证并移动主输出 ---

for out_suffix in "_pathabundance.tsv" "_pathcoverage.tsv" "_genefamilies.tsv"; do
    f="${TEMP_DIR}/${SAMPLE}${out_suffix}"
    if [ ! -f "${f}" ]; then
        echo "[ERROR] 未生成预期输出: ${f}"
        exit 1
    fi
done

mv "${TEMP_DIR}/${SAMPLE}_pathabundance.tsv" "${RESULT_DIR}/"
mv "${TEMP_DIR}/${SAMPLE}_pathcoverage.tsv"  "${RESULT_DIR}/"
mv "${TEMP_DIR}/${SAMPLE}_genefamilies.tsv"  "${RESULT_DIR}/"

# --- 标准化为相对丰度 ---

echo "[humann3] 标准化为相对丰度..."

for tsv in pathabundance genefamilies; do
    mgx_conda humann4 \
        humann_renorm_table \
            --input  "${RESULT_DIR}/${SAMPLE}_${tsv}.tsv" \
            --units  relab \
            --output "${RESULT_DIR}/${SAMPLE}_${tsv}_relab.tsv"
done

# --- 拆分 stratified / unstratified ---

echo "[humann3] 拆分 stratified/unstratified..."

mkdir -p "${RESULT_DIR}/unstratified" "${RESULT_DIR}/stratified"

for tsv in pathabundance_relab genefamilies_relab; do
    mgx_conda humann4 \
        humann_split_stratified_table \
            --input  "${RESULT_DIR}/${SAMPLE}_${tsv}.tsv" \
            --output "${RESULT_DIR}/"

    mv "${RESULT_DIR}/${SAMPLE}_${tsv}_unstratified.tsv" "${RESULT_DIR}/unstratified/" 2>/dev/null || true
    mv "${RESULT_DIR}/${SAMPLE}_${tsv}_stratified.tsv"   "${RESULT_DIR}/stratified/"   2>/dev/null || true
done

# --- 统计摘要 ---

N_PATHS=$(grep -v "^#\|UNMAPPED\|UNINTEGRATED" "${RESULT_DIR}/${SAMPLE}_pathabundance.tsv" \
          | grep -v "|" | wc -l 2>/dev/null || echo "N/A")
N_GENES=$(grep -v "^#\|UNMAPPED\|UNGROUPED" "${RESULT_DIR}/${SAMPLE}_genefamilies.tsv" \
          | grep -v "|" | wc -l 2>/dev/null || echo "N/A")

echo ""
echo "[humann3] ${SAMPLE} 完成，速度模式: ${SPEED_MODE}"
echo "[humann3] 结果目录: ${RESULT_DIR}/"
echo "    检测通路数: ${N_PATHS}"
echo "    基因家族数: ${N_GENES}"
echo "    关键输出:"
echo "    ├── ${SAMPLE}_pathabundance.tsv       (MetaCyc 通路 raw)"
echo "    ├── ${SAMPLE}_pathabundance_relab.tsv  (MetaCyc 通路 relab)"
echo "    ├── ${SAMPLE}_genefamilies_relab.tsv   (UniRef90 基因家族)"
echo "    ├── unstratified/  (社区整体，统计分析用)"
echo "    └── stratified/    (物种分层，溯源分析用)"
mgx_end "humann3"
