#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98c_vir_integration_tables.sh
# 功  能: 病毒维度功能整合 — 生成 6 张整合表格及标准化结果
#
#   类型 A (5 张): 功能聚合表 (行=功能条目, 列=样本, 值=Σ vOTU TPM)
#     1. phrog_category_abundance.tsv  PHROG category × 样本
#     2. vog_abundance.tsv             VOG ID × 样本
#     3. lifestyle_abundance.tsv       Lifestyle × 样本
#     4. host_genus_abundance.tsv      Host genus × 样本
#     5. viral_family_abundance.tsv    Viral family × 样本
#
#   类型 B (1 张): vOTU 级宽表
#     6. votu_annotation_matrix.tsv    vOTU × (TPM×N + 多类注释)
#
#   衍生标准化输出:
#     - normalized/*_relab.tsv         类型 A 表的相对丰度
#     - normalized/*_clr.tsv           类型 A 表的 CLR (epsilon=0.01)
#     - votu_annotation_matrix_relab.tsv 宽表 + RELAB 列
#
# 依  赖:
#   - scripts/60: vOTU abundance table
#   - scripts/64: PHAROKKA
#   - scripts/66: VOG annotation
#   - scripts/67: BACPHLIP
#   - scripts/68: iPHoP
#   - scripts/69: vConTACT3
#
# 输  出: ${WORKDIR}/result/integration/virus/
# 用  法: bash 98c_vir_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

show_help() {
cat << EOF
用法: bash 98c_vir_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]

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
VIRUS_DIR="${WORKDIR}/result/virus"
OUT_DIR="${WORKDIR}/result/integration/virus"
NORM_DIR="${OUT_DIR}/normalized"

# 幂等检查
if [ -f "${OUT_DIR}/votu_annotation_matrix.tsv" ]; then
    echo "[INFO] 整合表已存在，跳过。如需重建请先删除 ${OUT_DIR}"
    exit 0
fi

mkdir -p "${OUT_DIR}" "${NORM_DIR}"

# --- 检查必需输入 ---
VOTU_TABLE="${VIRUS_DIR}/votu/votu_table.tsv"
if [ ! -f "${VOTU_TABLE}" ]; then
    echo "[ERROR] 缺少必需输入文件: ${VOTU_TABLE}"
    exit 1
fi

echo "[integration] 开始病毒维度功能整合"
echo "[integration] 输出目录: ${OUT_DIR}"

# ==============================================================================
# Python 整合主逻辑
# ==============================================================================

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
python3 - \
    "${WORKDIR}" \
    "${REPO}" \
    "${OUT_DIR}" \
    "${NORM_DIR}" \
<<'PYEOF'
import sys
import os
import csv
import re
import math
import shutil
from collections import defaultdict

WORKDIR = sys.argv[1]
REPO = sys.argv[2]
OUT_DIR = sys.argv[3]
NORM_DIR = sys.argv[4]

VIRUS_DIR = os.path.join(WORKDIR, "result", "virus")

VOTU_TABLE = os.path.join(VIRUS_DIR, "votu", "votu_table.tsv")
PHAROKKA_FILE = os.path.join(VIRUS_DIR, "pharokka", "pharokka_cds_final_merged_output.tsv")
VOG_FILE = os.path.join(VIRUS_DIR, "vog", "vog_annot.tsv")
BACPHLIP_FILE = os.path.join(VIRUS_DIR, "bacphlip", "bacphlip_results.tsv")
IPHOP_FILE = os.path.join(VIRUS_DIR, "iphop", "Host_prediction_to_genus_m90.csv")
VCONTACT_FILE = os.path.join(VIRUS_DIR, "vcontact3", "exports", "final_assignments.csv")


def warn(msg):
    print(f"[WARN] {msg}")


def fmt_float(val, digits=4):
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
        writer = csv.writer(fh, delimiter="\t")
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
        header = next(reader)
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


# ──────────────────────────────────────────────────────────────────────────────
# Step 1: 读取 vOTU TPM — votu_name → {sample: TPM}
# ──────────────────────────────────────────────────────────────────────────────
print("[Step1] 读取 vOTU TPM 定量结果")

votu_tpm = defaultdict(lambda: defaultdict(float))
samples = []

with open(VOTU_TABLE) as fh:
    reader = csv.reader(fh, delimiter="\t")
    header = next(reader)
    tpm_indices = []
    for idx, col in enumerate(header):
        if col.endswith("_tpm"):
            sample = col[:-4]
            samples.append(sample)
            tpm_indices.append((sample, idx))

    for row in reader:
        if not row:
            continue
        gene_id = row[0].strip()
        votu_name = re.sub(r"_\d+$", "", gene_id)
        for sample, idx in tpm_indices:
            if idx >= len(row):
                continue
            try:
                votu_tpm[votu_name][sample] += float(row[idx])
            except ValueError:
                continue

