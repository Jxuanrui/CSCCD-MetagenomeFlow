#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 72_fun_metaphlan4_euk.sh
# 功  能: MetaPhlAn4 真核（真菌）物种组成分析，保留真核生物分类
#         工具版本：MetaPhlAn4 4.2.4+（conda env: humann4）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt
#         ${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}/${SAMPLE}.sam.bz2
# 用  法: bash 72_fun_metaphlan4_euk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
#
# 说  明: MetaPhlAn4 默认过滤真核生物分类。本脚本通过保留所有 bowtie2
#         比对结果，确保真核生物（真菌）marker 可被正确识别。
#         参考: https://github.com/biobakery/MetaPhlAn4
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 72_fun_metaphlan4_euk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 根目录
  --force  强制重跑
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
MAPOUT_BZ2="${WORKDIR}/temp/metaphlan4/${SAMPLE}/${SAMPLE}.mapout.bz2"

TEMP_DIR="${WORKDIR}/temp/fungi/metaphlan4/${SAMPLE}"
RESULT_DIR="${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}"
DB_DIR="${REPO}/db/metaphlan4"
DB_INDEX="mpa_vOct22_CHOCOPhlAnSGB_202212"

if [ ! -d "${DB_DIR}" ]; then echo "[ERROR] 数据库目录不存在: ${DB_DIR}"; exit 1; fi
if ! ls "${DB_DIR}/${DB_INDEX}"*.bt2l &>/dev/null; then
    echo "[ERROR] 数据库索引未找到: ${DB_DIR}/${DB_INDEX}*.bt2l"; exit 1
fi

# Skip only if output exists AND contains genuine Eukaryota entries
if [ ${FORCE} -eq 0 ] && [ -f "${RESULT_DIR}/${SAMPLE}_profile.txt" ] && \
   grep -q "k__Eukaryota" "${RESULT_DIR}/${SAMPLE}_profile.txt" 2>/dev/null; then
    echo "[INFO] 真核生物 profile 已存在（含 k__Eukaryota），跳过: ${SAMPLE}"
    exit 0
fi

if [ ! -f "${MAPOUT_BZ2}" ]; then
    if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] R1 不存在: ${INPUT_R1}"; exit 1; fi
    if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] R2 不存在: ${INPUT_R2}"; exit 1; fi
fi

mkdir -p "${TEMP_DIR}" "${RESULT_DIR}"

if [ -f "${MAPOUT_BZ2}" ]; then
    echo "[fun_metaphlan4] 复用步骤11比对结果（跳过 bowtie2 重新比对）: ${SAMPLE}"
    MAPOUT_TMP="${TEMP_DIR}/${SAMPLE}.mapout"
    bunzip2 -c "${MAPOUT_BZ2}" > "${MAPOUT_TMP}"

    EXIT_CODE=0
    mgx_try mgx_conda humann4 \
        metaphlan \
            "${MAPOUT_TMP}" \
            --input_type mapout \
            --db_dir "${DB_DIR}" \
            -x "${DB_INDEX}" \
            --nproc "${CPUS}" \
            --ignore_bacteria \
            --ignore_archaea \
            -o "${RESULT_DIR}/${SAMPLE}_profile.txt" \
            --offline \
            || EXIT_CODE=$?
    rm -f "${MAPOUT_TMP}"
else
    echo "[fun_metaphlan4] mapout 不存在，从 reads 重新比对: ${SAMPLE}"
    INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
    INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
    MERGED_FQ="${TEMP_DIR}/${SAMPLE}_merged.fastq.gz"
    zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${MERGED_FQ}"

    EXIT_CODE=0
    mgx_try mgx_conda humann4 \
        metaphlan \
            "${MERGED_FQ}" \
            --input_type fastq \
            --db_dir "${DB_DIR}" \
            -x "${DB_INDEX}" \
            --nproc "${CPUS}" \
            --ignore_bacteria \
            --ignore_archaea \
            -o "${RESULT_DIR}/${SAMPLE}_profile.txt" \
            --offline \
            || EXIT_CODE=$?
    rm -f "${MERGED_FQ}"
fi

if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] MetaPhlAn4 真核生物分析失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi
if [ ! -f "${RESULT_DIR}/${SAMPLE}_profile.txt" ]; then
    echo "[ERROR] Profile 未生成: ${RESULT_DIR}/${SAMPLE}_profile.txt"
    exit 1
fi

FUNGI_COUNT=$(grep -c "k__Eukaryota" "${RESULT_DIR}/${SAMPLE}_profile.txt" 2>/dev/null || echo "0")
echo "[fun_metaphlan4] ${SAMPLE} 完成 | 真核生物分类群数: ${FUNGI_COUNT}"
mgx_end "fun_metaphlan4"
