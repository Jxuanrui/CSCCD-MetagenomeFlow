#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98d_fun_integration_tables.sh
# 功  能: 真菌维度功能整合 — 生成基于基因计数的整合表格及标准化结果
#
#   类型 A (6 张): 功能聚合表 (行=功能条目, 列=样本, 值=基因数)
#     1. kegg_ko_gene_count.tsv          KEGG KO × 样本
#     2. cog_gene_count.tsv              COG category × 样本
#     3. cazyme_gene_count.tsv           CAZyme family × 样本
#     4. vfdb_gene_count.tsv             Virulence factor × 样本
#     5. amr_gene_count.tsv              ARG symbol × 样本
#     6. merops_family_gene_count.tsv    MEROPS family × 样本
#
#   类型 B (1 张): 基因级宽表
#     7. gene_annotation_matrix.tsv      gene × (样本存在性 + 多类注释)
#
#   类型 C (1 张): FunOMIC 物种丰度整合摘要
#     8. funomic_integrated_summary.tsv  species × (样本读数 + 相对丰度 + top_pathway)
#
#   衍生标准化输出:
#     - normalized/*_relab.tsv           类型 A 表的相对丰度
#     - normalized/*_clr.tsv             类型 A 表的 CLR (epsilon=0.01)
#     - normalized/funomic_species_relab.tsv
#     - funomic_species_clr.tsv
#
# 依  赖:
#   - result/fungi/prodigal/{sample}/{sample}.faa
#   - result/fungi/eggnog/eggnog.emapper.annotations
#   - result/fungi/dbcan/overview.txt
#   - result/fungi/vfdb/vfdb_hits.tsv
#   - result/fungi/amr/amrfinder_results.tsv
#   - result/fungi/merops/merops_hits.tsv
#   - result/integration/fungi/funomic_species_count.tsv
#   - result/fungi/humann4/{sample}/{sample}_fungi_funomic_pathway.tsv
#   - db/merops/misc/prot2family.txt
#
# 输  出: ${WORKDIR}/result/integration/fungi/
# 用  法: bash 98d_fun_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 98d_fun_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  -t  线程数（默认 4，Python 脚本暂未并行化）
  -h  显示帮助
EOF
}

CPUS=4

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

# --- 路径定义 ---
FUNGI_DIR="${WORKDIR}/result/fungi"
PRODIGAL_DIR="${FUNGI_DIR}/prodigal"
OUT_DIR="${WORKDIR}/result/integration/fungi"
NORM_DIR="${OUT_DIR}/normalized"
MEROPS_MAP="${REPO}/db/merops/misc/prot2family.txt"
MAIN_MATRIX="${OUT_DIR}/gene_annotation_matrix.tsv"
FUNOMIC_SUMMARY="${OUT_DIR}/funomic_integrated_summary.tsv"
FUNOMIC_RELAB="${NORM_DIR}/funomic_species_relab.tsv"
FUNOMIC_CLR="${OUT_DIR}/funomic_species_clr.tsv"

# 幂等检查
if [ ${FORCE} -eq 0 ] && [ -f "${MAIN_MATRIX}" ] && [ -f "${FUNOMIC_SUMMARY}" ] && [ -f "${FUNOMIC_RELAB}" ] && [ -f "${FUNOMIC_CLR}" ]; then
    echo "[INFO] 整合表和 FunOMIC 摘要已存在，跳过。如需重建请先删除 ${OUT_DIR}"
    exit 0
fi

mkdir -p "${OUT_DIR}" "${NORM_DIR}"

# --- 检查至少有一个 FAA 文件 ---
FAA_FOUND=$(find "${PRODIGAL_DIR}" -mindepth 2 -maxdepth 2 -name "*.faa" 2>/dev/null | wc -l)
if [ ! -f "${MAIN_MATRIX}" ] && [ "${FAA_FOUND}" -eq 0 ]; then
    echo "[ERROR] 未找到真菌 Prodigal FAA 文件: ${PRODIGAL_DIR}"
    exit 1
fi

echo "[integration] 开始真菌维度功能整合"
echo "[integration] 输出目录: ${OUT_DIR}"
if [ -f "${MAIN_MATRIX}" ]; then
    echo "[integration] 主整合表已存在，将仅补齐缺失的 FunOMIC 输出"
else
    echo "[integration] 找到 ${FAA_FOUND} 个 FAA 文件"
