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
用法: bash 60_vir_votu_table.sh [-m SAMPLES_TSV] [-t CPUS] -w WORKDIR -r REPO
必需参数:
  -w  工作目录
  -r  MaxMetagenome 项目根目录
可选参数:
  -m  样本列表 TSV（每行一个样本 ID，默认: WORKDIR/samples.txt）
  -t  线程数（兼容旧接口，当前未使用）
EOF
}

SAMPLES_TSV=""; WORKDIR=""; _REPO=""; _CPUS=""; FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m) SAMPLES_TSV="$2"; shift 2 ;;
        -t) _CPUS="$2";      shift 2 ;;
        -w) WORKDIR="$2";     shift 2 ;;
        -r) _REPO="$2";       shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        -) case "${OPTARG}" in
               *) echo "[ERROR] 未知参数: --${OPTARG}"; exit 1 ;;
           esac ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done
if [ -z "${SAMPLES_TSV}" ]; then
    SAMPLES_TSV="${WORKDIR}/samples.txt"
fi
if [ ! -f "${SAMPLES_TSV}" ]; then
    echo "[ERROR] 样本列表不存在: ${SAMPLES_TSV}"
    exit 1
fi

SECONDS=0
OUTDIR="${WORKDIR}/result/virus/votu/table"
TAXONOMY="${WORKDIR}/result/virus/votu/genomad/virus_taxonomy.tsv"
REPORT_DIR="${WORKDIR}/result/virus/salmon"
SENTINEL="${OUTDIR}/vOTU_table_ann.txt"
LEGACY_TABLE="${WORKDIR}/result/virus/votu/votu_table.tsv"

if [ ! -f "${TAXONOMY}" ]; then echo "[WARN] 分类注释不存在，将生成无注释矩阵"; TAXONOMY=""; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[votu_table] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[votu_table] 生成 vOTU 丰度矩阵 ..."

# Read all per-sample Salmon report.tsv files and merge by gene into one matrix
python3 - "${SAMPLES_TSV}" "${REPORT_DIR}" "${OUTDIR}/vOTU_table.txt" <<'PYEOF'
import sys, os

samples_tsv, report_dir, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
samples = [l.strip() for l in open(samples_tsv) if l.strip()]

# gene -> {length, S01_tpm, S01_count, ...}
tables = {}
gene_order = []

for sid in samples:
    report = os.path.join(report_dir, sid, "report.tsv")
    if not os.path.exists(report):
        print(f"[WARN] 跳过 {sid}: 无报告文件", file=sys.stderr)
        continue
    with open(report) as f:
        for i, line in enumerate(f):
            if i == 0:
                continue  # skip header
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            gene, length, tpm, count = parts[0], parts[1], parts[2], parts[3]
            if gene not in tables:
                tables[gene] = {"length": length}
                gene_order.append(gene)
            tables[gene][f"{sid}_tpm"] = tpm
            tables[gene][f"{sid}_count"] = count

# Write merged matrix: gene length S01_tpm S01_count S02_tpm S02_count ...
cols = []
for sid in samples:
    cols += [f"{sid}_tpm", f"{sid}_count"]

with open(out_file, "w") as f:
    f.write("gene\tlength\t" + "\t".join(cols) + "\n")
    for gene in gene_order:
        vals = tables[gene]
        row = [gene, vals.get("length", "0")] + [vals.get(c, "0") for c in cols]
        f.write("\t".join(row) + "\n")

print(f"[votu_table] 写入 {len(gene_order)} 个 vOTU，{len(samples)} 个样本")
PYEOF

# Clean up any leftover tmp files from previous partial runs
rm -f "${OUTDIR}"/_*.tmp

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

# Maintain the legacy path expected by integration and older wrappers.
cp "${OUTDIR}/vOTU_table.txt" "${LEGACY_TABLE}"

echo "[votu_table] 完成，耗时 ${SECONDS}s | 输出: ${OUTDIR}/"
