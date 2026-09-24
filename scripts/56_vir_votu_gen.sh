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

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 56_vir_votu_gen.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
OUTDIR="${WORKDIR}/result/virus/votu"
CONTIGS_DIR="${OUTDIR}/contigs"
ALL_VIRUS="${CONTIGS_DIR}/virus.fasta"
SENTINEL="${OUTDIR}/votu_representatives.tsv"

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[votu_gen] vOTU 结果已存在，跳过"; exit 0; fi

# Step 1: 收集所有样本的病毒 contigs
# 注：MEGAHIT 的 contig ID（如 k127_44127）只是样本内编号，非全局唯一，不同样本
# 独立组装会产生同名 ID；跨样本合并时若不加前缀区分，下游 pharokka/genomad/bacphlip
# 等工具会因 fasta 内重复 header 直接报错退出。这里为每条 header 加上样本名前缀。
echo "[votu_gen] 步骤 1/4: 合并全样本病毒 contigs ..."
mkdir -p "${CONTIGS_DIR}"
: > "${ALL_VIRUS}"  # 清空
merge_with_sample_prefix() {
    local pattern="$1"
    for f in "${WORKDIR}"/result/virus/checkv/*/${pattern}; do
        [ -f "$f" ] || continue
        local sample
        sample="$(basename "$(dirname "$f")")"
        sed "s/^>/>${sample}__/" "$f" >> "${ALL_VIRUS}"
    done
}
merge_with_sample_prefix "viruses_filtered.fna"
# fallback: 用 viruses.fna
if [ ! -s "${ALL_VIRUS}" ]; then
    merge_with_sample_prefix "viruses.fna"
fi
# second fallback: 用 virus_contigs.fasta
if [ ! -s "${ALL_VIRUS}" ]; then
    merge_with_sample_prefix "virus_contigs.fasta"
fi

if [ ! -s "${ALL_VIRUS}" ]; then echo "[ERROR] 无病毒 contigs"; exit 1; fi

mkdir -p "${OUTDIR}/vclust"

# Step 2: vclust prefilter
echo "[votu_gen] 步骤 2/4: vclust prefilter ..."
mgx_conda vclust \
    vclust prefilter \
        -i "${ALL_VIRUS}" \
        -o "${OUTDIR}/vclust/fltr.txt" \
        --min-ident 0.95

# Step 3: vclust align
echo "[votu_gen] 步骤 3/4: vclust align ..."
mgx_conda vclust \
    vclust align \
        -i "${ALL_VIRUS}" \
        -o "${OUTDIR}/vclust/ani.tsv" \
        --filter "${OUTDIR}/vclust/fltr.txt" \
        -t "${CPUS}"

# Step 4: vclust cluster
echo "[votu_gen] 步骤 4/4: vclust cluster (Leiden, ANI 0.95) ..."
mgx_conda vclust \
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
echo "[votu_gen] vOTUs: ${N_VOTUS}"
mgx_end "votu_gen"
