#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 57_vir_votu_genomad.sh
# 功  能: vOTU 分类学注释（geNomad end-to-end 对代表序列）
#         工具版本：geNomad 1.11+（conda env: genomad）
# 依  赖: 56_vir_votu_gen.sh 的输出（vOTU 代表序列）
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/votu/genomad/
#           virus_taxonomy.tsv        — vOTU 分类注释表
#
# 参  考: Camargo et al. 2024; Virus_Apptainer_pipline vOTU-genomad.sh
# 用  法: bash 57_vir_votu_genomad.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 57_vir_votu_genomad.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/votu/genomad"
TAXONOMY="${OUTDIR}/virus_taxonomy.tsv"
GENOMAD_DB="${REPO}/db/genomad"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在: ${VOTU_FA}"; exit 1; fi
if [ -f "${TAXONOMY}" ] && [ -s "${TAXONOMY}" ]; then echo "[votu_genomad] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[votu_genomad] vOTU 分类注释 ..."
conda run --prefix "${REPO}/envs/genomad" --no-capture-output \
    genomad end-to-end \
        --cleanup \
        --threads "${CPUS}" \
        --sensitivity 4.2 \
        --splits 4 \
        "${VOTU_FA}" \
        "${OUTDIR}" \
        "${GENOMAD_DB}"

# 提取分类注释
TAXONOMY_SRC="$(find "${OUTDIR}/identify" -type f \( -name 'virus_taxonomy.tsv' -o -name 'vOTU_taxonomy.tsv' \) | head -n 1)"
if [ -z "${TAXONOMY_SRC}" ]; then
    TAXONOMY_SRC="$(find "${OUTDIR}/identify" -type f -name '*taxonomy.tsv' | head -n 1)"
fi
if [ -n "${TAXONOMY_SRC}" ] && [ -f "${TAXONOMY_SRC}" ]; then
    cp "${TAXONOMY_SRC}" "${TAXONOMY}"
fi

echo "[votu_genomad] 完成，耗时 ${SECONDS}s"
