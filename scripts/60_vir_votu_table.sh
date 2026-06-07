#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 60_vir_votu_table.sh
# 功  能: 生成 vOTU 丰度矩阵 + 分类注释汇总表
#         工具版本：biostack/vtab-kit（conda env: assembly）
# 依  赖: 57_vir_votu_genomad.sh 的分类 + 59_vir_salmon_quant.sh 定量
# 输  入: samples.tsv（样本列表）+ Salmon 定量
# 输  出: ${WORKDIR}/result/virus/votu/table/
#           vOTU_table.txt        — 丰度矩阵
#           vOTU_table_ann.txt    — 带分类注释的丰度矩阵
#
# 参  考: Virus_Apptainer_pipline vOTU-table.sh
# 用  法: bash 60_vir_votu_table.sh -m SAMPLES_TSV -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 60_vir_votu_table.sh -m SAMPLES_TSV -w WORKDIR -r REPO
必需参数:
  -m  样本列表 TSV（每行一个样本 ID）
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

SAMPLES_TSV=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m) SAMPLES_TSV="$2"; shift 2 ;;
        -w) WORKDIR="$2";     shift 2 ;;
        -r) REPO="$2";        shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLES_TSV WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
OUTDIR="${WORKDIR}/result/virus/votu/table"
TAXONOMY="${WORKDIR}/result/virus/votu/genomad/virus_taxonomy.tsv"
REPORT_DIR="${WORKDIR}/result/virus/salmon"
SENTINEL="${OUTDIR}/vOTU_table_ann.txt"

if [ ! -f "${TAXONOMY}" ]; then echo "[WARN] 分类注释不存在，将生成无注释矩阵"; TAXONOMY=""; fi
if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[votu_table] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[votu_table] 生成 vOTU 丰度矩阵 ..."

# 收集所有样本的 Salmon report
FIRST=true
> "${OUTDIR}/vOTU_table.txt"
while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    REPORT="${REPORT_DIR}/${sid}/report.tsv"
    [ ! -f "$REPORT" ] && { echo "[WARN] 跳过 ${sid}: 无报告"; continue; }
    if [ "$FIRST" = true ]; then
        echo -e "gene\tlength\t${sid}_tpm\t${sid}_count" > "${OUTDIR}/vOTU_table.txt"
        tail -n +2 "$REPORT" | awk -v s="$sid" '{print $1"\t"$2"\t"$3"\t"$4}' >> "${OUTDIR}/vOTU_table.txt"
        FIRST=false
    else
        # 对齐 TPM 和 count
        # 简化：对每个报告输出 2 列
        awk -v s="$sid" 'NR==1{next} {
            if(NR==2) printf "gene\tlength\t%s_tpm\t%s_count\n", s, s
            else printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4
        }' "$REPORT" > "${OUTDIR}/_${sid}.tmp"
    fi
done < "${SAMPLES_TSV}"

# 加入分类注释
if [ -f "${TAXONOMY}" ] && [ -f "${OUTDIR}/vOTU_table.txt" ]; then
    python3 -c "
import sys
tax = {}
with open('${TAXONOMY}') as f:
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 2: tax[parts[0]] = parts[1]
with open('${OUTDIR}/vOTU_table.txt') as f:
    header = f.readline().strip()
    print(header + '\ttaxonomy')
    for line in f:
        g = line.split('\t')[0]
        t = tax.get(g, 'Unclassified')
        print(line.strip() + '\t' + t)
" > "${SENTINEL}"
else
    cp "${OUTDIR}/vOTU_table.txt" "${SENTINEL}"
fi

echo "[votu_table] 完成，耗时 ${SECONDS}s | 输出: ${OUTDIR}/"
