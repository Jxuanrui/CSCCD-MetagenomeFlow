#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 36_bac_dastool.sh
# 功  能: DAS_Tool 多算法分箱整合（MetaBAT2 + MaxBin2 + SemiBin2 → 最优 bins）
#         工具版本：DAS_Tool 1.1.7（conda env: dastool）
# 依  赖: 33-35 三种 binner 的 contig2bin 表 + contigs
# 输  入: contig2bin 表从 33/34/35
#         ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/binning/dastool/{sample}/
#           ${SAMPLE}_DASTool_contig2bin.tsv  — 整合 contig2bin
#           bins/*.fa                         — 提取的 bin fasta
#
# 参  考: Sieber et al. 2018 Microbiome (DAS_Tool)
# 用  法: bash 36_bac_dastool.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 36_bac_dastool.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
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
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/binning/dastool/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}_DASTool_contig2bin.tsv"
BINS_DIR="${OUTDIR}/bins"

METABAT2_TSV="${WORKDIR}/result/binning/metabat2/${SAMPLE}/${SAMPLE}.tsv"
MAXBIN2_TSV="${WORKDIR}/result/binning/maxbin2/${SAMPLE}/${SAMPLE}.maxbin2.tsv"
SEMIBIN2_TSV="${WORKDIR}/result/binning/semibin2/${SAMPLE}/${SAMPLE}.semibin2.tsv"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ] && [ -d "${BINS_DIR}" ]; then
    echo "[dastool] 结果已存在，跳过"; exit 0
fi

# 检查至少两个 binner 有输出
BINNERS=()
[ -f "${METABAT2_TSV}" ] && [ -s "${METABAT2_TSV}" ] && BINNERS+=("metabat2:${METABAT2_TSV}")
[ -f "${MAXBIN2_TSV}" ] && [ -s "${MAXBIN2_TSV}" ] && BINNERS+=("maxbin2:${MAXBIN2_TSV}")
[ -f "${SEMIBIN2_TSV}" ] && [ -s "${SEMIBIN2_TSV}" ] && BINNERS+=("semibin2:${SEMIBIN2_TSV}")
if [ ${#BINNERS[@]} -lt 2 ]; then
    echo "[ERROR] 需要至少 2 个 binner 的输出，当前: ${#BINNERS[@]}"; exit 1
fi

mkdir -p "${OUTDIR}"

# 构建标识列表和输入文件列表
LABELS=""; INPUTS=""
for entry in "${BINNERS[@]}"; do
    L="${entry%%:*}"
    F="${entry#*:}"
    [ -n "${LABELS}" ] && LABELS="${LABELS},"
    LABELS="${LABELS}${L}"
    [ -n "${INPUTS}" ] && INPUTS="${INPUTS},"
    INPUTS="${INPUTS}${F}"
done

echo "[dastool] ${SAMPLE} | binner: ${LABELS} | 整合分箱 ..."
conda run --prefix "${REPO}/envs/dastool" --no-capture-output \
    DAS_Tool \
        --threads "${CPUS}" \
        -i "${INPUTS}" \
        -l "${LABELS}" \
        -c "${CONTIGS}" \
        -o "${OUTDIR}/${SAMPLE}" \
        --score_threshold 0.3 \
        --write_bins 1

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] DAS_Tool 失败"; exit ${EXIT_CODE}; fi

N_BINS=0
[ -d "${BINS_DIR}" ] && N_BINS=$(ls "${BINS_DIR}"/*.fa 2>/dev/null | wc -l)
echo "[dastool] 完成，耗时 ${SECONDS}s | 整合 bins: ${N_BINS}"
