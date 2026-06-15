#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 80b_fun_metaeuk.sh
# 功  能: MetaEuk 真菌蛋白编码基因预测（easy-predict）
#         真核宏基因组基因预测，正确处理内含子，弥补 Prodigal 对真菌基因的低估
# 依  赖: 78_fun_megahit.sh 的输出（${SAMPLE}_fungi.contigs.fa）
# 输  入: ${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}_fungi.contigs.fa
# 数  据: ${REPO}/db/funomic/P/FunOMIC-P.dmnd
# 输  出: ${WORKDIR}/result/fungi/metaeuk/${SAMPLE}/
#           ${SAMPLE}.fas          — MetaEuk 蛋白序列输出
#           ${SAMPLE}.codon.fas    — 核苷酸 CDS 序列
#           ${SAMPLE}_metaeuk.faa  — 下游注释兼容蛋白序列
# 用  法: bash 80b_fun_metaeuk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 80b_fun_metaeuk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

示例:
  bash 80b_fun_metaeuk.sh -s SRR28210342 -t 8 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome
EOF
}

SAMPLE=""; CPUS="1"; WORKDIR=""; REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-s/-w/-r）"; show_help; exit 1
fi

SECONDS=0

INPUT_CONTIGS="${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}_fungi.contigs.fa"
DB="${REPO}/db/funomic/P/FunOMIC-P.dmnd"
OUTDIR="${WORKDIR}/result/fungi/metaeuk/${SAMPLE}"
TMP_DIR="${OUTDIR}/tmp_${SAMPLE}"
OUT_PREFIX="${OUTDIR}/${SAMPLE}"
FAS="${OUTDIR}/${SAMPLE}.fas"
CODON_FAS="${OUTDIR}/${SAMPLE}.codon.fas"
FAA="${OUTDIR}/${SAMPLE}_metaeuk.faa"

if [ ! -f "${INPUT_CONTIGS}" ]; then echo "[WARN] 输入不存在，跳过 MetaEuk: ${INPUT_CONTIGS}"; exit 0; fi
if [ ! -s "${INPUT_CONTIGS}" ]; then echo "[WARN] 输入为空，跳过 MetaEuk: ${INPUT_CONTIGS}"; exit 0; fi
if [ ! -f "${DB}" ]; then echo "[ERROR] 数据库不存在: ${DB}"; exit 1; fi
if [ ! -s "${DB}" ]; then echo "[ERROR] 数据库为空: ${DB}"; exit 1; fi

if [ -f "${FAA}" ] && [ -s "${FAA}" ]; then
    echo "[INFO] 结果已存在，跳过: ${SAMPLE}"; exit 0
fi

mkdir -p "${OUTDIR}"

echo "[fun_metaeuk] 开始真菌真核基因预测: ${SAMPLE} | 输入: ${INPUT_CONTIGS}"

conda run --prefix "${REPO}/envs/metaeuk" --no-capture-output \
    metaeuk easy-predict \
        "${INPUT_CONTIGS}" \
        "${DB}" \
        "${OUT_PREFIX}" \
        "${TMP_DIR}" \
        --threads "${CPUS}" \
        -s 7.5 \
        --min-length 100 \
        --translation-table 1

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] MetaEuk 失败（exit: ${EXIT_CODE}）"
    rm -f "${FAS}" "${CODON_FAS}" "${FAA}"; exit ${EXIT_CODE}
fi

if [ ! -s "${FAS}" ]; then
    echo "[ERROR] MetaEuk 未生成蛋白输出: ${FAS}"
    rm -f "${FAA}"; exit 1
fi

cp -f "${FAS}" "${FAA}"
rm -rf "${TMP_DIR}"

N_TOTAL=$(grep -c "^>" "${FAA}" 2>/dev/null || echo "0")
echo "[fun_metaeuk] ${SAMPLE} 完成，耗时 ${SECONDS}s | 预测基因: ${N_TOTAL} | 输出: ${OUTDIR}/"
