#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 80b_fun_metaeuk.sh
# 功  能: 真菌蛋白编码基因预测
#         支持 Prodigal（默认）或 MetaEuk 两种方法
# 依  赖: 78_fun_megahit.sh 的输出（${SAMPLE}.contigs.fa）
# 输  入: ${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/fungi/metaeuk/${SAMPLE}/
#           ${SAMPLE}_metaeuk.faa  — 下游注释兼容蛋白序列
#           ${SAMPLE}.gff          — Prodigal GFF 输出（使用 Prodigal 时）
#           ${SAMPLE}.fas          — MetaEuk 蛋白序列输出（使用 MetaEuk 时）
#           ${SAMPLE}.codon.fas    — MetaEuk CDS 输出（使用 MetaEuk 时）
# 用  法: bash 80b_fun_metaeuk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--method METHOD] [--db DB_PATH]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法:
  bash 80b_fun_metaeuk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--method METHOD] [--db DB_PATH]

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  --method  基因预测方法，可选值: prodigal | metaeuk（默认: prodigal）
  --db      MetaEuk 所需 MMseqs2 数据库前缀，仅在 --method metaeuk 时必需
            例如: db/metaeuk_db/fungi_refseq_mmseqs

示例:
  bash 80b_fun_metaeuk.sh -s SRR28210342 -t 8 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

  bash 80b_fun_metaeuk.sh -s SRR28210342 -t 8 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow \\
       --method metaeuk \\
       --db ~/Course/CSCCD-MetagenomeFlow/db/metaeuk_db/fungi_refseq_mmseqs
EOF
}

CPUS="1"; METHOD="prodigal"; DB=""

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="method:METHOD db:DB"
mgx_parse "$@"
mgx_require SAMPLE WORKDIR REPO

if [ "${METHOD}" != "prodigal" ] && [ "${METHOD}" != "metaeuk" ]; then
    echo "[ERROR] --method 仅支持: prodigal | metaeuk"; show_help; exit 1
fi

mgx_begin

INPUT_CONTIGS="${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/fungi/metaeuk/${SAMPLE}"
TMP_DIR="${OUTDIR}/tmp_${SAMPLE}"
OUT_PREFIX="${OUTDIR}/${SAMPLE}"
FAS="${OUTDIR}/${SAMPLE}.fas"
CODON_FAS="${OUTDIR}/${SAMPLE}.codon.fas"
FAA="${OUTDIR}/${SAMPLE}_metaeuk.faa"
GFF="${OUTDIR}/${SAMPLE}.gff"
METAEUK_ENV="${REPO}/envs/metaeuk"
METAEUK_DBTYPE="${DB}.dbtype"

if [ ! -f "${INPUT_CONTIGS}" ]; then echo "[WARN] 输入不存在，跳过 MetaEuk: ${INPUT_CONTIGS}"; exit 0; fi
if [ ! -s "${INPUT_CONTIGS}" ]; then echo "[WARN] 输入为空，跳过 MetaEuk: ${INPUT_CONTIGS}"; exit 0; fi

if [ ${FORCE} -eq 0 ] && [ -f "${FAA}" ] && [ -s "${FAA}" ]; then
    echo "[INFO] 结果已存在，跳过: ${SAMPLE}"; exit 0
fi

if [ "${METHOD}" = "metaeuk" ]; then
    if [ -z "${DB}" ]; then
        echo "[ERROR] --method metaeuk 时必须提供 --db"; exit 1
    fi
    if [ ! -d "${METAEUK_ENV}" ]; then
        echo "[ERROR] MetaEuk 环境不存在: ${METAEUK_ENV}"; exit 1
    fi
    if [ ! -e "${METAEUK_DBTYPE}" ]; then
        echo "[ERROR] MetaEuk 数据库不存在: ${DB}"; exit 1
    fi
    if [ ! -s "${METAEUK_DBTYPE}" ]; then
        echo "[ERROR] MetaEuk 数据库为空: ${DB}"; exit 1
    fi
fi

mkdir -p "${OUTDIR}"

echo "[fun_metaeuk] 开始真菌基因预测: ${SAMPLE} | 方法: ${METHOD} | 输入: ${INPUT_CONTIGS}"

if [ "${METHOD}" = "prodigal" ]; then
    EXIT_CODE=0
    mgx_try mgx_conda assembly \
        prodigal \
            -i "${INPUT_CONTIGS}" \
            -a "${FAA}" \
            -g 11 \
            -p meta \
            -f gff \
            -o "${GFF}" \
            -q \
            || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] Prodigal 失败（exit: ${EXIT_CODE}）"
        rm -f "${FAA}" "${GFF}"; exit ${EXIT_CODE}
    fi

    if [ ! -s "${FAA}" ]; then
        echo "[ERROR] Prodigal 未生成蛋白输出: ${FAA}"
        rm -f "${FAA}"; exit 1
    fi
else
    EXIT_CODE=0
    mgx_try mgx_conda metaeuk \
        metaeuk easy-predict \
            "${INPUT_CONTIGS}" \
            "${DB}" \
            "${OUT_PREFIX}" \
            "${TMP_DIR}" \
            --threads "${CPUS}" \
            -s 7.5 \
            --min-length 100 \
            --translation-table 1 \
            || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[ERROR] MetaEuk 失败（exit: ${EXIT_CODE}）"
        rm -f "${FAS}" "${CODON_FAS}" "${FAA}"
        rm -rf "${TMP_DIR}"
        exit ${EXIT_CODE}
    fi

    if [ ! -s "${FAS}" ]; then
        echo "[ERROR] MetaEuk 未生成蛋白输出: ${FAS}"
        rm -f "${FAA}"
        rm -rf "${TMP_DIR}"
        exit 1
    fi

    cp -f "${FAS}" "${FAA}"
    rm -rf "${TMP_DIR}"
fi

N_TOTAL=$(grep -c "^>" "${FAA}" 2>/dev/null || echo "0")
echo "[fun_metaeuk] ${SAMPLE} 完成 | 方法: ${METHOD} | 预测基因: ${N_TOTAL} | 输出: ${OUTDIR}/"
mgx_end "fun_metaeuk"
