#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 77_fun_microfisher.sh
# 功  能: 基于 Kraken2 报告生成真菌专属分类概览（MicroFisher 风格近似实现）
#         工具版本：Kraken2 报告过滤 / 可选 Kraken2 回退（conda env: assembly）
# 依  赖: 优先复用 71_fun_kraken2_fungi.sh 输出；否则使用 clean reads 快速补跑 Kraken2
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/microfisher/${SAMPLE}/${SAMPLE}_fungal_profile.tsv
# 用  法: bash 77_fun_microfisher.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 77_fun_microfisher.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/fungi/microfisher/${SAMPLE}"
OUTPUT_TSV="${OUTDIR}/${SAMPLE}_fungal_profile.tsv"
KRAKEN_REPORT="${WORKDIR}/result/fungi/kraken2/${SAMPLE}/${SAMPLE}.report"
TMP_REPORT="${OUTDIR}/${SAMPLE}.kraken.report"
DB_KRAKEN="${REPO}/db/kraken2/pluspf"

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"

REPORT_TO_USE="${KRAKEN_REPORT}"
if [ ! -f "${KRAKEN_REPORT}" ]; then
    if [ ! -d "${DB_KRAKEN}" ] || [ -z "$(ls -A "${DB_KRAKEN}" 2>/dev/null)" ]; then
        echo "[ERROR] 未找到现成 Kraken2 report，且 Kraken2 数据库不可用: ${DB_KRAKEN}"
        exit 1
    fi
    echo "[WARN] 未找到 71_fun_kraken2_fungi.sh 输出，补跑快速 Kraken2 生成报告"
    EXIT_CODE=0
    mgx_try mgx_conda kraken2 \
        kraken2 \
            --db "${DB_KRAKEN}" \
            --threads "${CPUS}" \
            --paired "${INPUT_R1}" "${INPUT_R2}" \
            --use-names \
            --report-zero-counts \
            --report "${TMP_REPORT}" \
            --output /dev/null \
            || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] Kraken2 回退运行失败（exit: ${EXIT_CODE}）"
        rm -f "${TMP_REPORT}"
        exit ${EXIT_CODE}
    fi
    REPORT_TO_USE="${TMP_REPORT}"
fi

EXIT_CODE=0
mgx_try awk '
BEGIN {
    FS = OFS = "\t"
    print "taxon", "taxid", "reads", "abundance_level"
}
{
    raw = $6
    clean = raw
    gsub(/^[[:space:]]+/, "", clean)
    depth = int((length(raw) - length(clean)) / 2)
    lineage[depth] = clean
    for (i = depth + 1; i < 64; i++) delete lineage[i]

    kingdom = ""
    phylum = ""
    for (i = 0; i <= depth; i++) {
        if (lineage[i] == "Fungi") kingdom = "Fungi"
        if (lineage[i] ~ /^(Ascomycota|Basidiomycota|Mucoromycota|Chytridiomycota|Microsporidia)$/) phylum = lineage[i]
    }

    if ((kingdom == "Fungi" || phylum != "") && ($4 == "S" || $4 == "G" || $4 == "P")) {
        level = ($4 == "S" ? "species" : ($4 == "G" ? "genus" : "phylum"))
        print clean, $5, $2, level
    }
}
' "${REPORT_TO_USE}" > "${OUTPUT_TSV}" || EXIT_CODE=$?
rm -f "${TMP_REPORT}"
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] Kraken2 报告过滤失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

N_ROWS=$(tail -n +2 "${OUTPUT_TSV}" 2>/dev/null | wc -l || echo "0")
echo "[fun_microfisher] 完成 | 真菌分类条目: ${N_ROWS}"
mgx_end "fun_microfisher"

