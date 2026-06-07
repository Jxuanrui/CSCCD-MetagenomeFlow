#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 39_bac_coverm_quant.sh
# 功  能: MAG 样本间丰度定量（CoverM genome）
#         工具版本：CoverM 0.7+（conda env: coverm）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs + 质控 reads
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
#         ${WORKDIR}/temp/qc/kneaddata/{sample}/{sample}_1/2_kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/binning/coverm_quant/{sample}.tsv
#           — 每样本一行，列=各 MAG 的相对丰度/RPKM/TPM
#
# 参  考: CoverM docs; Olm et al. (dRep companion)
# 用  法: bash 39_bac_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 39_bac_coverm_quant.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTPUT="${WORKDIR}/result/binning/coverm_quant/${SAMPLE}.tsv"
R1="${WORKDIR}/temp/qc/kneaddata/${SAMPLE}/${SAMPLE}_1_kneaddata.fastq.gz"
R2="${WORKDIR}/temp/qc/kneaddata/${SAMPLE}/${SAMPLE}_2_kneaddata.fastq.gz"

if [ ! -d "${MAGS_DIR}" ] || [ -z "$(ls "${MAGS_DIR}"/*.fa 2>/dev/null)" ]; then
    echo "[ERROR] 去冗余 MAGs 不存在: ${MAGS_DIR}"; exit 1
fi

if [ -f "${OUTPUT}" ] && [ -s "${OUTPUT}" ]; then echo "[coverm_quant] 结果已存在，跳过"; exit 0; fi

mkdir -p "$(dirname "${OUTPUT}")"

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
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm genome 失败"; exit ${EXIT_CODE}; fi

N_MAGS=$(awk 'NR>1{print $1}' "${OUTPUT}" 2>/dev/null | wc -l || echo 0)
echo "[coverm_quant] 完成，耗时 ${SECONDS}s | ${SAMPLE}: ${N_MAGS} MAGs 定量"
