#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 00_pipeline_virome.sh
# 功  能: 病毒维度一站式流程（Pipeline 模式，脚本 01-02 + 51-72）
#
# samplesheet.csv 格式（CSV，逗号分隔，有表头）：
#   sample_id,r1,r2,host_type,project_dir
#
# 参  数:
#   -i  samplesheet.csv 路径（必需）
#   -r  CSCCD-MetagenomeFlow 项目根目录（必需）
#   -t  每个样本的线程数（默认 8）
#   -j  并发样本数（默认 1）
#   --skip  跳过指定步骤，逗号分隔
#           可选值: qc, kneaddata, assembly, viral_id, checkv,
#                   prodigal_gv, quantify, cluster, mag, annotate
#   --from  从指定步骤继续（断点续跑）
#           可选值: kneaddata, assembly, viral_id, quantify, cluster, annotate
#   --only  只运行指定步骤
#           可选值: qc, kneaddata, assembly, viral_id, quantify, cluster, mag, annotate
#
# 示  例:
#   bash 00_pipeline_virome.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16
#   bash 00_pipeline_virome.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
#        --from assembly
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

SAMPLESHEET=""
REPO=""
CPUS=8
PARALLEL_JOBS=1
SKIP_STEPS=""
FROM_STEP=""
ONLY_STEP=""
FORCE=0

show_help() {
cat << 'EOF'
用法: bash 00_pipeline_virome.sh -i SAMPLESHEET -r REPO [选项]

必需参数:
  -i  samplesheet.csv 路径
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  -t  线程数（默认 8）
  -j  并发样本数（默认 1）
  --skip  跳过步骤（逗号分隔）:
          qc, kneaddata, assembly, viral_id, checkv,
          prodigal_gv, quantify, cluster, mag, annotate
  --from  从某步骤续跑:
          kneaddata, assembly, viral_id, quantify, cluster, annotate
  --only  只运行某步骤（同 --skip 可选值）

samplesheet.csv 格式（第一行为表头）:
  sample_id,r1,r2,host_type,project_dir
EOF
}

export MGX_OPTS_STRING="i:SAMPLESHEET r:REPO t:CPUS j:PARALLEL_JOBS"
export MGX_OPTS_LONG="skip:SKIP_STEPS from:FROM_STEP only:ONLY_STEP"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLESHEET REPO

if [ ! -f "${SAMPLESHEET}" ]; then
    echo "[ERROR] samplesheet 不存在: ${SAMPLESHEET}"; exit 1
fi

SCRIPTS="${REPO}/scripts"
mgx_begin

# 步骤执行顺序（用于 --from 逻辑）
STEPS_ORDER="qc kneaddata assembly viral_id checkv prodigal_gv quantify cluster mag annotate"

should_run() {
    local step="$1"
    if [ -n "${ONLY_STEP}" ]; then
        [[ "${step}" == "${ONLY_STEP}" ]] && return 0 || return 1
    fi
    if [ -n "${FROM_STEP}" ]; then
        local reached=0
        for s in ${STEPS_ORDER}; do
            [ "${s}" == "${FROM_STEP}" ] && reached=1
            [ "${s}" == "${step}" ] && [ ${reached} -eq 0 ] && return 1
        done
    fi
    if echo ",${SKIP_STEPS}," | grep -q ",${step},"; then
        return 1
    fi
    return 0
}

