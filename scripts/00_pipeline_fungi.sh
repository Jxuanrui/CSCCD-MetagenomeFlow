#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 00_pipeline_fungi.sh
# 功  能: 真菌维度一站式流程（Pipeline 模式，脚本 01-02 + 71-86）
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
#           可选值: qc, kneaddata, taxonomy, assembly, eukfinder,
#                   gene_predict, annotate
#   --from  从指定步骤继续（断点续跑）
#           可选值: kneaddata, taxonomy, assembly, eukfinder, gene_predict, annotate
#   --only  只运行指定步骤（同 --skip 可选值）
#
# 示  例:
#   bash 00_pipeline_fungi.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16
#   bash 00_pipeline_fungi.sh -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
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
用法: bash 00_pipeline_fungi.sh -i SAMPLESHEET -r REPO [选项]

必需参数:
  -i  samplesheet.csv 路径
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  -t  线程数（默认 8）
  -j  并发样本数（默认 1）
  --skip  跳过步骤（逗号分隔）:
          qc, kneaddata, taxonomy, assembly, eukfinder, gene_predict, annotate
  --from  从某步骤续跑:
          kneaddata, taxonomy, assembly, eukfinder, gene_predict, annotate
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

STEPS_ORDER="qc kneaddata taxonomy assembly eukfinder gene_predict annotate"

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

