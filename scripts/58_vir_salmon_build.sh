#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 58_vir_salmon_build.sh
# 功  能: 构建 vOTU 定量索引（Salmon index，gentrome+decoy）
#         工具版本：Salmon 1.10+（conda env: assembly）
# 依  赖: 56_vir_votu_gen.sh（vOTU 代表序列）
#         55_vir_prodigal_gv.sh 的基因核酸序列
# 输  入: vOTU 序列 + 所有样本病毒 CDS（.ffn）
# 输  出: ${WORKDIR}/result/virus/salmon/index/
#
# ── 索引策略 ─────────────────────────────────────────────────────
#   gentrome = CDS ffns + vOTU fna; decoy = vOTU fna
#   该索引同时支持基因级和 contig 级定量
#
# 参  考: Patro et al. 2017 Nat Methods (Salmon)
# 用  法: bash 58_vir_salmon_build.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 58_vir_salmon_build.sh -t CPUS -w WORKDIR -r REPO
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
INDEX_DIR="${WORKDIR}/result/virus/salmon/index"
SENTINEL="${INDEX_DIR}/info.json"

if [ ! -f "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在: ${VOTU_FA}"; exit 1; fi
if [ -f "${SENTINEL}" ]; then echo "[salmon_build] 索引已存在，跳过"; exit 0; fi

mkdir -p "${INDEX_DIR}"

echo "[salmon_build] 准备 gentrome + decoy ..."
# 收集所有病毒 CDS (ffn)
ALL_FFN="${INDEX_DIR}/virus_cds.ffn"
> "${ALL_FFN}"
for f in "${WORKDIR}"/result/virus/prodigal/*/*.fna; do
    [ -f "$f" ] && cat "$f" >> "${ALL_FFN}"
done

# gentrome = CDS + vOTU
cat "${ALL_FFN}" "${VOTU_FA}" > "${INDEX_DIR}/gentrome.fasta"
# decoy = vOTU only
grep '^>' "${VOTU_FA}" | sed 's/^>//' > "${INDEX_DIR}/decoys.txt"

if [ ! -s "${INDEX_DIR}/decoys.txt" ]; then
    echo "[salmon_build] WARN: decoys.txt 为空（可能是测试数据无病毒序列）"
    echo "       跳过 decoy，仅构建标准 index"
    conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        salmon index \
            -t "${INDEX_DIR}/gentrome.fasta" \
            -i "${INDEX_DIR}" \
            -p "${CPUS}" \
            --keepDuplicates
else
    conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        salmon index \
            -t "${INDEX_DIR}/gentrome.fasta" \
            -d "${INDEX_DIR}/decoys.txt" \
            -i "${INDEX_DIR}" \
            -p "${CPUS}" \
            --keepDuplicates
fi

echo "[salmon_build] 完成，耗时 ${SECONDS}s"
