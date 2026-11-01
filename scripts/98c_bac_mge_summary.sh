#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98c_bac_mge_summary.sh
# 功  能: 细菌维度 MGE + 质粒 per-sample 汇总表
#
#   输出:
#     mge_plasmid_summary.tsv
#       行=样本
#       列=5类 MGE 命中数 + PlasmidFinder contig/replicon 摘要
#
# 依  赖:
#   - scripts/42: MGE (result/mge/{isfinder,iceberg,integrall,transposase}/...)
#   - scripts/42: mobileOG NR (result/mge/mobileog/mobileog_nr_hits.tsv)
#   - scripts/42b: PlasmidFinder (result/mge/plasmidfinder/{sample}/results_tab.tsv, 可选)
#
# 输  出: ${WORKDIR}/result/integration/bacteria/
# 用  法: bash 98c_bac_mge_summary.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 98c_bac_mge_summary.sh -w WORKDIR -r REPO [-t CPUS]

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
MGE_DIR="${WORKDIR}/result/mge"
OUT_DIR="${WORKDIR}/result/integration/bacteria"
OUT_FILE="${OUT_DIR}/mge_plasmid_summary.tsv"

# 幂等检查
if [ ${FORCE} -eq 0 ] && [ -f "${OUT_FILE}" ]; then
    echo "[INFO] MGE/质粒汇总表已存在，跳过。如需重建请先删除 ${OUT_FILE}"
    exit 0
fi

mkdir -p "${OUT_DIR}"

# --- 检查至少存在一类 42/42b 输出 ---
MGE_FOUND=0
for pattern in \
    "isfinder/*/isfinder_hits.tsv" \
    "iceberg/*/iceberg_hits.tsv" \
    "integrall/*/integrall_hits.tsv" \
    "transposase/*/transposase_hits.tsv" \
    "mobileog/mobileog_nr_hits.tsv" \
    "plasmidfinder/*/results_tab.tsv"; do
    COUNT=$(find "${MGE_DIR}" -path "${MGE_DIR}/${pattern}" -type f 2>/dev/null | wc -l)
    MGE_FOUND=$((MGE_FOUND + COUNT))
done

if [ "${MGE_FOUND}" -eq 0 ]; then
    echo "[ERROR] 未找到任何 MGE/PlasmidFinder 输入文件: ${MGE_DIR}"
    echo "        请先至少运行一次 scripts/42_bac_mge.sh 或 scripts/42b_bac_plasmidfinder.sh"
    exit 1
fi

echo "[mge_summary] 开始 MGE + 质粒 per-sample 汇总"
echo "[mge_summary] 输出文件: ${OUT_FILE}"
echo "[mge_summary] 找到 ${MGE_FOUND} 个 MGE/PlasmidFinder 输入文件"

# ==============================================================================
# Python 整合主逻辑
# ==============================================================================

mgx_conda assembly python3 - \
    "${WORKDIR}" \
    "${OUT_DIR}" \
<<'PYEOF'
import sys
import os
import csv
import glob
from collections import defaultdict

WORKDIR = sys.argv[1]
OUT_DIR = sys.argv[2]

MGE_DIR = os.path.join(WORKDIR, "result", "mge")
OUT_FILE = os.path.join(OUT_DIR, "mge_plasmid_summary.tsv")

def read_samples():
    for fname in ("samplesheet_test10.csv", "samplesheet.csv"):
        path = os.path.join(WORKDIR, fname)
        if os.path.isfile(path):
            samples = []
            with open(path, newline="") as fh:
                reader = csv.DictReader(fh)
                for row in reader:
                    sample = row.get("sample_id", "").strip()
                    if sample:
                        samples.append(sample)
            if samples:
                print(f"  样本来源: {fname} ({len(samples)} samples)")
                return samples

    samples = set()
    for pattern in (
        os.path.join(MGE_DIR, "isfinder", "*"),
        os.path.join(MGE_DIR, "iceberg", "*"),
        os.path.join(MGE_DIR, "integrall", "*"),
        os.path.join(MGE_DIR, "transposase", "*"),
        os.path.join(MGE_DIR, "plasmidfinder", "*"),
    ):
        for path in glob.glob(pattern):
            if os.path.isdir(path):
                samples.add(os.path.basename(path))
    samples = sorted(samples)
    if samples:
        print(f"  [WARNING] 未找到 samplesheet，改用 result/mge 下的样本目录 ({len(samples)} samples)")
        return samples

    print("  [ERROR] 未找到样本列表（samplesheet_test10.csv/samplesheet.csv 或 result/mge 样本目录）")
    sys.exit(1)