all_votus = sorted(votu_tpm.keys())
print(f"  样本: {samples}")
print(f"  vOTU 数: {len(all_votus)}")


def make_abundance_table(func_map, samples, outpath, func_col_name="function"):
    """
    func_map: votu_name → function_label (str, 可含逗号分隔多功能)
    输出: function_label × sample 的 TPM 求和矩阵
    """
    func_tpm = defaultdict(lambda: defaultdict(float))
    for votu, funcs in func_map.items():
        if not funcs or funcs == "-":
            continue
        for func in funcs.split(","):
            func = func.strip()
            if not func or func == "-":
                continue
            for sample in samples:
                func_tpm[func][sample] += votu_tpm.get(votu, {}).get(sample, 0.0)

    with open(outpath, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow([func_col_name] + samples)
        for func in sorted(func_tpm):
            writer.writerow([func] + [fmt_float(func_tpm[func][sample]) for sample in samples])

    n = len(func_tpm)
    print(f"  → {os.path.basename(outpath)}: {n} 行 × {len(samples)+1} 列")
    return func_tpm


# ──────────────────────────────────────────────────────────────────────────────
# Step 2: 解析 PHAROKKA
# ──────────────────────────────────────────────────────────────────────────────
print("[Step2] 解析 PHAROKKA")

pharokka_gene_to_contig = {}
votu_category = {}

if os.path.isfile(PHAROKKA_FILE):
    votu_categories = defaultdict(list)
    with open(PHAROKKA_FILE) as fh:
        reader = csv.reader(fh, delimiter="\t")
        next(reader, None)
        for row in reader:
            if len(row) < 22:
                continue
            gene = row[0].strip()
            contig = row[4].strip()
            category = row[21].strip() or "-"
            if gene and contig:
                pharokka_gene_to_contig[gene] = contig
            if contig and category and category != "-":
                votu_categories[contig].append(category)

    for votu, categories in votu_categories.items():
        known = [c for c in categories if c != "unknown function"]
        pool = known if known else categories
        counts = defaultdict(int)
        for category in pool:
            counts[category] += 1
        best = sorted(counts.items(), key=lambda x: (-x[1], x[0]))[0][0] if counts else "-"
        votu_category[votu] = best

    print(f"  PHAROKKA CDS 映射: {len(pharokka_gene_to_contig)}")
    print(f"  PHROG category 覆盖 vOTU: {len(votu_category)}")
else:
    warn(f"缺少 PHAROKKA 文件，跳过相关表: {PHAROKKA_FILE}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 3: 解析 VOG
# ──────────────────────────────────────────────────────────────────────────────
print("[Step3] 解析 VOG")

votu_vog_ids = defaultdict(set)
vog_id_map = defaultdict(set)
vog_ready = False

if os.path.isfile(VOG_FILE):
    if pharokka_gene_to_contig:
        with open(VOG_FILE) as fh:
            reader = csv.reader(fh, delimiter="\t")
            for row in reader:
                if len(row) < 2:
                    continue
                vog_id = row[0].strip()
                gene = row[1].strip()
                if not vog_id or not gene:
                    continue
                votu = pharokka_gene_to_contig.get(gene)
                if not votu:
                    continue
                votu_vog_ids[votu].add(vog_id)
                vog_id_map[gene].add(vog_id)
        vog_ready = True
        print(f"  VOG 覆盖 vOTU: {len(votu_vog_ids)}")
    else:
        warn("VOG 文件存在，但缺少 PHAROKKA gene→contig 映射，跳过 VOG 表")
else:
    warn(f"缺少 VOG 文件，跳过相关表: {VOG_FILE}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 4: 解析 BACPHLIP
# ──────────────────────────────────────────────────────────────────────────────
print("[Step4] 解析 BACPHLIP")

votu_lifestyle = {}
votu_virulent_prob = {}
bacphlip_ready = False

if os.path.isfile(BACPHLIP_FILE):
    with open(BACPHLIP_FILE) as fh:
        reader = csv.reader(fh, delimiter="\t")
        next(reader, None)
        for row in reader:
            if len(row) < 3:
                continue
            votu = row[0].strip()
            try:
                virulent = float(row[1])
                temperate = float(row[2])
            except ValueError:
                continue
            if not votu:
                continue
            votu_lifestyle[votu] = "Virulent" if virulent >= 0.5 else "Temperate"
            votu_virulent_prob[votu] = virulent
    bacphlip_ready = True
    print(f"  BACPHLIP 覆盖 vOTU: {len(votu_lifestyle)}")
else:
    warn(f"缺少 BACPHLIP 文件，跳过相关表: {BACPHLIP_FILE}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 5: 解析 iPHoP
# ──────────────────────────────────────────────────────────────────────────────
print("[Step5] 解析 iPHoP")

votu_host = {}
votu_host_conf = {}
iphop_ready = False

if os.path.isfile(IPHOP_FILE):
    with open(IPHOP_FILE, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            votu = (row.get("Virus") or "").strip()
            lineage = (row.get("Host genus") or "").strip()
            conf = (row.get("Confidence score") or "").strip()
            if not votu or not lineage:
                continue
            genus = "-"
            if ";g__" in lineage:
                genus = lineage.split(";g__", 1)[1].strip() or "-"
            elif lineage.startswith("g__"):
                genus = lineage[3:].strip() or "-"
            if genus == "-":
                continue
            votu_host[votu] = genus
            votu_host_conf[votu] = conf if conf else "-"
    iphop_ready = True
    print(f"  iPHoP 覆盖 vOTU: {len(votu_host)}")
else:
    warn(f"缺少 iPHoP 文件，跳过相关表: {IPHOP_FILE}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 6: 解析 vConTACT3
# ──────────────────────────────────────────────────────────────────────────────
print("[Step6] 解析 vConTACT3")

votu_family = {}
vcontact_ready = False

if os.path.isfile(VCONTACT_FILE):
    with open(VCONTACT_FILE, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            reference = (row.get("Reference") or "").strip().lower()
            if reference != "false":
                continue
            genome = (row.get("Genome") or "").strip()
            family = (row.get("family_prediction") or "").strip()
            if not genome or not family:
                continue
            candidates = [genome]
            if genome.endswith("||full"):
                candidates.append(genome.replace("||full", ""))
            else:
                candidates.append(genome + "||full")
            for candidate in candidates:
                if candidate in votu_tpm:
                    votu_family[candidate] = family
                    break
    vcontact_ready = True
    print(f"  vConTACT3 family 覆盖 vOTU: {len(votu_family)}")
else:
    warn(f"缺少 vConTACT3 文件，跳过相关表: {VCONTACT_FILE}")


# ──────────────────────────────────────────────────────────────────────────────
# Step 7/8: 生成类型 A — 功能聚合表 (5 张)
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step7-8] 生成类型 A 功能聚合表（5 张）")

generated_type_a = []

if votu_category:
    outpath = os.path.join(OUT_DIR, "phrog_category_abundance.tsv")
    make_abundance_table(votu_category, samples, outpath, "PHROG_category")
    generated_type_a.append(outpath)
else:
    warn("PHROG category 数据不可用，跳过 phrog_category_abundance.tsv")

if vog_ready:
    votu_vog_map = {votu: ",".join(sorted(vog_ids)) for votu, vog_ids in votu_vog_ids.items() if vog_ids}
    outpath = os.path.join(OUT_DIR, "vog_abundance.tsv")
    make_abundance_table(votu_vog_map, samples, outpath, "VOG_ID")
    generated_type_a.append(outpath)
else:
    warn("VOG 数据不可用，跳过 vog_abundance.tsv")

if all_votus:
    lifestyle_map = {}
    for votu in all_votus:
        lifestyle_map[votu] = votu_lifestyle.get(votu, "Unclassified")
    outpath = os.path.join(OUT_DIR, "lifestyle_abundance.tsv")
    make_abundance_table(lifestyle_map, samples, outpath, "lifestyle")
    generated_type_a.append(outpath)

if iphop_ready:
    outpath = os.path.join(OUT_DIR, "host_genus_abundance.tsv")
    make_abundance_table(votu_host, samples, outpath, "host_genus")
    generated_type_a.append(outpath)
else:
    warn("iPHoP 数据不可用，跳过 host_genus_abundance.tsv")

if vcontact_ready and votu_family:
    outpath = os.path.join(OUT_DIR, "viral_family_abundance.tsv")
    make_abundance_table(votu_family, samples, outpath, "viral_family")
    generated_type_a.append(outpath)
else:
    warn("vConTACT3 family 数据不可用，跳过 viral_family_abundance.tsv")


# ──────────────────────────────────────────────────────────────────────────────
# Step 9: 生成类型 B — vOTU 级宽表
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step9] 生成类型 B vOTU 级宽表")

tpm_headers = [f"vOTU_TPM_{sample}" for sample in samples]
anno_headers = [
    "PHROG_category",
    "BACPHLIP_lifestyle",
    "BACPHLIP_virulent_prob",
    "host_genus",
    "host_confidence",
    "viral_family",
    "VOG_IDs",
]

matrix_path = os.path.join(OUT_DIR, "votu_annotation_matrix.tsv")
with open(matrix_path, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["vOTU_name"] + tpm_headers + anno_headers)
    for votu in all_votus:
        row = [votu]
        row.extend(fmt_float(votu_tpm[votu].get(sample, 0.0)) for sample in samples)
        row.extend([
            votu_category.get(votu, "-"),
            votu_lifestyle.get(votu, "-"),
            fmt_float(votu_virulent_prob[votu]) if votu in votu_virulent_prob else "-",
            votu_host.get(votu, "-"),
            votu_host_conf.get(votu, "-"),
            votu_family.get(votu, "-"),
            ",".join(sorted(votu_vog_ids.get(votu, set()))) if votu_vog_ids.get(votu) else "-",
        ])
        writer.writerow(row)

print(f"  → votu_annotation_matrix.tsv: {len(all_votus)} vOTU × {len(tpm_headers) + len(anno_headers) + 1} 列")


# ──────────────────────────────────────────────────────────────────────────────
# Step 10: 标准化输出
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step10] 生成标准化表")

for path in generated_type_a:
    base = os.path.splitext(os.path.basename(path))[0]
    relab_out = os.path.join(NORM_DIR, f"{base}_relab.tsv")
    clr_out = os.path.join(NORM_DIR, f"{base}_clr.tsv")
    normalize_table(path, relab_out, clr_out)

col_sums = {}
for sample in samples:
    col_sums[sample] = sum(votu_tpm[votu].get(sample, 0.0) for votu in all_votus)

matrix_relab_path = os.path.join(OUT_DIR, "votu_annotation_matrix_relab.tsv")
relab_headers = [f"vOTU_RELAB_{sample}" for sample in samples]
with open(matrix_relab_path, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["vOTU_name"] + tpm_headers + relab_headers + anno_headers)
    for votu in all_votus:
        tpm_vals = [votu_tpm[votu].get(sample, 0.0) for sample in samples]
        relab_vals = [
            (votu_tpm[votu].get(sample, 0.0) / col_sums[sample]) if col_sums[sample] > 0 else 0.0
            for sample in samples
        ]
        row = [votu]
        row.extend(fmt_float(val) for val in tpm_vals)
        row.extend(fmt_float(val) for val in relab_vals)
        row.extend([
            votu_category.get(votu, "-"),
            votu_lifestyle.get(votu, "-"),
            fmt_float(votu_virulent_prob[votu]) if votu in votu_virulent_prob else "-",
            votu_host.get(votu, "-"),
            votu_host_conf.get(votu, "-"),
            votu_family.get(votu, "-"),
            ",".join(sorted(votu_vog_ids.get(votu, set()))) if votu_vog_ids.get(votu) else "-",
        ])
        writer.writerow(row)

rows, cols = table_shape(matrix_relab_path)
print(f"  → votu_annotation_matrix_relab.tsv: {rows} 行 × {cols} 列")


# ──────────────────────────────────────────────────────────────────────────────
# 汇总报告
# ──────────────────────────────────────────────────────────────────────────────
print("\n" + "=" * 70)
print("[integration] 完成！输出目录:", OUT_DIR)
print("=" * 70)

summary_paths = []
for fname in sorted(os.listdir(OUT_DIR)):
    fpath = os.path.join(OUT_DIR, fname)
    if os.path.isfile(fpath):
        summary_paths.append(fpath)

if os.path.isdir(NORM_DIR):
    for fname in sorted(os.listdir(NORM_DIR)):
        fpath = os.path.join(NORM_DIR, fname)
        if os.path.isfile(fpath):
            summary_paths.append(fpath)

for fpath in summary_paths:
    nrows, ncols = table_shape(fpath)
    size_kb = os.path.getsize(fpath) // 1024
    relname = os.path.relpath(fpath, OUT_DIR)
    print(f"  {relname:<45s}  {nrows:>6} 行 × {ncols:>3} 列  ({size_kb} KB)")

PYEOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 整合脚本失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
echo "[integration] 病毒维度整合表生成完成，耗时 ${SECONDS}s"
echo "[integration] 输出目录: ${OUT_DIR}"
