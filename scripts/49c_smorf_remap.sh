#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 49c_smorf_remap.sh
# 功  能: B 路线 · 候选回映射器——把 antiSMASH / Macrel 候选映射回我方 Prodigal
#         基因，产出契约冻结的候选证据表 candidate_evidence.tsv（14 列，
#         docs/plans/peptide_contract.md，50 号按契约接入）。
# 口  径:
#   1) antiSMASH 前体: peptide_id 样本前缀选定该样本的 44 号 smorf.tsv，
#      gene_id（"|" 后段）直接 ID join（命中=exact_mapped，前体来自同源
#      基因预测，按 ID 对齐口径）；未命中=unmapped_only_candidate 并记原因。
#   2) Macrel 候选: 取 macrel.out.smorfs.faa 的 smORF 全序列（去尾部 *），
#      对 17 号 Prodigal FAA（去尾部 *）序列精确匹配 → exact_mapped；
#      未命中做双向包含性检查（候选 ⊆ 翻译 或 翻译 ⊆ 候选）→
#      contained_mapped；同一序列命中多个样本的基因 → ambiguous；
#      仍无命中 → unmapped_only_candidate。
#   3) 坐标列保留工具原样字符串（antiSMASH=GBk CDS location；Macrel 1.6.0
#      预测产物不含坐标列 → NA），coords_note 声明坐标体系。
#   4) 自测断言: 输出行数 == 两路输入候选合计（候选全保留）且五分项
#      合计 == 总行数，任一不成立则哨兵置 FAILED 并以非零退出。
# 依  赖: 49a antismash_precursors.tsv；49b macrel_precursors.tsv +
#         macrel_raw/macrel.out.smorfs.faa；44 smorf.tsv；17 prodigal faa；
#         28 region GBK（仅读 Version 注记作为 tool_version）
# 输  出: ${WORKDIR}/result/peptide/integration/candidate_evidence.tsv
#         ${WORKDIR}/result/peptide/broute/remap_qc.md
#         broute_remap.done / .FAILED
# 用  法: bash 49c_smorf_remap.sh -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 49c_smorf_remap.sh -w WORKDIR -r REPO

Remaps B-route peptide candidates (antiSMASH precursors + Macrel AMPs) back
onto our Prodigal genes; emits the frozen-contract candidate_evidence.tsv
(14 columns) plus remap_qc.md with five-way remap counts.
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

BROUTE="${WORKDIR}/result/peptide/broute"
INTEG="${WORKDIR}/result/peptide/integration"
SMORF_DIR="${WORKDIR}/result/peptide/smorf"
PRODIGAL_DIR="${WORKDIR}/result/assembly/prodigal"
AS_DIR="${WORKDIR}/result/annotation/antismash"
AS_TSV="${BROUTE}/antismash_precursors.tsv"
MAC_TSV="${BROUTE}/macrel_precursors.tsv"
SMORFS_FAA="${BROUTE}/macrel_raw/macrel.out.smorfs.faa"
OUT_TSV="${INTEG}/candidate_evidence.tsv"
QC_MD="${BROUTE}/remap_qc.md"
LOG="${WORKDIR}/logs/peptide/broute"
mkdir -p "${INTEG}" "${BROUTE}" "${LOG}"
LOG_FILE="${LOG}/49c_remap_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

SENTINEL="${BROUTE}/broute_remap.done"
rm -f "${SENTINEL}" "${SENTINEL}.FAILED"

fail() {
    echo "[ERROR] $1" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
}

for f in "${AS_TSV}" "${MAC_TSV}" "${SMORFS_FAA}"; do
    [ -s "${f}" ] || fail "输入缺失或为空: ${f}（需先跑 49a/49b）"
done
ls "${SMORF_DIR}"/*.smorf.tsv >/dev/null 2>&1 || fail "未找到 44 号 smorf.tsv: ${SMORF_DIR}/*.smorf.tsv"
ls "${PRODIGAL_DIR}"/*/*.faa >/dev/null 2>&1 || fail "未找到 17 号 Prodigal FAA: ${PRODIGAL_DIR}/*/*.faa"

# 输入候选行数（自测基准：输出行数必须等于两路合计）
N_AS=$(awk 'END{print NR-1}' "${AS_TSV}")
N_MAC=$(awk 'END{print NR-1}' "${MAC_TSV}")

echo "[INFO] 49c 候选回映射启动 $(date -u '+%F %T') | antismash=${N_AS} macrel=${N_MAC}"

if ! python3 -I - "${AS_TSV}" "${MAC_TSV}" "${SMORFS_FAA}" "${SMORF_DIR}" \
    "${PRODIGAL_DIR}" "${AS_DIR}" "${OUT_TSV}" "${QC_MD}" <<'PYEOF'
