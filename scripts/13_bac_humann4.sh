#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 13_bac_humann4.sh
# 功  能: HUMAnN4 功能通路定量分析（MetaCyc/KEGG/GO/COG 通路丰度）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
#         可选：11_bac_metaphlan4.sh 的输出（_profile.txt，避免重复 MetaPhlAn4 分析）
# 输  入: ${WORKDIR}/result/qc/kneaddata/${SAMPLE}/
#         ${WORKDIR}/result/taxonomy/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt（可选）
# 输  出: ${WORKDIR}/result/functional/humann4/${SAMPLE}/
#           ${SAMPLE}_pathabundance.tsv          — MetaCyc 通路丰度（raw）
#           ${SAMPLE}_pathcoverage.tsv           — 通路覆盖度
#           ${SAMPLE}_genefamilies.tsv           — 基因家族丰度（UniRef90）
#           ${SAMPLE}_pathabundance_relab.tsv    — 通路相对丰度（normalized）
#           ${SAMPLE}_genefamilies_relab.tsv     — 基因家族相对丰度（normalized）
#           unstratified/ / stratified/          — 分层/非分层拆分结果
# 临时文件: ${WORKDIR}/temp/humann4/${SAMPLE}/  （fast/balanced 模式自动清理）
#
# 速度模式（--speed-mode 参数）:
#   standard  默认。双端输入，物种阈值 1%，最小内存。适合低深度样本（<20M reads）
#   balanced  推荐。双端输入，物种阈值 5%，最大内存，自动清理 temp。
#             高深度样本（>20M reads）首选，速度提升约 2 倍，精度损失 <5%
#   fast      快速。只用 R1，物种阈值 10%，最大内存，大 block，自动清理 temp。
#             速度提升约 3-5 倍，低丰度物种（<10%）功能信息可能丢失
#
# 阈值说明：--prescreen-threshold 控制进入 custom db 的物种最低丰度占比
#   默认 0.01（1%）→ ~300 物种 → custom db ~60G → 索引 10-20 小时
#   0.05（5%）     → ~100 物种 → custom db ~20G → 索引 2-3 小时
#   0.1（10%）     → ~50  物种 → custom db ~10G → 索引 30-60 分钟
#
# 兼容性修复（已在 0Install.sh §5.4 记录）:
#   1. --bypass-prescreen：跳过 metaphlan 版本检测（metaphlan --version 多行输出导致解析失败）
#   2. config.py vOct22：HUMAnN3.9 默认只接受 vJun23，需修改为本项目使用的 vOct22
#
# 参  考: HUMAnN 官方文档 https://github.com/biobakery/humann
#         Beghini et al. eLife 2021; PMID 33944776
# 用  法: bash 13_bac_humann4.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--speed-mode MODE]
# ==============================================================================

# --- 参数解析（支持 --speed-mode 长参数）---

show_help() {
cat << EOF
用法: bash 13_bac_humann4.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--speed-mode MODE]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16）
  -w  工作目录（Project_example 路径）
  -r  MaxMetagenome 项目根目录

可选参数:
  --speed-mode  速度模式（默认 standard）
                standard  精确模式，物种阈值 1%，双端输入
                balanced  推荐，物种阈值 5%，内存优先，自动清理 temp（约 2× 提速）
                fast      快速，物种阈值 10%，只用 R1，内存优先（约 3-5× 提速）

示例:
  # 标准模式
  bash 13_bac_humann4.sh -s SRR28210342 -t 16 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome

  # 平衡模式（高深度样本推荐）
  bash 13_bac_humann4.sh -s SRR28210342 -t 16 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome --speed-mode balanced

  # 快速模式（探索性分析）
  bash 13_bac_humann4.sh -s SRR28210342 -t 16 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome --speed-mode fast
EOF
}

SAMPLE=""
CPUS=""
WORKDIR=""
REPO=""
SPEED_MODE="standard"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";     shift 2 ;;
        -t) CPUS="$2";       shift 2 ;;
        -w) WORKDIR="$2";    shift 2 ;;
        -r) REPO="$2";       shift 2 ;;
        --speed-mode) SPEED_MODE="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-s/-t/-w/-r）"
    show_help; exit 1
fi

if [[ ! "${SPEED_MODE}" =~ ^(standard|balanced|fast)$ ]]; then
    echo "[ERROR] --speed-mode 必须为 standard / balanced / fast"
    exit 1
fi

SECONDS=0

# --- 速度模式配置 ---

case "${SPEED_MODE}" in
    standard)
        PRESCREEN_THRESHOLD="0.01"
        MEMORY_MODE="minimum"
        DIAMOND_BLOCK=""
        REMOVE_TEMP=""
        USE_R1_ONLY=false
        ;;
    balanced)
        PRESCREEN_THRESHOLD="0.05"
        MEMORY_MODE="maximum"
        DIAMOND_BLOCK=""
        REMOVE_TEMP="--remove-temp-output"
        USE_R1_ONLY=false
        ;;
    fast)
        PRESCREEN_THRESHOLD="0.1"
        MEMORY_MODE="maximum"
        DIAMOND_BLOCK="--diamond-options \"--block-size 6.0 --top 1 --outfmt 6\""
        REMOVE_TEMP="--remove-temp-output"
        USE_R1_ONLY=true
        ;;
esac

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/qc/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/qc/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
METAPHLAN_PROFILE="${WORKDIR}/result/taxonomy/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt"

TEMP_DIR="${WORKDIR}/temp/humann4/${SAMPLE}"
RESULT_DIR="${WORKDIR}/result/functional/humann4/${SAMPLE}"

