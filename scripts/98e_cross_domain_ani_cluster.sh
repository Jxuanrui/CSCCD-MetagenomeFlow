#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98e_cross_domain_ani_cluster.sh
# 功  能: 跨域（细菌/病毒/真菌）基因组 ANI 相似度聚类
#         参考 VEBA (https://github.com/jolespin/veba) cluster 模块的方法思路
#         （FastANI 全基因组比对 + 图社区检测），不拷贝 VEBA 源码
#         （VEBA 为 AGPLv3 许可，FastANI/networkx 均为 MIT/BSD 系许可）
#         已知局限：跨"域"（细菌 vs 真菌）核酸 ANI 在演化距离过远时生物学意义有限，
#         此为用户在知悉该局限后仍选择执行的既定方案，非脚本缺陷
# 依  赖: 38_bac_drep.sh（细菌 dRep MAG）、56_vir_votu_gen.sh（vOTU 代表序列列表）、
#         79e_fun_euk_qc_per_bin.sh（真菌 euk MAG，可以为 0 个，合法结果）
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
#         ${WORKDIR}/result/virus/votu/votu_representatives.tsv + contigs/virus.fasta
#         ${WORKDIR}/result/fungi/veba_qc/*/euk_mags/bin.*.fa
# 输  出: ${WORKDIR}/result/cross_domain/cluster/
#           genome_manifest.tsv  — genome_id, domain, fasta_path
#           all_genomes.list     — FastANI 输入文件列表
#           ani_matrix.tsv       — FastANI 输出（query, ref, ANI, frag_mapped, frag_total）
#           genome_clusters.tsv  — genome_id, domain, cluster_id（Louvain 社区检测）
# 用  法: bash 98e_cross_domain_ani_cluster.sh -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 98e_cross_domain_ani_cluster.sh -t CPUS -w WORKDIR -r REPO [--force]
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
OUTDIR="${WORKDIR}/result/cross_domain/cluster"
MANIFEST="${OUTDIR}/genome_manifest.tsv"
GENOME_LIST="${OUTDIR}/all_genomes.list"
ANI_MATRIX="${OUTDIR}/ani_matrix.tsv"
CLUSTERS="${OUTDIR}/genome_clusters.tsv"

if [ ${FORCE} -eq 0 ] && [ -f "${CLUSTERS}" ] && [ -s "${CLUSTERS}" ]; then
    echo "[cross_domain_ani] 结果已存在，跳过: ${CLUSTERS}"
    exit 0
fi

mkdir -p "${OUTDIR}"
echo -e "genome_id\tdomain\tfasta_path" > "${MANIFEST}"

