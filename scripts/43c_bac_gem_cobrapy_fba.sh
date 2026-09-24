#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 43c_bac_gem_cobrapy_fba.sh
# 功  能: 基因组尺度代谢模型 FBA (Flux Balance Analysis) 模拟
#         工具版本：COBRApy 0.31+（conda env: cobrapy）
# 依  赖: 43_bac_gem_gapseq.sh 的 SBML 模型输出
# 输  入: ${WORKDIR}/result/gem/gapseq/{mag_name}/{mag_name}.xml
# 输  出: ${WORKDIR}/result/gem/fba/{mag_name}/
#           {mag_name}_growth_rate.txt        — 预测生长速率
#           {mag_name}_flux_distribution.tsv  — 反应通量分布
#           {mag_name}_essential_genes.tsv    — 必需基因列表
#           {mag_name}_substrate_utilization.tsv — 底物利用预测
#           fba.log                           — 运行日志
#
# ── 工作流程 ──────────────────────────────────────────────────────────────────
#   1. FBA 优化      — 预测最大生长速率
#   2. 通量分析      — 导出反应通量分布
#   3. 基因敲除      — 单基因敲除模拟，鉴定必需基因
#   4. 底物利用      — 测试常见底物（glucose/acetate/propionate/butyrate）
#
# 参  考: Orth et al. 2010 Nature Biotechnology (FBA)
#         Ebrahim et al. 2013 BMC Systems Biology (COBRApy)
# 用  法: bash 43c_bac_gem_cobrapy_fba.sh -m MAG_NAME -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 43c_bac_gem_cobrapy_fba.sh -m MAG_NAME -t CPUS -w WORKDIR -r REPO

必需参数:
  -m  MAG 名称（不含路径和扩展名，用于单 MAG 测试）
  -t  线程数（用于并行基因敲除）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force         强制重新运行（覆盖已有输出）
  --substrates    测试的底物列表（逗号分隔，默认：auto，自动检测模型中的碳源）

示例:
  # 单 MAG 模式
  bash scripts/43c_bac_gem_cobrapy_fba.sh -m Sample10__111 -t 16 \\
       -w Project/Project01 -r .

  # 批量模式（处理全部有 SBML 模型的 MAG）
  bash scripts/43c_bac_gem_cobrapy_fba.sh -t 16 -w Project/Project01 -r .
EOF
}

MAG_NAME=""; CPUS=""; WORKDIR=""; REPO=""; FORCE=0
SUBSTRATES=""  # 默认空，让 Python 脚本自动检测

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m) MAG_NAME="$2";     shift 2 ;;
        -t) CPUS="$2";         shift 2 ;;
        -w) WORKDIR="$2";      shift 2 ;;
        -r) REPO="$2";         shift 2 ;;
        --force) FORCE=1;      shift ;;
        --substrates) SUBSTRATES="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0

# 转换为绝对路径
WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"

OUTDIR="${WORKDIR}/result/gem/fba"

# 自动搜索 SBML 模型（优先 gapseq，其次 carveme）
find_sbml_model() {
    local mag=$1
    local gapseq_model="${WORKDIR}/result/gem/gapseq/${mag}/${mag}.xml"
    local carveme_model="${WORKDIR}/result/gem/carveme/${mag}/${mag}.xml"

    if [[ -f "$gapseq_model" ]]; then
        echo "$gapseq_model"
    elif [[ -f "$carveme_model" ]]; then
        echo "$carveme_model"
    else
        echo ""
    fi
}

# 收集 SBML 模型文件
if [ -n "${MAG_NAME}" ]; then
    # 单 MAG 模式
    XML_FILE=$(find_sbml_model "${MAG_NAME}")
    if [ -z "${XML_FILE}" ]; then
        echo "[ERROR] 未找到 ${MAG_NAME} 的 SBML 模型"
        echo "[ERROR] 请先运行 43_bac_gem_gapseq.sh 或 43b_bac_gem_carveme.sh"
        exit 1
    fi
    MODELS=("${XML_FILE}")
    echo "[FBA] 单 MAG 模式: ${MAG_NAME}"
    echo "[FBA] 模型文件: ${XML_FILE}"