import glob
import hashlib
import os
import re
import sys
from datetime import datetime, timezone

AS_TSV, MAC_TSV, SMORFS_FAA, SMORF_DIR, PRODIGAL_DIR, AS_DIR, OUT_TSV, QC_MD = sys.argv[1:9]

STATUS_ORDER = ["exact_mapped", "contained_mapped", "ambiguous",
                "unmapped_only_candidate", "not_attempted"]
HEADER = ["candidate_id", "source_tool", "tool_version", "sample", "gene_id",
          "contig_id", "coords", "coords_note", "family", "probability",
          "remap_status", "remap_note", "evidence_type", "nn_status"]


def read_fasta(path):
    name, chunks = None, []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith(">"):
                if name is not None:
                    yield name, "".join(chunks)
                name, chunks = line[1:].split()[0], []
            else:
                chunks.append(line.strip())
    if name is not None:
        yield name, "".join(chunks)


def norm(seq):
    """序列比对键：统一大写、去尾部终止符 *（坐标/前导不改动）。"""
    return seq.rstrip("*").upper()


def read_tsv(path):
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        col = {name: i for i, name in enumerate(header)}
        for line in fh:
            line = line.rstrip("\n")
            if line:
                yield line.split("\t"), col


counts = dict.fromkeys(STATUS_ORDER, 0)
per_tool = {}
rows = []
seen_ids = set()

# ---- antiSMASH tool_version：28 号产物注记（region GBK COMMENT Version 行）----
as_version = "unknown"
gbks = sorted(glob.glob(os.path.join(AS_DIR, "*", "*.region*.gbk")))
if gbks:
    with open(gbks[0], encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"\s+Version\s+::\s+(.+?)\s*$", line)
            if m:
                as_version = m.group(1)
                break

# ---- 44 号 smorf 目录：样本 -> gene_id 集合 ----
catalog = {}
for tsv in sorted(glob.glob(os.path.join(SMORF_DIR, "*.smorf.tsv"))):
    sample = os.path.basename(tsv).split(".")[0]
    with open(tsv, encoding="utf-8") as fh:
        next(fh)
        catalog[sample] = {ln.split("\t", 1)[0] for ln in fh if ln.strip()}

# ---- antiSMASH 前体回映射：44 号 ID join ----
n_as = 0
n_cid_sfx = 0
cid_seq = {}
for v, col in read_tsv(AS_TSV):
    n_as += 1
    pid = v[col["peptide_id"]]
    sample = v[col["sample"]]
    coords = v[col["cds_location"]]
    family = v[col["product"]]
    contig = re.sub(r"\.region\d+\.gbk$", "", v[col["region_file"]])
    gene_id = pid.split("|", 1)[1] if "|" in pid else pid
    cid = f"antismash:{pid}"
    # candidate_id 契约要求全局唯一，而输入 locus_tag 存在跨 region 撞名
    # （antiSMASH chunk 内部编号重启）；首现保留契约原格式，重现追加 #k 后缀，
    # 行全保留（候选全保留口径）。
    if cid in seen_ids:
        cid_seq[cid] = cid_seq.get(cid, 1) + 1
        cid = f"{cid}#{cid_seq[cid]}"
        n_cid_sfx += 1
    seen_ids.add(cid)
    if sample not in catalog:
        status, note = "unmapped_only_candidate", "sample_smorf_catalog_missing"
    elif gene_id in catalog[sample]:
        status, note = "exact_mapped", "id_join_44_smorf_catalog"
    else:
        status, note = ("unmapped_only_candidate",
                        "id_join_miss_gene_id_not_in_44_smorf_catalog")
    rows.append([cid, "antismash", as_version, sample,
                 gene_id if status == "exact_mapped" else "NA", contig, coords,
                 "antismash_1based_closed", family, "NA", status, note,
                 "annotation_rule", "not_applicable_b_route"])
    counts[status] += 1
    per_tool.setdefault("antismash", dict.fromkeys(STATUS_ORDER, 0))[status] += 1

# ---- Macrel 候选：smORF 全序列 -> 17 号 FAA 序列精确/包含匹配 ----
smorfs = dict(read_fasta(SMORFS_FAA))
prot_index = {}
n_prot = 0
for faa in sorted(glob.glob(os.path.join(PRODIGAL_DIR, "*", "*.faa"))):
    sample = os.path.basename(os.path.dirname(faa))
    for gid, seq in read_fasta(faa):
        n_prot += 1
        prot_index.setdefault(hashlib.md5(norm(seq).encode()).digest(), []).append((sample, gid))