def count_hit_lines(path, skip_comments=False):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return 0
    n = 0
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if skip_comments and line.startswith("#"):
                continue
            n += 1
    return n

def parse_mobileog_by_sample(path):
    counts = defaultdict(int)
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return counts
    with open(path) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            query = parts[0].strip()
            if "|" not in query:
                continue
            sample = query.split("|", 1)[0]
            counts[sample] += 1
    return counts

def parse_plasmidfinder(path):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return 0, "-"

    header = None
    rows = []
    with open(path, newline="") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            lower = [x.strip().lower() for x in parts]
            if header is None and (
                "contig" in lower or "plasmid" in lower or "replicon" in lower or
                "inc group" in lower or "incompatibility group" in lower
            ):
                header = parts
                continue
            if parts[0].startswith("Database") or parts[0].startswith("Plasmidfinder"):
                continue
            rows.append(parts)

    if not rows:
        return 0, "-"

    contigs = set()
    groups = set()

    if header:
        lower_header = [h.strip().lower() for h in header]
        contig_idx = None
        group_idx = None
        for i, name in enumerate(lower_header):
            if contig_idx is None and name in ("contig", "query", "qseqid", "contig id"):
                contig_idx = i
            if group_idx is None and name in (
                "plasmid", "replicon", "replicon type", "inc group",
                "incompatibility group", "inc_type"
            ):
                group_idx = i
        for row in rows:
            if contig_idx is not None and len(row) > contig_idx and row[contig_idx].strip():
                contigs.add(row[contig_idx].strip())
            if group_idx is not None and len(row) > group_idx and row[group_idx].strip():
                groups.add(row[group_idx].strip())
    else:
        for row in rows:
            if len(row) > 4 and row[4].strip():
                contigs.add(row[4].strip())
            if len(row) > 1 and row[1].strip():
                groups.add(row[1].strip())

    contig_count = len(contigs) if contigs else len(rows)
    group_list = ";".join(sorted(groups)) if groups else "-"
    return contig_count, group_list

samples = read_samples()
mobileog_file = os.path.join(MGE_DIR, "mobileog", "mobileog_nr_hits.tsv")
mobileog_counts = parse_mobileog_by_sample(mobileog_file)
if not os.path.isfile(mobileog_file):
    print(f"  [WARNING] mobileOG NR 输入缺失，MobileOG_hits 将填充 0: {mobileog_file}")

rows = []
for sample in samples:
    paths = {
        "ISfinder_hits": os.path.join(MGE_DIR, "isfinder", sample, "isfinder_hits.tsv"),
        "ICEberg_hits": os.path.join(MGE_DIR, "iceberg", sample, "iceberg_hits.tsv"),
        "Integrall_hits": os.path.join(MGE_DIR, "integrall", sample, "integrall_hits.tsv"),
        "Transposase_hits": os.path.join(MGE_DIR, "transposase", sample, "transposase_hits.tsv"),
        "PlasmidFinder": os.path.join(MGE_DIR, "plasmidfinder", sample, "results_tab.tsv"),
    }

    for label, path in paths.items():
        if not os.path.isfile(path):
            print(f"  [WARNING] {sample}: 可选输入缺失 ({label}): {path}")

    plasmid_count, plasmid_groups = parse_plasmidfinder(paths["PlasmidFinder"])
    rows.append([
        sample,
        count_hit_lines(paths["ISfinder_hits"]),
        count_hit_lines(paths["ICEberg_hits"]),
        count_hit_lines(paths["Integrall_hits"]),
        count_hit_lines(paths["Transposase_hits"], skip_comments=True),
        mobileog_counts.get(sample, 0),
        plasmid_count,
        plasmid_groups,
    ])

with open(OUT_FILE, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow([
        "sample_id", "ISfinder_hits", "ICEberg_hits", "Integrall_hits",
        "Transposase_hits", "MobileOG_hits", "Plasmid_contigs_count",
        "Plasmid_replicon_groups"
    ])
    writer.writerows(rows)

print(f"  → mge_plasmid_summary.tsv: {len(rows)} 行 × 8 列")

print("\n" + "="*70)
print("[mge_summary] 完成！输出目录:", OUT_DIR)
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
    echo "[ERROR] MGE/质粒汇总失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
mgx_end "mge_summary"
echo "[mge_summary] 输出文件: ${OUT_FILE}"
