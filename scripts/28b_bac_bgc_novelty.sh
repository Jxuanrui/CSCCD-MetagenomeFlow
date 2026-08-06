#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 28b_bac_bgc_novelty.sh
# 功  能: BGC（次级代谢产物生物合成基因簇）新颖度评分
#         对 28_bac_antismash.sh 产出的每个 region 提取 CDS 蛋白序列，
#         用 DIAMOND 比对 antiSMASH 自带的 MIBiG 3.1 蛋白库，按 MIBiG cluster
#         分组统计 CDS 命中比例，novelty_score = 1 - 最佳 cluster 命中比例
#         （无命中记 1.0，即完全新颖）
#         不重跑 antiSMASH（现有产出用 --minimal，未启用 KnownClusterBlast），
#         复用其数据库目录下已有的 MIBiG DIAMOND 库，不新建数据库/环境
# 依  赖: 28_bac_antismash.sh（{sample}/*.region*.gbk，antismash_done.txt sentinel）
# 输  入: ${WORKDIR}/result/annotation/antismash/{sample}/*.region*.gbk
#         ${REPO}/db/antismash/antismash-db/clustercompare/mibig/3.1/{proteins.dmnd,data.json}
# 输  出: ${WORKDIR}/result/annotation/antismash/{sample}/{sample}.bgc_novelty.tsv
#           列：sample, contig_id, region_id, product, n_cds,
#               best_mibig_cluster, best_mibig_organism, best_mibig_product,
#               best_mibig_hit_fraction, novelty_score
# 粒  度: sample + contig_id + region_id 为唯一标识，不强制关联 dRep MAG
#         （②cluster 模块是独立维度，两者不强耦合）
# 用  法: bash 28b_bac_bgc_novelty.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 28b_bac_bgc_novelty.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""; FORCE=0
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
REPO="$(readlink -f "${REPO}")"
WORKDIR="$(readlink -f "${WORKDIR}")"
ANTISMASH_DIR="${WORKDIR}/result/annotation/antismash/${SAMPLE}"
OUT_TSV="${ANTISMASH_DIR}/${SAMPLE}.bgc_novelty.tsv"
TMP_DIR="${ANTISMASH_DIR}/bgc_novelty_tmp"
MIBIG_DMND="${REPO}/db/antismash/antismash-db/clustercompare/mibig/3.1/proteins.dmnd"
MIBIG_JSON="${REPO}/db/antismash/antismash-db/clustercompare/mibig/3.1/data.json"
ANTISMASH_ENV="${REPO}/envs/antismash"

if [ ${FORCE} -eq 0 ] && [ -f "${OUT_TSV}" ] && [ -s "${OUT_TSV}" ]; then
    echo "[28b_bgc_novelty] 结果已存在，跳过: ${OUT_TSV}"
    exit 0
fi

if [ ! -d "${ANTISMASH_DIR}" ]; then
    echo "[ERROR] antiSMASH 输出目录不存在: ${ANTISMASH_DIR}"; exit 1
fi
if [ ! -f "${MIBIG_DMND}" ] || [ ! -f "${MIBIG_JSON}" ]; then
    echo "[ERROR] MIBiG DIAMOND 库缺失: ${MIBIG_DMND}"; exit 1
fi

N_REGION=$(find "${ANTISMASH_DIR}" -maxdepth 1 -name "*.region*.gbk" | wc -l)
if [ "${N_REGION}" -eq 0 ]; then
    echo "[28b_bgc_novelty] 样本 ${SAMPLE} 无 BGC region，写空结果"
    echo -e "sample\tcontig_id\tregion_id\tproduct\tn_cds\tbest_mibig_cluster\tbest_mibig_organism\tbest_mibig_product\tbest_mibig_hit_fraction\tnovelty_score" > "${OUT_TSV}"
    exit 0
fi

mkdir -p "${TMP_DIR}"

conda run --prefix "${ANTISMASH_ENV}" --no-capture-output \
    python3 "${REPO}/scripts/28b_bgc_novelty_score.py" \
        --sample "${SAMPLE}" \
        --antismash-dir "${ANTISMASH_DIR}" \
        --mibig-dmnd "${MIBIG_DMND}" \
        --mibig-data-json "${MIBIG_JSON}" \
        --diamond-bin "${ANTISMASH_ENV}/bin/diamond" \
        --tmp-dir "${TMP_DIR}" \
        --out "${OUT_TSV}" \
        --threads "${CPUS}"

rm -rf "${TMP_DIR}"
echo "[28b_bgc_novelty] 完成，耗时 ${SECONDS}s | 样本: ${SAMPLE} | region数: ${N_REGION}"
echo "[28b_bgc_novelty] 输出: ${OUT_TSV}"
