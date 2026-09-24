#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 78_fun_megahit.sh
# 功  能: MEGAHIT 真菌组装（meta-sensitive，更适合低丰度真菌）
#         工具版本：MEGAHIT 1.2.9（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa
# 用  法: bash 78_fun_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 78_fun_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

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
OUTDIR="${WORKDIR}/result/fungi/assembly/${SAMPLE}"
CONTIGS="${OUTDIR}/${SAMPLE}.contigs.fa"
MEGAHIT_TMP="${OUTDIR}/_megahit_tmp"

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${CONTIGS}" ] && [ -s "${CONTIGS}" ]; then
    echo "[INFO] 结果已存在，跳过: ${CONTIGS}"
    exit 0
fi

mkdir -p "${OUTDIR}"
rm -rf "${MEGAHIT_TMP}"

echo "[fun_megahit] 提示: 可先用 71/72 的真菌结果提取 reads，再组装以提高真菌 contig 纯度"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    megahit \
        -1 "${INPUT_R1}" \
        -2 "${INPUT_R2}" \
        -o "${MEGAHIT_TMP}" \
        -t "${CPUS}" \
        -m 0.9 \
        --presets meta-sensitive \
        --min-contig-len 1000 \
        || EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] MEGAHIT 运行失败（exit: ${EXIT_CODE}）"
    rm -rf "${MEGAHIT_TMP}"
    exit ${EXIT_CODE}
fi
if [ ! -f "${MEGAHIT_TMP}/final.contigs.fa" ] || [ ! -s "${MEGAHIT_TMP}/final.contigs.fa" ]; then
    echo "[ERROR] final.contigs.fa 未生成或为空"
    rm -rf "${MEGAHIT_TMP}"
    exit 1
fi

mv "${MEGAHIT_TMP}/final.contigs.fa" "${CONTIGS}"
cp "${MEGAHIT_TMP}/log" "${OUTDIR}/${SAMPLE}.megahit.log" 2>/dev/null || true
rm -rf "${MEGAHIT_TMP}"

N_CONTIGS=$(grep -c "^>" "${CONTIGS}" 2>/dev/null || echo "0")
echo "[fun_megahit] 完成 | Contig 数: ${N_CONTIGS}"
mgx_end "fun_megahit"

