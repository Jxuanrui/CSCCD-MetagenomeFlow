#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 12_bac_strainphlan4.sh
# 功  能: StrainPhlAn4 菌株追踪与系统发育分析
#         — 从 MetaPhlAn4 的 .sam.bz2 中提取 consensus markers，
#           对检测到的物种构建多样本系统发育树
# 依  赖: 11_bac_metaphlan4.sh 的输出（每个样本的 .sam.bz2）
# 流  程: Step1 sample2markers  → 提取每样本 consensus marker (.pkl)
#         Step2 extract_markers → 从数据库提取目标物种 clade marker
#         Step3 strainphlan     → 多序列比对 + 系统发育树
# 输  入: ${WORKDIR}/result/metaphlan4/*/  (扫描所有 .sam.bz2)
# 输  出: ${WORKDIR}/result/strainphlan4/
#           consensus_markers/          — 每样本 .pkl（Step1，可复用）
#           db_markers/                 — 物种 clade markers（Step2）
#           trees/{CLADE}/              — 系统发育树、MSA（Step3）
#           clades_detected.txt         — 可分析的菌株列表
# 参  考: MetaPhlAn4 Wiki (biobakery/MetaPhlAn/wiki/StrainPhlAn-4)
#         Blanco-Miguez et al. Nat Biotechnol 2023; PMID 36823356
# 用  法: bash 12_bac_strainphlan4.sh -w WORKDIR -r REPO [-t CPUS] [-c CLADE]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# --- 参数解析 ---

show_help() {
cat << EOF
用法: bash 12_bac_strainphlan4.sh -w WORKDIR -r REPO [-t CPUS] [-c CLADE]

必需参数:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  -t  线程数（默认 8）
  -c  指定目标菌株 ID（如 t__SGB1877 或 s__Faecalibacterium_prausnitzii）
      不指定时：Step1+Step2 自动运行，Step3 打印可分析菌株列表后退出，
      需要用户根据列表选择 CLADE 后带 -c 参数重新运行

示例:
  # 第一步：自动检测可分析菌株
  bash 12_bac_strainphlan4.sh \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow -t 8

  # 第二步：对指定菌株建树
  bash 12_bac_strainphlan4.sh \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow -t 8 \\
       -c t__SGB10068
EOF
}

CPUS=8
CLADE=""

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS c:CLADE"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

# --- 路径设置 ---

METAPHLAN_DIR="${WORKDIR}/result/metaphlan4"
STRAINPHLAN_DIR="${WORKDIR}/result/strainphlan4"

CONSENSUS_DIR="${STRAINPHLAN_DIR}/consensus_markers"   # Step1 输出
DB_MARKERS_DIR="${STRAINPHLAN_DIR}/db_markers"          # Step2 输出
TREES_DIR="${STRAINPHLAN_DIR}/trees"                    # Step3 输出
TEMP_DIR="${WORKDIR}/temp/strainphlan4"
CLADES_FILE="${STRAINPHLAN_DIR}/clades_detected.txt"

DB_PKL="${REPO}/db/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202212.pkl"

# --- 前置检查 ---

if [ ! -f "${DB_PKL}" ]; then
    echo "[ERROR] MetaPhlAn4 数据库 pkl 不存在: ${DB_PKL}"
    exit 1
fi