else
    # 批量模式：查找所有 .xml 文件（gapseq + carveme）
    mapfile -t MODELS < <(
        find "${WORKDIR}/result/gem/gapseq" -name "*.xml" -type f 2>/dev/null
        find "${WORKDIR}/result/gem/carveme" -name "*.xml" -type f 2>/dev/null
    )
    if [ ${#MODELS[@]} -eq 0 ]; then
        echo "[ERROR] 未找到任何 SBML 模型"
        echo "[ERROR] 请先运行 43_bac_gem_gapseq.sh 或 43b_bac_gem_carveme.sh"
        exit 1
    fi
    echo "[FBA] 批量模式: ${#MODELS[@]} 个 SBML 模型"
fi

mkdir -p "${OUTDIR}"
LOG="${OUTDIR}/fba_batch.log"
echo "[FBA] 开始 FBA 模拟..." | tee "${LOG}"
echo "[FBA] 输出目录: ${OUTDIR}" | tee -a "${LOG}"

N_SUCCESS=0
N_SKIPPED=0
N_FAILED=0

for xml_file in "${MODELS[@]}"; do
    # 提取 MAG 名称
    mag_name="$(basename "${xml_file}" .xml)"
    mag_outdir="${OUTDIR}/${mag_name}"
    mag_log="${mag_outdir}/fba.log"

    # 检查是否已完成（断点续传）
    if [ -f "${mag_outdir}/${mag_name}_growth_rate.txt" ] && [ ${FORCE} -eq 0 ]; then
        echo "[FBA] 跳过 ${mag_name}（已存在 FBA 结果）" | tee -a "${LOG}"
        N_SKIPPED=$((N_SKIPPED+1))
        continue
    fi

    mkdir -p "${mag_outdir}"

    echo "=== [${mag_name}] 开始 FBA 分析 ===" | tee "${mag_log}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Model: ${xml_file}" | tee -a "${mag_log}"

    # 调用 Python FBA 脚本
    if [ -z "${SUBSTRATES}" ]; then
        # 自动检测模式（不传 --substrates 参数）
        if ! conda run --prefix "${REPO}/envs/cobrapy" python3 "${REPO}/scripts/43c_fba_simulate.py" \
            --model "${xml_file}" \
            --output-dir "${mag_outdir}" \
            --threads "${CPUS}" >> "${mag_log}" 2>&1; then
            echo "[ERROR] FBA 模拟失败: ${mag_name}" | tee -a "${LOG}"
            echo "[ERROR] 详见日志: ${mag_log}" | tee -a "${LOG}"
            N_FAILED=$((N_FAILED+1))
            continue
        fi
    else
        # 用户指定底物
        if ! conda run --prefix "${REPO}/envs/cobrapy" python3 "${REPO}/scripts/43c_fba_simulate.py" \
            --model "${xml_file}" \
            --output-dir "${mag_outdir}" \
            --threads "${CPUS}" \
            --substrates "${SUBSTRATES}" >> "${mag_log}" 2>&1; then
            echo "[ERROR] FBA 模拟失败: ${mag_name}" | tee -a "${LOG}"
            echo "[ERROR] 详见日志: ${mag_log}" | tee -a "${LOG}"
            N_FAILED=$((N_FAILED+1))
            continue
        fi
    fi

    # 验证输出文件
    if [ ! -f "${mag_outdir}/${mag_name}_growth_rate.txt" ]; then
        echo "[ERROR] FBA 输出文件缺失: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    echo "[FBA] ✓ ${mag_name} 完成" | tee -a "${LOG}"
    N_SUCCESS=$((N_SUCCESS+1))
done

# 汇总统计
ELAPSED=$((SECONDS))
echo "" | tee -a "${LOG}"
echo "=== FBA 模拟完成 ===" | tee -a "${LOG}"
echo "成功: ${N_SUCCESS}" | tee -a "${LOG}"
echo "跳过: ${N_SKIPPED}" | tee -a "${LOG}"
echo "失败: ${N_FAILED}" | tee -a "${LOG}"
echo "总耗时: ${ELAPSED} 秒" | tee -a "${LOG}"

# 创建完成标志
touch "${OUTDIR}/fba_done.txt"

if [ ${N_FAILED} -gt 0 ]; then
    echo "[WARNING] ${N_FAILED} 个 MAG FBA 模拟失败，详见日志" | tee -a "${LOG}"
    exit 0  # 部分失败不报错，允许后续分析继续
fi

echo "[FBA] 全部完成" | tee -a "${LOG}"