# ── 步骤1：细菌 dRep MAG ──────────────────────────────────────────────────────
DREP_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
N_BAC=0
if [ -d "${DREP_DIR}" ]; then
    for FA in "${DREP_DIR}"/*.fa; do
        [ -e "${FA}" ] || continue
        GID=$(basename "${FA}" .fa)
        echo -e "${GID}\tbacteria\t${FA}" >> "${MANIFEST}"
        N_BAC=$((N_BAC+1))
    done
fi
echo "[cross_domain_ani] 细菌 MAG: ${N_BAC}"

# ── 步骤2：病毒 vOTU 代表序列（一次性 seqkit split2 拆分为一文件一vOTU）──────────
# 注：早期版本曾逐 ID 循环调用 seqkit grep（10000+次进程启动），在全量 vOTU 规模下
# 极慢；改为一次性 split2（--by-size 1），全部 17300 条序列 6 秒内拆完
VOTU_REP_TSV="${WORKDIR}/result/virus/votu/votu_representatives.tsv"
VOTU_CONTIGS="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
VOTU_FASTA_DIR="${WORKDIR}/result/virus/votu/votu_fasta"
N_VIR=0
if [ -f "${VOTU_REP_TSV}" ] && [ -f "${VOTU_CONTIGS}" ]; then
    if [ ${FORCE} -eq 1 ] || [ ! -d "${VOTU_FASTA_DIR}" ] || [ -z "$(ls -A "${VOTU_FASTA_DIR}" 2>/dev/null)" ]; then
        rm -rf "${VOTU_FASTA_DIR}"
        mkdir -p "${VOTU_FASTA_DIR}"
        mgx_conda assembly \
            seqkit split2 -s 1 --seqid-as-filename -O "${VOTU_FASTA_DIR}" "${VOTU_CONTIGS}"
    fi
    # votu_representatives.tsv 的 ID 就是 fasta header 原文（含 ||full 等标记）；
    # seqkit split2 --seqid-as-filename 把 header 中任意一段连续非法字符（如单个
    # 或连续多个 |）统一替换为字面 "__"（而非逐字符替换），必须用同样的正则规则
    # 才能定位对应拆分文件，简单的 tr '/|' '__' 逐字符替换在单个 | 场景下会算错
    while IFS= read -r RAW_ID; do
        [ -n "${RAW_ID}" ] || continue
        SAFE_ID=$(echo "${RAW_ID}" | sed -E 's/[^A-Za-z0-9._-]+/__/g')
        VOTU_FA="${VOTU_FASTA_DIR}/${SAFE_ID}.fasta"
        if [ -s "${VOTU_FA}" ]; then
            echo -e "${SAFE_ID}\tvirus\t${VOTU_FA}" >> "${MANIFEST}"
            N_VIR=$((N_VIR+1))
        fi
    done < <(cut -f1 "${VOTU_REP_TSV}")
fi
echo "[cross_domain_ani] 病毒 vOTU: ${N_VIR}"

# ── 步骤3：真菌 euk MAG（79e 产出，0个是合法结果）────────────────────────────
N_FUN=0
while IFS= read -r FA; do
    [ -n "${FA}" ] || continue
    SAMPLE_DIR=$(dirname "$(dirname "${FA}")")
    SAMPLE=$(basename "${SAMPLE_DIR}")
    BIN_ID=$(basename "${FA}" .fa)
    GID="${SAMPLE}__${BIN_ID}"
    echo -e "${GID}\tfungi\t${FA}" >> "${MANIFEST}"
    N_FUN=$((N_FUN+1))
done < <(find "${WORKDIR}/result/fungi/veba_qc" -mindepth 3 -maxdepth 3 -path '*/euk_mags/bin.*.fa' 2>/dev/null | sort)
echo "[cross_domain_ani] 真菌 euk MAG: ${N_FUN}"

N_TOTAL=$((N_BAC+N_VIR+N_FUN))
if [ ${N_TOTAL} -lt 2 ]; then
    echo "[cross_domain_ani] 可用基因组总数 < 2（${N_TOTAL}），无法进行两两 ANI 比对，写空结果"
    echo -e "genome_id\tdomain\tcluster_id" > "${CLUSTERS}"
    : > "${ANI_MATRIX}"
    echo "[cross_domain_ani] 完成，耗时 ${SECONDS}s（空结果）"
    exit 0
fi

cut -f3 "${MANIFEST}" | tail -n +2 > "${GENOME_LIST}"

# ── 步骤4：FastANI 批量比对（--ql/--rl 列表模式，全体两两比对）───────────────
echo "[cross_domain_ani] FastANI 批量比对: ${N_TOTAL} 个基因组 ..."
mgx_conda cluster \
    fastANI \
        --ql "${GENOME_LIST}" \
        --rl "${GENOME_LIST}" \
        -o "${ANI_MATRIX}" \
        -t "${CPUS}"

# ── 步骤5：networkx 建图 + Louvain 社区检测 ──────────────────────────────────
echo "[cross_domain_ani] networkx 建图 + Louvain 社区检测 ..."
mgx_conda cluster \
    python3 "${REPO}/scripts/98e_cross_domain_louvain.py" \
        --manifest "${MANIFEST}" \
        --ani-matrix "${ANI_MATRIX}" \
        --out "${CLUSTERS}"

N_CLUSTERS=$(tail -n +2 "${CLUSTERS}" | cut -f3 | sort -u | wc -l)
echo "[cross_domain_ani] 完成，耗时 ${SECONDS}s | 基因组: ${N_TOTAL} | 簇数: ${N_CLUSTERS}"
echo "[cross_domain_ani] 输出: ${CLUSTERS}"
