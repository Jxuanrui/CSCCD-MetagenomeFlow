#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 44_smorf_catalog.sh
# 功  能: smORF 子目录构建——从 17 号 Prodigal 蛋白预测中提取 <100 aa 短肽候选
#         独立于 18 号主目录口径（18 号过滤 <100 bp 核酸，33 aa 以下不可见）；
#         本脚本覆盖 20–99 aa 的肽段层，供功能肽分支（45–50）专用。
# 依  赖: 17_bac_prodigal.sh 的输出（${SAMPLE}.faa）
# 输  入: ${WORKDIR}/result/assembly/prodigal/${SAMPLE}/${SAMPLE}.faa
# 输  出: ${WORKDIR}/result/peptide/smorf/
#           ${SAMPLE}.smorf.faa      — 短肽序列（header 保留原始 gene_id）
#           ${SAMPLE}.smorf.tsv      — 元数据表：gene_id/contig/坐标/链/partial/长度/哈希
#           smorf_catalog.stats.md   — 全样本汇总（数量/长度分布/complete-partial 分层）
#           smorf_catalog.done       — 完成哨兵
# 口  径: 候选 = Prodigal(-p meta) 预测的 20–99 aa CDS；partial 标记原样保留并
#         分层（partial=00 记 complete，其余记 partial_g3/partial_g5/partial_both），
#         不做静默过滤；长度 = 序列实际 aa 数（不含终止子）。
# 用  法: bash 44_smorf_catalog.sh -w WORKDIR -r REPO [-t CPUS] [--force]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 44_smorf_catalog.sh -w WORKDIR -r REPO [-t CPUS] [--force]

