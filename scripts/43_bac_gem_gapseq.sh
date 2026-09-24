#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 43_bac_gem_gapseq.sh
# 功  能: 基因组尺度代谢模型（GEM）重建 - gapseq 主线流程
#         工具版本：gapseq 1.3+（conda env: gapseq）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs
#         41_bac_prokka.sh 的 Prokka 注释（可选，用于提升精度）
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
# 输  出: ${WORKDIR}/result/gem/gapseq/{mag_name}/
#           {mag_name}-draft.RDS          — gapseq 草图模型（R Sybil 格式）
#           {mag_name}-gapfilled.RDS      — gap-filling 后模型
#           {mag_name}.xml                — SBML 格式（COBRApy 输入）
#           {mag_name}_pathways.tsv       — 预测的代谢通路列表
#           {mag_name}_reactions.tsv      — 模型中的反应列表
#           {mag_name}_transporters.tsv   — 转运系统预测
#           gapseq.log                    — 运行日志
#
# ── 工作流程 ──────────────────────────────────────────────────────────────────
#   1. gapseq find   — 代谢通路预测（基于 MetaCyc/KEGG/BioCyc）
#   2. gapseq draft  — 草图模型构建（基于预测的反应和转运系统）
#   3. gapseq fill   — gap-filling（补全代谢网络中的缺口）
#   4. SBML 转换     — RDS → XML（COBRApy 标准输入格式）
#
# 参  考: Zimmermann et al. 2021 Genome Biology (gapseq)
#         https://github.com/jotech/gapseq
# 用  法: bash 43_bac_gem_gapseq.sh -m MAG_NAME -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 43_bac_gem_gapseq.sh -m MAG_NAME -t CPUS -w WORKDIR -r REPO

必需参数:
  -m  MAG 名称（不含路径和 .fa 后缀，用于单 MAG 测试）
  -t  线程数（推荐 16+）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force     强制重新运行（覆盖已有输出）

示例:
  # 单 MAG 模式
  bash scripts/43_bac_gem_gapseq.sh -m Sample10__111 -t 16 \\
       -w Project/Project01 -r .

  # 批量模式（处理全部 MAG，不指定 -m）
  bash scripts/43_bac_gem_gapseq.sh -t 16 -w Project/Project01 -r .
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
# （帮助文本里的 -t CPUS 并无对应解析分支：原 while/case 同样不接受 -t，保持一致）
export MGX_OPTS_STRING="m:MAG_NAME w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
MAG_NAME=""
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

# 转换为绝对路径（避免 cd 后路径错误）
WORKDIR="$(cd "${WORKDIR}" && pwd)"
REPO="$(cd "${REPO}" && pwd)"

MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/gem/gapseq"

# 检查输入
if [ ! -d "${MAGS_DIR}" ]; then
    echo "[ERROR] dRep MAG 目录不存在: ${MAGS_DIR}"
    exit 1
fi

# 收集 MAG 文件
if [ -n "${MAG_NAME}" ]; then
    # 单 MAG 模式
    MAG_FILE="${MAGS_DIR}/${MAG_NAME}.fa"
    if [ ! -f "${MAG_FILE}" ]; then
        echo "[ERROR] 指定的 MAG 文件不存在: ${MAG_FILE}"
        exit 1
    fi
    MAGS=("${MAG_FILE}")
    echo "[gapseq] 单 MAG 模式: ${MAG_NAME}"
