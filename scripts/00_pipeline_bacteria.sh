#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 00_pipeline_bacteria.sh
# 功  能: 细菌维度一站式流程（Pipeline 模式）
#         支持两种运行模式：
#           模式一（逐步）：通过主流程脚本或直接调用各步骤脚本
#           模式二（一站式）：本脚本，传入 samplesheet.csv，自动串联所有步骤
#
# 设计特点: 支持 --skip/--from/--only 灵活控制步骤，支持多样本并行（-j 参数）
#
# 用  法: bash 00_pipeline_bacteria.sh -i SAMPLESHEET -r REPO [-t CPUS] [options]
#
# samplesheet.csv 格式（CSV，逗号分隔，有表头）：
#   sample_id,r1,r2,host_type,project_dir
#   SRR001,/path/to/SRR001_1.fastq.gz,/path/to/SRR001_2.fastq.gz,human,/path/to/Project_A
#
#   字段说明：
#     sample_id   样本名（唯一，不含特殊字符）
#     r1/r2       原始数据绝对路径（*.fastq.gz）
#     host_type   宿主类型：human / mouse / rat（用于去宿主步骤）
#     project_dir 该样本的工作目录（结果输出到 project_dir/result/）
#
# 参  数:
#   -i  samplesheet.csv 路径（必需）
#   -r  CSCCD-MetagenomeFlow 项目根目录（必需）
#   -t  每个样本的线程数（默认 8）
#   -j  并发样本数（默认 1，多样本时可设置 2-4）
#   --skip  跳过指定步骤，逗号分隔（如 --skip qc,kneaddata）
#           可选值: qc, kneaddata, metaphlan4, strainphlan4, humann4, merge
#   --from  从指定步骤继续（断点续跑），前面步骤跳过
#           可选值: kneaddata, metaphlan4, humann4
#   --only  只运行指定步骤
#           可选值: qc, kneaddata, taxonomy, functional
#
# 示  例:
#   # 完整流程
#   bash 00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16
#
#   # 从去宿主开始（跳过质控）
#   bash 00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
#        --from kneaddata
#
#   # 只做分类分析（跳过质控和去宿主）
#   bash 00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
#        --only taxonomy
#
#   # 高深度样本使用平衡模式加速 HUMAnN4
#   bash 00_pipeline_bacteria.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
#        --humann-speed balanced
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# --- 默认参数 ---
SAMPLESHEET=""
REPO=""
CPUS=8
PARALLEL_JOBS=1
SKIP_STEPS=""
FROM_STEP=""
ONLY_STEP=""
HUMANN_SPEED="standard"
FORCE=0

show_help() {
cat << 'EOF'
用法: bash 00_pipeline_bacteria.sh -i SAMPLESHEET -r REPO [选项]

必需参数:
  -i  samplesheet.csv 路径
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  -t  线程数（默认 8）
  -j  并发样本数（默认 1）
  --skip  跳过步骤：qc,kneaddata,metaphlan4,strainphlan4,humann4,merge
  --from  从某步骤开始续跑：kneaddata,metaphlan4,humann4
  --only  只运行某模块：qc,kneaddata,taxonomy,functional
  --humann-speed  HUMAnN3 速度模式：standard（默认）/ balanced（推荐）/ fast

samplesheet.csv 格式（第一行为表头）:
  sample_id,r1,r2,host_type,project_dir

示例:
  bash 00_pipeline_bacteria.sh \
       -i ~/Course/CSCCD-MetagenomeFlow/Project/Project_A/samplesheet.csv \
       -r ~/Course/CSCCD-MetagenomeFlow -t 16 -j 2
EOF
}

# --- 参数解析（--skip/--from/--only 等由 libcommon.sh 的 mgx_parse 表驱动）---
export MGX_OPTS_STRING="i:SAMPLESHEET r:REPO t:CPUS j:PARALLEL_JOBS"
export MGX_OPTS_LONG="skip:SKIP_STEPS from:FROM_STEP only:ONLY_STEP humann-speed:HUMANN_SPEED"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLESHEET REPO

if [ ! -f "${SAMPLESHEET}" ]; then
    echo "[ERROR] samplesheet 不存在: ${SAMPLESHEET}"; exit 1
fi

SCRIPTS="${REPO}/scripts"
mgx_begin

# --- 步骤开关辅助函数 ---
# 返回 0（运行此步骤）/ 1（跳过此步骤）
should_run() {
    local step="$1"
    # --only 模式
    if [ -n "${ONLY_STEP}" ]; then
        case "${ONLY_STEP}" in
            qc)         [[ "${step}" == "qc" ]] && return 0 || return 1 ;;
            kneaddata)  [[ "${step}" == "kneaddata" ]] && return 0 || return 1 ;;
            taxonomy)   [[ "${step}" =~ metaphlan4|strainphlan4|merge ]] && return 0 || return 1 ;;
            functional) [[ "${step}" == "humann4" ]] && return 0 || return 1 ;;
        esac
    fi
    # --from 模式（跳过 from 之前的步骤）
    if [ -n "${FROM_STEP}" ]; then
        local steps_order="qc kneaddata metaphlan4 humann4 strainphlan4 merge"
        local reached=0
        for s in ${steps_order}; do
            [ "${s}" == "${FROM_STEP}" ] && reached=1
            [ "${s}" == "${step}" ] && [ ${reached} -eq 0 ] && return 1
        done
    fi
    # --skip 模式
    if echo ",${SKIP_STEPS}," | grep -q ",${step},"; then
        return 1
    fi
    return 0
}