echo "[pipeline_fungi] 解析 samplesheet: ${SAMPLESHEET}"
TOTAL=$(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#" | wc -l)
echo "[pipeline_fungi] 共 ${TOTAL} 个样本"
mapfile -t SAMPLES < <(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#")

# --- 单样本的 per-sample 步骤（01-02 + 71-80）---
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
    echo "[pipeline_fungi] 样本: ${SAMPLE_ID}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ ! -f "${R1}" ] || [ ! -f "${R2}" ]; then
        echo "[ERROR] ${SAMPLE_ID}: 输入文件不存在 R1=${R1} R2=${R2}"; return 1
    fi
    mkdir -p "${WORKDIR}/data"
    [ ! -f "${WORKDIR}/data/${SAMPLE_ID}_1.fastq.gz" ] && ln -sf "${R1}" "${WORKDIR}/data/${SAMPLE_ID}_1.fastq.gz"
    [ ! -f "${WORKDIR}/data/${SAMPLE_ID}_2.fastq.gz" ] && ln -sf "${R2}" "${WORKDIR}/data/${SAMPLE_ID}_2.fastq.gz"

    # 01 质控
    should_run "qc" && { echo "[${SAMPLE_ID}] Step 01: fastp 质控..."; bash "${SCRIPTS}/01_qc_fastp.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true; } || echo "[${SAMPLE_ID}] 跳过 qc"

    # 02 去宿主
    should_run "kneaddata" && { echo "[${SAMPLE_ID}] Step 02: kneaddata 去宿主..."; bash "${SCRIPTS}/02_qc_kneaddata.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true; } || echo "[${SAMPLE_ID}] 跳过 kneaddata"

    # 71-77 分类（Kraken2 + MetaPhlAn4 + HUMAnN4提取 + BLAST + FunOMIC + CCMetagen + MicroFisher）
    # 并行启动三种互补策略，提速
    if should_run "taxonomy"; then
        echo "[${SAMPLE_ID}] Step 71: Kraken2 真菌分类..."
        bash "${SCRIPTS}/71_fun_kraken2_fungi.sh"  -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
        echo "[${SAMPLE_ID}] Step 72: MetaPhlAn4 真菌分类..."
        bash "${SCRIPTS}/72_fun_metaphlan4_euk.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
        echo "[${SAMPLE_ID}] Step 73: 提取真菌功能通路..."
        bash "${SCRIPTS}/73_fun_humann4_fungi.sh"  -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
        echo "[${SAMPLE_ID}] Step 74: BLAST 比对肠道真菌库..."
        bash "${SCRIPTS}/74_fun_blast_gutdb.sh"    -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
        echo "[${SAMPLE_ID}] Step 75: FunOMIC 真菌分类..."
        bash "${SCRIPTS}/75_fun_funomics.sh"       -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
        echo "[${SAMPLE_ID}] Step 76: CCMetagen 真核分类..."
        bash "${SCRIPTS}/76_fun_ccmetagen.sh"      -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
        echo "[${SAMPLE_ID}] Step 77: MicroFisher 多标记提取..."
        bash "${SCRIPTS}/77_fun_microfisher.sh"    -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
    else
        echo "[${SAMPLE_ID}] 跳过 taxonomy"
    fi

    # 78 组装
    should_run "assembly" && { echo "[${SAMPLE_ID}] Step 78: 真菌组装 (MEGAHIT)..."; bash "${SCRIPTS}/78_fun_megahit.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true; } || echo "[${SAMPLE_ID}] 跳过 assembly"

    # 79 Eukfinder MAG 回收
    should_run "eukfinder" && { echo "[${SAMPLE_ID}] Step 79: Eukfinder MAG 回收..."; bash "${SCRIPTS}/79_fun_eukfinder.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true; } || echo "[${SAMPLE_ID}] 跳过 eukfinder"

    # 80 基因预测
    should_run "gene_predict" && { echo "[${SAMPLE_ID}] Step 80: Prodigal 基因预测..."; bash "${SCRIPTS}/80_fun_prodigal.sh" -s "${SAMPLE_ID}" -t "${CPUS}" -w "${WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true; } || echo "[${SAMPLE_ID}] 跳过 gene_predict"

    echo "[pipeline_fungi] 样本 ${SAMPLE_ID} per-sample 步骤完成"
}
export -f run_sample should_run
export SCRIPTS REPO CPUS FORCE SKIP_STEPS FROM_STEP ONLY_STEP STEPS_ORDER

# 聚合注释使用的 --force 透传标志（run_sample 内的 local FORCE_FLAG 不泄漏到全局）
FORCE_FLAG=""
[ ${FORCE} -eq 1 ] && FORCE_FLAG="--force"

# --- 执行 per-sample 步骤 ---
if [ "${PARALLEL_JOBS}" -gt 1 ] && command -v rush &>/dev/null; then
    echo "[pipeline_fungi] 并行模式（-j ${PARALLEL_JOBS}）"
    printf '%s\n' "${SAMPLES[@]}" | rush -j "${PARALLEL_JOBS}" 'run_sample "{}"'
else
    [ "${PARALLEL_JOBS}" -gt 1 ] && echo "[WARN] 未找到 rush，降级为顺序执行"
    for sample_line in "${SAMPLES[@]}"; do
        run_sample "${sample_line}"
    done
fi

# 取第一个样本的 project_dir 作为聚合操作的 WORKDIR
FIRST_LINE=$(tail -n+2 "${SAMPLESHEET}" | grep -v "^$\|^#" | head -n1)
IFS=',' read -r _ _ _ _ AGG_WORKDIR <<< "${FIRST_LINE}"
AGG_WORKDIR=$(echo "${AGG_WORKDIR}" | tr -d ' "')

# --- 聚合注释（所有样本的 FAA 文件都就绪后）---
if should_run "annotate"; then
    echo "[pipeline_fungi] Step 81-86: 聚合注释（所有样本合并）..."
    bash "${SCRIPTS}/81_fun_eggnog.sh" -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
    bash "${SCRIPTS}/82_fun_kegg.sh"   -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
    bash "${SCRIPTS}/83_fun_dbcan.sh"  -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
    bash "${SCRIPTS}/84_fun_vfdb.sh"   -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
    bash "${SCRIPTS}/85_fun_amr.sh"    -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
    bash "${SCRIPTS}/86_fun_merops.sh" -t "${CPUS}" -w "${AGG_WORKDIR}" -r "${REPO}" ${FORCE_FLAG}; [ ${FORCE} -eq 1 ] && echo " --force" || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[pipeline_fungi] 真菌维度流程完成，共处理 ${TOTAL} 个样本，耗时 ${SECONDS}s"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
