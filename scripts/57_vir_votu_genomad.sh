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

set -euo pipefail

show_help() { cat << EOF
用法: bash 57_vir_votu_genomad.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        --force) FORCE=1; shift ;;
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
GENOMAD_DB="${REPO}/db/genomad/genomad/genomad_db"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在: ${VOTU_FA}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${TAXONOMY}" ] && [ -s "${TAXONOMY}" ]; then echo "[votu_genomad] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

# geNomad 内部多处用 rsplit("_", N) 从基因名反推 contig 名（假设命名规则是
# {contig}_{geneNum}）。MEGAHIT 原始 contig ID 本身已含下划线（如 k127_116589），
# 叠加样本前缀"Sample10__k127_116589"后，这类按下划线拆分的逻辑会拆错位置，
# 导致 provirus 命名丢失前缀、summary 阶段回查 length_dict 时 KeyError。
# 为规避这一整类下划线解析假设，给 geNomad 专用一份完全不含下划线的编号
# （seq1/seq2/...），跑完后用严格的"整段替换"映射回原始带前缀 ID。
VOTU_FA_SAFE="${OUTDIR}/virus_safeid.fasta"
ID_MAP="${OUTDIR}/id_map.tsv"
awk '
    /^>/ {
        orig = substr($1, 2)
        safe = "seq" (++n)
        map[safe] = orig
        print ">" safe
        next
    }
    { print }
    END {
        for (k in map) print k "\t" map[k] > "'"${ID_MAP}"'"
    }
' "${VOTU_FA}" > "${VOTU_FA_SAFE}"

echo "[votu_genomad] vOTU 分类注释 ..."
conda run --prefix "${REPO}/envs/genomad" --no-capture-output \
    genomad end-to-end \
        --cleanup \
        --threads "${CPUS}" \
        --sensitivity 4.2 \
        --splits 4 \
        "${VOTU_FA_SAFE}" \
        "${OUTDIR}" \
        "${GENOMAD_DB}"

# 提取分类注释
TAXONOMY_SRC="${OUTDIR}/virus_safeid_summary/virus_safeid_virus_summary.tsv"
if [ ! -f "${TAXONOMY_SRC}" ]; then
    TAXONOMY_SRC="$(find "${OUTDIR}" -type f -path '*/*_summary/*_virus_summary.tsv' | head -n 1)"
fi
if [ -z "${TAXONOMY_SRC}" ] || [ ! -f "${TAXONOMY_SRC}" ]; then
    TAXONOMY_SRC="$(find "${OUTDIR}" -type f -name '*taxonomy.tsv' | head -n 1)"
fi
if [ -n "${TAXONOMY_SRC}" ] && [ -f "${TAXONOMY_SRC}" ]; then
    # seq_name 列可能是 "seqN" 或 "seqN|provirus_X_Y"，只替换 "|" 前的整段
    # safe ID，provirus 坐标后缀原样保留，避免子串误匹配
    awk -F'\t' 'NR==FNR {map[$1]=$2; next}
         FNR==1 {print; next}
         {
             split($1, parts, "|")
             if (parts[1] in map) {
                 $1 = map[parts[1]]
                 if (length(parts) > 1) $1 = $1 "|" parts[2]
             }
             print
         }' OFS='\t' \
        "${ID_MAP}" "${TAXONOMY_SRC}" > "${TAXONOMY}"
else
    echo "[WARN] 未找到 geNomad taxonomy 输出，跳过"
fi

rm -f "${VOTU_FA_SAFE}" "${ID_MAP}"  # 清理临时文件

echo "[votu_genomad] 完成，耗时 ${SECONDS}s"
