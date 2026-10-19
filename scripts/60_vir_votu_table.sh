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

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 60_vir_votu_table.sh [-m SAMPLES_TSV] [-t CPUS] -w WORKDIR -r REPO
必需参数:
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
可选参数:
  -m  样本列表 TSV（每行一个样本 ID，默认: WORKDIR/samples.txt）
  -t  线程数（兼容旧接口，当前未使用）
EOF
}

SAMPLES_TSV=""  # 可选参数默认值（未传 -m 时下方回退到 WORKDIR/samples.txt）

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="m:SAMPLES_TSV t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO
if [ -z "${SAMPLES_TSV}" ]; then
    SAMPLES_TSV="${WORKDIR}/samples.txt"
fi
if [ ! -f "${SAMPLES_TSV}" ]; then
    echo "[ERROR] 样本列表不存在: ${SAMPLES_TSV}"
    exit 1
fi

mgx_begin
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
        # 质量审核 2026-10-13 P1：缺样本报告即硬失败，不再整列补 0 静默通过
        sys.exit(f"[ERROR] {sid} 缺 report.tsv（先运行 59 号）: {report}")
    with open(report) as f:
        for i, line in enumerate(f):
            if i == 0:
                # 59 号 report.tsv 无表头（数据行开头）；仅当首行第二列非数值时才视为表头跳过
                first = line.rstrip("\n").split("\t")
                if len(first) > 1 and not first[1].replace(".", "", 1).isdigit():
                    continue
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
    f.write("contig\tlength\t" + "\t".join(cols) + "\n")
    for gene in gene_order:
        vals = tables[gene]
        row = [gene, vals.get("length", "0")] + [vals.get(c, "0") for c in cols]
        f.write("\t".join(row) + "\n")

print(f"[votu_table] 写入 {len(gene_order)} 个 vOTU，{len(samples)} 个样本")
PYEOF

# Clean up any leftover tmp files from previous partial runs
rm -f "${OUTDIR}"/_*.tmp

# --- T-16: aggregate CONTIG-level TPM to CANONICAL vOTU identity -------------
# 用户拍板 2026-10-13（D）：vOTU 丰度只用 contig 级行（一条 vOTU 一个数），
# 基因级行不再计入（旧实现把 contig 级与基因级 TPM 混加，vOTU 间不可比）。
# length 列取代表 contig 自身序列长度（旧实现取"第一条归入行"导致 66 bp 假 vOTU）。
# contig 级行无法归属时硬失败（旧实现仅 stderr 警告后 exit 0）。
ID_MAP="${WORKDIR}/result/virus/votu/votu_id_map.tsv"
MEMBERS_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
JOIN_STATS="${OUTDIR}/votu_join_stats.tsv"

python3 - "${OUTDIR}/vOTU_table.txt" "${ID_MAP}" "${MEMBERS_FA}" "${LEGACY_TABLE}" "${JOIN_STATS}" <<'PYINNER'
import sys, os
from collections import defaultdict

src, id_map_path, members_fa, out_path, stats_path = sys.argv[1:6]
if not os.path.exists(id_map_path):
    sys.exit(f"[ERROR] votu_id_map.tsv not found: {id_map_path} (run 56_vir_votu_gen.sh first)")

