#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 16b_bac_metaspades.sh
# 功  能: metaSPAdes 宏基因组组装 + 与 MEGAHIT 组装的 QUAST 并排质量对比
#         工具版本：SPAdes 3.15.5（conda env: assembly）+ QUAST 5.0.2（同 env）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/assembly_metaspades/${SAMPLE}/
#           contigs.fasta                    — metaSPAdes 组装结果（验证用，不进主流程）
#           ${SAMPLE}.spades.log             — 组装日志（k 值迭代过程）
#           quast_report/report.tsv          — 与 MEGAHIT 组装的并排质量对比（无 MEGAHIT 结果时仅评估本组装）
#           ${SAMPLE}.metaspades_done.txt    — sentinel（含 contig 数/碱基数/quast 状态）
#
# ── 定位说明 ──────────────────────────────────────────────────────────────────
#
#   2024-26 组装器基准的共识做法：MEGAHIT 与 metaSPAdes 双跑并用 QUAST 对比择优。
#   metaSPAdes 通常 N50 更高，但内存/耗时数倍于 MEGAHIT。本脚本作为**组装验证层**，
#   与 16_bac_megahit.sh（主流程组装器）并列互补而非替代；默认不入 Snakemake
#   rule all（内存高、性质为验证），按需显式请求 sentinel 目标触发（同 15e MetaX）。
#
# ── 参数说明 ─────────────────────────────────────────────────────────────────
#
#   --mem-gb N（默认 250）
#     metaSPAdes 需显式内存上限（--memory），实际传 0.9N（默认 225 GB）。
#     PE150 肠道单样本典型 100-250 GB，不足时 SPAdes 会主动退出。
#
# ── 注意事项 ──────────────────────────────────────────────────────────────────
#
#   1. SPAdes 拒绝写入非空已存在目录：脚本用 _spades_tmp 临时子目录，运行前清空，
#      完成后仅保留 contigs.fasta/日志/QUAST 报告（中间文件 >10x 磁盘）
#   2. metaQUAST 的参考基因组搜索需联网下载 SILVA/NCBI；脚本用 --max-ref-number 0
#      跳过参考搜索，离线完成两套组装的 metaQUAST 并排评估（N50/总长/contig 数等）
#   3. reads 过少时 contigs 可能为空 → 写 sentinel 优雅退出（验证层不阻塞队列）
#
# 参  考: Nurk et al. Genome Res 2017 (metaSPAdes)
#         Mikheenko et al. Bioinformatics 2016 (metaQUAST)
#         https://github.com/ablab/spades
# 用  法: bash 16b_bac_metaspades.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--mem-gb N] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 16b_bac_metaspades.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16-32）
  -w  工作目录（Project 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force   强制重新运行（忽略已存在的 sentinel）
  --mem-gb  内存上限 GB（默认 250；metaSPAdes --memory 取其 0.9 倍）
  -h        显示帮助

示例:
  bash 16b_bac_metaspades.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \\
       -r ~/Course/CSCCD-MetagenomeFlow

  # 显式触发 Snakemake 规则（默认不在 rule all 中）:
  snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml \\
            -R metaspades
EOF
}

MEM_GB="250"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="mem-gb:MEM_GB"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

case "${MEM_GB}" in
    ''|*[!0-9]*) echo "[ERROR] --mem-gb 必须为正整数，收到: ${MEM_GB}"; exit 1 ;;
esac
SPADES_MEM=$(( MEM_GB * 9 / 10 ))

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/assembly_metaspades/${SAMPLE}"
CONTIGS="${RESULT_DIR}/contigs.fasta"
SPADES_TMP="${RESULT_DIR}/_spades_tmp"
QUAST_DIR="${RESULT_DIR}/quast_report"
SENTINEL="${RESULT_DIR}/${SAMPLE}.metaspades_done.txt"

# 主流程 MEGAHIT 组装结果（存在则 QUAST 并排对比，否则仅评估 metaSPAdes）
MEGAHIT_CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"

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

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then
    echo "[INFO] metaSPAdes 结果已存在，跳过: ${SAMPLE}（--force 可强制重跑）"
    echo "       ${SENTINEL}"
    exit 0
fi

mkdir -p "${RESULT_DIR}"
rm -rf "${SPADES_TMP}" "${QUAST_DIR}"

# --- kneaddata trailing-garbage workaround ---
# 同 16_bac_megahit.sh：kneaddata 输出的 gzip 末尾残留字节会使 C++ gzip reader
# （MEGAHIT/SPAdes 同类）报错；检测到则原地重压缩，幂等（干净文件直接跳过）
_recompress_if_dirty() {
    local f="$1"
    if gzip -t "$f" 2>/dev/null; then
        return 0  # already clean
    fi
    echo "[metaspades] [WARN] trailing garbage detected in $(basename "$f"), recompressing..."
    local tmp="${f}.recompress.tmp.gz"
    zcat "$f" 2>/dev/null | gzip -c > "$tmp" && mv "$tmp" "$f"
    echo "[metaspades] [INFO] recompressed: $(basename "$f")"
}
_recompress_if_dirty "${INPUT_R1}"
_recompress_if_dirty "${INPUT_R2}"

