#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 49a_smorf_antismash_harvest.sh
# 功  能: B 路线 · antiSMASH 核心肽（前体）收割器——解析 28 号现产 region GBK，
#         从 RiPP/细菌素类区域提取 proto_core 坐标处的 CDS 翻译序列（前体肽）。
# 口  径（严格抽取，用户决策 D-1）:
#         1) 仅处理 protocluster /category 为 RiPP（含 RiPP-like、lanthipeptide、
#            ranthipeptide、lassopeptide、thiopeptide 等子类）的区域；
#         2) 核心肽 = 与 proto_core 特征坐标重叠的 CDS 的 /translation；
#         3) 该序列为**前体肽**（含 leader 区可能未切除），非成熟加工肽——
#            表中 precursor 列如实标注，不冒充成熟核心肽；
#         4) 一个区域含多个 protocluster/proto_core 时逐条输出（multi-core 标注）；
#         5) 无 proto_core、无重叠 CDS、无 /translation 的情况分别计数并保留
#            原因（不静默丢弃）。
# 依  赖: 28 号 antiSMASH 现产输出（${WORKDIR}/result/annotation/antismash/*/*.region*.gbk）
# 输  出: ${WORKDIR}/result/peptide/broute/antismash_precursors.tsv（元数据长表）
#         ${WORKDIR}/result/peptide/broute/antismash_precursors.faa（序列）
#         ${WORKDIR}/result/peptide/broute/antismash_harvest.qc.md（计数闭合报告）
#         broute_antismash.done / .FAILED
# 用  法: bash 49a_smorf_antismash_harvest.sh -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 49a_smorf_antismash_harvest.sh -w WORKDIR -r REPO [--force]

Harvests RiPP/bacteriocin precursor peptides from existing antiSMASH
region GBK files (zero new compute — parses 28号 production output).
EOF
}

if [ $# -eq 0 ]; then
    show_help; exit 0
fi

export MGX_OPTS_STRING="w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO
WORKDIR="$(cd "${WORKDIR}" && pwd)"

mgx_begin

AS_DIR="${WORKDIR}/result/annotation/antismash"
OUT="${WORKDIR}/result/peptide/broute"
LOG="${WORKDIR}/logs/peptide/broute"
mkdir -p "${OUT}" "${LOG}"
LOG_FILE="${LOG}/49a_harvest_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

SENTINEL="${OUT}/broute_antismash.done"
rm -f "${SENTINEL}" "${SENTINEL}.FAILED"

if ! ls "${AS_DIR}"/*/*.region*.gbk >/dev/null 2>&1; then
    echo "[ERROR] 未找到 28 号 region GBK: ${AS_DIR}/*/*.region*.gbk" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[INFO] 49a antiSMASH 前体肽收割启动 $(date -u '+%F %T')"

python3 - "${AS_DIR}" "${OUT}" <<'PYEOF'
import collections, glob, os, re, sys

AS_DIR, OUT = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(f"{AS_DIR}/*/*.region*.gbk"))
print(f"[plan] region GBK: {len(files)}")

# GBK 特征解析（最小实现，仅依赖标准库）
# 特征起始: 5 空格 + 特征名 + 空格 + 坐标；qualifier: ≥8 空格 + /key=value（值可跨行）
FEAT_RE = re.compile(r"^ {5}(\S+)\s+(\S+)")
QUAL_RE = re.compile(r"^\s+/(\w+)=(.*)$")

def parse_gbk(path):
    """产出 (feature_type, location, {qualifier: joined_value}) 序列。"""
    feats = []
    ftype = loc = None
    quals = {}
    cur_key = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = FEAT_RE.match(line)
            if m:
                if ftype is not None:
                    feats.append((ftype, loc, quals))
                ftype, loc = m.group(1), m.group(2)
                quals, cur_key = {}, None
                continue
            if ftype is None:
                continue
            qm = QUAL_RE.match(line)
            if qm:
                cur_key = qm.group(1)
                quals[cur_key] = qm.group(2).strip('"')
            elif cur_key and line.startswith(" "):
                quals[cur_key] += line.strip()
            else:
                cur_key = None
    if ftype is not None:
        feats.append((ftype, loc, quals))
    return feats