DB_CHOCOPHLAN="${REPO}/db/humann4/chocophlan"
DB_UNIREF="${REPO}/db/humann4/uniref"
MPA_DB_DIR="${REPO}/db/metaphlan4"
MPA_DB_INDEX="mpa_vOct22_CHOCOPhlAnSGB_202212"

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
        echo "[ERROR] HUMAnN4 数据库目录不存在或为空: ${db}"
        echo "        请先配置 HUMAnN4 数据库（参考 0Install.sh §2.2）"
        exit 1
    fi
done

# --- 幂等性检查 ---

PATHABUNDANCE="${RESULT_DIR}/${SAMPLE}_pathabundance.tsv"
PATHABUNDANCE_RELAB="${RESULT_DIR}/${SAMPLE}_pathabundance_relab.tsv"
if [ -f "${PATHABUNDANCE}" ] && [ -f "${PATHABUNDANCE_RELAB}" ]; then
    echo "[INFO] HUMAnN4 结果已存在，跳过: ${SAMPLE}"
    echo "       ${RESULT_DIR}/"
    exit 0
fi

mkdir -p "${TEMP_DIR}" "${RESULT_DIR}"

# --- 准备输入文件 ---

MERGED_FQ="${TEMP_DIR}/${SAMPLE}_input.fq.gz"

if [ "${USE_R1_ONLY}" = true ]; then
    echo "[humann4] 速度模式: fast（只用 R1）"
    cp "${INPUT_R1}" "${MERGED_FQ}"
else
    echo "[humann4] 速度模式: ${SPEED_MODE}（合并双端 reads）"
    zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${MERGED_FQ}"
fi

echo "[humann4] 开始功能通路定量: ${SAMPLE}"
echo "[humann4] 线程: ${CPUS}，物种阈值: ${PRESCREEN_THRESHOLD}，内存模式: ${MEMORY_MODE}"

# --- 构建 MetaPhlAn4 参数 ---
# 步骤 11 已生成 profile 时直接传入，避免重复运行 MetaPhlAn4

if [ -f "${METAPHLAN_PROFILE}" ]; then
    echo "[humann4] 使用步骤 11 的 MetaPhlAn4 profile，跳过重复分析"
    TAXONOMIC_PROFILE_ARG="--taxonomic-profile ${METAPHLAN_PROFILE}"
    METAPHLAN_OPTS_ARG=""
else
    echo "[humann4] 未找到 MetaPhlAn4 profile，将内部运行 MetaPhlAn4"
    TAXONOMIC_PROFILE_ARG=""
    METAPHLAN_OPTS_ARG="--metaphlan-options \"--input_type fastq --db_dir ${MPA_DB_DIR} -x ${MPA_DB_INDEX} --offline -t rel_ab_w_read_stats --nproc ${CPUS}\""
fi

# --- 运行 HUMAnN4 ---
# --bypass-prescreen: 跳过 metaphlan --version 检测（多行输出导致 HUMAnN3.9 解析失败）
# --prescreen-threshold: 控制进入 custom db 的物种最低丰度，是影响速度的核心参数

conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
    humann \
        --input "${MERGED_FQ}" \
        --output "${TEMP_DIR}" \
        --output-basename "${SAMPLE}" \
        --threads "${CPUS}" \
        --nucleotide-database "${DB_CHOCOPHLAN}" \
        --protein-database "${DB_UNIREF}" \
        --o-log "${TEMP_DIR}/${SAMPLE}.log" \
        --bypass-prescreen \
        --prescreen-threshold "${PRESCREEN_THRESHOLD}" \
        --memory-use "${MEMORY_MODE}" \
        ${REMOVE_TEMP} \
        ${TAXONOMIC_PROFILE_ARG} \
        ${METAPHLAN_OPTS_ARG} \
        ${DIAMOND_BLOCK}

EXIT_CODE=$?
rm -f "${MERGED_FQ}"
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] HUMAnN4 运行失败（exit code: ${EXIT_CODE}）"
    echo "        查看日志: ${TEMP_DIR}/${SAMPLE}.log"
    exit ${EXIT_CODE}
fi

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

echo "[humann4] 标准化为相对丰度..."

for tsv in pathabundance genefamilies; do
    conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
        humann_renorm_table \
            --input  "${RESULT_DIR}/${SAMPLE}_${tsv}.tsv" \
            --units  relab \
            --output "${RESULT_DIR}/${SAMPLE}_${tsv}_relab.tsv"
done

# --- 拆分 stratified / unstratified ---

echo "[humann4] 拆分 stratified/unstratified..."

mkdir -p "${RESULT_DIR}/unstratified" "${RESULT_DIR}/stratified"

for tsv in pathabundance_relab genefamilies_relab; do
    conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
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
echo "[humann4] ${SAMPLE} 完成，速度模式: ${SPEED_MODE}，耗时 ${SECONDS}s"
echo "[humann4] 结果目录: ${RESULT_DIR}/"
echo "    检测通路数: ${N_PATHS}"
echo "    基因家族数: ${N_GENES}"
echo "    关键输出:"
echo "    ├── ${SAMPLE}_pathabundance.tsv       (MetaCyc 通路 raw)"
echo "    ├── ${SAMPLE}_pathabundance_relab.tsv  (MetaCyc 通路 relab)"
echo "    ├── ${SAMPLE}_genefamilies_relab.tsv   (UniRef90 基因家族)"
echo "    ├── unstratified/  (社区整体，统计分析用)"
echo "    └── stratified/    (物种分层，溯源分析用)"