echo "[metaspades] 开始宏基因组组装: ${SAMPLE}"
echo "[metaspades] 线程: ${CPUS}，内存上限: ${SPADES_MEM} GB（--mem-gb ${MEM_GB} 的 0.9 倍）"

# --- 运行 metaSPAdes ---
# --meta 即 metaSPAdes 模式（多 k 值自动迭代）；输出到临时目录，完成后仅保留
# contigs.fasta 与日志，删除中间文件（节省 >90% 磁盘）

EXIT_CODE=0
# --phred-offset 33：kneaddata 输出在常数/退化质量范围下（模拟数据、CI fixture）
# 令 SPAdes 的 PHRED 自动检测失败（exit 255 "Failed to determine offset"），显式指定
mgx_try mgx_conda assembly \
    metaspades.py \
        -1 "${INPUT_R1}" \
        -2 "${INPUT_R2}" \
        -o "${SPADES_TMP}" \
        -t "${CPUS}" \
        -m "${SPADES_MEM}" \
        --phred-offset 33 \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] metaSPAdes 运行失败（exit code: ${EXIT_CODE}）"
    rm -rf "${SPADES_TMP}"
    exit ${EXIT_CODE}
fi

if [ ! -f "${SPADES_TMP}/contigs.fasta" ] || [ ! -s "${SPADES_TMP}/contigs.fasta" ]; then
    echo "[metaspades] [WARN] contigs.fasta 未生成或为空（可能原因：reads 太少 / 深度不足），写 sentinel 优雅退出"
    rm -rf "${SPADES_TMP}"
    echo "empty_assembly" > "${SENTINEL}"
    exit 0
fi

mv "${SPADES_TMP}/contigs.fasta" "${CONTIGS}"
cp "${SPADES_TMP}/spades.log" "${RESULT_DIR}/${SAMPLE}.spades.log" 2>/dev/null || true
rm -rf "${SPADES_TMP}"

# --- metaQUAST 并排对比（vs MEGAHIT）---
# metaQUAST 参考基因组搜索需联网下载 SILVA/NCBI；--max-ref-number 0 跳过该步
# （SILVA 完全不查，Mikheenko 2016 metaQUAST 文档），离线产出双组装并排报告

QUAST_RC=0
if [ -s "${MEGAHIT_CONTIGS}" ]; then
    echo "[metaspades] metaQUAST 对比: metaSPAdes vs MEGAHIT（${MEGAHIT_CONTIGS}）"
    mgx_try mgx_conda assembly \
        metaquast.py --max-ref-number 0 -t "${CPUS}" \
            -o "${QUAST_DIR}" \
            -l "metaSPAdes,MEGAHIT" \
            "${CONTIGS}" "${MEGAHIT_CONTIGS}" \
            || QUAST_RC=$?
else
    echo "[metaspades] 未发现 MEGAHIT 组装（${MEGAHIT_CONTIGS}），metaQUAST 仅评估 metaSPAdes"
    mgx_try mgx_conda assembly \
        metaquast.py --max-ref-number 0 -t "${CPUS}" \
            -o "${QUAST_DIR}" \
            -l "metaSPAdes" \
            "${CONTIGS}" \
            || QUAST_RC=$?
fi
if [ "${QUAST_RC}" -ne 0 ]; then
    echo "[metaspades] [WARN] metaQUAST 运行失败（exit: ${QUAST_RC}），跳过对比报告（不影响组装结果）"
fi

# --- 统计摘要 + sentinel ---

N_CONTIGS=$(grep -c "^>" "${CONTIGS}" 2>/dev/null || echo "N/A")
TOTAL_BP=$(grep -v "^>" "${CONTIGS}" | tr -d '\n' | wc -c 2>/dev/null || echo "N/A")
N1K=$(awk '/^>/{if(len>=1000) cnt++; len=0} !/^>/{len+=length($0)} END{if(len>=1000) cnt++; print cnt+0}' \
    "${CONTIGS}" 2>/dev/null || echo "N/A")

QUAST_STATUS="failed"
if [ -s "${QUAST_DIR}/report.tsv" ]; then QUAST_STATUS="ok"; fi
echo "contigs=${N_CONTIGS} total_bp=${TOTAL_BP} ge1k=${N1K} quast=${QUAST_STATUS}" > "${SENTINEL}"

echo ""
echo "[metaspades] ${SAMPLE} 组装完成"
echo "[metaspades] 结果: ${CONTIGS}"
echo "    Contig 总数:  ${N_CONTIGS}"
echo "    总碱基数:     ${TOTAL_BP} bp"
echo "    ≥1000 bp 数:  ${N1K}"
echo "    QUAST 报告:   ${QUAST_DIR}/report.tsv（${QUAST_STATUS}）"
echo ""
echo "[提示] 本步骤为组装验证层，结果不进入下游；对比结论看 quast_report/report.tsv 中"
echo "       metaSPAdes 与 MEGAHIT 两列的 N50 / Total length / # contigs"
mgx_end "metaspades"