# 收集所有 .sam.bz2 文件
SAM_FILES=()
for sample_dir in "${METAPHLAN_DIR}"/*/; do
    sample=$(basename "${sample_dir}")
    [ "${sample}" = "merged" ] && continue
    sam="${sample_dir}/${sample}.sam.bz2"
    [ -f "${sam}" ] && SAM_FILES+=("${sam}")
done

if [ ${#SAM_FILES[@]} -eq 0 ]; then
    echo "[ERROR] 未找到任何 .sam.bz2 文件"
    echo "        期望路径: ${METAPHLAN_DIR}/<SAMPLE>/<SAMPLE>.sam.bz2"
    echo "        请先运行 11_bac_metaphlan4.sh（需保留 --samout 输出）"
    exit 1
fi

# ==============================================================================
# 预处理：去除 SAM header 中的重复 @SQ 条目
# 原因：MetaPhlAn4 vOct22 数据库包含 VDB 病毒条目，存在重复的 @SQ SN 行，
#       pysam 无法解析含重复 SN 的 SAM header（已知 bug）
#       解决方案：仅保留第一次出现的 @SQ SN，去重后保存到 temp/strainphlan4/dedup_sam/
# 参考：github.com/biobakery/MetaPhlAn issues
# ==============================================================================

DEDUP_DIR="${TEMP_DIR}/dedup_sam"
mkdir -p "${DEDUP_DIR}"

DEDUP_SAM_FILES=()
for sam in "${SAM_FILES[@]}"; do
    sample=$(basename "$(dirname "${sam}")")
    dedup_sam="${DEDUP_DIR}/${sample}.sam.bz2"

    if [ ! -f "${dedup_sam}" ] || [ "${sam}" -nt "${dedup_sam}" ]; then
        echo "[INFO] 去重 SAM header: ${sample}"
        bzip2 -dk "${sam}" -c 2>/dev/null | \
            awk '/^@SQ/{sn=$2; if(!seen[sn]++) print; next} {print}' | \
            bzip2 -c > "${dedup_sam}"
    fi
    DEDUP_SAM_FILES+=("${dedup_sam}")
done
echo "[INFO] SAM 去重完成（${#DEDUP_SAM_FILES[@]} 个文件）"

N_SAMPLES=${#DEDUP_SAM_FILES[@]}
echo "[strainphlan4] 找到 ${N_SAMPLES} 个样本的 SAM 文件"

# StrainPhlAn4 要求样本数 ≥ 2 才能建树（单样本只能做 marker 提取）
if [ "${N_SAMPLES}" -lt 2 ]; then
    echo "[WARN] 样本数 < 2，无法构建系统发育树（至少需要 2 个样本）"
    echo "       仅运行 Step1 提取 consensus markers，供日后样本增加后使用"
fi

mkdir -p "${CONSENSUS_DIR}" "${DB_MARKERS_DIR}" "${TREES_DIR}" "${TEMP_DIR}"

# ==============================================================================
# Step 1: sample2markers — 从每个样本的 .sam.bz2 提取 consensus markers (.pkl)
# 参数说明：
#   -d  指定数据库 pkl（否则默认查找 metaphlan 安装目录，可能找不到）
#   -f bz2  输入格式
#   -n  线程数
# 幂等：如果所有 pkl 都已存在则跳过
# ==============================================================================

N_PKL=$(find "${CONSENSUS_DIR}" -maxdepth 1 -name "*.json.bz2" 2>/dev/null | wc -l)
STEP1_STALE=0
for dedup_sam in "${DEDUP_SAM_FILES[@]}"; do
    sample=$(basename "${dedup_sam}" .sam.bz2)
    marker="${CONSENSUS_DIR}/${sample}.json.bz2"
    if [ ! -f "${marker}" ] || [ "${dedup_sam}" -nt "${marker}" ]; then
        STEP1_STALE=1; break
    fi
done
if [ "${N_PKL}" -ge "${N_SAMPLES}" ] && [ ${STEP1_STALE} -eq 0 ]; then
    echo "[INFO] Step1 已完成（${N_PKL} 个 .json.bz2），跳过 sample2markers"
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[Step1] sample2markers — 提取样本 consensus markers"
    echo "        输入: ${N_SAMPLES} 个 .sam.bz2"
    echo "        输出: ${CONSENSUS_DIR}/"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    EXIT_CODE=0
    mgx_try mgx_conda humann4 \
        sample2markers.py \
            -i "${DEDUP_SAM_FILES[@]}" \
            -d "${DB_PKL}" \
            -o "${CONSENSUS_DIR}" \
            -f bz2 \
            -n "${CPUS}" \
            || EXIT_CODE=$?
    if [ "${EXIT_CODE}" -ne 0 ]; then
        echo "[strainphlan4] WARNING: sample2markers 失败（exit: ${EXIT_CODE}），跳过 StrainPhlAn4"
        mkdir -p "${CONSENSUS_DIR}"
        exit 0
    fi

    N_PKL=$(find "${CONSENSUS_DIR}" -maxdepth 1 -name "*.json.bz2" 2>/dev/null | wc -l)
    echo "[Step1] 完成：生成 ${N_PKL} 个 .json.bz2 文件"
fi

# ==============================================================================
# Step 2: strainphlan --print_clades_only — 列出可分析的菌株
# 在不知道目标 clade 的情况下先打印候选列表
# ==============================================================================

CLADES_STALE=0
if [ -f "${CLADES_FILE}" ]; then
    for marker in "${CONSENSUS_DIR}"/*.json.bz2; do
        [ -f "${marker}" ] || continue
        if [ "${marker}" -nt "${CLADES_FILE}" ]; then CLADES_STALE=1; break; fi
    done
fi
if [ ${CLADES_STALE} -eq 1 ] || [ ! -f "${CLADES_FILE}" ] || [ ! -s "${CLADES_FILE}" ] || \
   ! grep -qE "^t__|^s__" "${CLADES_FILE}" 2>/dev/null; then
    # 已存在但不含有效 t__/s__ 菌株行的文件视为陈旧缓存（例如旧版本参数错误
    # 导致的 usage/error 输出），需重新生成，否则下方逐行匹配会因找不到
    # 任何候选菌株在 pipefail 下返回非零，被 set -e 判定为脚本失败
    rm -f "${CLADES_FILE}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[Step2] 检测可分析菌株（--print_clades_only）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    mgx_conda humann4 \
        strainphlan \
            -s "${CONSENSUS_DIR}"/*.json.bz2 \
            -d "${DB_PKL}" \
            -o "${TREES_DIR}" \
            --print_clades_only \
            --non_interactive \
            -n "${CPUS}" \
        2>&1 | tee "${CLADES_FILE}" || true  # 样本不足时 strainphlan 返回非0，用 || true 避免脚本退出

    echo "[Step2] 菌株列表已保存: ${CLADES_FILE}"
fi

# 如果未指定 CLADE，则打印列表后退出，等待用户选择
if [ -z "${CLADE}" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[INFO] 可供分析的菌株（从 ${N_SAMPLES} 个样本中检测到）："
    grep -E "^t__|^s__" "${CLADES_FILE}" 2>/dev/null || \
        grep -v "^\[" "${CLADES_FILE}" 2>/dev/null | grep "__" | head -30 || true
    echo ""
    echo "[INFO] 请选择目标菌株后，带 -c 参数重新运行，例如："
    echo "       bash 12_bac_strainphlan4.sh -w ${WORKDIR} -r ${REPO} -t ${CPUS} -c t__SGB10068"
    echo "       (t__SGB 格式为 SGB 级别，精度更高；s__ 格式为种级别)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

# ==============================================================================
# Step 3: extract_markers + strainphlan — 对指定菌株建树
# 参数说明：
#   --sample_with_n_markers 20       样本至少有 20 个 markers（默认值）
#   --sample_with_n_markers_perc 25  样本覆盖至少 25% 的 markers
#   --marker_in_n_samples_perc 50    marker 出现在至少 50% 样本中
#   --breadth_thres 80               标记覆盖度 ≥ 80%（默认）
#   --phylophlan_mode fast           使用 PhyloPhlAn fast 模式（用 FastTree）
#   --non_interactive                避免交互提示（批处理友好）
# ==============================================================================

CLADE_OUT_DIR="${TREES_DIR}/${CLADE}"
CLADE_MARKER_DIR="${DB_MARKERS_DIR}/${CLADE}"
TREE_FILE="${CLADE_OUT_DIR}/RAxML_bestTree.${CLADE}.StrainPhlAn4.tre"

# 幂等检查
if [ ${FORCE} -eq 0 ] && [ -f "${TREE_FILE}" ]; then
    echo "[INFO] 菌株 ${CLADE} 的系统发育树已存在，跳过"
    echo "       ${TREE_FILE}"
    exit 0
fi

mkdir -p "${CLADE_OUT_DIR}" "${CLADE_MARKER_DIR}"
mkdir -p "${TEMP_DIR}/${CLADE}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[Step3a] extract_markers — 从数据库提取 ${CLADE} 的 clade markers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXIT_CODE=0
mgx_try mgx_conda humann4 \
    extract_markers.py \
        -c "${CLADE}" \
        -d "${DB_PKL}" \
        -o "${CLADE_MARKER_DIR}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] extract_markers 失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# 找到生成的 markers fasta 文件
CLADE_MARKERS_FA=$(ls "${CLADE_MARKER_DIR}"/*.fna 2>/dev/null | head -1)
if [ -z "${CLADE_MARKERS_FA}" ]; then
    echo "[ERROR] extract_markers 未生成 .fna 文件，请检查 CLADE 名称是否正确"
    echo "        已尝试路径: ${CLADE_MARKER_DIR}/"
    exit 1
fi
echo "[Step3a] clade markers: ${CLADE_MARKERS_FA}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[Step3b] strainphlan — 构建 ${CLADE} 系统发育树"
echo "         样本数: ${N_SAMPLES}，线程: ${CPUS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXIT_CODE=0
mgx_try mgx_conda humann4 \
    strainphlan \
        -s "${CONSENSUS_DIR}"/*.json.bz2 \
        -m "${CLADE_MARKERS_FA}" \
        -d "${DB_PKL}" \
        -o "${CLADE_OUT_DIR}" \
        -c "${CLADE}" \
        -n "${CPUS}" \
        --tmp "${TEMP_DIR}/${CLADE}" \
        --sample_with_n_markers 20 \
        --sample_with_n_markers_perc 25 \
        --marker_in_n_samples_perc 50 \
        --breadth_thres 80 \
        --phylophlan_mode fast \
        --non_interactive \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] strainphlan 失败（exit code: ${EXIT_CODE}）"
    echo "[HINT]  若因样本过滤后数量不足，可尝试放宽阈值重新运行："
    echo "        添加参数：--marker_in_n_samples_perc 30 --sample_with_n_markers 10"
    exit ${EXIT_CODE}
fi

# --- 输出汇总 ---

echo ""
echo "[strainphlan4] ${CLADE} 分析完成"
echo "[strainphlan4] 结果目录: ${CLADE_OUT_DIR}/"

# 列出生成的关键文件
for f in "${CLADE_OUT_DIR}"/*.tre "${CLADE_OUT_DIR}"/*.aln; do
    [ -f "${f}" ] && echo "    $(basename ${f})  ($(du -h "${f}" | cut -f1))"
done

# 提示 .tre 可视化方式
BEST_TREE="${CLADE_OUT_DIR}/RAxML_bestTree.${CLADE}.StrainPhlAn4.tre"
if [ ${FORCE} -eq 0 ] && [ -f "${BEST_TREE}" ]; then
    echo ""
    echo "[INFO] 系统发育树 (Newick): ${BEST_TREE}"
    echo "       可视化工具: iTOL (https://itol.embl.de/)  |  FigTree  |  ggtree (R)"
fi
mgx_end "strainphlan4"