def parse_core_locs(loc):
    """proto_core/complement(488..643) -> [(488,643), ...]（1-based 闭区间）。"""
    out = []
    for part in loc.split(","):
        mm = re.search(r"(\d+)\.\.(\d+)", part)
        if mm:
            out.append((int(mm.group(1)), int(mm.group(2))))
    return out

def cds_matches(cds_loc, core_locs, min_frac=0.5):
    """严格口径：CDS 跨度的 >=50% 落在任一 proto_core 区间内才算核心肽前体基因。
    仅擦边重叠（1-2 密码子）的碎片 CDS 会被排除，避免无意义微肽。"""
    nums = re.findall(r"\d+", cds_loc.replace("complement", ""))
    if len(nums) < 2:
        return False
    a, b = int(nums[0]), int(nums[1])
    span = max(b - a + 1, 1)
    for s, e in core_locs:
        ov = min(b, e) - max(a, s) + 1
        if ov > 0 and ov / span >= min_frac:
            return True
    return False

rows = []
skip = collections.Counter()
for f in files:
    sample = os.path.basename(os.path.dirname(f))
    region_file = os.path.basename(f)
    feats = parse_gbk(f)
    category = product = None
    proto_cores = []
    for ftype, loc, q in feats:
        if ftype == "protocluster":
            category = q.get("category", category)
            product = q.get("product", product)
        if ftype == "proto_core":
            proto_cores += parse_core_locs(loc)
    if category != "RiPP":
        skip["non_RiPP_category"] += 1
        continue
    if not proto_cores:
        skip["no_proto_core"] += 1
        continue
    hit = False
    for ftype, loc, q in feats:
        if ftype != "CDS":
            continue
        if not cds_matches(loc, proto_cores):
            continue
        tr = q.get("translation", "").strip('"')
        if not tr:
            skip["core_cds_without_translation"] += 1
            continue
        if len(tr) < 10:
            skip["tiny_precursor_lt10aa"] += 1
            continue
        hit = True
        rows.append((f"{sample}|{q.get('locus_tag', region_file)}",
                     sample, region_file, q.get("locus_tag", ""),
                     product or "", loc, proto_cores and str(proto_cores) or "",
                     len(tr), tr, "proto_core_overlapping_cds"))
    if not hit:
        skip["region_without_matching_cds"] += 1

# 计数闭合报告
qc = [f"# antiSMASH 前体肽收割 QC（RiPP 严格口径）", "",
      f"region GBK 总数: {len(files)}",
      f"proto_core 命中并提取前体: {len(rows)}",
      f"跳过/计数闭合:"]
for k, v in skip.items():
    qc.append(f"  - {k}: {v}")
qc.append("")
qc.append("口径: 前体肽 = proto_core 坐标重叠 CDS 的 translation（含 leader 可能未切除），非成熟加工肽")

with open(f"{OUT}/antismash_precursors.tsv", "w", encoding="utf-8") as t:
    t.write("peptide_id\tsample\tregion_file\tlocus_tag\tproduct\tcds_location\t"
            "proto_core_coords\tlength_aa\textraction_rule\n")
    for r in rows:
        t.write("\t".join(str(x) for x in r[:8]) + "\tprecursor:proto_core_overlapping_cds\n")
with open(f"{OUT}/antismash_precursors.faa", "w", encoding="utf-8") as fa:
    for r in rows:
        fa.write(f">{r[0]}\n{r[8]}\n")
with open(f"{OUT}/antismash_harvest.qc.md", "w", encoding="utf-8") as m:
    m.write("\n".join(qc) + "\n")
print("\n".join(qc))
print(f"[done] precursors: {len(rows)}")
if len(files) and not rows:
    print("[WARN] 无任何前体提取（请核对口径）", file=sys.stderr)
PYEOF

if [ ! -s "${OUT}/antismash_precursors.tsv" ]; then
    echo "[ERROR] 未产出前体表" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[DONE] $(date -u '+%F %T') antismash_harvest"
date -u '+%F %T' > "${SENTINEL}"
mgx_end "broute_antismash"
