#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98c_vir_integration_tables.sh
# 功  能: 病毒维度功能整合 — 生成 5 张功能聚合表、2 张 vOTU 宽表及标准化结果
#
#   类型 A (5 张): 功能聚合表 (行=功能条目, 列=样本, 值=Σ vOTU TPM)
#     1. phrog_category_abundance.tsv  PHROG category × 样本
#     2. vog_abundance.tsv             VOG ID × 样本
#     3. lifestyle_abundance.tsv       Lifestyle × 样本
#     4. host_genus_abundance.tsv      Host genus × 样本
#     5. viral_family_abundance.tsv    Viral family × 样本
#
#   类型 B (2 张): vOTU 级宽表
#     6. votu_annotation_matrix.tsv        vOTU × (TPM×N + 注释字段)
#     7. votu_annotation_matrix_relab.tsv  vOTU × (TPM×N + RELAB×N + 注释字段)
#
#   衍生标准化输出:
#     - normalized/*_relab.tsv         类型 A 表的相对丰度
#     - normalized/*_clr.tsv           类型 A 表的 CLR (epsilon=0.01)
#
# 依  赖:
#   - scripts/60: vOTU abundance table
#   - scripts/64: PHAROKKA
#   - scripts/66: VOG annotation
#   - scripts/67: BACPHLIP
#   - scripts/68: iPHoP
#   - scripts/69: vConTACT3
#   - scripts/63: CheckV
#
# 输  出: ${WORKDIR}/result/integration/virus/
# 用  法: bash 98c_vir_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 98c_vir_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  -t  线程数（默认 4，Python 脚本暂未并行化）
  -h  显示帮助
EOF
}

CPUS=4
# -t 为保留接口（Python 侧暂未并行化）；export 供子进程读取
export CPUS

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

VIRUS_DIR="${WORKDIR}/result/virus"
OUT_DIR="${WORKDIR}/result/integration/virus"
NORM_DIR="${OUT_DIR}/normalized"

VOTU_TABLE="${VIRUS_DIR}/votu/votu_table.tsv"
VOTU_LENGTHS="${VIRUS_DIR}/votu/votu_lengths.tsv"
PHAROKKA_FILE="${VIRUS_DIR}/pharokka/pharokka_cds_final_merged_output.tsv"
VOG_FILE="${VIRUS_DIR}/vog/vog_annot.tsv"
BACPHLIP_FILE="${VIRUS_DIR}/bacphlip/bacphlip_results.tsv"
IPHOP_FILE="${VIRUS_DIR}/iphop/Host_prediction_to_genus_m90.csv"
VCONTACT_FILE="${VIRUS_DIR}/vcontact3/exports/final_assignments.csv"
CHECKV_DIR="${VIRUS_DIR}/checkv"

MISSING=0
for f in \
    "${VOTU_TABLE}" \
    "${VOTU_LENGTHS}" \
    "${PHAROKKA_FILE}" \
    "${VOG_FILE}" \
    "${BACPHLIP_FILE}" \
    "${IPHOP_FILE}" \
    "${VCONTACT_FILE}"; do
    if [ ! -f "${f}" ]; then
        echo "[ERROR] 缺少输入文件: ${f}"
        MISSING=1
    fi
done

if [ ! -d "${CHECKV_DIR}" ]; then
    echo "[ERROR] 缺少 CheckV 目录: ${CHECKV_DIR}"
    MISSING=1
fi

[ ${MISSING} -eq 1 ] && exit 1

mkdir -p "${OUT_DIR}" "${NORM_DIR}"

VOTU_TABLE_OUTPUT="${OUT_DIR}/votu_abundance_matrix.tsv"
if [ ${FORCE} -eq 0 ] && [ -f "${VOTU_TABLE_OUTPUT}" ] && [ -s "${VOTU_TABLE_OUTPUT}" ]; then
    echo "[INFO] 结果已存在，跳过: ${VOTU_TABLE_OUTPUT}"; exit 0
fi

echo "[integration] 开始病毒维度功能整合"
echo "[integration] 输出目录: ${OUT_DIR}"
echo "[integration] 将重建已有病毒整合输出"

mgx_conda assembly python3 - \
    "${WORKDIR}" \
    "${OUT_DIR}" \
    "${NORM_DIR}" \
<<'PYEOF'
import csv
import math
import os
import re
import sys
from collections import defaultdict

WORKDIR = sys.argv[1]
OUT_DIR = sys.argv[2]
NORM_DIR = sys.argv[3]

