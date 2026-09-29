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

# --- T-16: aggregate gene-level TPM to CANONICAL vOTU identity -------------
# votu_id_map.tsv (from 56_vir_votu_gen.sh) is the single source of identity.
# gene "X_<digits>" -> contig X via the Prodigal naming rule (legitimate
# suffix), then contig -> representative vOTU strictly through the map.
ID_MAP="${WORKDIR}/result/virus/votu/votu_id_map.tsv"
JOIN_STATS="${OUTDIR}/votu_join_stats.tsv"

python3 - "${OUTDIR}/vOTU_table.txt" "${ID_MAP}" "${LEGACY_TABLE}" "${JOIN_STATS}" <<'PYINNER'
import sys, os, re
from collections import defaultdict

src, id_map_path, out_path, stats_path = sys.argv[1:5]
if not os.path.exists(id_map_path):
    sys.exit(f"[ERROR] votu_id_map.tsv not found: {id_map_path} (run 56_vir_votu_gen.sh first)")

# map: original_contig_id | cluster_id | representative_votu_id | sample_id | source_step
by_original = {}
by_bare = {}
ambiguous = set()
for line in open(id_map_path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 5:
        continue
    orig, _cluster, repr_id, _sample, _src = parts[:5]
    by_original[orig] = repr_id
    bare = orig.split("__", 1)[-1]
    if bare in by_bare and by_bare[bare] != repr_id:
        # one bare contig name mapping to two representatives: refuse to guess
        ambiguous.add(bare)
    by_bare[bare] = repr_id

def canonical(gene, sid):
    # gene/target -> canonical vOTU or None.
    # Order matters: salmon reports mix contig-level rows (k127_1717) with
    # gene-level rows (k127_1717_1). A bare contig id must be looked up as-is;
    # only fall back to stripping the Prodigal gene index when the raw name is
    # not itself a known contig. Never guess identity by suffix alone.
    if gene in by_original:
        return by_original[gene]
    if gene in by_bare:
        return None if gene in ambiguous else by_bare[gene]
    contig = re.sub(r"_[0-9]+$", "", gene)
    if contig in ambiguous:
        return None
    return by_bare.get(contig)

columns = []
with open(src) as fh:
    header = fh.readline().rstrip("\n").split("\t")
    for c in header[2:]:
        if c.endswith("_tpm"):
            pass
        columns.append(c)
    agg = defaultdict(lambda: defaultdict(float))
    lengths = {}
    failed, njoined = [], 0
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        gene = parts[0]
        votu = canonical(gene, "")
        if votu is None:
            failed.append(gene)
            continue
        njoined += 1
        if votu not in lengths:
            lengths[votu] = parts[1]
        for c, v in zip(columns, parts[2:]):
            try:
                agg[votu][c] += float(v)
            except ValueError:
                pass

with open(out_path, "w") as out:
    out.write("votu\tlength\t" + "\t".join(columns) + "\n")
    for votu in sorted(agg):
        vals = agg[votu]
        out.write(votu + "\t" + lengths.get(votu, "0") + "\t" +
                  "\t".join(f"{vals.get(c, 0.0):.10g}" for c in columns) + "\n")

with open(stats_path, "w") as st:
    st.write("metric\tvalue\n")
    st.write(f"joined_gene_rows\t{njoined}\n")
    st.write(f"join_failed_gene_rows\t{len(failed)}\n")
    st.write(f"canonical_votus\t{len(agg)}\n")
    for g in failed:
        st.write(f"join_failed_row\t{g}\n")
print(f"[votu_table] canonical aggregation: {len(agg)} vOTUs, joined={njoined}, join_failed={len(failed)} -> {stats_path}")
if failed:
    print("[votu_table] WARNING: join-failed rows are listed in " + stats_path, file=sys.stderr)
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
import sys, re
table, tax_path, id_map_path, out = sys.argv[1:5]
tax = {}
for line in open(tax_path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 5:
        tax[parts[0]] = parts[4].strip()          # lineage column

bare_to_repr = {}
for line in open(id_map_path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 5:
        bare_to_repr[parts[0].split("__", 1)[-1]] = parts[2]

def status_for(votu):
    contig = votu.split("__", 1)[-1]
    repr_id = bare_to_repr.get(contig, contig)
    lineage = None
    for key in (repr_id, contig, votu):
        if key in tax:
            lineage = tax[key]
            break
    if lineage is None:
        return "", "source_missing"
    if lineage == "" or lineage.lower() in ("unclassified", "na", "nan", "-"):
        return lineage, "source_truly_unclassified"
    return lineage, "annotated"

with open(table) as fh, open(out, "w") as fo:
    header = fh.readline().rstrip("\n")
    fo.write(header + "\ttaxonomy\tannotation_status\n")
    for line in fh:
        row = line.rstrip("\n").split("\t")
        lineage, status = status_for(row[0])
        fo.write(line.rstrip("\n") + "\t" + (lineage or "Unclassified") + "\t" + status + "\n")
PYANN
else
    cp "${OUTDIR}/vOTU_table.txt" "${SENTINEL}"
fi

# LEGACY_TABLE (votu_table.tsv) is written by the canonical aggregation above;
# consumers (98c/98g/93/96) expect canonical vOTU keys since T-16.

echo "[votu_table] 输出: ${OUTDIR}/"
mgx_end "votu_table"
