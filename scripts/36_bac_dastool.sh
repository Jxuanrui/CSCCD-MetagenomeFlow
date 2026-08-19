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

set -euo pipefail

show_help() { cat << EOF
用法: bash 36_bac_dastool.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
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
BINS_DIR="${OUTDIR}/${SAMPLE}_DASTool_bins"

METABAT2_TSV="${WORKDIR}/result/binning/metabat2/${SAMPLE}/${SAMPLE}.tsv"
MAXBIN2_TSV="${WORKDIR}/result/binning/maxbin2/${SAMPLE}/${SAMPLE}.maxbin2.tsv"
SEMIBIN2_TSV="${WORKDIR}/result/binning/semibin2/${SAMPLE}/${SAMPLE}.semibin2.tsv"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ] && [ -d "${BINS_DIR}" ]; then
    echo "[dastool] 结果已存在，跳过"; exit 0
fi

count_assignments() {
    local file="$1"
    if [ ! -f "${file}" ] || [ ! -s "${file}" ]; then
        echo 0
        return
    fi
    awk '
        NR == 1 && $1 == "contig_id" && $2 == "bin_id" { next }
        NF >= 2 { count++ }
        END { print count + 0 }
    ' "${file}"
}

METABAT2_ROWS=$(count_assignments "${METABAT2_TSV}")
MAXBIN2_ROWS=$(count_assignments "${MAXBIN2_TSV}")
SEMIBIN2_ROWS=$(count_assignments "${SEMIBIN2_TSV}")
TOTAL_BINS=$((METABAT2_ROWS + MAXBIN2_ROWS + SEMIBIN2_ROWS))

if [ "${TOTAL_BINS}" -le 0 ]; then
    echo "[dastool] WARNING: No bins from any binner. Creating empty output."
    mkdir -p "${OUTDIR}" "${BINS_DIR}"
    : > "${SENTINEL}"
    exit 0
fi

# 检查至少两个 binner 有实际输出
BINNERS=()
[ "${METABAT2_ROWS}" -gt 0 ] && BINNERS+=("metabat2:${METABAT2_TSV}")
[ "${MAXBIN2_ROWS}" -gt 0 ] && BINNERS+=("maxbin2:${MAXBIN2_TSV}")
[ "${SEMIBIN2_ROWS}" -gt 0 ] && BINNERS+=("semibin2:${SEMIBIN2_TSV}")
if [ ${#BINNERS[@]} -lt 2 ]; then
    echo "[dastool] WARNING: Need at least 2 non-empty binner outputs, found ${#BINNERS[@]}. Creating empty output."
    mkdir -p "${OUTDIR}" "${BINS_DIR}"
    : > "${SENTINEL}"
    exit 0
fi

mkdir -p "${OUTDIR}"

# DAS_Tool 要求 contig2bin 表无表头、两列 tab 分隔；33/35 的输出带表头，需清洗后再传入
CLEAN_DIR="${OUTDIR}/input_clean"
mkdir -p "${CLEAN_DIR}"

# 各分箱工具的中间产物可能残留极少数不在当前 assembly 中的 contig ID
# （如极短 contig 被后续步骤过滤），需据当前 CONTIGS 白名单过滤，否则 DAS_Tool 直接报错退出
CONTIG_IDS="${CLEAN_DIR}/.contig_ids.txt"
grep "^>" "${CONTIGS}" | sed 's/^>//;s/[[:space:]].*//' > "${CONTIG_IDS}"

# 构建标识列表和输入文件列表
LABELS=""; INPUTS=""
for entry in "${BINNERS[@]}"; do
    L="${entry%%:*}"
    F="${entry#*:}"
    CLEAN_F="${CLEAN_DIR}/${L}.tsv"
    awk 'BEGIN{FS=OFS="\t"} NR==1 && ($1=="contig_id" || $1=="contig") {next} NF>=2 {print $1,$2}' "${F}" \
        | awk -v ids="${CONTIG_IDS}" 'BEGIN{FS=OFS="\t"; while((getline line < ids) > 0) keep[line]=1} $1 in keep {print}' \
        > "${CLEAN_F}"
    [ -n "${LABELS}" ] && LABELS="${LABELS},"
    LABELS="${LABELS}${L}"
    [ -n "${INPUTS}" ] && INPUTS="${INPUTS},"
    INPUTS="${INPUTS}${CLEAN_F}"
done

set +e
echo "[dastool] ${SAMPLE} | binner: ${LABELS} | 整合分箱 ..."
# R_LIBS_USER (项目全局 Rlib，R 4.5.3 编译) 与本环境 R 4.4.3 ABI 不兼容，
# 会覆盖 envs/dastool 自带且兼容的 data.table，导致 DAS_Tool 内部 R 脚本崩溃
env -u R_LIBS_USER conda run --prefix "${REPO}/envs/dastool" --no-capture-output \
    DAS_Tool \
        --threads "${CPUS}" \
        -i "${INPUTS}" \
        -l "${LABELS}" \
        -c "${CONTIGS}" \
        -o "${OUTDIR}/${SAMPLE}" \
        --score_threshold 0.3 \
        --write_bins

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] DAS_Tool 失败"; exit ${EXIT_CODE}; fi

N_BINS=0
[ -d "${BINS_DIR}" ] && N_BINS=$(ls "${BINS_DIR}"/*.fa 2>/dev/null | wc -l)
echo "[dastool] 完成，耗时 ${SECONDS}s | 整合 bins: ${N_BINS}"
