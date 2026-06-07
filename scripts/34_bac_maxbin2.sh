#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 34_bac_maxbin2.sh
# 功  能: MaxBin2 宏基因组分箱（基于 EM 算法 + tetranucleotide）
#         工具版本：MaxBin2 2.2.7（conda env: metawrap）
# 依  赖: 32_bac_coverm_depth.sh 的输出（depth.txt）
#         MaxBin2 需要转换 depth 为 2 列格式（contig, depth）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/depth.txt
# 输  出: ${WORKDIR}/result/binning/maxbin2/{sample}/
#           bin.{n}.fasta            — 每个 bin 的 fasta
#           ${SAMPLE}.maxbin2.tsv    — contig2bin 表
#
# 参  考: Wu et al. 2014 Microbiome (MaxBin2)
# 用  法: bash 34_bac_maxbin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 34_bac_maxbin2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
DEPTH="${WORKDIR}/result/binning/coverm/${SAMPLE}/depth.txt"
OUTDIR="${WORKDIR}/result/binning/maxbin2/${SAMPLE}"
ABUND="${OUTDIR}/abundance.txt"
SENTINEL="${OUTDIR}/${SAMPLE}.maxbin2.tsv"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi
if [ ! -f "${DEPTH}" ]; then echo "[ERROR] Depth missing"; exit 1; fi

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[maxbin2] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# MaxBin2 需要 2 列 abundance (contig, depth)，从 coverm 深度表提取
if [ ! -f "${ABUND}" ]; then
    tail -n +2 "${DEPTH}" | cut -f1,4 > "${ABUND}"
fi

echo "[maxbin2] ${SAMPLE} | 线程: ${CPUS}"
conda run --prefix "${REPO}/envs/metawrap" --no-capture-output \
    run_MaxBin.pl \
        -contig "${CONTIGS}" \
        -max_iteration 50 \
        -thread "${CPUS}" \
        -abund "${ABUND}" \
        -out "${OUTDIR}/bin"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] MaxBin2 失败"; exit ${EXIT_CODE}; fi

# 构建 contig2bin 表
for f in "${OUTDIR}"/bin.*.fasta; do
    bname=$(basename "$f" .fasta)
    grep '^>' "$f" | sed "s/^>//" | awk -v bin="$bname" '{print $1"\t"bin}'
done > "${SENTINEL}"

N_FA=$(ls "${OUTDIR}"/bin.*.fasta 2>/dev/null | wc -l || echo 0)
echo "[maxbin2] 完成，耗时 ${SECONDS}s | bins: ${N_FA}"