# map: original_contig_id | cluster_id | representative_votu_id | sample_id | source_step
by_original = {}
for line in open(id_map_path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 5:
        by_original[parts[0]] = parts[2]

# length 正源：代表 contig 自身长度（代表也是 member，members FASTA 必有）
member_len = {}
name, buf = None, 0
for line in open(members_fa):
    if line.startswith(">"):
        if name is not None:
            member_len[name] = buf
        fields = line[1:].split()
        name = fields[0] if fields else ""
        buf = 0
    else:
        buf += len(line.strip())
if name is not None:
    member_len[name] = buf

with open(src) as fh:
    header = fh.readline().rstrip("\n").split("\t")
    columns = header[2:]
    agg = defaultdict(lambda: defaultdict(float))
    joined = failed = gene_rows = 0
    failed_rows = []
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        cid = parts[0]
        # 基因行判定（质量审核 2026-10-13 P1）：基因 ID 形如 样本|contig_N（| 在任何
        # __ 之前）；contig 行形如 样本__contig[|provirus...]（先有 __ 再可能有 |）
        head_part = cid.split("__", 1)[0]
        is_gene_row = "|" in head_part
        if cid in by_original:
            votu = by_original[cid]
            joined += 1
            for c, v in zip(columns, parts[2:]):
                try:
                    agg[votu][c] += float(v)
                except ValueError:
                    pass
        elif is_gene_row:
            # 基因级行：按拍板 D 不计入
            gene_rows += 1
        else:
            # 形如 contig 级 ID 却无法归属：不允许静默丢弃
            failed += 1
            failed_rows.append(cid)

with open(stats_path, "w") as st:
    st.write("metric\tvalue\n")
    st.write(f"joined_contig_rows\t{joined}\n")
    st.write(f"gene_rows_skipped_by_design\t{gene_rows}\n")
    st.write(f"failed_contig_rows\t{failed}\n")
    st.write(f"canonical_votus\t{len(agg)}\n")
    for c in failed_rows:
        st.write(f"join_failed_row\t{c}\n")

if failed > 0:
    sys.exit(f"[ERROR] {failed} contig-level rows failed to map (see {stats_path}); "
             f"refusing to silently drop rows")

with open(out_path, "w") as out:
    out.write("votu\tlength\t" + "\t".join(columns) + "\n")
    for votu in sorted(agg):
        vals = agg[votu]
        out.write(votu + "\t" + str(member_len.get(votu, 0)) + "\t" +
                  "\t".join(f"{vals.get(c, 0.0):.10g}" for c in columns) + "\n")

print(f"[votu_table] contig-level aggregation: {len(agg)} vOTUs, joined={joined}, "
      f"gene_rows_skipped={gene_rows}, failed={failed} -> {stats_path}")
PYINNER


# 加入分类注释 (T-17 four-state join)
# geNomad taxonomy.tsv columns: seq_name | n_genes | agreement | taxid | lineage.
# The old join read column 2 (a gene count) and keyed on gene-level rows, so
# nearly every row came out 'Unclassified'. Now: canonical vOTU rows are
# annotated via their representative contig (through votu_id_map.tsv), with an
# explicit annotation_status column so 'truly unclassified' is never confused
# with 'join failed'.
if [ -f "${TAXONOMY}" ] && [ -f "${OUTDIR}/vOTU_table.txt" ]; then
    python3 - "${LEGACY_TABLE}" "${TAXONOMY}" "${ID_MAP}" "${SENTINEL}" <<'PYANN'
import sys

table, tax_path, id_map_path, out = sys.argv[1:5]

# 分类列按表头名取（质量审核 2026-10-13 P0-2：旧代码写死 parts[4]，取到的
# 是 n_genes 而非 taxonomy，2,529 行被标成假 annotated）
tax = {}
with open(tax_path) as fh:
    header = fh.readline().rstrip("\n").split("\t")
    try:
        tcol = header.index("taxonomy")
    except ValueError:
        tcol = 10  # 回退：taxonomy 为第 11 列
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) > tcol:
            tax[parts[0]] = parts[tcol].strip()

# 代表关系只用完整 ID（旧代码先查"去样本前缀"表，跨样本重名会拿错分类）
repr_of = {}
for line in open(id_map_path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 5:
        repr_of[parts[0]] = parts[2]

def status_for(votu):
    lineage = None
    for key in (votu, repr_of.get(votu, votu)):
        if key in tax:
            lineage = tax[key]
            break
    if lineage is None:
        return "", "source_missing"
    if lineage == "" or lineage.lower() in ("unclassified", "na", "nan", "-"):
        return lineage, "source_truly_unclassified"
    return lineage, "annotated"

# 输出列名用 lineage（质量审核 P0-3：91/92 的 R 代码按 lineage 列名读取）
with open(table) as fh, open(out, "w") as fo:
    header = fh.readline().rstrip("\n")
    fo.write(header + "\tlineage\tannotation_status\n")
    for line in fh:
        row = line.rstrip("\n").split("\t")
        lineage, status = status_for(row[0])
        fo.write(line.rstrip("\n") + "\t" + (lineage or "Unclassified") + "\t" + status + "\n")
PYANN
else
    # 无分类文件时哨兵与正常分支同构（质量审核 P1：旧代码复制的是基因+contig 混合中间表）
    cp "${LEGACY_TABLE}" "${SENTINEL}"
fi

# LEGACY_TABLE (votu_table.tsv) is written by the canonical aggregation above;
# consumers (98c/98g/93/96) expect canonical vOTU keys since T-16.

echo "[votu_table] 输出: ${OUTDIR}/"
mgx_end "votu_table"