fi

# ==============================================================================
# Python 整合主逻辑
# ==============================================================================

export OMP_NUM_THREADS="${CPUS}"
export OPENBLAS_NUM_THREADS="${CPUS}"
mgx_conda assembly python3 - \
    "${WORKDIR}" \
    "${REPO}" \
    "${OUT_DIR}" \
    "${NORM_DIR}" \
    "${MEROPS_MAP}" \
<<'PYEOF'
import sys
import os
import csv
import glob
import re
import math
from collections import defaultdict

WORKDIR = sys.argv[1]
REPO = sys.argv[2]
OUT_DIR = sys.argv[3]
NORM_DIR = sys.argv[4]
MEROPS_MAP = sys.argv[5]

FUNGI_DIR = os.path.join(WORKDIR, "result", "fungi")
PRODIGAL_DIR = os.path.join(FUNGI_DIR, "prodigal")

EGGNOG_FILE = os.path.join(FUNGI_DIR, "eggnog", "eggnog.emapper.annotations")
DBCAN_FILE = os.path.join(FUNGI_DIR, "dbcan", "overview.txt")
VFDB_FILE = os.path.join(FUNGI_DIR, "vfdb", "vfdb_hits.tsv")
AMR_FILE = os.path.join(FUNGI_DIR, "amr", "amrfinder_results.tsv")
MEROPS_FILE = os.path.join(FUNGI_DIR, "merops", "merops_hits.tsv")
MAIN_MATRIX = os.path.join(OUT_DIR, "gene_annotation_matrix.tsv")
FUNOMIC_COUNT_FILE = os.path.join(OUT_DIR, "funomic_species_count.tsv")
FUNOMIC_RELAB_FILE = os.path.join(NORM_DIR, "funomic_species_relab.tsv")
FUNOMIC_CLR_FILE = os.path.join(OUT_DIR, "funomic_species_clr.tsv")
FUNOMIC_SUMMARY_FILE = os.path.join(OUT_DIR, "funomic_integrated_summary.tsv")


def warn(msg):
    print(f"[WARN] {msg}")


def fmt_float(val, digits=6):
    return f"{val:.{digits}f}"


def table_shape(path):
    with open(path) as fh:
        first = fh.readline()
        if not first:
            return 0, 0
        ncols = len(first.rstrip("\n").split("\t"))
        nrows = sum(1 for _ in fh)
    return nrows, ncols


