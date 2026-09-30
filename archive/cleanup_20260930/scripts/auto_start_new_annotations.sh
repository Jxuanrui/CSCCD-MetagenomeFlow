#!/usr/bin/env bash
# ==============================================================================
# 脚本名: auto_start_new_annotations.sh
# 功  能: antiSMASH 完成后自动启动新增功能注释脚本（31b-31e, 42, 42b）
# 触发条件: antiSMASH 10/10 样本完成
# 执行顺序: 批次1（31b/31c/31d 并行）→ 批次2（31e）→ 批次3（42/42b per-sample）
# 用  法: bash auto_start_new_annotations.sh -w WORKDIR [-r REPO]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=""

show_help() {
cat << EOF
用法: bash auto_start_new_annotations.sh -w WORKDIR [-r REPO]

必需参数:
  -w  工作目录（项目目录，如 Project/Project01）

可选参数:
  -r  CSCCD-MetagenomeFlow 项目根目录（默认自动检测: ${REPO}）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO"
mgx_parse "$@"
mgx_require WORKDIR

LOGDIR="${WORKDIR}/temp/logs/auto_annotations"

mkdir -p "${LOGDIR}"

echo "============================== 自动化注释流程 =============================="
echo "启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "工作目录: ${WORKDIR}"
echo "=========================================================================="

# ============================================================================
# 批次 1: 功能注释补充（31b-31e，aggregate，并行）
# ============================================================================
echo ""
echo "=== 批次 1: 功能注释补充 (31b/31c/31d 并行) ==="

# 31b SCyc 硫循环（快速，~10 分钟）
echo "[$(date '+%H:%M:%S')] 启动 31b SCyc..." | tee -a "${LOGDIR}/batch1.log"
bash ${REPO}/scripts/31b_bac_scyc.sh -t 16 \
  -w ${WORKDIR} -r ${REPO} \
  > ${LOGDIR}/31b_scyc.log 2>&1 &
PID_31B=$!

# 31d UniProt Swiss-Prot（中速，~20-40 分钟）
echo "[$(date '+%H:%M:%S')] 启动 31d UniProt..." | tee -a "${LOGDIR}/batch1.log"
bash ${REPO}/scripts/31d_bac_uniprot.sh -t 16 \
  -w ${WORKDIR} -r ${REPO} \
  > ${LOGDIR}/31d_uniprot.log 2>&1 &
PID_31D=$!

# 31c Pfam-A（慢速，~1-3 小时）
echo "[$(date '+%H:%M:%S')] 启动 31c Pfam-A..." | tee -a "${LOGDIR}/batch1.log"
bash ${REPO}/scripts/31c_bac_pfam.sh -t 32 \
  -w ${WORKDIR} -r ${REPO} \
  > ${LOGDIR}/31c_pfam.log 2>&1 &
PID_31C=$!

echo "[批次1] 三个任务已启动（PID: ${PID_31B}, ${PID_31D}, ${PID_31C}）"
echo "[批次1] 等待全部完成..." | tee -a "${LOGDIR}/batch1.log"

# 等待批次1全部完成
EXIT_31B=0
mgx_try wait ${PID_31B} || EXIT_31B=$?
echo "[$(date '+%H:%M:%S')] 31b SCyc 完成 (exit: ${EXIT_31B})" | tee -a "${LOGDIR}/batch1.log"

EXIT_31D=0
mgx_try wait ${PID_31D} || EXIT_31D=$?
echo "[$(date '+%H:%M:%S')] 31d UniProt 完成 (exit: ${EXIT_31D})" | tee -a "${LOGDIR}/batch1.log"

EXIT_31C=0
mgx_try wait ${PID_31C} || EXIT_31C=$?
echo "[$(date '+%H:%M:%S')] 31c Pfam-A 完成 (exit: ${EXIT_31C})" | tee -a "${LOGDIR}/batch1.log"

if [ ${EXIT_31B} -ne 0 ] || [ ${EXIT_31D} -ne 0 ] || [ ${EXIT_31C} -ne 0 ]; then
    echo "[ERROR] 批次1 有任务失败，请检查日志" | tee -a "${LOGDIR}/batch1.log"
    exit 1
fi

echo "[批次1] ✓ 全部完成" | tee -a "${LOGDIR}/batch1.log"

# ============================================================================
# 批次 2: 铁代谢基因预测（31e FeGenie，NR 模式）
# ============================================================================
echo ""
echo "=== 批次 2: 铁代谢基因预测 (31e FeGenie NR模式) ==="
echo "[$(date '+%H:%M:%S')] 启动 31e FeGenie..." | tee -a "${LOGDIR}/batch2.log"

EXIT_31E=0
mgx_try bash ${REPO}/scripts/31e_bac_fegenie.sh -s NR -t 16 \
  -w ${WORKDIR} -r ${REPO} --input-type nr \
  > ${LOGDIR}/31e_fegenie.log 2>&1 || EXIT_31E=$?
if [ ${EXIT_31E} -ne 0 ]; then
    echo "[ERROR] 31e FeGenie 失败 (exit: ${EXIT_31E})" | tee -a "${LOGDIR}/batch2.log"
    exit 1
fi

echo "[$(date '+%H:%M:%S')] [批次2] ✓ 31e FeGenie 完成" | tee -a "${LOGDIR}/batch2.log"

# ============================================================================
# 批次 3: MGE + 质粒分析（42/42b，per-sample，串行）
# ============================================================================
echo ""
echo "=== 批次 3: MGE + 质粒分析 (42/42b per-sample) ==="

# 检查 MEGAHIT 组装是否完成
ASSEMBLY_DIR="${WORKDIR}/result/assembly/megahit"
if [ ! -d "${ASSEMBLY_DIR}" ]; then
    echo "[WARNING] MEGAHIT 组装目录不存在，跳过批次3" | tee -a "${LOGDIR}/batch3.log"
    echo "请先运行步骤 16 (MEGAHIT 组装) 后再手动执行批次3"
    exit 0
fi

# 获取样本列表
SAMPLESHEET="${WORKDIR}/samplesheet.csv"
if [ ! -f "${SAMPLESHEET}" ]; then
    SAMPLESHEET="${WORKDIR}/samplesheet_test10.csv"
fi

if [ ! -f "${SAMPLESHEET}" ]; then
    echo "[ERROR] 未找到 samplesheet" | tee -a "${LOGDIR}/batch3.log"
    exit 1
fi

echo "[批次3] 读取样本列表..." | tee -a "${LOGDIR}/batch3.log"
mapfile -t SAMPLES < <(tail -n +2 "${SAMPLESHEET}" | cut -d',' -f1)
echo "[批次3] 找到 ${#SAMPLES[@]} 个样本" | tee -a "${LOGDIR}/batch3.log"

# 单样本测试
TEST_SAMPLE="${SAMPLES[0]}"
echo "[$(date '+%H:%M:%S')] 单样本测试: ${TEST_SAMPLE}" | tee -a "${LOGDIR}/batch3.log"

# 42 MGE
echo "[批次3] 启动 42 MGE (${TEST_SAMPLE})..." | tee -a "${LOGDIR}/batch3.log"
EXIT_42=0
mgx_try bash ${REPO}/scripts/42_bac_mge.sh -s ${TEST_SAMPLE} -t 16 \
  -w ${WORKDIR} -r ${REPO} \
  > ${LOGDIR}/42_mge_${TEST_SAMPLE}.log 2>&1 || EXIT_42=$?
if [ ${EXIT_42} -ne 0 ]; then
    echo "[ERROR] 42 MGE 测试失败 (exit: ${EXIT_42})" | tee -a "${LOGDIR}/batch3.log"
    exit 1
fi

# 42b 质粒
echo "[批次3] 启动 42b PlasmidFinder (${TEST_SAMPLE})..." | tee -a "${LOGDIR}/batch3.log"
EXIT_42B=0
mgx_try bash ${REPO}/scripts/42b_bac_plasmidfinder.sh -s ${TEST_SAMPLE} -t 8 \
  -w ${WORKDIR} -r ${REPO} \
  > ${LOGDIR}/42b_plasmidfinder_${TEST_SAMPLE}.log 2>&1 || EXIT_42B=$?
if [ ${EXIT_42B} -ne 0 ]; then
    echo "[ERROR] 42b PlasmidFinder 测试失败 (exit: ${EXIT_42B})" | tee -a "${LOGDIR}/batch3.log"
    exit 1
fi

echo "[$(date '+%H:%M:%S')] [批次3] ✓ 单样本测试完成" | tee -a "${LOGDIR}/batch3.log"

# 批量运行（rush 并行）
echo "[批次3] 启动批量运行（rush -j 2）..." | tee -a "${LOGDIR}/batch3.log"

set +e
printf "%s\n" "${SAMPLES[@]}" | \
  ${REPO}/miniforge3/bin/rush -j 2 -k \
  "bash ${REPO}/scripts/42_bac_mge.sh -s {} -t 16 \
     -w ${WORKDIR} -r ${REPO} \
     > ${LOGDIR}/42_mge_{}.log 2>&1 && \
   bash ${REPO}/scripts/42b_bac_plasmidfinder.sh -s {} -t 8 \
     -w ${WORKDIR} -r ${REPO} \
     > ${LOGDIR}/42b_plasmidfinder_{}.log 2>&1 && \
   echo '[{}] MGE+Plasmid done'" \
  2>&1 | tee -a "${LOGDIR}/batch3_rush.log"
set -e

COMPLETED=$(grep -c "MGE+Plasmid done" "${LOGDIR}/batch3_rush.log" 2>/dev/null || true)
echo "[$(date '+%H:%M:%S')] [批次3] 完成 ${COMPLETED}/${#SAMPLES[@]} 样本" | tee -a "${LOGDIR}/batch3.log"

if [ ${COMPLETED} -lt ${#SAMPLES[@]} ]; then
    echo "[WARNING] 批次3 部分样本失败，请检查日志" | tee -a "${LOGDIR}/batch3.log"
fi

# ============================================================================
# 完成总结
# ============================================================================
echo ""
echo "============================== 全部完成 =============================="
echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "日志目录: ${LOGDIR}/"
echo "  - batch1.log: 31b/31c/31d 功能注释补充"
echo "  - batch2.log: 31e FeGenie 铁代谢"
echo "  - batch3.log: 42/42b MGE+质粒分析"
echo "====================================================================="

exit 0