VIRUS_DIR = os.path.join(WORKDIR, "result", "virus")
VOTU_TABLE = os.path.join(VIRUS_DIR, "votu", "votu_table.tsv")
VOTU_LENGTHS = os.path.join(VIRUS_DIR, "votu", "votu_lengths.tsv")
PHAROKKA_FILE = os.path.join(VIRUS_DIR, "pharokka", "pharokka_cds_final_merged_output.tsv")
VOG_FILE = os.path.join(VIRUS_DIR, "vog", "vog_annot.tsv")
BACPHLIP_FILE = os.path.join(VIRUS_DIR, "bacphlip", "bacphlip_results.tsv")
IPHOP_FILE = os.path.join(VIRUS_DIR, "iphop", "Host_prediction_to_genus_m90.csv")
VCONTACT_FILE = os.path.join(VIRUS_DIR, "vcontact3", "exports", "final_assignments.csv")
CHECKV_DIR = os.path.join(VIRUS_DIR, "checkv")

TYPE_A_FILES = [
    "phrog_category_abundance.tsv",
    "vog_abundance.tsv",
    "lifestyle_abundance.tsv",
    "host_genus_abundance.tsv",
    "viral_family_abundance.tsv",
]
TOP_LEVEL_FILES = TYPE_A_FILES + [
    "votu_annotation_matrix.tsv",
    "votu_annotation_matrix_relab.tsv",
]

QUALITY_RANK = {
    "Complete": 5,
    "High-quality": 4,
    "Medium-quality": 3,
    "Low-quality": 2,
    "Not-determined": 1,
    "-": 0,
}


def warn(msg):
    print(f"[WARN] {msg}")


def fmt_float(val, digits=4):
    return f"{val:.{digits}f}"


def fmt_number_or_dash(val, digits=2):
    if val is None:
        return "-"
    return f"{val:.{digits}f}"


def fmt_int_or_dash(val):
    if val is None:
        return "-"
    return str(int(val))


def table_shape(path):
    with open(path) as fh:
        first = fh.readline()
        if not first:
            return 0, 0
        cols = len(first.rstrip("\n").split("\t"))
        rows = sum(1 for _ in fh)
    return rows, cols


def cleanup_outputs():
    for fname in TOP_LEVEL_FILES:
        path = os.path.join(OUT_DIR, fname)
        if os.path.exists(path):
            os.remove(path)
    if os.path.isdir(NORM_DIR):
        for fname in os.listdir(NORM_DIR):
            path = os.path.join(NORM_DIR, fname)
            if os.path.isfile(path):
                os.remove(path)


def write_matrix(path, header, row_names, matrix, samples):
    with open(path, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(header)
        for row_name in row_names:
            writer.writerow([row_name] + [fmt_float(matrix[row_name].get(sample, 0.0)) for sample in samples])


def normalize_to_relab(raw_matrix, row_names, samples):
    relab = defaultdict(dict)
    for sample in samples:
        total = sum(raw_matrix[row].get(sample, 0.0) for row in row_names)
        for row in row_names:
            value = raw_matrix[row].get(sample, 0.0)
            relab[row][sample] = (value / total) if total > 0 else 0.0
    return relab


def relab_to_clr(relab_matrix, row_names, samples, eps=0.01):
    clr = defaultdict(dict)
    for sample in samples:
        logs = [math.log(relab_matrix[row].get(sample, 0.0) + eps) for row in row_names]
        mean_log = sum(logs) / len(logs) if logs else 0.0
        for row_name, log_val in zip(row_names, logs):
            clr[row_name][sample] = log_val - mean_log
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
            row_name = row[0]
            row_names.append(row_name)
            for sample, value in zip(local_samples, row[1:]):
                try:
                    raw[row_name][sample] = float(value)
                except ValueError:
                    raw[row_name][sample] = 0.0

    relab = normalize_to_relab(raw, row_names, local_samples)
    clr = relab_to_clr(relab, row_names, local_samples, eps=0.01)
    write_matrix(relab_out, header, row_names, relab, local_samples)
    write_matrix(clr_out, header, row_names, clr, local_samples)

    relab_rows, relab_cols = table_shape(relab_out)
    clr_rows, clr_cols = table_shape(clr_out)
    print(f"  → {os.path.basename(relab_out)}: {relab_rows} 行 × {relab_cols} 列")
    print(f"  → {os.path.basename(clr_out)}: {clr_rows} 行 × {clr_cols} 列")


def load_votu_tpm():
    print("[Step1] 聚合 CDS-level TPM 到 vOTU-level")
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
            gene = row[0].strip()
            votu = re.sub(r"_[0-9]+$", "", gene)
            for sample, idx in tpm_indices:
                if idx >= len(row):
                    continue
                try:
                    votu_tpm[votu][sample] += float(row[idx])
                except ValueError:
                    continue

    all_votus = sorted(votu_tpm)
    print(f"  样本: {samples}")
    print(f"  CDS 行数聚合后 vOTU 数: {len(all_votus)}")
    return votu_tpm, samples, all_votus


def load_votu_lengths():
    print("[Step2] 读取 vOTU 长度")
    votu_lengths = {}
    with open(VOTU_LENGTHS) as fh:
        reader = csv.reader(fh, delimiter="\t")
        for row in reader:
            if not row or len(row) < 2:
                continue
            votu = row[0].strip()
            if votu.lower() in ("votu", "votu_name", "contig", "contig_id"):
                continue
            length_raw = row[1].strip()
            try:
                votu_lengths[votu] = int(float(length_raw))
            except ValueError:
                votu_lengths[votu] = None
    print(f"  长度记录: {len(votu_lengths)}")
    return votu_lengths


def load_pharokka():
    print("[Step3] 解析 PHAROKKA")
    pharokka_gene_to_contig = {}
    votu_categories_raw = defaultdict(list)
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
                votu_categories_raw[contig].append(category)

    votu_category = {}
    for votu, categories in votu_categories_raw.items():
        known = [cat for cat in categories if cat != "unknown function"]
        pool = known if known else categories
        counts = defaultdict(int)
        for category in pool:
            counts[category] += 1
        best = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0][0] if counts else "-"
        votu_category[votu] = best

    print(f"  PHAROKKA CDS 映射: {len(pharokka_gene_to_contig)}")
    print(f"  PHROG category 覆盖 vOTU: {len(votu_category)}")
    return pharokka_gene_to_contig, votu_category


