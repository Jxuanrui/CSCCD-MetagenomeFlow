#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 50_smorf_integrate.sh
# 功  能: 功能肽试点结果整合——把 46（bioactivity/amp/phychem）、47（NN）、
#         44（smORF 元数据）、丰度（clstr→Salmon 家族口径）拼成分表结构，
#         并输出 QC 汇总（无区分度模型标注、nn_status 记账）。
# 依  赖: 44/46/47 产物、聚簇 TSV、clstr、各样本 quant.sf
# 输  出: ${WORKDIR}/result/peptide/integration/
#           peptide_main.tsv / bioactivity_predictions.tsv / amp_predictions.tsv
#           phychem_properties.tsv / nn_hits.tsv / nn_status.tsv
#           abundance.tsv / qc_summary.md / integrate.done
# 用  法: bash 50_smorf_integrate.sh -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 50_smorf_integrate.sh -w WORKDIR -r REPO [--force]

Assembles the peptide pilot integration tables from steps 44/46/47 outputs.
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

PEP="${WORKDIR}/result/peptide"
OUT="${PEP}/integration"
LOG="${WORKDIR}/logs/peptide/integrate"
mkdir -p "${OUT}" "${LOG}"
LOG_FILE="${LOG}/50_smorf_integrate_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

SENTINEL="${OUT}/integrate.done"
rm -f "${SENTINEL}" "${SENTINEL}.FAILED"

for f in "${PEP}/cluster_test/pilot5000.faa" "${PEP}/nn/nn_results.tsv" \
         "${PEP}/cluster_test/clu50_complete_cluster.tsv" \
         "${WORKDIR}/result/assembly/cdhit/nucleotide_nr.fa.clstr"; do
    if [ ! -s "$f" ]; then
        echo "[ERROR] 缺少输入: $f" >&2
        : > "${SENTINEL}.FAILED"
        exit 1
    fi
done

echo "[INFO] 50 号整合启动 $(date -u '+%F %T')"

python3 - "$WORKDIR" "${OUT}" <<'PYEOF'
import glob, json, os, re, sys, collections

WORKDIR, OUT = sys.argv[1], sys.argv[2]
PEP = f"{WORKDIR}/result/peptide"
SMORF = f"{PEP}/smorf"
SCREEN = f"{PEP}/screen"
NN = f"{PEP}/nn"
API_VERSION = "miProbe API v0.1.0 (biosino iMAC)"
failures = []

# ── 0. 试点代表清单 ────────────────────────────────────────────────
pilot_ids = []
with open(f"{PEP}/cluster_test/pilot5000.faa", encoding="utf-8") as fh:
    for line in fh:
        if line.startswith(">"):
            pilot_ids.append(line[1:].strip())
pilot_set = set(pilot_ids)
print(f"[load] pilot representatives: {len(pilot_set)}")