echo "[pipeline_virome] 解析 samplesheet: ${SAMPLESHEET}"
TOTAL=$(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#" | wc -l)
echo "[pipeline_virome] 共 ${TOTAL} 个样本"
mapfile -t SAMPLES < <(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#")

# --- 单样本的 per-sample 步骤（01-02 + 51-55 + 59 + 63）---
run_sample() {
    local line="$1"
    local FORCE_FLAG=""
    [ ${FORCE} -eq 1 ] && FORCE_FLAG="--force"
    local line="$1"
    local SAMPLE_ID R1 R2 _HOST_TYPE WORKDIR
    IFS=',' read -r SAMPLE_ID R1 R2 _HOST_TYPE WORKDIR <<< "${line}"
    SAMPLE_ID=$(echo "${SAMPLE_ID}" | tr -d ' "')
    WORKDIR=$(echo "${WORKDIR}" | tr -d ' "')

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[pipeline_virome] 样本: ${SAMPLE_ID}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ ! -f "${R1}" ] || [ ! -f "${R2}" ]; then
        echo "[ERROR] ${SAMPLE_ID}: 输入文件不存在 R1=${R1} R2=${R2}"; return 1
    fi
    mkdir -p "${WORKDIR}/data"
    [ ! -f "${WORKDIR}/data/${SAMPLE_ID}_1.fastq.gz" ] && ln -sf "${R1}" "${WORKDIR}/data/${SAMPLE_ID}_1.fastq.gz"
    [ ! -f "${WORKDIR}/data/${SAMPLE_ID}_2.fastq.gz" ] && ln -sf "${R2}" "${WORKDIR}/data/${SAMPLE_ID}_2.fastq.gz"

    # 01 质控
    should_run "qc" && { echo "[${SAMPLE_ID}] Step 01: fastp 质控..."; bash "${SCRIPTS}/01_qc_fastp.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; } || echo "[${SAMPLE_ID}] 跳过 qc"

    # 02 去宿主
    should_run "kneaddata" && { echo "[${SAMPLE_ID}] Step 02: kneaddata 去宿主..."; bash "${SCRIPTS}/02_qc_kneaddata.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; } || echo "[${SAMPLE_ID}] 跳过 kneaddata"

    # 51 组装
    should_run "assembly" && { echo "[${SAMPLE_ID}] Step 51: 病毒组装 (MEGAHIT)..."; bash "${SCRIPTS}/51_vir_megahit.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; } || echo "[${SAMPLE_ID}] 跳过 assembly"

    # 52-53 病毒鉴定（geNomad + VirSorter2）
    if should_run "viral_id"; then
        echo "[${SAMPLE_ID}] Step 52: geNomad 病毒鉴定..."
        bash "${SCRIPTS}/52_vir_genomad.sh"    -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
        echo "[${SAMPLE_ID}] Step 53: VirSorter2 病毒预测..."
        bash "${SCRIPTS}/53_vir_virsorter2.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    else
        echo "[${SAMPLE_ID}] 跳过 viral_id"
    fi

    # 54 CheckV contig 质评
    should_run "checkv" && { echo "[${SAMPLE_ID}] Step 54: CheckV contig 质评..."; bash "${SCRIPTS}/54_vir_checkv_contig.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; } || echo "[${SAMPLE_ID}] 跳过 checkv"

    # 55 蛋白预测
    should_run "prodigal_gv" && { echo "[${SAMPLE_ID}] Step 55: Prodigal-gv 蛋白预测..."; bash "${SCRIPTS}/55_vir_prodigal_gv.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; } || echo "[${SAMPLE_ID}] 跳过 prodigal_gv"

    echo "[pipeline_virome] 样本 ${SAMPLE_ID} per-sample 步骤完成"
}
export -f run_sample should_run
export SCRIPTS REPO CPUS FORCE SKIP_STEPS FROM_STEP ONLY_STEP STEPS_ORDER

# 聚合步骤使用的 --force 透传标志（run_sample 内的 local FORCE_FLAG 不泄漏到全局）
FORCE_FLAG=""
[ ${FORCE} -eq 1 ] && FORCE_FLAG="--force"

# --- 执行 per-sample 步骤 ---
if [ "${PARALLEL_JOBS}" -gt 1 ] && command -v rush &>/dev/null; then
    echo "[pipeline_virome] 并行模式（-j ${PARALLEL_JOBS}）"
    printf '%s\n' "${SAMPLES[@]}" | rush -j "${PARALLEL_JOBS}" 'run_sample "{}"'
else
    [ "${PARALLEL_JOBS}" -gt 1 ] && echo "[WARN] 未找到 rush，降级为顺序执行"
    for sample_line in "${SAMPLES[@]}"; do
        run_sample "${sample_line}"
    done
fi

# 取第一个样本的 project_dir 作为聚合操作的 WORKDIR
# （假设同一 samplesheet 内的样本共享同一 project_dir）
FIRST_LINE=$(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#" | head -n1)
IFS=',' read -r _ _ _ _ AGG_WORKDIR <<< "${FIRST_LINE}"
AGG_WORKDIR=$(echo "${AGG_WORKDIR}" | tr -d ' "')

# --- 聚合步骤（所有样本完成后运行一次）---
if should_run "cluster"; then
    echo "[pipeline_virome] Step 56: vOTU 生成 (vclust)..."
    bash "${SCRIPTS}/56_vir_votu_gen.sh"    -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    echo "[pipeline_virome] Step 57: vOTU 分类注释 (geNomad)..."
    bash "${SCRIPTS}/57_vir_votu_genomad.sh" -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    echo "[pipeline_virome] Step 58: 构建 Salmon 索引..."
    bash "${SCRIPTS}/58_vir_salmon_build.sh" -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
fi

if should_run "quantify"; then
    echo "[pipeline_virome] Step 59/63: 丰度定量（逐样本）..."
    for sample_line in "${SAMPLES[@]}"; do
        IFS=',' read -r SID _ _ _ WDIR <<< "${sample_line}"
        SID=$(echo "${SID}" | tr -d ' "')
        WDIR=$(echo "${WDIR}" | tr -d ' "')
        bash "${SCRIPTS}/59_vir_salmon_quant.sh" -s "${SID}" -t "${CPUS}" -w "${WDIR}" -r "${REPO}" ${FORCE_FLAG}
    done
    bash "${SCRIPTS}/60_vir_votu_table.sh" -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
fi

if should_run "mag"; then
    echo "[pipeline_virome] Step 61-62: vMAG 生成 + CheckV 质评..."
    bash "${SCRIPTS}/61_vir_vmag.sh"       -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/62_vir_checkv_mag.sh" -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    echo "[pipeline_virome] Step 63: CoverM vMAG 丰度..."
    for sample_line in "${SAMPLES[@]}"; do
        IFS=',' read -r SID _ _ _ WDIR <<< "${sample_line}"
        SID=$(echo "${SID}" | tr -d ' "')
        WDIR=$(echo "${WDIR}" | tr -d ' "')
        bash "${SCRIPTS}/63_vir_coverm_quant.sh" -s "${SID}" -t "${CPUS}" -w "${WDIR}" -r "${REPO}" ${FORCE_FLAG}
    done
fi

if should_run "annotate"; then
    echo "[pipeline_virome] Step 64-69: 病毒注释..."
    bash "${SCRIPTS}/64_vir_pharokka.sh"   -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/65_vir_phold.sh"      -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/66_vir_vog.sh"        -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/67_vir_bacphlip.sh"   -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/68_vir_iphop.sh"      -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/69_vir_vcontact3.sh"  -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    echo "[pipeline_virome] Step 70-72: 扩展工具（PhaBox2/DRAM-v/PhaGCN3）..."
    bash "${SCRIPTS}/70_vir_phabox2.sh"    -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/71_vir_dram.sh"       -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
    bash "${SCRIPTS}/72_vir_phagcn3.sh"    -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[pipeline_virome] 病毒维度流程完成，共处理 ${TOTAL} 个样本，耗时 ${SECONDS}s"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
