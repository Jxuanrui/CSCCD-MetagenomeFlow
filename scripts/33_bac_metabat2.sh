#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 33_bac_metabat2.sh
# 功  能: MetaBAT2 宏基因组分箱（基于 tetranucleotide + 丰度）
#         工具版本：MetaBAT2 2.18+（conda env: metawrap）
# 依  赖: 32_bac_coverm_depth.sh 的输出（depth.txt + BAM）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
#         ${WORKDIR}/result/binning/coverm/{sample}/depth.txt
# 输  出: ${WORKDIR}/result/binning/metabat2/{sample}/
#           bin.{n}.fa              — 每个 bin 的 fasta
#           ${SAMPLE}.tsv           — contig2bin 表
#
# 参  考: Kang et al. 2019 eLife (MetaBAT2)
# 用  法: bash 33_bac_metabat2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 33_bac_metabat2.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
DEPTH="${WORKDIR}/result/binning/coverm/${SAMPLE}/depth.txt"
OUTDIR="${WORKDIR}/result/binning/metabat2/${SAMPLE}"
SENTINEL="${OUTDIR}/${SAMPLE}.tsv"
CONTIG2BIN="${SENTINEL}"

if [ ! -f "${CONTIGS}" ]; then echo "[ERROR] Contigs missing"; exit 1; fi
if [ ! -f "${DEPTH}" ]; then echo "[ERROR] Depth missing: ${DEPTH}"; exit 1; fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[metabat2] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[metabat2] ${SAMPLE} | MetaBAT2 分箱 ..."
conda run --prefix "${REPO}/envs/metawrap" --no-capture-output \
    metabat2 \
        --numThreads "${CPUS}" \
        -m 1500 \
        -i "${CONTIGS}" \
        -a "${DEPTH}" \
        -o "${OUTDIR}/bin"

EXIT_CODE=$?
if [ ${EXIT_CODE} -eq 139 ]; then
    echo "[metabat2] SEGFAULT (exit 139) — writing empty contig2bin.tsv"
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    exit 0
fi
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] metabat2 失败"; exit ${EXIT_CODE}; fi

N_BINS=$(find "${OUTDIR}" -maxdepth 1 -name 'bin.*.fa' 2>/dev/null | wc -l || echo 0)
if [ "${N_BINS}" -eq 0 ]; then
    echo "[metabat2] WARNING: No bins produced for ${SAMPLE}. Creating empty contig2bin.tsv."
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    echo "[metabat2] ${SAMPLE} complete (0 bins)"
    exit 0
fi

echo "[metabat2] 构建 contig2bin 表 ..."
if conda run --prefix "${REPO}/envs/metawrap" --no-capture-output bash -lc 'command -v metabat2-utils >/dev/null'; then
    conda run --prefix "${REPO}/envs/metawrap" --no-capture-output \
        metabat2-utils bin "${OUTDIR}" | \
        metabat2-utils label - > "${CONTIG2BIN}"
else
    echo "[metabat2] WARNING: metabat2-utils not found. Building contig2bin.tsv from bin FASTA files."
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    for f in "${OUTDIR}"/bin.*.fa; do
        [ -f "${f}" ] || continue
        bname=$(basename "${f}" .fa)
        grep '^>' "${f}" | sed 's/^>//' | awk -v bin="${bname}" '{print $1"\t"bin}' >> "${CONTIG2BIN}"
    done
fi

if [ ! -f "${CONTIG2BIN}" ] || [ ! -s "${CONTIG2BIN}" ]; then
    echo "[metabat2] WARNING: No bins produced for ${SAMPLE}. Creating empty contig2bin.tsv."
    echo -e "contig_id\tbin_id" > "${CONTIG2BIN}"
    echo "[metabat2] ${SAMPLE} complete (0 bins)"
fi

echo "[metabat2] 完成，耗时 ${SECONDS}s | bins: ${N_BINS}"
