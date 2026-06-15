#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74d_fun_cgf_aggregate.sh
# 功  能: 汇总 CGF profiler 真菌结果为 species x sample 矩阵
# 输  入: ${WORKDIR}/result/fungi/cgf_profiler/${SAMPLE}/${SAMPLE}_cgf_abundance.tsv
# 输  出: ${WORKDIR}/result/integration/fungi/cgf_species_norm.tsv
#         ${WORKDIR}/result/integration/fungi/cgf_species_count.tsv
#         ${WORKDIR}/result/integration/fungi/normalized/cgf_species_relab.tsv
#         ${WORKDIR}/result/integration/fungi/normalized/cgf_species_clr.tsv
# 用  法: bash 74d_fun_cgf_aggregate.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

show_help() {
cat << EOF
用法: bash 74d_fun_cgf_aggregate.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录
  -r  MaxMetagenome 项目根目录

可选参数:
  -t  线程数（保留参数；聚合步骤不并行使用，默认: 1）
EOF
}

WORKDIR=""; REPO=""; CPUS="1"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

for v in WORKDIR REPO; do
    if [ -z "${!v}" ]; then
        echo "[ERROR] 缺少必需参数: ${v}"
        show_help
        exit 1
    fi
done

SECONDS=0

CGF_DIR="${WORKDIR}/result/fungi/cgf_profiler"
OUTDIR="${WORKDIR}/result/integration/fungi"
NORMDIR="${OUTDIR}/normalized"
NORM_TSV="${OUTDIR}/cgf_species_norm.tsv"
COUNT_TSV="${OUTDIR}/cgf_species_count.tsv"
RELAB_TSV="${NORMDIR}/cgf_species_relab.tsv"
CLR_TSV="${NORMDIR}/cgf_species_clr.tsv"
RUN_ENV="${REPO}/envs/assembly"

if [ -s "${NORM_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${NORM_TSV}"
    exit 0
fi

if [ ! -d "${CGF_DIR}" ]; then
    echo "[WARN] 未找到 CGF profiler 结果目录: ${CGF_DIR}"
    echo "[WARN] 无可汇总结果，退出 0"
    exit 0
fi

if ! find "${CGF_DIR}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
    echo "[WARN] 未检测到 CGF profiler 样本目录: ${CGF_DIR}"
    echo "[WARN] 无可汇总结果，退出 0"
    exit 0
fi

mkdir -p "${OUTDIR}" "${NORMDIR}"

conda run --prefix "${RUN_ENV}" --no-capture-output \
    python3 - "${WORKDIR}" "${CPUS}" <<'PY'
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

workdir = Path(sys.argv[1])
cpus = sys.argv[2]

cgf_dir = workdir / "result" / "fungi" / "cgf_profiler"
outdir = workdir / "result" / "integration" / "fungi"
normdir = outdir / "normalized"
norm_tsv = outdir / "cgf_species_norm.tsv"
count_tsv = outdir / "cgf_species_count.tsv"
relab_tsv = normdir / "cgf_species_relab.tsv"
clr_tsv = normdir / "cgf_species_clr.tsv"


def parse_float(value, path, line_number, column_name):
    try:
        return float(value)
    except ValueError:
        print(f"[WARN] skip non-numeric {column_name}: {path}:{line_number}: {value!r}")
        return None


def write_matrix(path, row_label, rows, samples, values, formatter):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow([row_label] + samples)
        for row in rows:
            writer.writerow([row] + [formatter(values[row].get(sample, 0.0)) for sample in samples])


sample_dirs = sorted(p for p in cgf_dir.iterdir() if p.is_dir())
samples = []
abundance_files = []

for sample_dir in sample_dirs:
    sample = sample_dir.name
    abundance_file = sample_dir / f"{sample}_cgf_abundance.tsv"
    if abundance_file.is_file() and abundance_file.stat().st_size > 0:
        samples.append(sample)
        abundance_files.append((sample, abundance_file))
    else:
        print(f"[WARN] skip sample without non-empty CGF abundance file: {sample}")

if not abundance_files:
    print(f"[WARN] no CGF abundance files found under: {cgf_dir}")
    sys.exit(0)

norm_matrix = defaultdict(lambda: defaultdict(float))
count_matrix = defaultdict(lambda: defaultdict(float))
total_lines = 0
parsed_lines = 0

for sample, abundance_file in abundance_files:
    with abundance_file.open("r", encoding="utf-8", errors="replace", newline="") as handle:
        for line_number, row in enumerate(csv.reader(handle, delimiter="\t"), start=1):
            total_lines += 1
            if not row or all(not field.strip() for field in row):
                continue
            if len(row) < 6:
                print(f"[WARN] skip short row: {abundance_file}:{line_number}")
                continue

            species = row[0].strip()
            if not species or species.lower() == "species":
                continue

            total = parse_float(row[3].strip(), abundance_file, line_number, "total")
            norm_abundance = parse_float(row[5].strip(), abundance_file, line_number, "norm_abundance")
            if total is None or norm_abundance is None:
                continue

            count_matrix[species][sample] += total
            norm_matrix[species][sample] += norm_abundance
            parsed_lines += 1

species_rows = sorted(
    norm_matrix,
    key=lambda species: (-sum(norm_matrix[species].values()), species),
)

relab = defaultdict(dict)
sample_totals = {
    sample: sum(norm_matrix[species].get(sample, 0.0) for species in species_rows)
    for sample in samples
}
for species in species_rows:
    for sample in samples:
        total = sample_totals[sample]
        relab[species][sample] = (norm_matrix[species].get(sample, 0.0) / total) if total else 0.0

clr = defaultdict(dict)
epsilon = 0.01
for sample in samples:
    log_values = [
        math.log(norm_matrix[species].get(sample, 0.0) + epsilon)
        for species in species_rows
    ]
    mean_log = sum(log_values) / len(log_values) if log_values else 0.0
    for species, log_value in zip(species_rows, log_values):
        clr[species][sample] = log_value - mean_log

outdir.mkdir(parents=True, exist_ok=True)
normdir.mkdir(parents=True, exist_ok=True)
write_matrix(norm_tsv, "species", species_rows, samples, norm_matrix, lambda value: f"{value:.10g}")
write_matrix(count_tsv, "species", species_rows, samples, count_matrix, lambda value: f"{value:.10g}")
write_matrix(relab_tsv, "species", species_rows, samples, relab, lambda value: f"{value:.10g}")
write_matrix(clr_tsv, "species", species_rows, samples, clr, lambda value: f"{value:.10g}")

print(f"[fun_cgf_aggregate] shape: {len(species_rows)} species x {len(samples)} samples")
print(f"[fun_cgf_aggregate] parsed rows: {parsed_lines} / {total_lines}")
print("[fun_cgf_aggregate] top 5 species by total abundance:")
for species in species_rows[:5]:
    total = sum(norm_matrix[species].get(sample, 0.0) for sample in samples)
    print(f"  {species}\t{total:.10g}")

print("[fun_cgf_aggregate] outputs:")
print(f"  {norm_tsv}")
print(f"  {count_tsv}")
print(f"  {relab_tsv}")
print(f"  {clr_tsv}")
print(f"[fun_cgf_aggregate] cpus parameter accepted: {cpus}")
PY

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] CGF profiler 汇总失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo "[fun_cgf_aggregate] 完成，耗时 ${SECONDS}s"
