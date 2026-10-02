#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 16_bac_megahit.sh
# 功  能: MEGAHIT 宏基因组从头组装（de novo assembly）
#         工具版本：MEGAHIT v1.2.9（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/assembly/megahit/${SAMPLE}/
#           ${SAMPLE}.contigs.fa    — 最终组装结果（下游 Prodigal/CD-HIT/Salmon 输入）
#           ${SAMPLE}.megahit.log   — 组装日志（k值选择、运行参数）
#
# ── 参数说明 ─────────────────────────────────────────────────────────────────
#
#   --presets meta-large（默认）
#     k 值列表：21,29,39,59,79,99,119,141
#     适合：肠道宏基因组、中高多样性样本（推荐）
#     备选 meta-sensitive：保留更多低丰度序列（较慢）
#
#   --min-contig-len 500（默认）
#     通用分析取 500；MAG 挖掘工作流（binning，脚本 32-36）推荐 1000-1500
#     参考：Meren Lab（≥1000）；Song et al. 2024 Genome Biology（≥1500 for MAG）
#
#   内存：-m 0.9（使用 90% 可用内存，MEGAHIT 自动计算上限）
#         PE150 单样本约需 30-80G RAM
#
# ── 注意事项 ──────────────────────────────────────────────────────────────────
#
#   1. MEGAHIT 不允许输出到已有目录，脚本用临时子目录后移动结果
#   2. intermediate_contigs/ 随临时目录一起删除（节省 >80% 磁盘空间）
#
# 参  考: Li et al. Bioinformatics 2015; Li et al. Genome Methods 2016
#         https://github.com/voutcn/megahit
# 用  法: bash 16_bac_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 16_bac_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（如 SRR28210342）
  -t  线程数（推荐 16-32）
  -w  工作目录（Project 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  --min-contig-len  最小 contig 长度（默认 500；MAG 分析建议 1000）
  --presets         MEGAHIT 预设（默认 meta-large；可选 meta-sensitive）

示例:
  bash 16_bac_megahit.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

  # MAG 挖掘工作流（更长 contig，更高 binning 质量）
  bash 16_bac_megahit.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow --min-contig-len 1000
EOF
}

MIN_CONTIG_LEN="500"
PRESETS="meta-large"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_LONG="min-contig-len:MIN_CONTIG_LEN presets:PRESETS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/assembly/megahit/${SAMPLE}"
CONTIGS="${RESULT_DIR}/${SAMPLE}.contigs.fa"
MEGAHIT_TMP="${RESULT_DIR}/_megahit_tmp"

# --- 输入检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
if [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${CONTIGS}" ] && [ -s "${CONTIGS}" ]; then
    echo "[INFO] MEGAHIT 组装结果已存在，跳过: ${SAMPLE}"
    echo "       ${CONTIGS}"
    exit 0
fi

mkdir -p "${RESULT_DIR}"
rm -rf "${MEGAHIT_TMP}"

# --- kneaddata trailing-garbage workaround ---
# kneaddata writes gzip files with trailing bytes that MEGAHIT's reader rejects.
# Detect and silently recompress if needed; idempotent (skipped when file is already clean).
_recompress_if_dirty() {
    local f="$1"
    if gzip -t "$f" 2>/dev/null; then
        return 0  # already clean
    fi
    echo "[megahit] [WARN] trailing garbage detected in $(basename "$f"), recompressing..."
    local tmp="${f}.recompress.tmp.gz"
    zcat "$f" 2>/dev/null | gzip -c > "$tmp" && mv "$tmp" "$f"
    echo "[megahit] [INFO] recompressed: $(basename "$f")"
}
_recompress_if_dirty "${INPUT_R1}"
_recompress_if_dirty "${INPUT_R2}"

echo "[megahit] 开始宏基因组组装: ${SAMPLE}"
echo "[megahit] 预设: ${PRESETS}，最小 contig: ${MIN_CONTIG_LEN} bp，线程: ${CPUS}"

# --- 运行 MEGAHIT ---
# -m 0.9:          使用 90% 可用内存（MEGAHIT 自动计算上限）
# --presets:       k 值列表 21,29,39,59,79,99,119,141（meta-large）
# --min-contig-len 过滤短 contig（通用 500；binning 推荐 1000-1500）
# 输出到临时目录，完成后移动 final.contigs.fa 并删除中间文件节省磁盘

EXIT_CODE=0
mgx_try mgx_conda assembly \
    megahit \
        -1 "${INPUT_R1}" \
        -2 "${INPUT_R2}" \
        -o "${MEGAHIT_TMP}" \
        -t "${CPUS}" \
        -m 0.9 \
        --presets "${PRESETS}" \
        --min-contig-len "${MIN_CONTIG_LEN}" || EXIT_CODE=$?

if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] MEGAHIT 运行失败（exit code: ${EXIT_CODE}）"
    rm -rf "${MEGAHIT_TMP}"
    exit ${EXIT_CODE}
fi

if [ ! -f "${MEGAHIT_TMP}/final.contigs.fa" ] || [ ! -s "${MEGAHIT_TMP}/final.contigs.fa" ]; then
    echo "[ERROR] final.contigs.fa 未生成或为空（可能原因：reads 太少 / 内存不足 / --min-contig-len 过高）"
    rm -rf "${MEGAHIT_TMP}"
    exit 1
fi

# 移动最终结果；删除临时目录（含 intermediate_contigs，节省 >80% 磁盘）
mv "${MEGAHIT_TMP}/final.contigs.fa" "${CONTIGS}"
cp "${MEGAHIT_TMP}/log" "${RESULT_DIR}/${SAMPLE}.megahit.log" 2>/dev/null || true
rm -rf "${MEGAHIT_TMP}"

# --- 统计摘要 ---

N_CONTIGS=$(grep -c "^>" "${CONTIGS}" 2>/dev/null || echo "N/A")
TOTAL_BP=$(grep -v "^>" "${CONTIGS}" | tr -d '\n' | wc -c 2>/dev/null || echo "N/A")
N1K=$(awk '/^>/{if(len>=1000) cnt++; len=0} !/^>/{len+=length($0)} END{if(len>=1000) cnt++; print cnt+0}' \
    "${CONTIGS}" 2>/dev/null || echo "N/A")

echo ""
echo "[megahit] ${SAMPLE} 组装完成，耗时 ${SECONDS}s"
echo "[megahit] 结果: ${CONTIGS}"
echo "    Contig 总数:  ${N_CONTIGS}"
echo "    总碱基数:     ${TOTAL_BP} bp"
echo "    ≥1000 bp 数:  ${N1K}"
echo ""
echo "[提示] 下一步: 运行 17_bac_prodigal.sh 进行基因预测"
