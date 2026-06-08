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

show_help() {
cat << EOF
用法: bash 78_fun_megahit.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
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
for v in SAMPLE CPUS WORKDIR REPO; do if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; exit 1; fi; done

SECONDS=0

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/fungi/assembly/${SAMPLE}"
CONTIGS="${OUTDIR}/${SAMPLE}.contigs.fa"
MEGAHIT_TMP="${OUTDIR}/_megahit_tmp"

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] 输入文件不存在: ${INPUT_R2}"; exit 1; fi

if [ -f "${CONTIGS}" ] && [ -s "${CONTIGS}" ]; then
    echo "[INFO] 结果已存在，跳过: ${CONTIGS}"
    exit 0
fi

mkdir -p "${OUTDIR}"
rm -rf "${MEGAHIT_TMP}"

echo "[fun_megahit] 提示: 可先用 71/72 的真菌结果提取 reads，再组装以提高真菌 contig 纯度"

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    megahit \
        -1 "${INPUT_R1}" \
        -2 "${INPUT_R2}" \
        -o "${MEGAHIT_TMP}" \
        -t "${CPUS}" \
        -m 0.9 \
        --presets meta-sensitive \
        --min-contig-len 1000
EXIT_CODE=$?
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
echo "[fun_megahit] 完成，耗时 ${SECONDS}s | Contig 数: ${N_CONTIGS}"

