#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 47_smorf_nn.sh
# 功  能: miProbe 嵌入最近邻检索——对代表序列逐条调用 embedding-search（k=3），
#         返回库内最相似肽的 internal_id 与相似度。结果供 50 号整合时关联
#         物种/生境档案（by-internal-id/sources）。
# 口  径: 串行（0.3s 间隔，curl 传输——urllib 被 Cloudflare 拦截）；按 D4/D5
#         决策仅查 complete 层代表；游标断点续传；单次失败重试 2 次。
# 依  赖: 44 号产物 + 聚簇代表 FASTA
# 输  出: ${WORKDIR}/result/peptide/nn/nn_results.tsv（query_id, rank, hit_id, sim）
#         ${WORKDIR}/result/peptide/nn/nn_cursor.txt（已处理条数）
# 用  法: bash 47_smorf_nn.sh -w WORKDIR -r REPO -i INPUT_FASTA [--force]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 47_smorf_nn.sh -w WORKDIR -r REPO -i INPUT_FASTA [--force]

Serial miProbe embedding-search (k=3) over the given representative FASTA.
Resumable via cursor file.  Serial by design: concurrent load triggers the
60s gateway 504s.
EOF
}

if [ $# -eq 0 ]; then
    show_help; exit 0
fi

export MGX_OPTS_STRING="w:WORKDIR r:REPO i:INPUT"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO INPUT
WORKDIR="$(cd "${WORKDIR}" && pwd)"
INPUT="$(cd "$(dirname "${INPUT}")" && pwd)/$(basename "${INPUT}")"

mgx_begin

OUT="${WORKDIR}/result/peptide/nn"
LOG="${WORKDIR}/logs/peptide/nn"
mkdir -p "${OUT}" "${LOG}"
LOG_FILE="${LOG}/47_smorf_nn_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

if [ ! -s "${INPUT}" ]; then
    echo "[ERROR] 输入 FASTA 不存在: ${INPUT}" >&2
    : > "${OUT}/nn.FAILED"
    exit 1
fi

RESULTS="${OUT}/nn_results.tsv"
CURSOR="${OUT}/nn_cursor.txt"

echo "[INFO] 47 号 NN 检索启动 $(date -u '+%F %T')（k=3，串行 0.3s，curl）"

python3 - "${INPUT}" "${RESULTS}" "${CURSOR}" <<'PYEOF'
import json, os, subprocess, sys, time

input_fa, results, cursor = sys.argv[1], sys.argv[2], sys.argv[3]
API = os.environ.get("PEPTIDE_API_BASE", "https://www.biosino.org/iMAC/miProbe/api")  # env override, default = production
INTERVAL = 0.3
RETRIES = 2
K = 3

entries, cur_id, cur = [], None, []
with open(input_fa, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if line.startswith(">"):
            if cur_id is not None:
                entries.append((cur_id, "".join(cur)))
            cur_id, cur = line[1:].strip(), []
        else:
            cur.append(line)
if cur_id is not None:
    entries.append((cur_id, "".join(cur)))
n = len(entries)

start = 0
if os.path.exists(cursor) and os.path.getsize(cursor):
    start = int(open(cursor).read().strip())
print(f"[plan] total={n} resume_from={start}")

# F2 修复：启动时读取已写 query_id 集合——重启重跑时跳过已完成查询（幂等），
# 且追加前逐条去重，杜绝崩溃后重复 API 调用与重复结果行
# ERR 语义（D-B P0）：ERR 行 = 未完成（临时故障），重启时移除 ERR 行并重查该
# query；仅非 ERR 结果行计入 written_ids（永久完成，跳过）。人工如需永久记账
# 可手工将 ERR 行移入旁路文件——默认行为是自动重试。
written_ids = set()
err_retry_ids = set()
if os.path.exists(results) and os.path.getsize(results):
    keep_lines = []
    with open(results, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("query_id"):
                keep_lines.append(line)
                continue
            qid = line.split("\t", 1)[0]
            if not qid:
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[1] == "ERR":
                err_retry_ids.add(qid)   # 未完成：本轮重查，旧行删除
            else:
                written_ids.add(qid)
                keep_lines.append(line)
    if err_retry_ids:
        with open(results, "w", encoding="utf-8") as f:
            f.writelines(keep_lines)
        print(f"[resume] 移除 {len(err_retry_ids)} 条 ERR 行并纳入本轮重查: "
              f"{sorted(err_retry_ids)[:5]}{'...' if len(err_retry_ids) > 5 else ''}")
if not os.path.exists(results) or os.path.getsize(results) == 0:
    with open(results, "w", encoding="utf-8") as f:
        f.write("query_id\trank\thit_internal_id\tsimilarity\n")

ok = err = 0
t0 = time.time()
with open(results, "a", encoding="utf-8") as out_f:
    skipped_existing = 0
    for i in range(start, n):
        gid, seq = entries[i]
        if gid in written_ids:
            skipped_existing += 1
            continue
        body = json.dumps({"sequence": seq, "k": K})
        rows = None
        for attempt in range(1, RETRIES + 2):
            r = subprocess.run(["curl", "-s", "--max-time", "120", "-X", "POST",
                                f"{API}/embedding-search/search",
                                "-H", "Content-Type: application/json", "-d", body],
                               capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip().startswith("{"):
                try:
                    d = json.loads(r.stdout)
                    rows = [(h["rank"], h["internal_id"], h["similarity"]) for h in d.get("results", [])]
                    break
                except json.JSONDecodeError:
                    pass
            time.sleep(2 * attempt + 1)
        if rows is None:
            err += 1
            print(f"[retry-exhausted] {gid}: {RETRIES} 次重试后仍失败，记 ERR 行")
            out_f.write(f"{gid}\tERR\t0\t0.0\n")
        else:
            ok += 1
            for rank, hid, sim in rows:
                out_f.write(f"{gid}\t{rank}\t{hid}\t{sim}\n")
        out_f.flush()
        with open(cursor, "w") as c:
            c.write(str(i + 1))  # 逐条落游标（D-B F2：50 条粒度太粗，小运行不可续传）
        if (i + 1) % 50 == 0:
            el = time.time() - t0
            done_n = i + 1 - start
            eta = el / done_n * (n - i - 1) if done_n else 0
            print(f"[progress] {i+1}/{n} | ok={ok} err={err} | elapsed={el/60:.0f}m eta={eta/3600:.1f}h")
        time.sleep(INTERVAL)

with open(cursor, "w") as c:
    c.write(str(n))
el = time.time() - t0
print(f"[done] total={n} ok={ok} err={err} skipped_existing={skipped_existing} elapsed={el/3600:.2f}h")
PYEOF

echo "[DONE] $(date -u '+%F %T') nn"
date -u '+%F %T' > "${OUT}/nn.done"
mgx_end "nn"