def classify(hits, status, base_note):
    """多命中消歧：同序列命中多个样本 -> ambiguous；单样本 -> 取该样本基因。"""
    samples = sorted({s for s, _ in hits})
    if len(samples) > 1:
        pairs = ",".join(f"{s}:{g}" for s, g in sorted(hits)[:5])
        if len(hits) > 5:
            pairs += ",..."
        return ("ambiguous", "NA", "NA", f"{base_note}_multi_sample:{pairs}")
    genes = sorted({g for _, g in hits})
    note = base_note if len(genes) == 1 else f"{base_note}_multi_gene_same_sample"
    return (status, samples[0], ",".join(genes), note)


mac_cands = []
n_mac = 0
for v, col in read_tsv(MAC_TSV):
    n_mac += 1
    pid = v[col["peptide_id"]]
    family = v[col["amp_family"]]
    prob = v[col["amp_probability"]] or "NA"
    ev = v[col["evidence_type"]] or "model_prediction"
    ver = v[col["tool_version"]] or "macrel"
    contig = pid.rsplit("_", 1)[0] if "_" in pid else pid
    if pid in smorfs:
        seq, seq_src = norm(smorfs[pid]), "macrel_smorf_full_seq"
    else:
        seq, seq_src = norm(v[col["sequence"]]), "smorf_seq_missing_fallback_prediction_seq"
    mac_cands.append((pid, seq, seq_src, family, prob, ev, ver, contig))

unmatched = []
for pid, seq, seq_src, family, prob, ev, ver, contig in mac_cands:
    cid = f"macrel:{pid}"
    if cid in seen_ids:
        cid_seq[cid] = cid_seq.get(cid, 1) + 1
        cid = f"{cid}#{cid_seq[cid]}"
        n_cid_sfx += 1
    seen_ids.add(cid)
    seq_src_sfx = "" if seq_src == "macrel_smorf_full_seq" else f"|{seq_src}"
    hits = prot_index.get(hashlib.md5(seq.encode()).digest(), [])
    if hits:
        status, sample, gene_id, note = classify(hits, "exact_mapped", "seq_exact")
        note += seq_src_sfx
        rows.append([cid, "macrel", ver, sample, gene_id, contig, "NA",
                     "macrel_1based_closed", family, prob, status, note,
                     ev, "not_applicable_b_route"])
        counts[status] += 1
        per_tool.setdefault("macrel", dict.fromkeys(STATUS_ORDER, 0))[status] += 1
    else:
        unmatched.append((pid, seq, family, prob, ev, ver, contig, seq_src_sfx))

# ---- 包含性回映射（仅精确未命中候选；单次流式扫描全蛋白）----
if unmatched:
    cont_hits = {i: [] for i in range(len(unmatched))}
    for faa in sorted(glob.glob(os.path.join(PRODIGAL_DIR, "*", "*.faa"))):
        sample = os.path.basename(os.path.dirname(faa))
        for gid, pseq in read_fasta(faa):
            p = norm(pseq)
            for i, cand in enumerate(unmatched):
                s = cand[1]
                if (len(p) >= len(s) and s in p) or (len(p) <= len(s) and p in s):
                    cont_hits[i].append((sample, gid))
    for i, (pid, seq, family, prob, ev, ver, contig, seq_src_sfx) in enumerate(unmatched):
        hits = cont_hits[i]
        if hits:
            status, sample, gene_id, note = classify(hits, "contained_mapped", "seq_contained")
            note += seq_src_sfx
        else:
            status, sample, gene_id = "unmapped_only_candidate", "NA", "NA"
            note = "no_exact_or_containment_match_vs_prodigal_faa" + seq_src_sfx
        rows.append([f"macrel:{pid}", "macrel", ver, sample, gene_id, contig, "NA",
                     "macrel_1based_closed", family, prob, status, note,
                     ev, "not_applicable_b_route"])
        counts[status] += 1
        per_tool.setdefault("macrel", dict.fromkeys(STATUS_ORDER, 0))[status] += 1

# ---- 自测断言（候选全保留 + 五分项闭合 + candidate_id 唯一）----
total = len(rows)
five_sum = sum(counts.values())
if not (total == n_as + n_mac == five_sum):
    print(f"[ERROR] 自测失败: total={total} in={n_as + n_mac} five_sum={five_sum}",
          file=sys.stderr)
    sys.exit(2)

rows.sort(key=lambda r: r[0])
os.makedirs(os.path.dirname(OUT_TSV), exist_ok=True)
with open(OUT_TSV, "w", encoding="utf-8") as o:
    o.write("\t".join(HEADER) + "\n")
    for r in rows:
        o.write("\t".join(r) + "\n")

# ---- QC 报告 ----
def tool_line(tool):
    c = per_tool.get(tool, dict.fromkeys(STATUS_ORDER, 0))
    return " ".join(f"{k}={c[k]}" for k in STATUS_ORDER)


