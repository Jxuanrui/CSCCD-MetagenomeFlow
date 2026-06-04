#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 13_bac_humann4.sh
# 功  能: HUMAnN4 功能通路定量分析（MetaCyc/KEGG/GO/COG 通路丰度）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
#         可选：11_bac_metaphlan4.sh 的输出（_profile.txt，避免重复 MetaPhlAn4 分析）
# 输  入: ${WORKDIR}/result/qc/kneaddata/${SAMPLE}/  (clean reads)
#         ${WORKDIR}/result/taxonomy/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt (可选)
# 输  出: ${WORKDIR}/result/functional/humann4/${SAMPLE}/
#           ${SAMPLE}_pathabundance.tsv          — MetaCyc 通路丰度（raw reads count）
#           ${SAMPLE}_pathcoverage.tsv           — 通路覆盖度
#           ${SAMPLE}_genefamilies.tsv           — 基因家族丰度（UniRef90）
#           ${SAMPLE}_pathabundance_relab.tsv    — 通路相对丰度（normalized）
#           ${SAMPLE}_genefamilies_relab.tsv     — 基因家族相对丰度（normalized）
#           unstratified/stratified/             — 分层/非分层拆分结果
# 临时文件: ${WORKDIR}/temp/humann4/${SAMPLE}/  （可达 60-100G，完成后自动保留）
#
# 性能说明（重要）:
#   HUMAnN4 第一步构建 custom chocophlan 索引（bowtie2-build）耗时极长：
#   - 检测物种数 ~100：custom db ~10G，索引约 30-60 分钟
#   - 检测物种数 ~300：custom db ~60G，索引约 10-20 小时
#   建议：高深度样本（>60M reads）先用 --prescreen-threshold 0.1 限制物种数
#   临时目录（temp/humann4/）需预留 100G+ 磁盘空间
#
# 兼容性修复（已在 0Install.sh §5.4 记录）:
#   1. --bypass-prescreen：跳过 metaphlan 版本检测（metaphlan --version 有多行输出导致解析失败）
#   2. config.py vOct22：HUMAnN3.9 默认只接受 vJun23，需修改为本项目使用的 vOct22
#
# 参  考: HUMAnN 官方文档 https://github.com/biobakery/humann
#         Beghini et al. eLife 2021; PMID 33944776
# 用  法: bash 13_bac_humann4.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

# --- 参数解析 ---

show_help() {
cat << EOF
用法: bash 13_bac_humann4.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 8-16，HUMAnN4 耗时较长）
  -w  工作目录（Project_example 路径）
  -r  MaxMetagenome 项目根目录

示例:
  bash 13_bac_humann4.sh -s SRR28210342 -t 16 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome
EOF
}

while getopts "s:t:w:r:h" opt; do
    case "${opt}" in
        s) SAMPLE=${OPTARG} ;;
        t) CPUS=${OPTARG} ;;
        w) WORKDIR=${OPTARG} ;;
        r) REPO=${OPTARG} ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-s/-t/-w/-r）"
    show_help; exit 1
fi

SECONDS=0

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/qc/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/qc/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

# 步骤 11 输出的 MetaPhlAn4 profile（如存在则直接传入，跳过 HUMAnN 内部 MetaPhlAn 调用）
METAPHLAN_PROFILE="${WORKDIR}/result/taxonomy/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt"

TEMP_DIR="${WORKDIR}/temp/humann4/${SAMPLE}"
RESULT_DIR="${WORKDIR}/result/functional/humann4/${SAMPLE}"

# HUMAnN4 数据库路径
DB_CHOCOPHLAN="${REPO}/db/humann4/chocophlan"
DB_UNIREF="${REPO}/db/humann4/uniref"
DB_MAPPING="${REPO}/db/humann4/utility_mapping"

# MetaPhlAn4 数据库路径（HUMAnN4 内部 MetaPhlAn 调用时使用）
MPA_DB_DIR="${REPO}/db/metaphlan4"
MPA_DB_INDEX="mpa_vOct22_CHOCOPhlAnSGB_202212"

# --- 输入检查 ---

for f in "${INPUT_R1}" "${INPUT_R2}"; do
    if [ ! -f "${f}" ]; then
        echo "[ERROR] 输入文件不存在: ${f}"
        echo "        请先运行 02_qc_kneaddata.sh"
        exit 1
    fi
done

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

# --- 合并双端 reads（HUMAnN4 要求单文件输入）---

MERGED_FQ="${TEMP_DIR}/${SAMPLE}_merged.fq.gz"
echo "[humann4] 合并双端 reads: ${SAMPLE}"
zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${MERGED_FQ}"

echo "[humann4] 开始功能通路定量: ${SAMPLE}"
echo "[humann4] 线程: ${CPUS}"