def write_matrix(path, header, row_names, matrix, samples):
    with open(path, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        for row_name in row_names:
            writer.writerow([row_name] + [fmt_float(matrix[row_name].get(sample, 0.0)) for sample in samples])


def normalize_to_relab(raw_matrix, row_names, samples):
    relab = defaultdict(dict)
    for sample in samples:
        col_sum = sum(raw_matrix[row].get(sample, 0.0) for row in row_names)
        for row in row_names:
            value = raw_matrix[row].get(sample, 0.0)
            relab[row][sample] = (value / col_sum) if col_sum > 0 else 0.0
    return relab


def relab_to_clr(relab_matrix, row_names, samples, eps=0.01):
    clr = defaultdict(dict)
    for sample in samples:
        logs = [math.log(relab_matrix[row].get(sample, 0.0) + eps) for row in row_names]
        mean_log = sum(logs) / len(logs) if logs else 0.0
        for row, log_val in zip(row_names, logs):
            clr[row][sample] = log_val - mean_log
    return clr


def normalize_table(infile, relab_out, clr_out):
    row_names = []
    raw = defaultdict(dict)
    with open(infile) as fh:
        reader = csv.reader(fh, delimiter="\t")
        header = next(reader, None)
        if not header:
            return
        local_samples = header[1:]
        for row in reader:
            if not row:
                continue
            feature = row[0]
            row_names.append(feature)
            for sample, value in zip(local_samples, row[1:]):
                try:
                    raw[feature][sample] = float(value)
                except ValueError:
                    raw[feature][sample] = 0.0

    relab = normalize_to_relab(raw, row_names, local_samples)
    clr = relab_to_clr(relab, row_names, local_samples, eps=0.01)
    write_matrix(relab_out, header, row_names, relab, local_samples)
    write_matrix(clr_out, header, row_names, clr, local_samples)

    relab_rows, relab_cols = table_shape(relab_out)
    clr_rows, clr_cols = table_shape(clr_out)
    print(f"  → {os.path.basename(relab_out)}: {relab_rows} 行 × {relab_cols} 列")
    print(f"  → {os.path.basename(clr_out)}: {clr_rows} 行 × {clr_cols} 列")


def read_numeric_matrix(infile):
    row_names = []
    raw = defaultdict(dict)
    with open(infile) as fh:
        reader = csv.reader(fh, delimiter="\t")
        header = next(reader, None)
        if not header:
            return [], [], raw
        local_samples = header[1:]
        for row in reader:
            if not row:
                continue
            feature = row[0].strip()
            if not feature:
                continue
            row_names.append(feature)
            for sample, value in zip(local_samples, row[1:]):
                try:
                    raw[feature][sample] = float(value)
                except ValueError:
                    raw[feature][sample] = 0.0
            for sample in local_samples[len(row) - 1:]:
                raw[feature][sample] = 0.0
    return row_names, local_samples, raw


def fmt_count(val):
    return str(int(val)) if float(val).is_integer() else fmt_float(val)


def compute_clr_from_count_table(infile, clr_out):
    row_names, local_samples, raw = read_numeric_matrix(infile)
    relab = normalize_to_relab(raw, row_names, local_samples)
    clr = relab_to_clr(relab, row_names, local_samples, eps=0.01)
    write_matrix(clr_out, ["species"] + local_samples, row_names, clr, local_samples)
    clr_rows, clr_cols = table_shape(clr_out)
    print(f"  → {os.path.basename(clr_out)}: {clr_rows} 行 × {clr_cols} 列")


def add_label(mapping, gene, label):
    if not gene or not label or label == "-":
        return
    if gene in mapping and mapping[gene] != "-":
        labels = [x.strip() for x in mapping[gene].split(",") if x.strip() and x.strip() != "-"]
        if label not in labels:
            labels.append(label)
        mapping[gene] = ",".join(labels)
    else:
        mapping[gene] = label


def parse_faa_gene_ids(path):
    gene_ids = set()
    with open(path) as fh:
        for line in fh:
            if not line.startswith(">"):
                continue
            token = line[1:].strip().split()[0]
            if token:
                gene_ids.add(token)
    return gene_ids


def make_count_table(func_map, sample_genes, samples, outpath, func_col_name):
    """
    func_map: gene_id → function_label (str, 可含逗号分隔多功能)
    输出: function_label × sample 的基因计数矩阵
    """
    func_count = defaultdict(lambda: defaultdict(int))
    sample_gene_sets = {sample: sample_genes.get(sample, set()) for sample in samples}

    for gene, funcs in func_map.items():
        if not funcs or funcs == "-":
            continue
        for func in funcs.split(","):
            func = func.strip()
            if not func or func == "-":
                continue
            for sample in samples:
                if gene in sample_gene_sets[sample]:
                    func_count[func][sample] += 1

    with open(outpath, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow([func_col_name] + samples)
        for func in sorted(func_count):
            writer.writerow([func] + [str(func_count[func].get(sample, 0)) for sample in samples])

    n = len(func_count)
    print(f"  → {os.path.basename(outpath)}: {n} 行 × {len(samples)+1} 列")
    return func_count


def load_sample_top_pathways(samples):
    sample_top = {}
    global_counts = defaultdict(float)
    for sample in samples:
        path = os.path.join(FUNGI_DIR, "humann4", sample, f"{sample}_fungi_funomic_pathway.tsv")
        if not os.path.isfile(path):
            warn(f"缺少 FunOMIC pathway 文件，样本 {sample} 将无 top_pathway: {path}")
            continue

        pathway_counts = defaultdict(float)
        with open(path) as fh:
            reader = csv.reader(fh, delimiter="\t")
            for row in reader:
                if len(row) < 2:
                    continue
                pathway = row[0].strip()
                try:
                    count = float(row[1])
                except ValueError:
                    continue
                if not pathway:
                    continue
                pathway_counts[pathway] += count
                global_counts[pathway] += count

        if pathway_counts:
            sample_top[sample] = max(pathway_counts.items(), key=lambda item: (item[1], item[0]))[0]
            print(f"  {sample}: top_pathway={sample_top[sample]}")
        else:
            warn(f"FunOMIC pathway 文件无有效计数，样本 {sample}: {path}")

    global_top = max(global_counts.items(), key=lambda item: (item[1], item[0]))[0] if global_counts else "-"
    return sample_top, global_top


def build_funomic_summary():
    row_names, local_samples, raw = read_numeric_matrix(FUNOMIC_COUNT_FILE)
    if not local_samples:
        warn(f"FunOMIC 物种计数矩阵为空，跳过摘要: {FUNOMIC_COUNT_FILE}")
        return

    sample_totals = {
        sample: sum(raw[row].get(sample, 0.0) for row in row_names)
        for sample in local_samples
    }
    sample_top_pathways, global_top_pathway = load_sample_top_pathways(local_samples)

    header = (
        ["species", "total_reads"]
        + [f"{sample}_count" for sample in local_samples]
        + [f"{sample}_relab_percent" for sample in local_samples]
        + ["top_pathway"]
    )

    with open(FUNOMIC_SUMMARY_FILE, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        for species in row_names:
            counts = [raw[species].get(sample, 0.0) for sample in local_samples]
            total_reads = sum(counts)
            relab_percent = [
                (raw[species].get(sample, 0.0) / sample_totals[sample] * 100.0)
                if sample_totals[sample] > 0 else 0.0
                for sample in local_samples
            ]
            best_sample = local_samples[counts.index(max(counts))] if counts else ""
            top_pathway = sample_top_pathways.get(best_sample, global_top_pathway)
            writer.writerow(
                [species, fmt_count(total_reads)]
                + [fmt_count(value) for value in counts]
                + [fmt_float(value) for value in relab_percent]
                + [top_pathway]
            )

    nrows, ncols = table_shape(FUNOMIC_SUMMARY_FILE)
    print(f"  → {os.path.basename(FUNOMIC_SUMMARY_FILE)}: {nrows} 行 × {ncols} 列")


def run_funomic_step():
    print("\n[Step6] FunOMIC 物种丰度标准化验证与整合摘要")

    if not os.path.isfile(FUNOMIC_COUNT_FILE):
        warn(f"缺少 FunOMIC 物种计数矩阵，跳过 Step6: {FUNOMIC_COUNT_FILE}")
        return

    count_rows, count_cols = table_shape(FUNOMIC_COUNT_FILE)
    print(f"  → funomic_species_count.tsv: {count_rows} 行 × {count_cols} 列")

    if os.path.isfile(FUNOMIC_RELAB_FILE):
        relab_rows, relab_cols = table_shape(FUNOMIC_RELAB_FILE)
        print(f"  → normalized/funomic_species_relab.tsv 已存在: {relab_rows} 行 × {relab_cols} 列")
    else:
        print("  normalized/funomic_species_relab.tsv 不存在，从计数矩阵计算 relab/CLR")
        normalize_table(FUNOMIC_COUNT_FILE, FUNOMIC_RELAB_FILE, FUNOMIC_CLR_FILE)

    if os.path.isfile(FUNOMIC_CLR_FILE):
        clr_rows, clr_cols = table_shape(FUNOMIC_CLR_FILE)
        print(f"  → funomic_species_clr.tsv 已存在: {clr_rows} 行 × {clr_cols} 列")
    else:
        print("  funomic_species_clr.tsv 不存在，从计数矩阵计算 CLR")
        compute_clr_from_count_table(FUNOMIC_COUNT_FILE, FUNOMIC_CLR_FILE)

    if os.path.isfile(FUNOMIC_SUMMARY_FILE):
        summary_rows, summary_cols = table_shape(FUNOMIC_SUMMARY_FILE)
        print(f"  → funomic_integrated_summary.tsv 已存在: {summary_rows} 行 × {summary_cols} 列，跳过重建")
        return

    build_funomic_summary()


def print_summary_report():
    print("\n" + "="*70)
    print("[integration] 完成！输出目录:", OUT_DIR)
    print("="*70)
    for root, dirs, files in os.walk(OUT_DIR):
        dirs.sort()
        for fname in sorted(files):
            fpath = os.path.join(root, fname)
            relpath = os.path.relpath(fpath, OUT_DIR)
            try:
                nrows, ncols = table_shape(fpath)
            except OSError:
                continue
            size_kb = os.path.getsize(fpath) / 1024.0
            print(f"  {relpath:<55s}  {nrows:>6} 行 × {ncols:>3} 列  ({size_kb:.1f} KB)")


TYPE_A_FILES = [
    os.path.join(OUT_DIR, "kegg_ko_gene_count.tsv"),
    os.path.join(OUT_DIR, "cog_gene_count.tsv"),
    os.path.join(OUT_DIR, "cazyme_gene_count.tsv"),
    os.path.join(OUT_DIR, "vfdb_gene_count.tsv"),
    os.path.join(OUT_DIR, "amr_gene_count.tsv"),
    os.path.join(OUT_DIR, "merops_family_gene_count.tsv"),
]

if os.path.isfile(MAIN_MATRIX) and all(os.path.isfile(f) for f in TYPE_A_FILES):
    print("[INFO] gene_annotation_matrix.tsv 和 6 个类型 A 表均已存在，跳过 Step1-Step5")
    run_funomic_step()
    print_summary_report()
    sys.exit(0)
elif os.path.isfile(MAIN_MATRIX):
    print("[WARN] gene_annotation_matrix.tsv 存在但类型 A 表不完整，删除后重建")
    os.remove(MAIN_MATRIX)


# ──────────────────────────────────────────────────────────────────────────────
# Step 1: 读取每个样本的 Prodigal FAA 基因集合
# ──────────────────────────────────────────────────────────────────────────────
print("[Step1] 读取真菌 Prodigal FAA 基因集合")

sample_genes = {}
samples = []

for sample_dir in sorted(glob.glob(os.path.join(PRODIGAL_DIR, "*"))):
    if not os.path.isdir(sample_dir):
        continue
    sample = os.path.basename(sample_dir)
    faa = os.path.join(sample_dir, f"{sample}.faa")
    if not os.path.isfile(faa):
        warn(f"缺少样本 FAA，跳过样本 {sample}: {faa}")
        continue
    genes = parse_faa_gene_ids(faa)
    sample_genes[sample] = genes
    samples.append(sample)
    print(f"  {sample}: {len(genes)} 基因")

if not samples:
    print("[ERROR] 未解析到任何样本 FAA 基因")
    sys.exit(1)

all_genes = sorted(set().union(*sample_genes.values()))
print(f"  样本: {samples}")
print(f"  合并基因数: {len(all_genes)}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 2: 解析功能注释文件
# ──────────────────────────────────────────────────────────────────────────────
print("[Step2] 解析功能注释文件")

gene_ko = {}
gene_cog = {}
gene_cazyme = {}
gene_vf = {}
gene_amr = {}
gene_merops_family = {}

if os.path.isfile(EGGNOG_FILE):
    with open(EGGNOG_FILE) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 12:
                continue
            gene = parts[0].strip()
            cog = parts[6].strip() if len(parts) > 6 else "-"
            ko = parts[11].strip() if len(parts) > 11 else "-"
            if gene and cog and cog != "-":
                gene_cog[gene] = cog
            if gene and ko and ko != "-":
                kos = []
                for item in ko.split(","):
                    item = item.strip()
                    if item and item != "-":
                        kos.append(item.replace("ko:", ""))
                if kos:
                    gene_ko[gene] = ",".join(kos)
    print(f"  eggNOG: KO覆盖 {len(gene_ko)} 基因, COG覆盖 {len(gene_cog)} 基因")
else:
    warn(f"缺少 eggNOG 文件，跳过 KO/COG 表: {EGGNOG_FILE}")

if os.path.isfile(DBCAN_FILE):
    with open(DBCAN_FILE) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            gene = (row.get("Gene ID") or "").strip()
            diamond = (row.get("DIAMOND") or "-").strip()
            hmmer = (row.get("HMMER") or "-").strip()
            label = diamond if diamond != "-" else hmmer
            if gene and label and label != "-":
                gene_cazyme[gene] = label
    print(f"  dbCAN: {len(gene_cazyme)} 基因")
else:
    warn(f"缺少 dbCAN 文件，跳过 CAZyme 表: {DBCAN_FILE}")

if os.path.isfile(VFDB_FILE):
    with open(VFDB_FILE) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            gene = parts[0].strip()
            vfg = parts[1].strip()
            add_label(gene_vf, gene, vfg)
    print(f"  VFDB: {len(gene_vf)} 基因")
else:
    warn(f"缺少 VFDB 文件，跳过 VFDB 表: {VFDB_FILE}")

if os.path.isfile(AMR_FILE):
    with open(AMR_FILE) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            gene = (row.get("Protein id") or "").strip()
            symbol = (row.get("Element symbol") or "").strip()
            add_label(gene_amr, gene, symbol)
    print(f"  AMRFinder: {len(gene_amr)} 基因")
else:
    warn(f"缺少 AMRFinder 文件，跳过 AMR 表: {AMR_FILE}")

merops_prot_to_family = {}
if os.path.isfile(MEROPS_MAP):
    with open(MEROPS_MAP) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                prot = parts[0].strip()
                family = parts[1].strip()
                if prot and family:
                    merops_prot_to_family[prot] = family
else:
    warn(f"缺少 MEROPS prot2family 映射: {MEROPS_MAP}")

if os.path.isfile(MEROPS_FILE) and merops_prot_to_family:
    with open(MEROPS_FILE) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            gene = parts[0].strip()
            mer_id = parts[1].strip()
            family = merops_prot_to_family.get(mer_id, mer_id)
            add_label(gene_merops_family, gene, family)
    print(f"  MEROPS: {len(gene_merops_family)} 基因")
elif os.path.isfile(MEROPS_FILE):
    warn("MEROPS 命中文件存在，但缺少 prot2family 映射，跳过 MEROPS 表")
else:
    warn(f"缺少 MEROPS 文件，跳过 MEROPS 表: {MEROPS_FILE}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 3: 生成类型 A — 功能聚合表 (6 张)
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step3] 生成类型 A 功能聚合表（6 张，值=基因计数）")

generated_type_a = []

type_a_specs = [
    (gene_ko, "kegg_ko_gene_count.tsv", "KEGG_KO", "KO"),
    (gene_cog, "cog_gene_count.tsv", "COG_category", "COG"),
    (gene_cazyme, "cazyme_gene_count.tsv", "CAZyme_family", "CAZyme"),
    (gene_vf, "vfdb_gene_count.tsv", "VF_gene", "VFDB"),
    (gene_amr, "amr_gene_count.tsv", "ARG_symbol", "AMR"),
    (gene_merops_family, "merops_family_gene_count.tsv", "MEROPS_family", "MEROPS"),
]

for func_map, filename, func_col_name, label in type_a_specs:
    if not func_map:
        warn(f"{label} 数据不可用，跳过 {filename}")
        continue
    outpath = os.path.join(OUT_DIR, filename)
    make_count_table(func_map, sample_genes, samples, outpath, func_col_name)
    generated_type_a.append(outpath)


# ──────────────────────────────────────────────────────────────────────────────
# Step 4: 生成类型 B — 基因级宽表
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step4] 生成类型 B 基因级宽表")

present_headers = [f"{sample}_present" for sample in samples]
anno_headers = ["COG_category", "KEGG_KO", "CAZyme", "VFDB", "AMR", "MEROPS_family"]

matrix_path = os.path.join(OUT_DIR, "gene_annotation_matrix.tsv")
with open(matrix_path, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
    writer.writerow(["gene_id"] + present_headers + anno_headers)
    for gene in all_genes:
        present_vals = ["1" if gene in sample_genes.get(sample, set()) else "0" for sample in samples]
        writer.writerow([gene] + present_vals + [
            gene_cog.get(gene, "-"),
            gene_ko.get(gene, "-"),
            gene_cazyme.get(gene, "-"),
            gene_vf.get(gene, "-"),
            gene_amr.get(gene, "-"),
            gene_merops_family.get(gene, "-"),
        ])

print(f"  → gene_annotation_matrix.tsv: {len(all_genes)} 基因 × {len(present_headers)+len(anno_headers)+1} 列")


# ──────────────────────────────────────────────────────────────────────────────
# Step 5: 生成标准化表
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step5] 生成标准化表")

for path in generated_type_a:
    base = os.path.splitext(os.path.basename(path))[0]
    relab_out = os.path.join(NORM_DIR, f"{base}_relab.tsv")
    clr_out = os.path.join(NORM_DIR, f"{base}_clr.tsv")
    normalize_table(path, relab_out, clr_out)


# ──────────────────────────────────────────────────────────────────────────────
# Step 6: FunOMIC 物种丰度标准化验证与整合摘要
# ──────────────────────────────────────────────────────────────────────────────
run_funomic_step()


# ──────────────────────────────────────────────────────────────────────────────
# 汇总报告
# ──────────────────────────────────────────────────────────────────────────────
print_summary_report()

PYEOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 整合脚本失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
mgx_end "integration"
echo "[integration] 输出目录: ${OUT_DIR}"
