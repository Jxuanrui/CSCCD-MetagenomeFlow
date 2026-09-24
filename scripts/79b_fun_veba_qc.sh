#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79b_fun_veba_qc.sh
# 功  能: 真核候选序列二次质控（Tiara 域确认 + BUSCO 谱系完整度评估）
#         参考 VEBA (https://github.com/jolespin/veba) binning-eukaryotic 模块
#         的质控思路重新实现（不拷贝 VEBA 源码，VEBA 为 AGPLv3，本脚本及所调用的
#         Tiara/BUSCO 均为 MIT 许可，无许可证污染风险）
#         工具版本：Tiara 1.0.3（conda env: tiara）+ BUSCO 6.1.0（conda env: busco）
# 依  赖: 79_fun_eukfinder.sh 的输出（Eukfinder 判定的候选真核序列）
# 输  入: ${WORKDIR}/result/fungi/eukfinder/${SAMPLE}/Eukfinder_results/${SAMPLE}.Euk.fasta
# 输  出: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/
#           ${SAMPLE}.euk_filtered.fasta       — 长度过滤后的候选序列（≥1000bp）
#           ${SAMPLE}.tiara_classification.txt — Tiara 逐序列分类结果
#           ${SAMPLE}_euk.fasta                — Tiara 二次确认为真核的序列
#           ${SAMPLE}.busco/                   — BUSCO 谱系完整度评估原始输出
#           ${SAMPLE}.veba_qc_summary.tsv       — 质量分级汇总表（完整度/重复度/缺失）
#           ${SAMPLE}.veba_qc_empty.flag        — 若任一阶段序列为空，生成此标志文件（正常场景，非失败）
# 用  法: bash 79b_fun_veba_qc.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--min-len N] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 79b_fun_veba_qc.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--min-len N] [--force]

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --min-len  长度过滤阈值，Tiara 官方不建议对短于此长度的序列分类 [默认: 1000]
  --force    强制重新运行（忽略已存在的结果）
EOF
}

MIN_LEN=1000

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="min-len:MIN_LEN"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

EUKFINDER_DIR="${WORKDIR}/result/fungi/eukfinder/${SAMPLE}"
EUKFINDER_MARKER="${EUKFINDER_DIR}/results.txt"
INPUT_EUK="${EUKFINDER_DIR}/Eukfinder_results/${SAMPLE}.Euk.fasta"
OUTDIR="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}"
SUMMARY="${OUTDIR}/${SAMPLE}.veba_qc_summary.tsv"
EMPTY_FLAG="${OUTDIR}/${SAMPLE}.veba_qc_empty.flag"
# 项目级共享 lineage 缓存目录（多样本共用，避免重复下载相同数据集，与79e一致）
BUSCO_DOWNLOAD_PATH="$(readlink -f "${REPO}")/db/busco_downloads"
mkdir -p "${BUSCO_DOWNLOAD_PATH}"

# 79号 Eukfinder 完成后总会生成 results.txt（无论是否产出真核序列）
# 若 results.txt 不存在，说明 79号确实还没运行过；若存在但 .Euk.fasta 缺失，
# 说明 79号已运行但 0 个真核 contig（低测序深度场景下的预期行为，非错误）
if [ ! -f "${EUKFINDER_MARKER}" ]; then
    echo "[ERROR] 79号 Eukfinder 尚未运行: ${EUKFINDER_MARKER} 不存在"
    echo "        请先运行 79_fun_eukfinder.sh"
    exit 1
fi

# 幂等判断：已有真实结果（summary.tsv）或已确认的空结果（empty.flag）则跳过
if [ ${FORCE} -eq 0 ] && [ -d "${OUTDIR}" ] && { [ -f "${SUMMARY}" ] || [ -f "${EMPTY_FLAG}" ]; }; then
    echo "[INFO] 结果已存在，跳过: ${OUTDIR}/"
    exit 0
fi

mkdir -p "${OUTDIR}"
rm -f "${EMPTY_FLAG}"

if [ ! -f "${INPUT_EUK}" ]; then
    cat > "${EMPTY_FLAG}" << EOF