def load_vog(pharokka_gene_to_contig):
    print("[Step4] 解析 VOG")
    votu_vog_ids = defaultdict(set)
    with open(VOG_FILE) as fh:
        reader = csv.reader(fh, delimiter="\t")
        for row in reader:
            if len(row) < 2:
                continue
            vog_id = row[0].strip()
            gene = row[1].strip()
            votu = pharokka_gene_to_contig.get(gene)
            if not vog_id or not gene or not votu:
                continue
            votu_vog_ids[votu].add(vog_id)
    print(f"  VOG 覆盖 vOTU: {len(votu_vog_ids)}")
    return votu_vog_ids


def load_bacphlip():
    print("[Step5] 解析 BACPHLIP")
    votu_lifestyle = {}
    votu_virulent_prob = {}
    with open(BACPHLIP_FILE) as fh:
        reader = csv.reader(fh, delimiter="\t")
        next(reader, None)
        for row in reader:
            if len(row) < 3:
                continue
            votu = row[0].strip()
            if not votu:
                continue
            try:
                virulent = float(row[1])
            except ValueError:
                continue
            votu_lifestyle[votu] = "Virulent" if virulent >= 0.5 else "Temperate"
            votu_virulent_prob[votu] = virulent
    print(f"  BACPHLIP 覆盖 vOTU: {len(votu_lifestyle)}")
    return votu_lifestyle, votu_virulent_prob