utc = datetime.now(timezone.utc).strftime("%F %T")
qc = [
    "# B 路线候选回映射 QC（49c · candidate_evidence.tsv）",
    "",
    f"- 生成时间 (UTC): {utc}",
    f"- 输入: antismash_precursors.tsv {n_as} 行; macrel_precursors.tsv {n_mac} 行; "
    f"macrel smorfs.faa {len(smorfs)} 条; 44 号样本目录 {len(catalog)} 个; "
    f"17 号 Prodigal 蛋白 {n_prot} 条",
    f"- 输出: candidate_evidence.tsv {total} 行 == 输入合计 {n_as}+{n_mac}（候选全保留断言通过）",
    "- 五分项: " + " ".join(f"{k}={counts[k]}" for k in STATUS_ORDER)
    + f"（合计 {five_sum} == 行数，断言通过）",
    f"- antismash 明细: {tool_line('antismash')}",
    f"- macrel 明细: {tool_line('macrel')}",
    "",
    "口径:",
    "- antismash: peptide_id 样本前缀选 44 号 smorf.tsv，gene_id（|后段）ID join，"
    "命中=exact_mapped，未命中=unmapped_only_candidate 并记原因",
    "- macrel: macrel.out.smorfs.faa smORF 全序列（去尾部 *）对 17 号 Prodigal FAA "
    "（去尾部 *）先精确后双向包含；同序列命中多个样本=ambiguous",
    "- 坐标列保留工具原样（antiSMASH=GBK CDS location；Macrel 1.6.0 预测产物无坐标列 → NA），"
    "coords_note 声明体系",
    f"- antiSMASH tool_version 取 28 号 region GBK Version 注记: {as_version}",
    "",
    "结果注记:",
    f"- candidate_id 唯一化: {n_cid_sfx} 行因输入 locus_tag 跨 region 撞名追加 #k 后缀"
    "（antiSMASH chunk 内部编号重启所致；行全保留，首现保留契约原格式）",
    "- antiSMASH 前体基因 ID 为工具内部命名（其自带 genefinding 产物），与 44 号目录的 "
    "Prodigal 基因命名不一致，ID join 未命中；按口径全部记 unmapped_only_candidate，"
    "原因保留在 remap_note（如需序列级回映射属后续增量，不在本步范围）",
    "- Macrel 候选精确/包含命中的样本与基因见 candidate_evidence.tsv 的 sample/gene_id 列",
]
with open(QC_MD, "w", encoding="utf-8") as m:
    m.write("\n".join(qc) + "\n")

print("[qc] " + " ".join(f"{k}={counts[k]}" for k in STATUS_ORDER))
print(f"[done] candidate_evidence.tsv: {total} rows (antismash={n_as} macrel={n_mac})")
PYEOF
then
    fail "49c python 回映射执行失败"
fi

# ---- bash 层自测（契约点独立复核）----
OUT_ROWS=$(awk 'END{print NR-1}' "${OUT_TSV}")
[ -n "${OUT_ROWS}" ] && [ "${OUT_ROWS}" -eq "$((N_AS + N_MAC))" ] \
    || fail "行数断言失败: out=${OUT_ROWS} expect=$((N_AS + N_MAC))"
[ "$(head -1 "${OUT_TSV}" | awk -F'\t' '{print NF}')" -eq 14 ] \
    || fail "列数断言失败: candidate_evidence.tsv 必须 14 列"
FIVE_SUM=$(awk -F'\t' 'NR>1{c[$11]++} END{
    s=c["exact_mapped"]+c["contained_mapped"]+c["ambiguous"]+c["unmapped_only_candidate"]+c["not_attempted"];
    print s+0}' "${OUT_TSV}")
[ "${FIVE_SUM}" -eq "${OUT_ROWS}" ] || fail "五分项合计断言失败: ${FIVE_SUM} != ${OUT_ROWS}"
BAD_STATUS=$(awk -F'\t' 'NR>1 && $11!~/^(exact_mapped|contained_mapped|ambiguous|unmapped_only_candidate|not_attempted)$/{n++} END{print n+0}' "${OUT_TSV}")
[ "${BAD_STATUS}" -eq 0 ] || fail "remap_status 存在非法取值: ${BAD_STATUS} 行"
DUP_ID=$(awk -F'\t' 'NR>1{c[$1]++} END{n=0; for(k in c) if(c[k]>1) n++; print n+0}' "${OUT_TSV}")
[ "${DUP_ID}" -eq 0 ] || fail "candidate_id 唯一性断言失败"

echo "[INFO] 自测通过: 行数=${OUT_ROWS}==输入合计 五分项合计=${FIVE_SUM} 列数=14 状态取值合法 id唯一"
cat "${QC_MD}"
echo "[DONE] $(date -u '+%F %T') broute_remap"
date -u '+%F %T' > "${SENTINEL}"
mgx_end "broute_remap"
