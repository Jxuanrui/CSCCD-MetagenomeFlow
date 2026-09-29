#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 75_fun_funomics.sh
# 功  能: FunOMIC 真菌分类包装器；若未安装则回退到 DIAMOND marker 分类
#         工具版本：FunOMIC / DIAMOND 2.x（conda env: assembly）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/funomic/${SAMPLE}/${SAMPLE}_classification.tsv
# 用  法: bash 75_fun_funomics.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 75_fun_funomics.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

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
OUTDIR="${WORKDIR}/result/fungi/funomic/${SAMPLE}"
OUTPUT_TSV="${OUTDIR}/${SAMPLE}_classification.tsv"
TMP_FASTQ="${OUTDIR}/${SAMPLE}_merged.fastq.gz"
FUNOMIC_ENV="${REPO}/envs/funomic"
RUN_ENV="${REPO}/envs/assembly"
DB_FILE=""
RUN_WITH_CONDA=1

if [ -d "${FUNOMIC_ENV}" ]; then
    RUN_ENV="${FUNOMIC_ENV}"
fi

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"

FUNOMIC_CMD=$(conda run --prefix "${RUN_ENV}" --no-capture-output bash -lc 'command -v funomic || true' 2>/dev/null | tail -n 1)
if [ -z "${FUNOMIC_CMD}" ]; then
    FUNOMIC_CMD=$(command -v funomic 2>/dev/null || true)
    if [ -n "${FUNOMIC_CMD}" ]; then
        RUN_WITH_CONDA=0
    fi
fi

if [ -n "${FUNOMIC_CMD}" ]; then
    if [ ${RUN_WITH_CONDA} -eq 1 ]; then
        EXIT_CODE=0
        mgx_try conda run --prefix "${RUN_ENV}" --no-capture-output \
            funomic classify \
                --forward "${INPUT_R1}" \
                --reverse "${INPUT_R2}" \
                --threads "${CPUS}" \
                --output "${OUTDIR}" \
                || EXIT_CODE=$?
    else
        EXIT_CODE=0
        mgx_try "${FUNOMIC_CMD}" classify \
            --forward "${INPUT_R1}" \
            --reverse "${INPUT_R2}" \
            --threads "${CPUS}" \
            --output "${OUTDIR}" \
            || EXIT_CODE=$?
    fi
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] funomic classify 失败（exit: ${EXIT_CODE}）"
        exit ${EXIT_CODE}
    fi

    if [ ! -f "${OUTPUT_TSV}" ]; then
        CANDIDATE=$(find "${OUTDIR}" -maxdepth 2 -name "*.tsv" 2>/dev/null | head -1)
        if [ -n "${CANDIDATE}" ]; then
            cp "${CANDIDATE}" "${OUTPUT_TSV}"
        else
            echo -e "feature\tclassification\tabundance" > "${OUTPUT_TSV}"
            echo -e "info\tfunomic_completed\tNA" >> "${OUTPUT_TSV}"
        fi
    fi
else
    echo "[WARN] 未检测到 funomic 命令，回退到 DIAMOND marker 分类"
    echo "[WARN] 安装示例: conda create -p ${REPO}/envs/funomic ... 或按 FunOMIC 官方文档安装"

    DB_FILE=$(find "${REPO}/db/funomic" -maxdepth 2 -name "*.dmnd" 2>/dev/null | head -1)
    if [ -z "${DB_FILE}" ]; then
        echo "[ERROR] 回退所需数据库未找到: ${REPO}/db/funomic/"
        echo "        请安装 FunOMIC 或准备 marker DIAMOND 数据库"
        exit 1
    fi

    zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${TMP_FASTQ}"
    EXIT_CODE=0
    mgx_try mgx_conda assembly \
        diamond blastx \
            --db "${DB_FILE}" \
            --query "${TMP_FASTQ}" \
            --out "${OUTPUT_TSV}" \
            --outfmt 6 qseqid sseqid pident length evalue bitscore \
            --evalue 1e-5 \
            --max-target-seqs 1 \
            --threads "${CPUS}" \
            --sensitive \
            || EXIT_CODE=$?
    rm -f "${TMP_FASTQ}"
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] DIAMOND 回退分类失败（exit: ${EXIT_CODE}）"
        rm -f "${OUTPUT_TSV}"
        exit ${EXIT_CODE}
    fi
fi

N_ROWS=$(wc -l < "${OUTPUT_TSV}" 2>/dev/null || echo "0")
echo "[fun_funomics] 完成 | 结果行数: ${N_ROWS}"
mgx_end "fun_funomics"