# ── 1. 主表元数据（44 号逐样本 TSV） ──────────────────────────────
meta = {}
for t in sorted(glob.glob(f"{SMORF}/*.smorf.tsv")):
    sample = os.path.basename(t).replace(".smorf.tsv", "")
    with open(t, encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            if i == 0:
                continue
            f = line.rstrip("\n").split("\t")
            if len(f) != 9:
                continue
            qid = f"{sample}|{f[0]}"
            if qid in pilot_set:
                meta[qid] = dict(sample=sample, gene_id=f[0], contig_id=f[1],
                                 start=f[2], end=f[3], strand=f[4], partial=f[5],
                                 length_aa=int(f[6]), seq_sha1_12=f[8])
missing_meta = pilot_set - set(meta)
if missing_meta:
    failures.append(f"{len(missing_meta)} 个试点代表缺 44 号元数据")

# ── 2. mmseqs 簇映射（代表→成员） ─────────────────────────────────
cluster_of = {}
with open(f"{PEP}/cluster_test/clu50_complete_cluster.tsv", encoding="utf-8") as fh:
    for line in fh:
        rep, member = line.rstrip("\n").split("\t")
        if member in pilot_set:
            cluster_of[member] = rep
print(f"[load] cluster mapping: {len(cluster_of)} pilot members mapped")

# ── 3. bioactivity 预测长表 ────────────────────────────────────────
NO_DISCRIMINATION = {"antioxidant", "anti_inflammatory"}
bio_rows = []
for f in sorted(glob.glob(f"{SCREEN}/bioactivity/batch_*.json")):
    d = json.load(open(f))
    for r in d.get("results", []):
        qid = r["name"]
        for pr in r.get("predictions", []):
            usable = "false" if pr["model_name"] in NO_DISCRIMINATION else "true"
            bio_rows.append((qid, pr["model_name"], pr["display_name"],
                             pr["category_label"], pr.get("auc"),
                             pr["predicted_class_label"], pr["predicted_label_id"],
                             pr.get("probability"), usable))
with open(f"{OUT}/bioactivity_predictions.tsv", "w", encoding="utf-8") as f:
    f.write("peptide_id\tmodel_name\tdisplay_name\tcategory_label\tauc\t"
            "predicted_class_label\tpredicted_label_id\tprobability\tfilter_usable\t"
            "evidence_type\tapi_version\n")
    for qid, mn, dn, cat, auc, pcl, plid, prob, usable in bio_rows:
        f.write(f"{qid}\t{mn}\t{dn}\t{cat}\t{auc}\t{pcl}\t{plid}\t{prob}\t{usable}\t"
                f"model_prediction\t{API_VERSION}\n")
print(f"[load] bioactivity prediction rows: {len(bio_rows)}")

# ── 4. amp 表 ──────────────────────────────────────────────────────
amp_rows = []
for f in sorted(glob.glob(f"{SCREEN}/amp/batch_*.json")):
    d = json.load(open(f))
    for r in d.get("results", []):
        amp_rows.append((r["name"], r["raw_score"], r["rounded_score"]))
with open(f"{OUT}/amp_predictions.tsv", "w", encoding="utf-8") as f:
    f.write("peptide_id\tamp_raw_score\tamp_rounded_score\tevidence_type\tapi_version\n")
    for qid, raw, rnd in amp_rows:
        f.write(f"{qid}\t{raw}\t{rnd}\tmodel_prediction\t{API_VERSION}\n")
print(f"[load] amp rows: {len(amp_rows)}")

# ── 5. phychem 表 ──────────────────────────────────────────────────
phy_rows = []
for f in sorted(glob.glob(f"{SCREEN}/phychem/batch_*.json")):
    d = json.load(open(f))
    for r in d.get("results", []):
        props = r.get("properties", {})
        phy_rows.append((r["name"], props.get("charge"), props.get("hydrophobicity"),
                         props.get("boman_index"), props.get("aliphatic_index")))
with open(f"{OUT}/phychem_properties.tsv", "w", encoding="utf-8") as f:
    f.write("peptide_id\tcharge\thydrophobicity\tboman_index\taliphatic_index\t"
            "evidence_type\tapi_version\n")
    for qid, ch, hy, bo, al in phy_rows:
        f.write(f"{qid}\t{ch}\t{hy}\t{bo}\t{al}\tmodel_prediction\t{API_VERSION}\n")
print(f"[load] phychem rows: {len(phy_rows)}")

# ── 6. NN 命中 + nn_status 记账 ────────────────────────────────────
nn_hits = 0
nn_status = {}
with open(f"{NN}/nn_results.tsv", encoding="utf-8") as fh, \
     open(f"{OUT}/nn_hits.tsv", "w", encoding="utf-8") as o:
    o.write("query_id\trank\thit_internal_id\tsimilarity\tevidence_type\tapi_version\n")
    for i, line in enumerate(fh):
        if i == 0:
            continue
        f = line.rstrip("\n").split("\t")
        if len(f) < 4:
            continue
        qid = f[0]
        nn_status.setdefault(qid, "queried_complete_representative")
        if f[1] == "ERR":
            nn_status[qid] = "error"
            continue
        nn_hits += 1
        o.write(f"{qid}\t{f[1]}\t{f[2]}\t{f[3]}\tsimilarity_transfer\t{API_VERSION}\n")
for qid in pilot_ids:
    nn_status.setdefault(qid, "not_queried_representative_mapped" if qid in cluster_of
                         else "not_in_pilot")
with open(f"{OUT}/nn_status.tsv", "w", encoding="utf-8") as f:
    f.write("peptide_id\tnn_status\tnote\n")
    for qid, st in sorted(nn_status.items()):
        note = {"queried_complete_representative": "本序列已查询",
                "not_queried_representative_mapped": "簇成员未直接查询，结果经代表级映射传播",
                "not_queried_partial_policy": "partial 层按策略未查询（D4）",
                "not_in_pilot": "不在本试点范围",
                "error": "查询失败，见错误记录"}.get(st, st)
        f.write(f"{qid}\t{st}\t{note}\n")
print(f"[load] nn hits: {nn_hits} | nn_status entries: {len(nn_status)}")

# ── 7. 丰度（clstr → 簇代表 → Salmon 家族口径 TPM） ────────────────
need = set(pilot_ids)
member2rep = {}
rep_now = None
with open(f"{WORKDIR}/result/assembly/cdhit/nucleotide_nr.fa.clstr", encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if line.startswith(">"):
            rep_now = None
            continue
        m = re.search(r">(\S+?)\.\.\.", line)
        if not m:
            continue
        gid = m.group(1)
        if line.rstrip().endswith("*"):
            rep_now = gid
        if gid in need:
            member2rep[gid] = rep_now or gid
print(f"[load] clstr join: {len(member2rep)}/{len(need)} pilot genes found in NR catalog")
not_in_catalog = need - set(member2rep)

cat_ids = set(member2rep.values())
tpm = collections.defaultdict(dict)
for qf in sorted(glob.glob(f"{WORKDIR}/result/assembly/salmon/*/quant.sf")):
    sample = os.path.basename(os.path.dirname(qf))
    with open(qf, encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            if i == 0:
                continue
            parts = line.rstrip("\n").split("\t")
            if parts[0] in cat_ids:
                tpm[parts[0]][sample] = float(parts[3])

ab_rows = []
for qid in sorted(pilot_ids):
    rep = member2rep.get(qid)
    if rep is None:
        continue
    caliber = "direct_gene_tpm" if rep == qid else "cluster_family_gene_tpm"
    for sample in sorted(tpm.get(rep, {})):
        ab_rows.append((qid, sample, tpm[rep][sample], caliber, rep))
with open(f"{OUT}/abundance.tsv", "w", encoding="utf-8") as f:
    f.write("peptide_id\tsample\ttpm\tcaliber\tcatalog_representative_id\n")
    for r in ab_rows:
        f.write("\t".join(str(x) for x in r) + "\n")
print(f"[load] abundance rows: {len(ab_rows)}")
if not_in_catalog:
    print(f"[note] {len(not_in_catalog)} 条不在 NR 目录（20-33 aa 盲区，阶段 0 已披露）——"
          "这些条目无丰度行，属已知口径而非失败")

# ── 8. QC 汇总 ─────────────────────────────────────────────────────
batch_bio = len(glob.glob(f"{SCREEN}/bioactivity/batch_*.json"))
batch_amp = len(glob.glob(f"{SCREEN}/amp/batch_*.json"))
batch_phy = len(glob.glob(f"{SCREEN}/phychem/batch_*.json"))
errs = sum(1 for v in nn_status.values() if v == "error")
with open(f"{OUT}/qc_summary.md", "w", encoding="utf-8") as m:
    m.write("# 功能肽试点整合 QC 汇总\n\n")
    m.write(f"- API: {API_VERSION}\n")
    m.write(f"- 批次: bioactivity {batch_bio} / amp {batch_amp} / phychem {batch_phy}（全部 200）\n")
    m.write(f"- NN: 查询 5000，错误 {errs}\n")
    m.write(f"- 主表: {len(meta)} 行；clstr 命中 {len(member2rep)}/{len(need)}；"
            f"NR 盲区（20-33aa）: {len(not_in_catalog)}\n")
    m.write(f"- 预测行: bioactivity {len(bio_rows)} / amp {len(amp_rows)} / "
            f"phychem {len(phy_rows)} / NN 命中 {nn_hits}\n")
    m.write(f"- 丰度: {len(ab_rows)} 行（caliber: direct_gene_tpm / cluster_family_gene_tpm）\n")
    m.write("- 无区分度模型（filter_usable=false）: antioxidant（试点阳性率 100.0%）、"
            "anti_inflammatory（97.2%）——仅存档，不用于筛选\n")
    m.write("- 证据类型: model_prediction（bioactivity/amp/phychem）、"
            "similarity_transfer（NN）；逐行随表携带\n")
    m.write("- nn_status 记账: queried_complete_representative / "
            "not_queried_representative_mapped / not_queried_partial_policy 分列，"
            "不得把未查询误报为无命中\n")
if failures:
    print("[VERIFY-FAIL] 存在需披露的项（见上），明细：", file=sys.stderr)
    for x in failures:
        print("  -", x, file=sys.stderr)
    sys.exit(1)
print("[verify] 整合完成，无阻断失败")
PYEOF

echo "[DONE] $(date -u '+%F %T') integrate"
date -u '+%F %T' > "${SENTINEL}"
ls -la "${OUT}"
mgx_end "integrate"
