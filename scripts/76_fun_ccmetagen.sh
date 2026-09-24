#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 76_fun_ccmetagen.sh
# 功  能: KMA + CCMetagen 真菌分类；若 CCMetagen 不可用则保留 KMA 分类结果
#         工具版本：KMA / CCMetagen（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/ccmetagen/${SAMPLE}/
# 用  法: bash 76_fun_ccmetagen.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 76_fun_ccmetagen.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

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
OUTDIR="${WORKDIR}/result/fungi/ccmetagen/${SAMPLE}"
TEMPDIR="${OUTDIR}/temp"
SPECIES_TXT="${OUTDIR}/${SAMPLE}_species.txt"
KRONA_HTML="${OUTDIR}/${SAMPLE}_krona.html"
DB_PREFIX=$(find "${REPO}/db/kma/nt" -name "*.idx" 2>/dev/null | head -1 | sed 's/\.idx$//')
KMA_PREFIX="${TEMPDIR}/kma_out"

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi
if [ -z "${DB_PREFIX}" ]; then
    echo "[ERROR] 未找到 KMA 数据库索引: ${REPO}/db/kma/nt/*.idx"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SPECIES_TXT}" ] && [ -s "${SPECIES_TXT}" ]; then
    echo "[INFO] 结果已存在，跳过: ${SPECIES_TXT}"
    exit 0
fi

mkdir -p "${OUTDIR}" "${TEMPDIR}"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    kma \
        -ipe "${INPUT_R1}" "${INPUT_R2}" \
        -o "${KMA_PREFIX}" \
        -t_db "${DB_PREFIX}" \
        -t "${CPUS}" \
        -1t1 \
        -mem_mode \
        -and \
        -apm f \
        -ef \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] KMA 比对失败（exit: ${EXIT_CODE}）"
    rm -rf "${TEMPDIR}"
    exit ${EXIT_CODE}
fi

CCMETAGEN_CMD=$(mgx_conda assembly bash -lc 'command -v CCMetagen.py || command -v CCMetagen || true' 2>/dev/null | tail -n 1)

if [ -n "${CCMETAGEN_CMD}" ]; then
    EXIT_CODE=0
    mgx_try mgx_conda assembly \
        bash -lc '
            set -e
            CMD=$(command -v CCMetagen.py || command -v CCMetagen)
            "${CMD}" -i "$1" -o "$2"
        ' _ "${KMA_PREFIX}.res" "${OUTDIR}" \
        || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[WARN] CCMetagen 失败，回退到 KMA 结果整理"
    fi
else
    echo "[WARN] 未检测到 CCMetagen.py，回退到 KMA 分类结果"
fi

if [ ! -f "${SPECIES_TXT}" ]; then
    awk 'BEGIN{FS=OFS="\t"; print "template","score","depth","species"} NR>1{print $1,$2,$9,$1}' \
        "${KMA_PREFIX}.res" > "${SPECIES_TXT}"
fi

if [ ! -f "${KRONA_HTML}" ]; then
    cat > "${KRONA_HTML}" << EOF
<html><body><h1>CCMetagen/KMA summary for ${SAMPLE}</h1><p>Krona output was not generated automatically. Review ${SPECIES_TXT} and KMA result files in ${OUTDIR}.</p></body></html>
EOF
fi

rm -rf "${TEMPDIR}"
N_ROWS=$(tail -n +2 "${SPECIES_TXT}" 2>/dev/null | wc -l || echo "0")
echo "[fun_ccmetagen] 完成 | 物种条目: ${N_ROWS}"
mgx_end "fun_ccmetagen"
