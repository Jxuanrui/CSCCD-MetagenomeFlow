#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 31e_bac_fegenie.sh
# 功  能: 铁代谢基因预测（FeGenie 1.2，iron uptake/storage/cycling）
#         预测宏基因组中与铁获取、储存、氧化还原、调控相关的基因
#         涵盖 10 个功能类别：
#           - Siderophore synthesis / transport（铁载体合成/转运）
#           - Heme transport / oxygenase（血红素转运/分解）
#           - Iron transport（铁直接转运）
#           - Iron oxidation / reduction（铁氧化/还原）
#           - Iron storage（铁储存，如 ferritin）
#           - Iron gene regulation（铁调控，如 Fur）
#           - Magnetosome formation（磁小体形成）
#
# 依  赖: 17_bac_prodigal.sh 的输出（蛋白预测 .faa）
#         或 18_bac_cdhit.sh 的输出（NR 蛋白集，用于 MAG-level 分析）
#
# 输  入: ${WORKDIR}/result/assembly/prodigal/${SAMPLE}/${SAMPLE}.faa
# 输  出: ${WORKDIR}/result/annotation/fegenie/${SAMPLE}/
#           FeGenie_results.txt           — 主结果表（基因 ID + 功能分类 + HMM hit）
#           iron-transport_results.txt    — 各功能类别详细注释
#           FeGenie_summary.txt           — 样本级铁代谢功能概览
#
# ── 工具说明 ──────────────────────────────────────────────────────────────────
#   FeGenie 1.2（conda env: fegenie）
#   DB：内嵌于 envs/fegenie/share/fegenie-1.2/hmms/iron/（10 个子目录）
#   方法：hmmsearch vs 蛋白序列（.faa），输出功能分类 + HMM 得分
#   阈值：默认 HMM gathering cutoff（GA）
#
# ── 与 eggNOG/KEGG/Pfam 的关系 ──────────────────────────────────────────────
#   eggNOG/KEGG 给出通用 KO/COG 注释（如 K02013 = iron transport）
#   Pfam-A 覆盖蛋白域（如 PF01032 = FecA，铁柠檬酸盐受体）
#   FeGenie 聚焦铁代谢专项，提供：
#     1. 更细粒度分类（区分 siderophore synthesis vs transport）
#     2. 铁氧化/还原酶的详细亚型（如 Cyc2 vs MtoA）
#     3. 样本级铁代谢功能 profile（FeGenie_summary.txt）
#
# 参  考: Garber et al. 2020 Front. Microbiol.; https://github.com/Arkadiy-Garber/FeGenie
# 用  法: bash 31e_bac_fegenie.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 31e_bac_fegenie.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名称
  -t  线程数（推荐 8+）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  --input-type  输入蛋白来源（默认 prodigal）
                prodigal — per-sample 蛋白（result/assembly/prodigal/${SAMPLE}/${SAMPLE}.faa）
                nr       — NR 蛋白集（result/assembly/cdhit/protein_nr.fa，适合 MAG-level）

示例:
  # Per-sample 模式（推荐，与其他注释脚本对齐）
  bash scripts/31e_bac_fegenie.sh -s S01 -t 8 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

  # NR 模式（单次运行，所有样本共享结果）
  bash scripts/31e_bac_fegenie.sh -s NR -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow --input-type nr
EOF
}

SAMPLE=""   # show_help 的 ${SAMPLE} 在 -h 时需已定义（set -u）
INPUT_TYPE="prodigal"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="input-type:INPUT_TYPE"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 输入路径判断 ---
if [ "${INPUT_TYPE}" = "nr" ]; then
    PROTEINS="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
    RESULT_DIR="${WORKDIR}/result/annotation/fegenie/NR"
else
    PROTEINS="${WORKDIR}/result/assembly/prodigal/${SAMPLE}/${SAMPLE}.faa"
    RESULT_DIR="${WORKDIR}/result/annotation/fegenie/${SAMPLE}"
fi

SENTINEL="${RESULT_DIR}/FeGenie-geneSummary.csv"

if [ ! -f "${PROTEINS}" ] || [ ! -s "${PROTEINS}" ]; then
    echo "[ERROR] 蛋白文件不存在: ${PROTEINS}"
    [ "${INPUT_TYPE}" = "prodigal" ] && echo "        请先运行 17_bac_prodigal.sh"
    [ "${INPUT_TYPE}" = "nr" ] && echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] FeGenie 结果已存在，跳过: ${SENTINEL}"; exit 0
fi

# FeGenie.py 内部只用普通 mkdir 创建输出目录，父目录必须预先存在
mkdir -p "$(dirname "${RESULT_DIR}")"

# 清理旧输出目录（FeGenie 会交互式询问覆盖，非交互模式需先删除）
if [ -d "${RESULT_DIR}" ]; then
    echo "[INFO] 清理旧输出目录: ${RESULT_DIR}"
    rm -rf "${RESULT_DIR}"
fi

# 注意：不要 mkdir -p "${RESULT_DIR}"，让 FeGenie 自己创建以避免交互式提示

# --- 路径说明 ---
HMM_DIR="${REPO}/envs/fegenie/share/fegenie-1.2/hmms"

if [ ! -d "${HMM_DIR}" ]; then
    echo "[ERROR] FeGenie HMM 数据库不存在: ${HMM_DIR}"
    echo "        请确认 envs/fegenie 已正确安装"
    exit 1
fi

echo "[fegenie] ${SAMPLE}: 铁代谢基因预测"
echo "  输入蛋白: ${PROTEINS}"
echo "  HMM 数据库: ${HMM_DIR}/iron/"
echo "  输出目录: ${RESULT_DIR}/"

# FeGenie 需要输入为目录（-bin_dir），且每个"bin"一个 .faa 文件
# 创建临时目录结构
TMP_BIN_DIR="${WORKDIR}/temp/fegenie/${SAMPLE}"
mkdir -p "${TMP_BIN_DIR}"
cp "${PROTEINS}" "${TMP_BIN_DIR}/${SAMPLE}.faa"

EXIT_CODE=0
mgx_try mgx_conda fegenie FeGenie.py \
    -bin_dir "${TMP_BIN_DIR}" \
    -bin_ext faa \
    -out     "${RESULT_DIR}" \
    -t       "${CPUS}" \
    --orfs || EXIT_CODE=$?
rm -rf "${TMP_BIN_DIR}"

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] FeGenie 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# --- 摘要统计 ---
if [ -f "${SENTINEL}" ]; then
    N_HITS=$(tail -n +2 "${SENTINEL}" | wc -l)
    echo "[fegenie] ${SAMPLE}: 完成"
    echo "  铁代谢基因命中: ${N_HITS} 条"
    echo "  主结果: ${SENTINEL}"

    # 列出功能类别覆盖
    if [ -f "${RESULT_DIR}/FeGenie-geneSummary.csv" ]; then
        echo "  功能类别分布:"
        tail -n +2 "${RESULT_DIR}/FeGenie-geneSummary.csv" | \
            cut -d',' -f2 | sort | uniq -c | sort -rn | head -10 | \
            awk '{printf "    %-40s %d\n", $2, $1}'
    fi
else
    echo "[WARN] FeGenie 未生成预期输出文件: ${SENTINEL}"
    exit 1
fi
mgx_end "fegenie"
