#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 69_vir_vcontact3.sh
# 功  能: 病毒分类基因共享网络（vConTACT3）
#         工具版本：vConTACT3 3.0+（conda env: vcontact3）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
#         64_vir_pharokka.sh 的预测蛋白
# 输  入: vOTU 核酸序列 + 蛋白序列
# 输  出: ${WORKDIR}/result/virus/vcontact3/
#           genome_by_genome_overview.csv  — 分类汇总
#           vConTACT3_*.cyjs              — 可视图表
#
# ── 数据库 ────────────────────────────────────────────────────────────────────
#   vConTACT3 自动下载参考数据库。如需离线部署：
#   vcontact3 prepare_databases --db-path ${REPO}/db/vcontact3/
#
# 参  考: Bin Jang et al. 2019 Nat Biotechnol (vConTACT2)
#         vConTACT3 2025 Nat Biotechnol
# 用  法: bash 69_vir_vcontact3.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 69_vir_vcontact3.sh -t CPUS -w WORKDIR -r REPO
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
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
PROTEINS="${WORKDIR}/result/virus/pharokka/phanotate.faa"
G2G="${WORKDIR}/result/virus/votu/votu_gene2genome.tsv"
LEN="${WORKDIR}/result/virus/votu/votu_lengths.tsv"
OUTDIR="${WORKDIR}/result/virus/vcontact3"
SENTINEL="${OUTDIR}/exports/final_assignments.csv"
VDB="${REPO}/db/vcontact3"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[vcontact3] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# 准备 gene2genome 映射（如果 pharokka 输出可用，从 GFF 提取）
if [ ! -f "${G2G}" ]; then
    echo "[vcontact3] 准备 gene2genome 映射表 ..."
    GFF="${WORKDIR}/result/virus/pharokka/pharokka.gff"
    if [ -f "${GFF}" ]; then
        awk -F'\t' '$3=="CDS" {
            split($9,a,";"); gid=""; vid=""
            for(i in a) {
                if(a[i] ~ /^ID=/) gid=substr(a[i],4)
                if(a[i] ~ /^locus_tag=/) vid=substr(a[i],11)
            }
            if(gid && vid) print gid"\t"vid
        }' "${GFF}" > "${G2G}"
    else
        # 简单映射：每条序列 > 到第一个空格为基因名
        grep '^>' "${PROTEINS}" 2>/dev/null | awk '{print substr($1,2)"\t"$1}' > "${G2G}" || true
    fi
fi

# 准备序列长度表
if [ ! -f "${LEN}" ]; then
    grep '^>' "${VOTU_FA}" | while read -r h; do
        sid=$(echo "$h" | sed 's/^>//' | awk '{print $1}')
        echo -e "${sid}\t0"  # vConTACT3 可以从核酸自行计算
    done > "${LEN}"
fi

echo "[vcontact3] 病毒分类基因共享网络分析 ..."
EXIT_CODE=0
mgx_try mgx_conda vcontact3 \
    vcontact3 run \
        --nucleotide "${VOTU_FA}" \
        --output "${OUTDIR}" \
        --db-path "${VDB}" \
        -t "${CPUS}" \
        -e graphml cytoscape completeness \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[WARN] vcontact3 失败（exit: ${EXIT_CODE}）"; touch "${SENTINEL}"; fi

echo "[vcontact3] 输出: ${OUTDIR}/"
mgx_end "vcontact3"
