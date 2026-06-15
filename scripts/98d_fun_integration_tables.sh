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
#   衍生标准化输出:
#     - normalized/*_relab.tsv           类型 A 表的相对丰度
#     - normalized/*_clr.tsv             类型 A 表的 CLR (epsilon=0.01)
#
# 依  赖:
#   - result/fungi/prodigal/{sample}/{sample}.faa
#   - result/fungi/eggnog/eggnog.emapper.annotations
#   - result/fungi/dbcan/overview.txt
#   - result/fungi/vfdb/vfdb_hits.tsv
#   - result/fungi/amr/amrfinder_results.tsv
#   - result/fungi/merops/merops_hits.tsv
#   - db/merops/misc/prot2family.txt
#
# 输  出: ${WORKDIR}/result/integration/fungi/
# 用  法: bash 98d_fun_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

show_help() {
cat << EOF
用法: bash 98d_fun_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录（Project_example 路径）
  -r  MaxMetagenome 项目根目录

可选参数:
  -t  线程数（默认 4，Python 脚本暂未并行化）
  -h  显示帮助
EOF
}

WORKDIR=""
REPO=""
CPUS=4

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-w/-r）"; show_help; exit 1
fi

SECONDS=0

# --- 路径定义 ---
FUNGI_DIR="${WORKDIR}/result/fungi"
PRODIGAL_DIR="${FUNGI_DIR}/prodigal"
OUT_DIR="${WORKDIR}/result/integration/fungi"
NORM_DIR="${OUT_DIR}/normalized"
MEROPS_MAP="${REPO}/db/merops/misc/prot2family.txt"

# 幂等检查
if [ -f "${OUT_DIR}/gene_annotation_matrix.tsv" ]; then
    echo "[INFO] 整合表已存在，跳过。如需重建请先删除 ${OUT_DIR}"
    exit 0
fi

mkdir -p "${OUT_DIR}" "${NORM_DIR}"

# --- 检查至少有一个 FAA 文件 ---
FAA_FOUND=$(find "${PRODIGAL_DIR}" -mindepth 2 -maxdepth 2 -name "*.faa" 2>/dev/null | wc -l)
if [ "${FAA_FOUND}" -eq 0 ]; then
    echo "[ERROR] 未找到真菌 Prodigal FAA 文件: ${PRODIGAL_DIR}"
    exit 1
fi

echo "[integration] 开始真菌维度功能整合"
echo "[integration] 输出目录: ${OUT_DIR}"
echo "[integration] 找到 ${FAA_FOUND} 个 FAA 文件"

# ==============================================================================
# Python 整合主逻辑
# ==============================================================================

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
python3 - \
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
# 汇总报告
# ──────────────────────────────────────────────────────────────────────────────
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

PYEOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 整合脚本失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
echo "[integration] 真菌维度整合表生成完成，耗时 ${SECONDS}s"
echo "[integration] 输出目录: ${OUT_DIR}"