Required:
  -w  Project work directory (contains result/assembly/prodigal/<sample>/*.faa)
  -r  Repository root

Optional:
  -t  Parallel workers (default: 4)
  --force  Re-run even if the done sentinel exists
  -h, --help  Show this help message

Outputs: ${WORKDIR}/result/peptide/smorf/  (per-sample TSV+FASTA, pooled stats, done sentinel)
EOF
}

# 无参数直接运行时给出用法（避免只看到"缺少必需参数"而不知如何调用）
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO
CPUS="${CPUS:-4}"
WORKDIR="$(cd "${WORKDIR}" && pwd)"

mgx_begin

OUT="${WORKDIR}/result/peptide/smorf"
LOG="${WORKDIR}/logs/peptide/smorf"
mkdir -p "${OUT}" "${LOG}"
# 每次运行独立日志文件：历史失败运行（含旧版 bug 的 SyntaxError）不会混入
# 当前运行的成功日志，避免"旧错误 + 新哨兵"造成假完成误读。
LOG_FILE="${LOG}/44_smorf_catalog_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

SENTINEL="${OUT}/smorf_catalog.done"
if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] smorf_catalog.done 存在且非空，跳过（--force 重跑）"
    mgx_end "smorf"
    exit 0
fi

# 清理旧状态标记：done 与 FAILED 都不残留，避免旧失败标记与新成功哨兵并存
rm -f "${SENTINEL}" "${SENTINEL}.FAILED"

echo "[INFO] 扫描 ${WORKDIR}/result/assembly/prodigal/*/（--force=${FORCE}）"
shopt -s nullglob
FAAS=("${WORKDIR}"/result/assembly/prodigal/*/*.faa)
shopt -u nullglob
if [ "${#FAAS[@]}" -eq 0 ]; then
    echo "[ERROR] 未找到任何 17 号 FAA 产物：${WORKDIR}/result/assembly/prodigal/*/*.faa" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

export OUT
printf '%s\n' "${FAAS[@]}" | xargs -P "${CPUS}" -n 1 bash -c '
    set -e   # python 任一失败即以非零退出，向 xargs 传播
    faa="$1"; sample="$(basename "$(dirname "$faa")")"; out="${OUT}"
    python3 - "$faa" "$sample" "$out" <<PYEOF
import sys, hashlib

faa, sample, out = sys.argv[1], sys.argv[2], sys.argv[3]

def parse_headers(fa):
    """逐条产出 (gene_id, start, end, strand, attrs, seq)。header 形如
    >ctg_1 # 271 # 969 # -1 # ID=1_1;partial=00;start_type=ATG;rbs_motif=..."""
    out_list, cur, meta = [], None, None
    with open(fa, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if cur is not None:
                    out_list.append(cur)
                parts = line[1:].split(" # ")
                gene_id = parts[0].strip()
                attrs = dict()
                if len(parts) >= 5:
                    for kv in parts[4].split(";"):
                        if "=" in kv:
                            k, v = kv.split("=", 1)
                            attrs[k.strip()] = v.strip()
                meta = (gene_id, parts[1], parts[2], parts[3], attrs) if len(parts) >= 5 else (gene_id, None, None, None, attrs)
                cur = [meta, []]
            else:
                cur[1].append(line.strip())
    if cur is not None:
        out_list.append(cur)
    return [(m[0], m[1], m[2], m[3], m[4], "".join(s)) for m, s in out_list]

PARTIAL_LABEL = {"00": "complete", "01": "partial_g3", "10": "partial_g5", "11": "partial_both"}

fa_out = f"{out}/{sample}.smorf.faa"
tsv_out = f"{out}/{sample}.smorf.tsv"
rows, seqs = [], []
for gene_id, start, end, strand, attrs, seq in parse_headers(faa):
    aa = len(seq)
    if not (20 <= aa <= 99):
        continue
    partial = PARTIAL_LABEL.get(attrs.get("partial", ""), "unknown")
    seq_hash = hashlib.sha1(seq.encode()).hexdigest()[:12]
    rows.append((gene_id, gene_id.rsplit("_", 1)[0], start, end, strand,
                 partial, aa, attrs.get("start_type", ""), seq_hash))
    seqs.append((gene_id, seq))

with open(tsv_out, "w", encoding="utf-8") as t:
    t.write("gene_id\tcontig_id\tstart\tend\tstrand\tpartial\tlength_aa\tstart_type\tseq_sha1_12\n")
    for r in rows:
        t.write("\t".join(str(x) for x in r) + "\n")
with open(fa_out, "w", encoding="utf-8") as f:
    for gene_id, seq in seqs:
        f.write(f">{gene_id}\n{seq}\n")

print(f"[{sample}] candidates={len(rows)}")
PYEOF
' _
# PIPESTATUS[1] = xargs 的退出码（GNU xargs：任一子任务失败 → 123）。
# PIPESTATUS[0] 是 printf，几乎不会失败——错误检查必须挂在 xargs 上。
XARGS_STATUS=${PIPESTATUS[1]}
if [ "${XARGS_STATUS}" -ne 0 ]; then
    echo "[ERROR] 子样本解析失败（xargs exit=${XARGS_STATUS}；123=存在失败子任务）" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[INFO] 独立核验：TSV/FASTA 逐行对应、序列长度一致、长度边界、partial 取值、gene_id 唯一性"
python3 - "${OUT}" <<'PYEOF'
import glob, os, sys

out = sys.argv[1]
VALID_PARTIAL = {"complete", "partial_g3", "partial_g5", "unknown"}
failures = []
for t in sorted(glob.glob(f"{out}/*.smorf.tsv")):
    fa = t.replace(".smorf.tsv", ".smorf.faa")
    sample = os.path.basename(t).replace(".smorf.tsv", "")
    rows = {}
    with open(t, encoding="utf-8") as fh:
        header = fh.readline()
        if header.rstrip("\n") != "gene_id\tcontig_id\tstart\tend\tstrand\tpartial\tlength_aa\tstart_type\tseq_sha1_12":
            failures.append(f"{sample}: tsv 表头不符")
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) != 9:
                failures.append(f"{sample}: tsv 列数异常: {line[:60]}")
                continue
            if f[0] in rows:
                failures.append(f"{sample}: gene_id 重复 {f[0]}")
            rows[f[0]] = (int(f[6]), f[5])
    if not rows:
        failures.append(f"{sample}: tsv 为空")
        continue
    fa_ids = {}
    cur_id, cur = None, []
    with open(fa, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if cur_id is not None:
                    fa_ids[cur_id] = len("".join(cur))
                cur_id, cur = line[1:].strip(), []
            else:
                cur.append(line)
    if cur_id is not None:
        fa_ids[cur_id] = len("".join(cur))
    missing = set(rows) - set(fa_ids)
    extra = set(fa_ids) - set(rows)
    if missing:
        failures.append(f"{sample}: {len(missing)} 条在 TSV 有而 FASTA 无（如 {sorted(missing)[:2]}）")
    if extra:
        failures.append(f"{sample}: {len(extra)} 条在 FASTA 有而 TSV 无（如 {sorted(extra)[:2]}）")
    len_mismatch = [gid for gid in (set(rows) & set(fa_ids)) if rows[gid][0] != fa_ids[gid]]
    if len_mismatch:
        failures.append(f"{sample}: {len(len_mismatch)} 条 length_aa 与 FASTA 实际序列长度不一致")
    bad_len = [gid for gid, (ln, _) in rows.items() if not (20 <= ln <= 99)]
    if bad_len:
        failures.append(f"{sample}: 长度越界 {len(bad_len)} 条")
    bad_partial = sorted({p for _, p in rows.values()} - VALID_PARTIAL)
    if bad_partial:
        failures.append(f"{sample}: 非法 partial 取值 {bad_partial}")
    print(f"  [verify] {sample}: rows={len(rows)} fasta={len(fa_ids)} "
          f"逐行对应={not missing and not extra} 长度一致={not len_mismatch} "
          f"length={min(r[0] for r in rows.values())}-{max(r[0] for r in rows.values())}")

if failures:
    print("[VERIFY-FAIL] 独立核验未通过：", file=sys.stderr)
    for f_ in failures:
        print("  -", f_, file=sys.stderr)
    sys.exit(1)
print("[verify] 全部样本独立核验通过（逐行 gene_id 对应 + 序列长度一致）")
PYEOF
VERIFY_STATUS=$?
if [ "${VERIFY_STATUS}" -ne 0 ]; then
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[INFO] 生成全样本汇总"
python3 - "${OUT}" <<'PYEOF'
import glob, os, sys, collections

out = sys.argv[1]
tsvs = sorted(glob.glob(f"{out}/*.smorf.tsv"))
total = collections.Counter()
per_sample = []
lens = collections.Counter()
for t in tsvs:
    sample = os.path.basename(t).replace(".smorf.tsv", "")
    n = c = 0
    with open(t, encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            if i == 0:
                continue
            f = line.rstrip("\n").split("\t")
            if len(f) < 7:
                continue
            n += 1
            if f[5] == "complete":
                c += 1
            lens[int(f[6]) // 10 * 10] += 1
    per_sample.append((sample, n, c))
    total["candidates"] += n
    total["complete"] += c

with open(f"{out}/smorf_catalog.stats.md", "w", encoding="utf-8") as m:
    m.write("# smORF 子目录汇总\n\n")
    m.write("| 样本 | 候选数 | complete | complete 占比 |\n|---|---|---|---|\n")
    for s, n, c in per_sample:
        pct = f"{100 * c / n:.1f}%" if n else "-"
        m.write(f"| {s} | {n} | {c} | {pct} |\n")
    m.write(f"| **合计** | **{total['candidates']}** | **{total['complete']}** | - |\n\n")
    m.write("长度分布（aa 桶，左闭右闭 10 的倍数）：\n\n| 区间 | 条数 |\n|---|---|\n")
    for b in sorted(lens):
        m.write(f"| {b}-{b + 9} | {lens[b]} |\n")
print(f"[stats] samples={len(per_sample)} total={total['candidates']} "
      f"complete={total['complete']}")
PYEOF

if [ ! -s "${OUT}/smorf_catalog.stats.md" ]; then
    echo "[ERROR] 汇总未生成" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[DONE] $(date -u '+%F %T') smorf_catalog"
date -u '+%F %T' > "${SENTINEL}"
mgx_end "smorf"