else
    # 批量模式
    mapfile -t MAGS < <(find "${MAGS_DIR}" -maxdepth 1 -name "*.fa" -type f | sort)
    if [ ${#MAGS[@]} -eq 0 ]; then
        echo "[ERROR] ${MAGS_DIR} 下未找到 *.fa MAGs"
        exit 1
    fi
    echo "[gapseq] 批量模式: ${#MAGS[@]} 个 MAG"
fi

mkdir -p "${OUTDIR}"
LOG="${OUTDIR}/gapseq_batch.log"
echo "[gapseq] 开始 GEM 重建..." | tee "${LOG}"
echo "[gapseq] 输出目录: ${OUTDIR}" | tee -a "${LOG}"

# 创建 SBML 转换 R 脚本（循环外，避免重复写入）
cat > "${OUTDIR}/convert_sbml.R" << 'RSCRIPT'
args <- commandArgs(trailingOnly = TRUE)
rds_file <- args[1]
xml_file <- args[2]

library(sybil)
mod <- readRDS(rds_file)
writeSBML(mod, xml_file)
cat("SBML conversion complete\n")
RSCRIPT

N_SUCCESS=0
N_SKIPPED=0
N_FAILED=0

for mag_fa in "${MAGS[@]}"; do
    # 转换为绝对路径
    mag_fa="$(cd "$(dirname "${mag_fa}")" && pwd)/$(basename "${mag_fa}")"
    mag_name="$(basename "${mag_fa}" .fa)"
    mag_outdir="${OUTDIR}/${mag_name}"
    mag_log="${mag_outdir}/gapseq.log"

    # 检查是否已完成（断点续传）
    if [ -f "${mag_outdir}/${mag_name}.xml" ] && [ ${FORCE} -eq 0 ]; then
        echo "[gapseq] 跳过 ${mag_name}（已存在 SBML 模型）" | tee -a "${LOG}"
        N_SKIPPED=$((N_SKIPPED+1))
        continue
    fi

    mkdir -p "${mag_outdir}"
    cd "${mag_outdir}"

    echo "=== [${mag_name}] 开始处理 ===" | tee -a "${mag_log}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MAG: ${mag_fa}" | tee -a "${mag_log}"

    # Step 1: Pathway prediction
    echo "[gapseq] Step 1/4: Pathway prediction..." | tee -a "${mag_log}"
    if ! conda run --prefix "${REPO}/envs/gapseq" gapseq find \
        -p all -b 200 "${mag_fa}" >> "${mag_log}" 2>&1; then
        echo "[ERROR] gapseq find 失败: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    # Step 2: Draft model construction
    echo "[gapseq] Step 2/4: Draft model construction..." | tee -a "${mag_log}"
    reactions_tbl="${mag_name}-all-Reactions.tbl"
    transporter_tbl="${mag_name}-all-Transporter.tbl"
    pathways_tbl="${mag_name}-all-Pathways.tbl"

    if [ ! -f "${reactions_tbl}" ] || [ ! -f "${pathways_tbl}" ]; then
        echo "[ERROR] gapseq find 输出文件缺失: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    if ! conda run --prefix "${REPO}/envs/gapseq" gapseq draft \
        -r "${reactions_tbl}" \
        -t "${transporter_tbl}" \
        -p "${pathways_tbl}" \
        -c "${mag_fa}" \
        -u 200 -l 100 >> "${mag_log}" 2>&1; then
        echo "[ERROR] gapseq draft 失败: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    draft_model="${mag_name}-draft.RDS"
    if [ ! -f "${draft_model}" ]; then
        echo "[ERROR] Draft model 未生成: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    # Step 3: Gap-filling
    echo "[gapseq] Step 3/4: Gap-filling..." | tee -a "${mag_log}"

    # 检查 gap-filling 所需的文件是否存在
    rxn_weights="${mag_name}-rxnWeights.RDS"
    rxn_genes="${mag_name}-rxnXgenes.RDS"

    if [ ! -f "${rxn_weights}" ] || [ ! -f "${rxn_genes}" ]; then
        echo "[WARNING] Gap-filling 依赖文件缺失，跳过 fill 步骤: ${mag_name}" | tee -a "${LOG}"
        cp "${draft_model}" "${mag_name}-gapfilled.RDS"
    elif ! conda run --prefix "${REPO}/envs/gapseq" gapseq fill \
        -m "${draft_model}" \
        -n medium \
        -c "${rxn_weights}" \
        -g "${rxn_genes}" >> "${mag_log}" 2>&1; then
        echo "[WARNING] gapseq fill 失败，使用 draft 模型: ${mag_name}" | tee -a "${LOG}"
        cp "${draft_model}" "${mag_name}-gapfilled.RDS"
    fi

    gapfilled_model="${mag_name}-gapfilled.RDS"
    if [ ! -f "${gapfilled_model}" ]; then
        echo "[ERROR] Gap-filled model 未生成: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    # Step 4: SBML 转换
    echo "[gapseq] Step 4/4: SBML conversion..." | tee -a "${mag_log}"

    if ! conda run --prefix "${REPO}/envs/gapseq" Rscript "${OUTDIR}/convert_sbml.R" \
        "${gapfilled_model}" "${mag_name}.xml" >> "${mag_log}" 2>&1; then
        echo "[ERROR] SBML 转换失败: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    if [ ! -f "${mag_name}.xml" ]; then
        echo "[ERROR] SBML 文件未生成: ${mag_name}" | tee -a "${LOG}"
        N_FAILED=$((N_FAILED+1))
        continue
    fi

    # 整理输出文件
    cp "${pathways_tbl}" "${mag_name}_pathways.tsv" 2>/dev/null || true
    cp "${reactions_tbl}" "${mag_name}_reactions.tsv" 2>/dev/null || true
    cp "${transporter_tbl}" "${mag_name}_transporters.tsv" 2>/dev/null || true

    echo "[gapseq] ✓ ${mag_name} 完成" | tee -a "${LOG}"
    N_SUCCESS=$((N_SUCCESS+1))

    cd "${WORKDIR}"
done

# 汇总统计（gapseq 各步 conda 调用位于 if ! 条件分支且无 --no-capture-output，
# 不满足 mgx_conda 的字节等价条件，保留原 conda run 形式）
ELAPSED=$((SECONDS))
echo "" | tee -a "${LOG}"
echo "=== GEM 重建完成 ===" | tee -a "${LOG}"
echo "成功: ${N_SUCCESS}" | tee -a "${LOG}"
echo "跳过: ${N_SKIPPED}" | tee -a "${LOG}"
echo "失败: ${N_FAILED}" | tee -a "${LOG}"
echo "总耗时: ${ELAPSED} 秒" | tee -a "${LOG}"

# 创建完成标志
touch "${OUTDIR}/gapseq_done.txt"

if [ ${N_FAILED} -gt 0 ]; then
    echo "[WARNING] ${N_FAILED} 个 MAG 重建失败，详见日志" | tee -a "${LOG}"
    exit 0  # 部分失败不报错，允许后续分析继续
fi

echo "[gapseq] 全部完成" | tee -a "${LOG}"
