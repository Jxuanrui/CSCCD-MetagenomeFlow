#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98d_bac_mag_integration.sh
# 功  能: 细菌维度 MAG-level 主整合表
#
#   输出:
#     mag_integration_table.tsv
#       行=dRep dereplicated/representative MAG
#       列=GTDB-Tk taxonomy + CheckM2 quality + dRep cluster/score + CoverM TPM
#
# 依  赖:
#   - dRep dereplicated genomes (result/binning/drep/dereplicated_genomes/*.fa)
#   - GTDB-Tk (result/binning/gtdbtk/classify/gtdbtk.bac120.summary.tsv)
#   - CheckM2 (result/binning/checkm2/quality_report.tsv)
#   - dRep Wdb (result/binning/drep/data_tables/Wdb.csv)
#   - CoverM quant (result/binning/coverm_quant/{sample}.tsv, 可选 per sample)
#
# 输  出: ${WORKDIR}/result/integration/bacteria/
# 用  法: bash 98d_bac_mag_integration.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 98d_bac_mag_integration.sh -w WORKDIR -r REPO [-t CPUS]

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
# -t 为保留接口（Python 侧暂未并行化）；export 供子进程读取
export CPUS

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

# --- 路径定义 ---
BIN_DIR="${WORKDIR}/result/binning"
DEREP_DIR="${BIN_DIR}/drep/dereplicated_genomes"
GTDB_FILE="${BIN_DIR}/gtdbtk/classify/gtdbtk.bac120.summary.tsv"
CHECKM2_FILE="${BIN_DIR}/checkm2/quality_report.tsv"
DREP_WDB="${BIN_DIR}/drep/data_tables/Wdb.csv"
COVERM_DIR="${BIN_DIR}/coverm_quant"
OUT_DIR="${WORKDIR}/result/integration/bacteria"
OUT_FILE="${OUT_DIR}/mag_integration_table.tsv"

if [ -f "${WORKDIR}/samplesheet_test10.csv" ]; then
    SAMPLESHEET="${WORKDIR}/samplesheet_test10.csv"
elif [ -f "${WORKDIR}/samplesheet.csv" ]; then
    SAMPLESHEET="${WORKDIR}/samplesheet.csv"
else
    SAMPLESHEET=""
fi

# 幂等检查
if [ ${FORCE} -eq 0 ] && [ -f "${OUT_FILE}" ]; then
    echo "[INFO] MAG 整合表已存在，跳过。如需重建请先删除 ${OUT_FILE}"
    exit 0
fi

mkdir -p "${OUT_DIR}"