def load_iphop():
    print("[Step6] 解析 iPHoP")
    votu_host = {}
    votu_host_conf = {}
    with open(IPHOP_FILE, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            votu = (row.get("Virus") or "").strip()
            lineage = (row.get("Host genus") or "").strip()
            confidence = (row.get("Confidence score") or "").strip()
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
            votu_host_conf[votu] = confidence if confidence else "-"
    print(f"  iPHoP 覆盖 vOTU: {len(votu_host)}")
    return votu_host, votu_host_conf


def load_vcontact(votu_names):
    print("[Step7] 解析 vConTACT3")
    votu_family = {}
    votu_set = set(votu_names)
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
                candidates.append(genome[:-6])
            else:
                candidates.append(genome + "||full")
            for candidate in candidates:
                if candidate in votu_set:
                    votu_family[candidate] = family
                    break
    print(f"  vConTACT3 family 覆盖 vOTU: {len(votu_family)}")
    return votu_family


def parse_completeness(value):
    value = (value or "").strip()
    if not value or value == "NA":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def load_checkv():
    print("[Step8] 合并 CheckV quality_summary.tsv")
    best_checkv = {}
    sample_dirs = sorted(os.listdir(CHECKV_DIR))
    file_count = 0
    for sample in sample_dirs:
        quality_path = os.path.join(CHECKV_DIR, sample, "quality_summary.tsv")
        if not os.path.isfile(quality_path):
            continue
        file_count += 1
        with open(quality_path) as fh:
            reader = csv.DictReader(fh, delimiter="\t")
            for row in reader:
                votu = (row.get("contig_id") or "").strip()
                if not votu:
                    continue
                quality = (row.get("checkv_quality") or "").strip() or "Not-determined"
                completeness = parse_completeness(row.get("completeness"))
                contig_length = row.get("contig_length")
                try:
                    contig_length = int(float(contig_length))
                except (TypeError, ValueError):
                    contig_length = None

                current_rank = QUALITY_RANK.get(quality, 0)
                current_comp = completeness if completeness is not None else -1.0
                previous = best_checkv.get(votu)
                if previous is None:
                    best_checkv[votu] = {
                        "checkv_quality": quality,
                        "checkv_completeness": completeness,
                        "contig_length": contig_length,
                        "rank": current_rank,
                    }
                    continue

                prev_comp = previous["checkv_completeness"]
                prev_score = (
                    previous["rank"],
                    prev_comp if prev_comp is not None else -1.0,
                    previous["contig_length"] if previous["contig_length"] is not None else -1,
                )
                curr_score = (
                    current_rank,
                    current_comp,
                    contig_length if contig_length is not None else -1,
                )
                if curr_score > prev_score:
                    best_checkv[votu] = {
                        "checkv_quality": quality,
                        "checkv_completeness": completeness,
                        "contig_length": contig_length,
                        "rank": current_rank,
                    }

    print(f"  CheckV 文件数: {file_count}")
    print(f"  CheckV 合并后 vOTU: {len(best_checkv)}")
    return best_checkv


def make_abundance_table(func_map, votu_tpm, samples, outpath, func_col_name):
    func_tpm = defaultdict(lambda: defaultdict(float))
    for votu, labels in func_map.items():
        if not labels or labels == "-":
            continue
        for label in labels.split(","):
            label = label.strip()
            if not label or label == "-":
                continue
            for sample in samples:
                func_tpm[label][sample] += votu_tpm.get(votu, {}).get(sample, 0.0)

    with open(outpath, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow([func_col_name] + samples)
        for label in sorted(func_tpm):
            writer.writerow([label] + [fmt_float(func_tpm[label].get(sample, 0.0)) for sample in samples])

    rows = len(func_tpm)
    print(f"  → {os.path.basename(outpath)}: {rows} 行 × {len(samples) + 1} 列")


cleanup_outputs()
votu_tpm, samples, all_votus = load_votu_tpm()
votu_lengths = load_votu_lengths()
pharokka_gene_to_contig, votu_category = load_pharokka()
votu_vog_ids = load_vog(pharokka_gene_to_contig)
votu_lifestyle, votu_virulent_prob = load_bacphlip()
votu_host, votu_host_conf = load_iphop()
votu_family = load_vcontact(all_votus)
best_checkv = load_checkv()

print("\n[Step9] 生成 5 张功能聚合表")
generated_type_a = []

phrog_path = os.path.join(OUT_DIR, "phrog_category_abundance.tsv")
make_abundance_table(votu_category, votu_tpm, samples, phrog_path, "PHROG_category")
generated_type_a.append(phrog_path)

votu_vog_map = {}
for votu, vog_ids in votu_vog_ids.items():
    if vog_ids:
        votu_vog_map[votu] = ",".join(sorted(vog_ids))
vog_path = os.path.join(OUT_DIR, "vog_abundance.tsv")
make_abundance_table(votu_vog_map, votu_tpm, samples, vog_path, "VOG_ID")
generated_type_a.append(vog_path)

lifestyle_map = {}
for votu in all_votus:
    lifestyle_map[votu] = votu_lifestyle.get(votu, "Unclassified")
lifestyle_path = os.path.join(OUT_DIR, "lifestyle_abundance.tsv")
make_abundance_table(lifestyle_map, votu_tpm, samples, lifestyle_path, "lifestyle")
generated_type_a.append(lifestyle_path)

host_path = os.path.join(OUT_DIR, "host_genus_abundance.tsv")
make_abundance_table(votu_host, votu_tpm, samples, host_path, "host_genus")
generated_type_a.append(host_path)

family_path = os.path.join(OUT_DIR, "viral_family_abundance.tsv")
make_abundance_table(votu_family, votu_tpm, samples, family_path, "viral_family")
generated_type_a.append(family_path)

print("\n[Step10] 生成 vOTU 注释宽表")
tpm_headers = [f"vOTU_TPM_{sample}" for sample in samples]
relab_headers = [f"vOTU_RELAB_{sample}" for sample in samples]
anno_headers = [
    "vOTU_length",
    "checkv_quality",
    "checkv_completeness",
    "PHROG_category",
    "BACPHLIP_lifestyle",
    "BACPHLIP_virulent_prob",
    "host_genus",
    "host_confidence",
    "viral_family",
    "VOG_IDs",
]

col_sums = {}
for sample in samples:
    col_sums[sample] = sum(votu_tpm[votu].get(sample, 0.0) for votu in all_votus)

matrix_path = os.path.join(OUT_DIR, "votu_annotation_matrix.tsv")
with open(matrix_path, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["vOTU_name"] + tpm_headers + anno_headers)
    for votu in all_votus:
        checkv_row = best_checkv.get(votu, {})
        writer.writerow(
            [votu]
            + [fmt_float(votu_tpm[votu].get(sample, 0.0)) for sample in samples]
            + [
                fmt_int_or_dash(votu_lengths.get(votu)),
                checkv_row.get("checkv_quality", "-"),
                fmt_number_or_dash(checkv_row.get("checkv_completeness"), digits=2),
                votu_category.get(votu, "-"),
                votu_lifestyle.get(votu, "-"),
                fmt_float(votu_virulent_prob[votu]) if votu in votu_virulent_prob else "-",
                votu_host.get(votu, "-"),
                votu_host_conf.get(votu, "-"),
                votu_family.get(votu, "-"),
                ",".join(sorted(votu_vog_ids.get(votu, set()))) if votu_vog_ids.get(votu) else "-",
            ]
        )

rows, cols = table_shape(matrix_path)
print(f"  → votu_annotation_matrix.tsv: {rows} 行 × {cols} 列")

matrix_relab_path = os.path.join(OUT_DIR, "votu_annotation_matrix_relab.tsv")
with open(matrix_relab_path, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["vOTU_name"] + tpm_headers + relab_headers + anno_headers)
    for votu in all_votus:
        checkv_row = best_checkv.get(votu, {})
        relab_values = []
        for sample in samples:
            value = votu_tpm[votu].get(sample, 0.0)
            total = col_sums[sample]
            relab_values.append((value / total) if total > 0 else 0.0)
        writer.writerow(
            [votu]
            + [fmt_float(votu_tpm[votu].get(sample, 0.0)) for sample in samples]
            + [fmt_float(val) for val in relab_values]
            + [
                fmt_int_or_dash(votu_lengths.get(votu)),
                checkv_row.get("checkv_quality", "-"),
                fmt_number_or_dash(checkv_row.get("checkv_completeness"), digits=2),
                votu_category.get(votu, "-"),
                votu_lifestyle.get(votu, "-"),
                fmt_float(votu_virulent_prob[votu]) if votu in votu_virulent_prob else "-",
                votu_host.get(votu, "-"),
                votu_host_conf.get(votu, "-"),
                votu_family.get(votu, "-"),
                ",".join(sorted(votu_vog_ids.get(votu, set()))) if votu_vog_ids.get(votu) else "-",
            ]
        )

rows, cols = table_shape(matrix_relab_path)
print(f"  → votu_annotation_matrix_relab.tsv: {rows} 行 × {cols} 列")

print("\n[Step11] 生成标准化表")
for path in generated_type_a:
    base = os.path.splitext(os.path.basename(path))[0]
    relab_out = os.path.join(NORM_DIR, base + "_relab.tsv")
    clr_out = os.path.join(NORM_DIR, base + "_clr.tsv")
    normalize_table(path, relab_out, clr_out)

print("\n" + "=" * 70)
print("[integration] 完成！输出目录:", OUT_DIR)
print("=" * 70)

summary_paths = []
for fname in sorted(os.listdir(OUT_DIR)):
    fpath = os.path.join(OUT_DIR, fname)
    if os.path.isfile(fpath):
        summary_paths.append(fpath)
for fname in sorted(os.listdir(NORM_DIR)):
    fpath = os.path.join(NORM_DIR, fname)
    if os.path.isfile(fpath):
        summary_paths.append(fpath)

for fpath in summary_paths:
    rows, cols = table_shape(fpath)
    relpath = os.path.relpath(fpath, OUT_DIR)
    print(f"  {relpath:<45s}  {rows:>6} 行 × {cols:>3} 列")

PYEOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 整合脚本失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
mgx_end "integration"
echo "[integration] 输出目录: ${OUT_DIR}"
