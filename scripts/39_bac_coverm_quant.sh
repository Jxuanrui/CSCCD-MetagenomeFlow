#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 39_bac_coverm_quant.sh
# 功  能: MAG 样本间丰度定量（CoverM genome）
#         工具版本：CoverM 0.7+（conda env: coverm）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs + 质控 reads
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/coverm_quant/{sample}/{sample}.tsv
#           — 每样本一行，列=各 MAG 的相对丰度/RPKM/TPM
#
# 参  考: CoverM docs; Olm et al. (dRep companion)
# 用  法: bash 39_bac_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 39_bac_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

FORCE=0
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
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
RESULT_DIR="${WORKDIR}/result/binning/coverm_quant"
OUTPUT="${RESULT_DIR}/${SAMPLE}.tsv"
R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

N_MAGS=0
if [ -d "${MAGS_DIR}" ]; then
    N_MAGS=$(find "${MAGS_DIR}" -maxdepth 1 -type f -name "*.fa" | wc -l)
fi
if [ "${N_MAGS}" -eq 0 ]; then
    echo "[coverm_quant] WARNING: 去冗余 MAGs 为 0，创建空结果哨兵: ${OUTPUT}"
    mkdir -p "${RESULT_DIR}"
    : > "${OUTPUT}"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then echo "[coverm_quant] 结果已存在，跳过"; exit 0; fi

mkdir -p "${RESULT_DIR}"

set +e
echo "[coverm_quant] ${SAMPLE} | MAG 定量 ..."
conda run --prefix "${REPO}/envs/coverm" --no-capture-output \
    coverm genome \
        -p minimap2-sr \
        -t "${CPUS}" \
        -x fa \
        --min-covered-fraction 0 \
        -m relative_abundance rpkm tpm count covered_bases \
        -d "${MAGS_DIR}" \
        -1 "${R1}" -2 "${R2}" \
        -o "${OUTPUT}"

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm genome 失败"; exit ${EXIT_CODE}; fi

N_MAGS=$(awk 'NR>1{print $1}' "${OUTPUT}" 2>/dev/null | wc -l || echo 0)
echo "[coverm_quant] 完成，耗时 ${SECONDS}s | ${SAMPLE}: ${N_MAGS} MAGs 定量"