# --- 解析 samplesheet ---
echo "[pipeline] 解析 samplesheet: ${SAMPLESHEET}"
TOTAL=$(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#" | wc -l)
echo "[pipeline] 共 ${TOTAL} 个样本"

# 读取所有样本信息到数组
mapfile -t SAMPLES < <(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#")

# --- 运行函数：对单个样本运行所有步骤 ---
run_sample() {
    local line="$1"
    local FORCE_FLAG=""
    [ ${FORCE} -eq 1 ] && FORCE_FLAG="--force"
    local line="$1"
    local SAMPLE_ID R1 R2 HOST_TYPE WORKDIR

    IFS=',' read -r SAMPLE_ID R1 R2 HOST_TYPE WORKDIR <<< "${line}"

    # 去除可能的空格和引号
    SAMPLE_ID=$(echo "${SAMPLE_ID}" | tr -d ' "')
    WORKDIR=$(echo "${WORKDIR}" | tr -d ' "')

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[pipeline] 开始处理样本: ${SAMPLE_ID}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 验证输入文件
    if [ ! -f "${R1}" ] || [ ! -f "${R2}" ]; then
        echo "[ERROR] ${SAMPLE_ID}: 输入文件不存在 R1=${R1} R2=${R2}"
        return 1
    fi

    # 确保原始数据在 WORKDIR/data/ 下（软链接或已存在）
    mkdir -p "${WORKDIR}/data"
    [ ! -f "${WORKDIR}/data/${SAMPLE_ID}_1.fastq.gz" ] && \
        ln -sf "${R1}" "${WORKDIR}/data/${SAMPLE_ID}_1.fastq.gz"
    [ ! -f "${WORKDIR}/data/${SAMPLE_ID}_2.fastq.gz" ] && \
        ln -sf "${R2}" "${WORKDIR}/data/${SAMPLE_ID}_2.fastq.gz"

    # Step 01: 质量控制
    if should_run "qc"; then
        echo "[${SAMPLE_ID}] Step 01: fastp 质控..."
        bash "${SCRIPTS}/01_qc_fastp.sh" \
            -s "${SAMPLE_ID}" -t "${CPUS}" \
            -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    else
        echo "[${SAMPLE_ID}] Step 01: 跳过 fastp 质控"
    fi

    # Step 02: 去宿主
    if should_run "kneaddata"; then
        echo "[${SAMPLE_ID}] Step 02: kneaddata 去宿主（宿主: ${HOST_TYPE}）..."
        bash "${SCRIPTS}/02_qc_kneaddata.sh" \
            -s "${SAMPLE_ID}" -t "${CPUS}" \
            -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    else
        echo "[${SAMPLE_ID}] Step 02: 跳过去宿主"
    fi

    # Step 11: MetaPhlAn4 物种组成
    if should_run "metaphlan4"; then
        echo "[${SAMPLE_ID}] Step 11: MetaPhlAn4 物种组成..."
        bash "${SCRIPTS}/11_bac_metaphlan4.sh" \
            -s "${SAMPLE_ID}" -t "${CPUS}" \
            -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    else
        echo "[${SAMPLE_ID}] Step 11: 跳过 MetaPhlAn4"
    fi

    # Step 13: HUMAnN4 功能通路
    if should_run "humann4"; then
        echo "[${SAMPLE_ID}] Step 13: HUMAnN4 功能通路定量（速度模式: ${HUMANN_SPEED}）..."
        bash "${SCRIPTS}/13_bac_humann3.sh" \
            -s "${SAMPLE_ID}" -t "${CPUS}" \
            -w "${WORKDIR}" -r "${REPO}" \
            --speed-mode "${HUMANN_SPEED}"
    else
        echo "[${SAMPLE_ID}] Step 13: 跳过 HUMAnN4"
    fi

    echo "[pipeline] 样本 ${SAMPLE_ID} 完成"
}
export -f run_sample should_run
export SCRIPTS REPO CPUS FORCE SKIP_STEPS FROM_STEP ONLY_STEP HUMANN_SPEED

# --- 执行（支持并行）---
if [ "${PARALLEL_JOBS}" -gt 1 ] && command -v rush &>/dev/null; then
    echo "[pipeline] 并行模式（-j ${PARALLEL_JOBS}）"
    printf '%s\n' "${SAMPLES[@]}" | rush -j "${PARALLEL_JOBS}" 'run_sample "{}"'
else
    if [ "${PARALLEL_JOBS}" -gt 1 ]; then
        echo "[WARN] 未找到 rush，降级为顺序执行（安装 rush 可启用并行）"
    fi
    for sample_line in "${SAMPLES[@]}"; do
        run_sample "${sample_line}"
    done
fi

# --- 合并步骤（所有样本完成后）---
if should_run "merge"; then
    # 按 project_dir 分组合并
    declare -A PROJECTS
    while IFS=',' read -r sid _r1 _r2 _host wd; do
        [[ "${sid}" == "sample_id" ]] && continue
        wd=$(echo "${wd}" | tr -d ' "')
        PROJECTS["${wd}"]=1
    done < "${SAMPLESHEET}"

    for proj_dir in "${!PROJECTS[@]}"; do
        echo ""
        echo "[pipeline] 合并项目: ${proj_dir}"
        bash "${SCRIPTS}/11b_bac_metaphlan4_merge.sh" \
            -w "${proj_dir}" -r "${REPO}" 2>/dev/null || \
            echo "[WARN] 合并 MetaPhlAn4 profiles 失败，可能样本不足"
    done
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[pipeline] 细菌维度流程完成，共处理 ${TOTAL} 个样本，耗时 ${SECONDS}s"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
