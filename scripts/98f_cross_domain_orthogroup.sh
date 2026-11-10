#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98f_cross_domain_orthogroup.sh
# 功  能: 跨域（细菌/病毒/真菌）蛋白正交基因组检测（MMseqs2 蛋白层聚类）
#         参考 VEBA (https://github.com/jolespin/veba) cluster 模块的正交基因组
#         检测思路（SLC/SSPC，MMseqs2 蛋白聚类），不拷贝 VEBA 源码
#         （VEBA 为 AGPLv3 许可，MMseqs2 为 MIT/GPLv3 双许可，本项目仅调用其
#         command-line 接口，不链接/拷贝其源码，无许可证污染风险）
#         蛋白层相似度阈值远宽松于核酸ANI，跨演化距离更远的域仍可能检出真实同源
#         关系（如保守结构域/功能基因），比 98e 的核酸ANI比对更具生物学意义
# 依  赖: Prokka 细菌蛋白（38_bac_drep.sh 之后各 MAG 的 prokka 输出）、
#         病毒 pharokka/prodigal 蛋白、79f_fun_metaeuk_per_bin.sh（真菌 euk MAG 蛋白）
# 输  入: ${WORKDIR}/result/binning/prokka/*/*.faa
#         ${WORKDIR}/result/virus/prodigal/*/*.faa（fallback，若 pharokka 未启用）
#         ${WORKDIR}/result/fungi/veba_qc/*/euk_mags/bin.*/*.faa
# 输  出: ${WORKDIR}/result/cross_domain/orthogroup/
#           merged_proteins.faa   — 三域蛋白合并（序列ID前缀标注 domain__genome__）
#           mmseqs_cluster_cluster.tsv — MMseqs2 easy-cluster 原始输出（rep\tmember）
#           orthogroup_table.tsv  — protein_id, genome_id, domain, orthogroup_id
# 用  法: bash 98f_cross_domain_orthogroup.sh -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 98f_cross_domain_orthogroup.sh -t CPUS -w WORKDIR -r REPO [--force]
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
REPO="$(readlink -f "${REPO}")"
WORKDIR="$(readlink -f "${WORKDIR}")"
OUTDIR="${WORKDIR}/result/cross_domain/orthogroup"
MERGED_FAA="${OUTDIR}/merged_proteins.faa"
MMSEQS_PREFIX="${OUTDIR}/mmseqs_cluster"
MMSEQS_TMP="${OUTDIR}/mmseqs_tmp"
ORTHOGROUP_TABLE="${OUTDIR}/orthogroup_table.tsv"

if [ ${FORCE} -eq 0 ] && [ -f "${ORTHOGROUP_TABLE}" ] && [ -s "${ORTHOGROUP_TABLE}" ]; then
    echo "[cross_domain_orthogroup] 结果已存在，跳过: ${ORTHOGROUP_TABLE}"
    exit 0
fi

mkdir -p "${OUTDIR}"
: > "${MERGED_FAA}"

add_domain_proteins() {
    local domain="$1"; shift
    local n=0
    for FAA in "$@"; do
        [ -s "${FAA}" ] || continue
        # genome_id 取 .faa 所在目录名（Prokka/79f 均遵循"每基因组一子目录"命名）
        local genome_id
        genome_id=$(basename "$(dirname "${FAA}")")
        # 序列ID加前缀 domain###genome###，用 ### 分隔（genome_id/protein_id 本身
        # 可能含 __，用 __ 做分隔符会导致后续 split 解析错位）
        awk -v prefix="${domain}###${genome_id}###" \
            '/^>/{sub(/^>/, ">" prefix); print; next} {print}' "${FAA}" >> "${MERGED_FAA}"
        n=$((n+1))
    done
    echo "${n}"
}

echo "[cross_domain_orthogroup] 收集三域蛋白 ..."
N_BAC=$(add_domain_proteins bacteria "${WORKDIR}"/result/binning/prokka/*/*.faa)
N_VIR=$(add_domain_proteins virus "${WORKDIR}"/result/virus/pharokka/*/*.faa "${WORKDIR}"/result/virus/prodigal/*/*.faa)
N_FUN=$(add_domain_proteins fungi "${WORKDIR}"/result/fungi/veba_qc/*/euk_mags/bin.*/*.faa)
echo "[cross_domain_orthogroup] 细菌蛋白文件: ${N_BAC} | 病毒蛋白文件: ${N_VIR} | 真菌蛋白文件: ${N_FUN}"

if [ ! -s "${MERGED_FAA}" ]; then
    echo "[cross_domain_orthogroup] 无任何蛋白输入，写空结果"
    echo -e "protein_id\tgenome_id\tdomain\torthogroup_id" > "${ORTHOGROUP_TABLE}"
    exit 0
fi

echo "[cross_domain_orthogroup] MMseqs2 easy-cluster 正交基因组检测 ..."
mkdir -p "${MMSEQS_TMP}"
mgx_conda cluster \
    mmseqs easy-cluster \
        "${MERGED_FAA}" \
        "${MMSEQS_PREFIX}" \
        "${MMSEQS_TMP}" \
        --min-seq-id 0.3 \
        -c 0.8 \
        --cov-mode 0 \
        --threads "${CPUS}" \
        -v 1
rm -rf "${MMSEQS_TMP}"

CLUSTER_TSV="${MMSEQS_PREFIX}_cluster.tsv"
if [ ! -s "${CLUSTER_TSV}" ]; then
    echo "[ERROR] MMseqs2 未产出聚类结果: ${CLUSTER_TSV}"; exit 1
fi

echo "[cross_domain_orthogroup] 生成正交基因组表 ..."
mgx_conda cluster \
    python3 -c "
import sys, csv

rep_to_og = {}
og_counter = 0
rows = []
with open('${CLUSTER_TSV}') as fh:
    for line in fh:
        rep, member = line.rstrip('\n').split('\t')
        if rep not in rep_to_og:
            rep_to_og[rep] = f'OG_{og_counter}'
            og_counter += 1
        og_id = rep_to_og[rep]
        parts = member.split('###', 2)
        domain = parts[0] if len(parts) == 3 else 'NA'
        genome_id = parts[1] if len(parts) == 3 else 'NA'
        rows.append((member, genome_id, domain, og_id))

with open('${ORTHOGROUP_TABLE}', 'w', newline='') as fh:
    writer = csv.writer(fh, delimiter='\t')
    writer.writerow(['protein_id', 'genome_id', 'domain', 'orthogroup_id'])
    writer.writerows(rows)

print(f'[cross_domain_orthogroup] 蛋白数: {len(rows)} | 正交基因组数: {og_counter}')
"

mgx_end "cross_domain_orthogroup"
echo "[cross_domain_orthogroup] 输出: ${ORTHOGROUP_TABLE}"