# --- 构建 MetaPhlAn4 选项 ---
# 优先：如步骤11已生成 profile，直接传入（--taxonomic-profile），跳过 MetaPhlAn4 重复运行
# 如步骤11已生成 profile，直接传入（--taxonomic-profile），跳过 HUMAnN 内部 MetaPhlAn 调用
# 避免对同一样本重复运行 MetaPhlAn4，节省时间
if [ -f "${METAPHLAN_PROFILE}" ]; then
    echo "[humann4] 使用已有 MetaPhlAn4 profile（步骤11输出），跳过重复 MetaPhlAn4 分析"
    TAXONOMIC_PROFILE_ARG="--taxonomic-profile ${METAPHLAN_PROFILE}"
    METAPHLAN_OPTS_ARG=""
else
    echo "[humann4] 未找到 MetaPhlAn4 profile，HUMAnN4 将内部运行 MetaPhlAn4"
    TAXONOMIC_PROFILE_ARG=""
    METAPHLAN_OPTS_ARG="--metaphlan-options \"--input_type fastq --db_dir ${MPA_DB_DIR} -x ${MPA_DB_INDEX} --offline -t rel_ab_w_read_stats --nproc ${CPUS}\""
fi

# --- 运行 HUMAnN4 ---

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
        ${TAXONOMIC_PROFILE_ARG} \
        ${METAPHLAN_OPTS_ARG}

EXIT_CODE=$?
rm -f "${MERGED_FQ}"
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] HUMAnN4 运行失败（exit code: ${EXIT_CODE}）"
    echo "        查看日志: ${TEMP_DIR}/${SAMPLE}.log"
    exit ${EXIT_CODE}
fi

# 验证主输出文件
for out_suffix in "_pathabundance.tsv" "_pathcoverage.tsv" "_genefamilies.tsv"; do
    f="${TEMP_DIR}/${SAMPLE}${out_suffix}"
    if [ ! -f "${f}" ]; then
        echo "[ERROR] 未生成预期输出: ${f}"
        exit 1
    fi
done

# 移动原始输出到 result 目录
mv "${TEMP_DIR}/${SAMPLE}_pathabundance.tsv" "${RESULT_DIR}/"
mv "${TEMP_DIR}/${SAMPLE}_pathcoverage.tsv"  "${RESULT_DIR}/"
mv "${TEMP_DIR}/${SAMPLE}_genefamilies.tsv"  "${RESULT_DIR}/"

# --- 标准化为相对丰度（relab）---
# 标准化为相对丰度（relab）

echo "[humann4] 标准化为相对丰度..."

for tsv in pathabundance genefamilies; do
    conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
        humann_renorm_table \
            --input  "${RESULT_DIR}/${SAMPLE}_${tsv}.tsv" \
            --units  relab \
            --output "${RESULT_DIR}/${SAMPLE}_${tsv}_relab.tsv"
done

# --- 拆分 stratified / unstratified ---
# stratified:   每条通路中各物种的贡献
# unstratified: 通路整体丰度（社区水平，下游统计主要使用）

echo "[humann4] 拆分 stratified/unstratified..."

mkdir -p "${RESULT_DIR}/unstratified" "${RESULT_DIR}/stratified"

for tsv in pathabundance_relab genefamilies_relab; do
    conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
        humann_split_stratified_table \
            --input  "${RESULT_DIR}/${SAMPLE}_${tsv}.tsv" \
            --output "${RESULT_DIR}/"

    # 移动到对应子目录
    mv "${RESULT_DIR}/${SAMPLE}_${tsv}_unstratified.tsv" "${RESULT_DIR}/unstratified/" 2>/dev/null || true
    mv "${RESULT_DIR}/${SAMPLE}_${tsv}_stratified.tsv"   "${RESULT_DIR}/stratified/"   2>/dev/null || true
done

# --- 统计摘要 ---

N_PATHS=$(grep -v "^#\|UNMAPPED\|UNINTEGRATED" "${RESULT_DIR}/${SAMPLE}_pathabundance.tsv" \
          | grep -v "|" | wc -l 2>/dev/null || echo "N/A")
N_GENES=$(grep -v "^#\|UNMAPPED\|UNGROUPED" "${RESULT_DIR}/${SAMPLE}_genefamilies.tsv" \
          | grep -v "|" | wc -l 2>/dev/null || echo "N/A")

echo ""
echo "[humann4] ${SAMPLE} 完成，耗时 ${SECONDS}s"
echo "[humann4] 结果目录: ${RESULT_DIR}/"
echo "    检测通路数: ${N_PATHS}"
echo "    基因家族数: ${N_GENES}"
echo "    关键输出:"
echo "    ├── ${SAMPLE}_pathabundance.tsv     (MetaCyc 通路 raw)"
echo "    ├── ${SAMPLE}_pathabundance_relab.tsv (MetaCyc 通路 relab)"
echo "    ├── ${SAMPLE}_genefamilies_relab.tsv  (UniRef90 基因家族)"
echo "    ├── unstratified/  (社区整体，统计分析用)"
echo "    └── stratified/    (物种分层，溯源分析用)"