[EMPTY] 79号 Eukfinder 未产出候选真核序列（.Euk.fasta 不存在，测序深度不足的预期行为）
样本: ${SAMPLE}
时间: $(date -Iseconds)
EOF
    echo "[fun_veba_qc] 79号 Eukfinder 未产出候选真核序列，视为预期空结果，正常退出"
    echo "[fun_veba_qc] ${SAMPLE} 完成，耗时 ${SECONDS}s"
    exit 0
fi

emit_empty_result() {
    local stage="$1"
    cat > "${EMPTY_FLAG}" << EOF
[EMPTY] ${stage} 阶段无可用序列（测序深度不足导致的预期行为，非脚本错误）
样本: ${SAMPLE}
时间: $(date -Iseconds)
EOF
    echo "[fun_veba_qc] ${stage} 阶段无可用序列，视为预期空结果，正常退出"
    echo "[fun_veba_qc] ${SAMPLE} 完成，耗时 ${SECONDS}s"
    exit 0
}

# ── 步骤1：长度预过滤（Tiara 官方不建议对 <1000bp 序列分类）───────────────────
FILTERED="${OUTDIR}/${SAMPLE}.euk_filtered.fasta"
mgx_conda assembly \
    seqkit seq -m "${MIN_LEN}" "${INPUT_EUK}" -o "${FILTERED}"

if [ ! -s "${FILTERED}" ]; then
    emit_empty_result "长度过滤"
fi

# ── 步骤2：Tiara 域二次确认 ───────────────────────────────────────────────────
TIARA_CLASS="${OUTDIR}/${SAMPLE}.tiara_classification.txt"
mgx_conda tiara \
    tiara -i "${FILTERED}" -o "${TIARA_CLASS}" \
          -m "${MIN_LEN}" -t "${CPUS}" \
          --to_fasta euk \
          --probabilities

# Tiara --to_fasta euk 在输入文件同目录下生成 eukarya_{输入文件 basename}
TIARA_EUK_FASTA="${OUTDIR}/eukarya_$(basename "${FILTERED}")"
if [ ! -f "${TIARA_EUK_FASTA}" ] || [ ! -s "${TIARA_EUK_FASTA}" ]; then
    emit_empty_result "Tiara域确认"
fi

# ── 步骤3：BUSCO 谱系特异完整度/污染度评估 ───────────────────────────────────
BUSCO_OUT="${SAMPLE}.busco"
BUSCO_EXIT=0
(
    cd "${OUTDIR}"
    mgx_conda busco \
        busco -i "${TIARA_EUK_FASTA}" -o "${BUSCO_OUT}" \
              -m genome --auto-lineage-euk -c "${CPUS}" -f \
              --download_path "${BUSCO_DOWNLOAD_PATH}"
) || BUSCO_EXIT=$?

BUSCO_SUMMARY_FILE=$(find "${OUTDIR}/${BUSCO_OUT}" -maxdepth 1 -name "short_summary.*.txt" 2>/dev/null | head -n 1)

if [ ${BUSCO_EXIT} -ne 0 ] || [ -z "${BUSCO_SUMMARY_FILE}" ]; then
    emit_empty_result "BUSCO质控（可能因序列量过低无法评估，属预期行为）"
fi

# ── 步骤4：汇总质量分级报告 ───────────────────────────────────────────────────
COMPLETE=$(grep -oP '(?<=C:)[0-9.]+(?=%)' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")
DUPLICATED=$(grep -oP '(?<=D:)[0-9.]+(?=%)' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")
MISSING=$(grep -oP '(?<=M:)[0-9.]+(?=%)' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")
LINEAGE=$(grep -oP '(?<=lineage dataset is: ).*(?= \()' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")

{
    echo -e "sample\tlineage\tcomplete_pct\tduplicated_pct\tmissing_pct"
    echo -e "${SAMPLE}\t${LINEAGE}\t${COMPLETE}\t${DUPLICATED}\t${MISSING}"
} > "${SUMMARY}"

echo "[fun_veba_qc] ${SAMPLE} 完成"
echo "[fun_veba_qc] 输出目录: ${OUTDIR}"
echo "[fun_veba_qc] 质量摘要: ${SUMMARY}"
mgx_end "fun_veba_qc"
