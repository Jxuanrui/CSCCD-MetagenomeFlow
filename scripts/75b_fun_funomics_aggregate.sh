#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 75b_fun_funomics_aggregate.sh
# 功  能: 汇总 FunOMIC/DIAMOND 真菌分类结果为 species x sample 矩阵
# 输  入: ${WORKDIR}/result/fungi/funomic/${SAMPLE}/${SAMPLE}_classification.tsv
# 输  出: ${WORKDIR}/result/integration/fungi/funomic_species_count.tsv
#         ${WORKDIR}/result/integration/fungi/normalized/funomic_species_relab.tsv
#         ${WORKDIR}/result/integration/fungi/normalized/funomic_species_clr.tsv
# 用  法: bash 75b_fun_funomics_aggregate.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 75b_fun_funomics_aggregate.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  -t  线程数（保留参数；聚合步骤不并行使用，默认: 1）
EOF
}

CPUS="1"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

FUNOMIC_DIR="${WORKDIR}/result/fungi/funomic"
OUTDIR="${WORKDIR}/result/integration/fungi"
NORMDIR="${OUTDIR}/normalized"
COUNT_TSV="${OUTDIR}/funomic_species_count.tsv"
RELAB_TSV="${NORMDIR}/funomic_species_relab.tsv"
CLR_TSV="${NORMDIR}/funomic_species_clr.tsv"

if [ ${FORCE} -eq 0 ] && [ -s "${COUNT_TSV}" ] && [ -s "${RELAB_TSV}" ] && [ -s "${CLR_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${COUNT_TSV}"
    echo "[INFO] 结果已存在，跳过: ${RELAB_TSV}"
    echo "[INFO] 结果已存在，跳过: ${CLR_TSV}"
    exit 0
fi

if [ ! -d "${FUNOMIC_DIR}" ]; then
    echo "[WARN] 未找到 FunOMIC 结果目录: ${FUNOMIC_DIR}"
    echo "[WARN] 无可汇总结果，退出 0"
    exit 0
fi

if ! find "${FUNOMIC_DIR}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
    echo "[WARN] 未检测到 FunOMIC 样本目录: ${FUNOMIC_DIR}"
    echo "[WARN] 无可汇总结果，退出 0"
    exit 0
fi

mkdir -p "${OUTDIR}" "${NORMDIR}"

EXIT_CODE=0
mgx_try mgx_conda assembly \
    python3 - "${WORKDIR}" "${REPO}" "${CPUS}" <<'PY' || EXIT_CODE=$?
import csv
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

workdir = Path(sys.argv[1])
repo = Path(sys.argv[2])
cpus = sys.argv[3]

funomic_dir = workdir / "result" / "fungi" / "funomic"
outdir = workdir / "result" / "integration" / "fungi"
normdir = outdir / "normalized"
count_tsv = outdir / "funomic_species_count.tsv"
relab_tsv = normdir / "funomic_species_relab.tsv"
clr_tsv = normdir / "funomic_species_clr.tsv"
taxonomy_tsv = repo / "db" / "funomic" / "P" / "taxonomy_for_function.csv"


def load_taxonomy(path):
    taxonomy = {}
    if not path.is_file():
        print(f"[WARN] taxonomy mapping file not found, using genome codes as labels: {path}")
        return taxonomy

    with path.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 2:
                continue
            genome_code = row[0].strip()
            species = row[1].strip()
            if genome_code and species:
                taxonomy[genome_code] = species
    return taxonomy


def genome_code_from_protein_id(protein_id):
    parts = protein_id.split("_")
    if len(parts) > 1 and parts[1]:
        return parts[1]
    return protein_id or "UNMAPPED"


def write_matrix(path, row_label, rows, samples, values, formatter):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow([row_label] + samples)
        for row in rows:
            writer.writerow([row] + [formatter(values[row].get(sample, 0.0)) for sample in samples])


taxonomy = load_taxonomy(taxonomy_tsv)
sample_dirs = sorted(p for p in funomic_dir.iterdir() if p.is_dir())
samples = []
classification_files = []

for sample_dir in sample_dirs:
    sample = sample_dir.name
    classification_file = sample_dir / f"{sample}_classification.tsv"
    if classification_file.is_file() and classification_file.stat().st_size > 0:
        samples.append(sample)
        classification_files.append((sample, classification_file))
    else:
        print(f"[WARN] skip sample without non-empty classification file: {sample}")

if not classification_files:
    print(f"[WARN] no FunOMIC classification files found under: {funomic_dir}")
    sys.exit(0)

matrix = defaultdict(lambda: defaultdict(int))
total_lines = 0
parsed_lines = 0
unmapped_codes = Counter()

for sample, classification_file in classification_files:
    genome_counts = Counter()
    with classification_file.open("r", encoding="utf-8", errors="replace", newline="") as handle:
        for line in handle:
            total_lines += 1
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 2:
                continue
            genome_code = genome_code_from_protein_id(fields[1].strip())
            genome_counts[genome_code] += 1
            parsed_lines += 1

    for genome_code, count in genome_counts.items():
        species = taxonomy.get(genome_code, genome_code)
        if genome_code not in taxonomy:
            unmapped_codes[genome_code] += count
        matrix[species][sample] += count

species_rows = sorted(matrix, key=lambda sp: (-sum(matrix[sp].values()), sp))

relab = defaultdict(dict)
sample_totals = {
    sample: sum(matrix[species].get(sample, 0) for species in species_rows)
    for sample in samples
}
for species in species_rows:
    for sample in samples:
        total = sample_totals[sample]
        relab[species][sample] = (matrix[species].get(sample, 0) / total) if total else 0.0

clr = defaultdict(dict)
epsilon = 0.01
for sample in samples:
    log_values = [math.log(matrix[species].get(sample, 0) + epsilon) for species in species_rows]
    mean_log = sum(log_values) / len(log_values) if log_values else 0.0
    for species, log_value in zip(species_rows, log_values):
        clr[species][sample] = log_value - mean_log

outdir.mkdir(parents=True, exist_ok=True)
normdir.mkdir(parents=True, exist_ok=True)
write_matrix(count_tsv, "species", species_rows, samples, matrix, lambda value: str(int(value)))
write_matrix(relab_tsv, "species", species_rows, samples, relab, lambda value: f"{value:.10g}")
write_matrix(clr_tsv, "species", species_rows, samples, clr, lambda value: f"{value:.10g}")

print(f"[fun_funomics_aggregate] shape: {len(species_rows)} species x {len(samples)} samples")
print(f"[fun_funomics_aggregate] parsed reads: {parsed_lines} / {total_lines}")
if unmapped_codes:
    print(f"[WARN] unmapped genome codes: {len(unmapped_codes)} (fallback labels used)")

print("[fun_funomics_aggregate] top 5 species by total count:")
for species in species_rows[:5]:
    total = sum(matrix[species].get(sample, 0) for sample in samples)
    print(f"  {species}\t{total}")

print(f"[fun_funomics_aggregate] outputs:")
print(f"  {count_tsv}")
print(f"  {relab_tsv}")
print(f"  {clr_tsv}")
print(f"[fun_funomics_aggregate] cpus parameter accepted: {cpus}")
PY

if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] FunOMIC 汇总失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo "[fun_funomics_aggregate] 完成"
mgx_end "fun_funomics_aggregate"
