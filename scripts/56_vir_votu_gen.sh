#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 56_vir_votu_gen.sh
# 功  能: vOTU 生成（vclust，跨样本 95% ANI 聚类）
#         工具版本：vclust 1.3+（conda env: vclust）
#         流  程: prefilter → align → cluster (Leiden, ANI 0.95, qcov 0.85)
# 依  赖: 54_vir_checkv_contig.sh 的病毒 contigs（跨样本合并）
# 输  入: ${WORKDIR}/result/virus/checkv/*/viruses_filtered.fna
# 输  出: ${WORKDIR}/result/virus/votu/
#           contigs/virus.fasta  — 全样本病毒 contigs 合并
#           vclust/clusters.tsv  — vclust 聚类结果
#           votu_representatives.tsv — 代表序列列表
#
# 参  考: vclust; Bin Jang et al. 2019; Virus_Apptainer_pipline
# 用  法: bash 56_vir_votu_gen.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 56_vir_votu_gen.sh -t CPUS -w WORKDIR -r REPO
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
OUTDIR="${WORKDIR}/result/virus/votu"
CONTIGS_DIR="${OUTDIR}/contigs"
ALL_VIRUS="${CONTIGS_DIR}/virus.fasta"
SENTINEL="${OUTDIR}/votu_representatives.tsv"

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[votu_gen] vOTU 结果已存在，跳过"; exit 0; fi

# Step 1: 收集所有样本的病毒 contigs
echo "[votu_gen] 步骤 1/4: 合并全样本病毒 contigs ..."
mkdir -p "${CONTIGS_DIR}"
> "${ALL_VIRUS}"  # 清空
for f in "${WORKDIR}"/result/virus/checkv/*/viruses_filtered.fna; do
    [ -f "$f" ] && cat "$f" >> "${ALL_VIRUS}"
done
# fallback: 用 viruses.fna
if [ ! -s "${ALL_VIRUS}" ]; then
    for f in "${WORKDIR}"/result/virus/checkv/*/viruses.fna; do
        [ -f "$f" ] && cat "$f" >> "${ALL_VIRUS}"
    done
fi
# second fallback: 用 virus_contigs.fasta
if [ ! -s "${ALL_VIRUS}" ]; then
    for f in "${WORKDIR}"/result/virus/checkv/*/virus_contigs.fasta; do
        [ -f "$f" ] && cat "$f" >> "${ALL_VIRUS}"
    done
fi

if [ ! -s "${ALL_VIRUS}" ]; then echo "[ERROR] 无病毒 contigs"; exit 1; fi

mkdir -p "${OUTDIR}/vclust"

# Step 2: vclust prefilter
echo "[votu_gen] 步骤 2/4: vclust prefilter ..."
conda run --prefix "${REPO}/envs/vclust" --no-capture-output \
    vclust prefilter \
        -i "${ALL_VIRUS}" \
        -o "${OUTDIR}/vclust/fltr.txt" \
        --min-ident 0.95

# Step 3: vclust align
echo "[votu_gen] 步骤 3/4: vclust align ..."
conda run --prefix "${REPO}/envs/vclust" --no-capture-output \
    vclust align \
        -i "${ALL_VIRUS}" \
        -o "${OUTDIR}/vclust/ani.tsv" \
        --filter "${OUTDIR}/vclust/fltr.txt" \
        -t "${CPUS}"

# Step 4: vclust cluster
echo "[votu_gen] 步骤 4/4: vclust cluster (Leiden, ANI 0.95) ..."
conda run --prefix "${REPO}/envs/vclust" --no-capture-output \
    vclust cluster \
        -i "${OUTDIR}/vclust/ani.tsv" \
        -o "${OUTDIR}/vclust/clusters.tsv" \
        --out-repr \
        --ids "${OUTDIR}/vclust/ani.ids.tsv" \
        --algorithm leiden \
        --metric ani \
        --ani 0.95 \
        --qcov 0.85

cut -f2 "${OUTDIR}/vclust/clusters.tsv" | tail -n +2 | sort -u > "${SENTINEL}"

N_VOTUS=$(wc -l < "${SENTINEL}")
echo "[votu_gen] 完成，耗时 ${SECONDS}s | vOTUs: ${N_VOTUS}"
