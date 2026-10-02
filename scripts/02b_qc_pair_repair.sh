#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 02b_qc_pair_repair.sh
# 功  能: 修复 kneaddata 输出中 R1/R2 配对顺序错位问题（严格重新配对）
#         工具版本：seqkit pair（conda env: assembly，已含 seqkit）
# 依  赖: 02_qc_kneaddata.sh 的输出
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz (+_2)
# 输  出: 原地覆盖同名文件（保持下游全部引用路径不变）
#
# ── 背景 ──────────────────────────────────────────────────────────────────────
#   2026-08-04 排查 36b_bac_bin_reassembly.sh 时发现：kneaddata 产出的 R1/R2
#   reads 集合完全一致（数量相同），但顺序在中途发生错位（同一 read 在两个文件
#   里位置不同），导致 bwa mem 遇到 "paired reads have different names" 直接
#   abort。samtools/bowtie2 等工具容忍度更高未必报错，但结果可能已隐性受影响。
#   本步骤用 seqkit pair 按 read ID 严格重新配对，原地覆盖 kneaddata 的输出，
#   保证下游全部 41 处引用（bacteria_assembly/binning/taxonomy、virome、
#   mycobiome 等 rule）无需改动即可拿到严格配对的 reads。
#
# 参  考: seqkit pair 官方文档
# 用  法: bash 02b_qc_pair_repair.sh -s SAMPLE -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 02b_qc_pair_repair.sh -s SAMPLE -w WORKDIR -r REPO [选项]
必需参数:
  -s  样本 ID
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE WORKDIR REPO

mgx_begin
OUTDIR="${WORKDIR}/result/kneaddata/${SAMPLE}"
RAW_R1="${OUTDIR}/${SAMPLE}_1.kneaddata_raw.fastq.gz"
RAW_R2="${OUTDIR}/${SAMPLE}_2.kneaddata_raw.fastq.gz"
FINAL_R1="${OUTDIR}/${SAMPLE}_1.kneaddata.fastq.gz"
FINAL_R2="${OUTDIR}/${SAMPLE}_2.kneaddata.fastq.gz"
SENTINEL="${OUTDIR}/${SAMPLE}.pair_repair_done.txt"
PAIR_TMPDIR="${WORKDIR}/temp/pair_repair/${SAMPLE}"

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[pair_repair] 结果已存在，跳过: ${SENTINEL}"
    exit 0
fi

if [ ! -f "${RAW_R1}" ] || [ ! -f "${RAW_R2}" ]; then
    echo "[ERROR] kneaddata 中间产物不存在: ${RAW_R1} / ${RAW_R2}"
    exit 1
fi

rm -rf "${PAIR_TMPDIR}"
mkdir -p "${PAIR_TMPDIR}"

echo "[pair_repair] 样本 ${SAMPLE} | 严格重新配对 R1/R2 ..."
mgx_conda assembly \
    seqkit pair \
        --id-regexp '^(\S+)\/[12]' \
        -1 "${RAW_R1}" \
        -2 "${RAW_R2}" \
        -O "${PAIR_TMPDIR}" \
        --force

PAIRED_R1="${PAIR_TMPDIR}/$(basename "${RAW_R1}")"
PAIRED_R2="${PAIR_TMPDIR}/$(basename "${RAW_R2}")"
if [ ! -s "${PAIRED_R1}" ] || [ ! -s "${PAIRED_R2}" ]; then
    echo "[ERROR] seqkit pair 未产出有效配对文件"
    exit 1
fi

N_BEFORE=$(zcat "${RAW_R1}" | wc -l)
N_AFTER=$(zcat "${PAIRED_R1}" | wc -l)

mv "${PAIRED_R1}" "${FINAL_R1}"
mv "${PAIRED_R2}" "${FINAL_R2}"
rm -rf "${PAIR_TMPDIR}"

echo "READS_BEFORE=$((N_BEFORE / 4))" > "${SENTINEL}"
echo "READS_AFTER=$((N_AFTER / 4))" >> "${SENTINEL}"

echo "[pair_repair] 配对前: $((N_BEFORE / 4)) reads | 配对后: $((N_AFTER / 4)) reads"
mgx_end "pair_repair"