# --- 检查必需输入 ---
MISSING=0
if [ ! -d "${DEREP_DIR}" ] || [ "$(find "${DEREP_DIR}" -maxdepth 1 -type f -name '*.fa' 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "[ERROR] 缺少 dRep dereplicated genomes: ${DEREP_DIR}"; MISSING=1
fi
for f in "${GTDB_FILE}" "${CHECKM2_FILE}" "${DREP_WDB}"; do
    if [ ! -f "${f}" ]; then
        echo "[ERROR] 缺少输入文件: ${f}"; MISSING=1
    fi
done
if [ -z "${SAMPLESHEET}" ]; then
    echo "[ERROR] 缺少样本表: ${WORKDIR}/samplesheet_test10.csv 或 ${WORKDIR}/samplesheet.csv"; MISSING=1
fi
[ ${MISSING} -eq 1 ] && exit 1

if [ ! -d "${COVERM_DIR}" ]; then
    echo "[WARNING] CoverM quant 目录缺失，所有 TPM 将填充 0: ${COVERM_DIR}"
fi

MAG_COUNT=$(find "${DEREP_DIR}" -maxdepth 1 -type f -name "*.fa" | wc -l)
echo "[mag_integration] 开始 MAG-level 整合"
echo "[mag_integration] 输出文件: ${OUT_FILE}"
echo "[mag_integration] dereplicated MAG 数: ${MAG_COUNT}"
echo "[mag_integration] 样本表: ${SAMPLESHEET}"

# ==============================================================================
# Python 整合主逻辑
# ==============================================================================

mgx_conda assembly python3 - \
    "${WORKDIR}" \
    "${OUT_DIR}" \
    "${DEREP_DIR}" \
    "${GTDB_FILE}" \
    "${CHECKM2_FILE}" \
    "${DREP_WDB}" \
    "${COVERM_DIR}" \
    "${SAMPLESHEET}" \
<<'PYEOF'
import sys
import os
import csv
import glob
from collections import defaultdict

WORKDIR      = sys.argv[1]
OUT_DIR      = sys.argv[2]
DEREP_DIR    = sys.argv[3]
GTDB_FILE    = sys.argv[4]
CHECKM2_FILE = sys.argv[5]
DREP_WDB     = sys.argv[6]
COVERM_DIR   = sys.argv[7]
SAMPLESHEET  = sys.argv[8]

OUT_FILE = os.path.join(OUT_DIR, "mag_integration_table.tsv")

def strip_fa(name):
    return name[:-3] if name.endswith(".fa") else name

def read_samples(path):
    samples = []
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            sample = row.get("sample_id", "").strip()
            if sample:
                samples.append(sample)
    return samples

def read_gtdb(path):
    data = {}
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            mag = row.get("user_genome", "").strip()
            if mag:
                data[mag] = row.get("classification", "-").strip() or "-"
    return data

def read_checkm2(path):
    data = {}
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            mag = row.get("Name", "").strip()
            if mag:
                data[mag] = (
                    row.get("Completeness", "-").strip() or "-",
                    row.get("Contamination", "-").strip() or "-",
                )
    return data

def read_drep(path):
    data = {}
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            mag = strip_fa(row.get("genome", "").strip())
            if mag:
                data[mag] = (
                    row.get("cluster", "-").strip() or "-",
                    row.get("score", "-").strip() or "-",
                )
    return data

def read_coverm(samples):
    tpm = defaultdict(dict)
    seen_mags = set()
    used_samples = []
    missing_samples = []
    skipped_empty = []

    for sample in samples:
        path = os.path.join(COVERM_DIR, f"{sample}.tsv")
        if not os.path.isfile(path):
            missing_samples.append(sample)
            print(f"  [WARNING] CoverM quant 文件缺失，TPM_{sample} 将填充 0: {path}")
            continue
        if os.path.getsize(path) == 0:
            skipped_empty.append(sample)
            continue
        with open(path, newline="") as fh:
            reader = csv.DictReader(fh, delimiter="\t")
            if not reader.fieldnames:
                skipped_empty.append(sample)
                continue
            tpm_cols = [c for c in reader.fieldnames if c.endswith(" TPM")]
            if not tpm_cols:
                print(f"  [WARNING] CoverM quant 缺少 TPM 列，TPM_{sample} 将填充 0: {path}")
                continue
            tpm_col = tpm_cols[0]
            row_count = 0
            for row in reader:
                row_count += 1
                mag = row.get("Genome", "").strip()
                if not mag or mag == "unmapped":
                    continue
                val = row.get(tpm_col, "").strip()
                if not val or val == "NA":
                    val = "0"
                tpm[mag][sample] = val
                seen_mags.add(mag)
            if row_count == 0:
                skipped_empty.append(sample)
                continue
            used_samples.append(sample)

    if skipped_empty:
        print(f"  CoverM skipped empty/header-only files: {','.join(skipped_empty)}")
    print(f"  CoverM usable sample files: {len(used_samples)} / {len(samples)}")
    return tpm, seen_mags

samples = read_samples(SAMPLESHEET)
mags = sorted(strip_fa(os.path.basename(p)) for p in glob.glob(os.path.join(DEREP_DIR, "*.fa")))

gtdb = read_gtdb(GTDB_FILE)
checkm2 = read_checkm2(CHECKM2_FILE)
drep = read_drep(DREP_WDB)
coverm_tpm, coverm_seen_mags = read_coverm(samples)

print(f"  GTDB-Tk rows: {len(gtdb)}")
print(f"  CheckM2 rows: {len(checkm2)}")
print(f"  dRep Wdb rows: {len(drep)}")
print(f"  CoverM MAGs with TPM data: {len(coverm_seen_mags)}")

complete = 0
partial = 0
rows = []

for mag in mags:
    missing_sources = []
    if mag not in gtdb:
        missing_sources.append("GTDB-Tk")
    if mag not in checkm2:
        missing_sources.append("CheckM2")
    if mag not in drep:
        missing_sources.append("dRep")
    if mag not in coverm_seen_mags:
        missing_sources.append("CoverM")

    if missing_sources:
        partial += 1
        print(f"  [WARNING] {mag}: missing source(s): {','.join(missing_sources)}")
    else:
        complete += 1

    comp, cont = checkm2.get(mag, ("-", "-"))
    cluster, score = drep.get(mag, ("-", "-"))
    row = [
        mag,
        gtdb.get(mag, "-"),
        comp,
        cont,
        cluster,
        score,
    ]
    row.extend(coverm_tpm.get(mag, {}).get(sample, "0") for sample in samples)
    rows.append(row)

with open(OUT_FILE, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow([
        "MAG_id", "GTDB_classification", "CheckM2_Completeness",
        "CheckM2_Contamination", "dRep_cluster", "dRep_score",
    ] + [f"TPM_{s}" for s in samples])
    writer.writerows(rows)

print(f"  MAG complete across all 4 sources: {complete}")
print(f"  MAG partial data: {partial}")
print(f"  → mag_integration_table.tsv: {len(rows)} 行 × {len(rows[0]) if rows else 6+len(samples)} 列")

print("\n" + "="*70)
print("[mag_integration] 完成！输出目录:", OUT_DIR)
print("="*70)
for fname in sorted(os.listdir(OUT_DIR)):
    fpath = os.path.join(OUT_DIR, fname)
    if os.path.isfile(fpath):
        with open(fpath) as fh:
            nrows = sum(1 for _ in fh) - 1
        with open(fpath) as fh:
            ncols = len(fh.readline().rstrip("\n").split("\t"))
        size_kb = os.path.getsize(fpath) // 1024
        print(f"  {fname:<45s}  {nrows:>6} 行 × {ncols:>3} 列  ({size_kb} KB)")
PYEOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] MAG-level 整合失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
mgx_end "mag_integration"
echo "[mag_integration] 输出文件: ${OUT_FILE}"
