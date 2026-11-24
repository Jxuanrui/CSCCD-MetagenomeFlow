#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 46_smorf_screen.sh
# 功  能: smORF 代表序列批量功能预测——调用 miProbe 托管三端点：
#           prediction/bioactivity（33 分类器，单次上限 10 条，实测）
#           prediction/amp（0-4 ordinal）
#           prediction/phychem（理化性质 MLP）
#         输入为 44 号子目录经 50% AAI 聚簇后的代表序列；簇成员结果由
#         代表级映射传播（50 号整合时标注 representative-mapped）。
# 口  径: 序列剥除末尾 '*'（Prodigal 终止子翻译字符，实测仅出现在末尾）；
#         单批 10 条（服务端上限）；串行 + 0.3s 间隔；失败批次重试 2 次后
#         落盘 error 记录，不阻塞后续批次（可恢复）。
# 依  赖: 44 号产物 + MMseqs 聚簇代表（result/peptide/cluster_test/）
# 输  出: ${WORKDIR}/result/peptide/screen/{bioactivity,amp,phychem}/batch_*.json
#         ${WORKDIR}/result/peptide/screen/state.json（批次游标，可恢复）
# 用  法: bash 46_smorf_screen.sh -w WORKDIR -r REPO [-t CONCURRENCY] [--force]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 46_smorf_screen.sh -w WORKDIR -r REPO [-i INPUT_FASTA] [--force]

Runs hosted miProbe predictions (bioactivity/amp/phychem) over the
complete-tier cluster representatives in batches of 10. Resumable via
state.json cursor.
EOF
}

if [ $# -eq 0 ]; then
    show_help; exit 0
fi

export MGX_OPTS_STRING="w:WORKDIR r:REPO i:INPUT"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO
WORKDIR="$(cd "${WORKDIR}" && pwd)"

mgx_begin

REPS="${WORKDIR}/result/peptide/cluster_test/clu50_complete_rep_seq.fasta"
if [ -n "${INPUT:-}" ]; then
    REPS="$(cd "$(dirname "${INPUT}")" && pwd)/$(basename "${INPUT}")"
    echo "[INFO] 输入覆盖：${REPS}（试点子集模式）"
fi
OUT="${WORKDIR}/result/peptide/screen"
LOG="${WORKDIR}/logs/peptide/screen"
mkdir -p "${OUT}/bioactivity" "${OUT}/amp" "${OUT}/phychem" "${LOG}"
LOG_FILE="${LOG}/46_smorf_screen_$(date -u +%Y%m%d_%H%M%S%N).log"
exec > >(tee "${LOG_FILE}") 2>&1

if [ ! -s "${REPS}" ]; then
    echo "[ERROR] 代表序列不存在: ${REPS}（先运行聚簇）" >&2
    : > "${OUT}/screen.FAILED"
    exit 1
fi

# 游标状态文件：记录各端点已完成的最大批次号，重跑自动续传
STATE="${OUT}/state.json"
[ -s "${STATE}" ] || echo '{}' > "${STATE}"

echo "[INFO] 46 号批量功能预测启动 $(date -u '+%F %T')（分端点限批 bioactivity cap=3/11 模型子集、amp|phychem cap=10；串行 0.3s，curl）"
date -u '+%F %T' > "${OUT}/screen.started"

python3 - "${REPS}" "${OUT}" "${STATE}" <<'PYEOF'
import json, os, subprocess, sys, time, hashlib

reps_path, out, state_path = sys.argv[1], sys.argv[2], sys.argv[3]
API = "https://www.biosino.org/iMAC/miProbe/api"
# 实测容量（60s 网关硬限制）：bioactivity 33 模型 @10 条必 504；11 模型子集 @3 条 22.6s 通过。
# 因此 bioactivity 用 11 模型子集 + cap=3；amp/phychem 轻量，cap=10。
CAPS = {"bioactivity": 3, "amp": 10, "phychem": 10}
MODELS_SUBSET = ["anti_diabetic", "anti_hypertensive", "anti_inflammatory", "antioxidant",
                 "chemotaxis", "antibacterial", "anti_biofilm", "antifungal", "antiviral",
                 "general_toxicity", "hemolytic_activity"]
INTERVAL = 0.3                # 串行间隔（s）
RETRIES = 2
ENDPOINTS = ["bioactivity", "amp", "phychem"]

# 读取代表序列（剥尾 *）
entries, cur_id, cur = [], None, []
with open(reps_path, encoding="utf-8") as fh:
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
n_seq = len(entries)
batches = {ep: [entries[i:i+CAPS[ep]] for i in range(0, n_seq, CAPS[ep])] for ep in ENDPOINTS}
print(f"[plan] representatives={n_seq} "
      f"batches={ {ep: len(b) for ep, b in batches.items()} }")

state = json.load(open(state_path, encoding="utf-8")) if os.path.getsize(state_path) else {}
done = {e: state.get(e, {}) for e in ENDPOINTS}

def post(endpoint, fasta):
    body = json.dumps({"fasta": fasta, "models": MODELS_SUBSET} if endpoint == "bioactivity"
                      else {"fasta": fasta})
    for attempt in range(1, RETRIES + 2):
        r = subprocess.run(["curl", "-s", "--max-time", "120", "-w", "\n%{http_code}",
                            "-X", "POST", f"{API}/prediction/{endpoint}",
                            "-H", "Content-Type: application/json", "-d", body],
                           capture_output=True, text=True)
        parts = r.stdout.rsplit("\n", 1)
        resp = parts[0] if len(parts) == 2 else ""
        code = parts[-1] if parts else ""
        if r.returncode == 0 and code == "200" and resp.strip():
            return resp, code, attempt
        print(f"  [retry {attempt}] {endpoint} batch http={code} rc={r.returncode} resp={resp[:120]}")
        time.sleep(2 * attempt + 1)
    return resp, code, RETRIES + 1

t0 = time.time()
calls = fails = 0
max_batches = max(len(b) for b in batches.values())
for bi in range(max_batches):
    for ep in ENDPOINTS:
        if bi >= len(batches[ep]):
            continue
        if str(bi) in done[ep].get("done_batches", []):
            continue
        batch = batches[ep][bi]
        fasta = "".join(f">{gid}\n{seq}\n" for gid, seq in batch)
        resp, code, attempts = post(ep, fasta)
        calls += 1
        fn = f"{out}/{ep}/batch_{bi:05d}.json"
        if code == "200":
            with open(fn, "w", encoding="utf-8") as f:
                f.write(resp)
            done[ep].setdefault("done_batches", []).append(str(bi))
            state.update(done)
        else:
            fails += 1
            with open(f"{out}/{ep}/batch_{bi:05d}.error", "a", encoding="utf-8") as f:
                f.write(f"{json.dumps({'batch': bi, 'http': code, 'resp': resp[:400]})}\n")
        time.sleep(INTERVAL)
    if (bi + 1) % 200 == 0:
        el = time.time() - t0
        eta = el / (bi + 1) * (max_batches - bi - 1)
        print(f"[progress] batch {bi+1}/{max_batches} | calls={calls} fails={fails} "
              f"| elapsed={el/60:.0f}m eta={eta/3600:.1f}h")
        json.dump(state, open(state_path, "w"), indent=0)

json.dump(state, open(state_path, "w"), indent=0)
el = time.time() - t0
print(f"[done] max_batches={max_batches} calls={calls} fails={fails} elapsed={el/3600:.2f}h")
for ep in ENDPOINTS:
    n_ok = len(glob := __import__("glob").glob(f"{out}/{ep}/batch_*.json"))
    print(f"  {ep}: {n_ok} batch files")
PYEOF

VERIFY=${PIPESTATUS[0]}
if [ "${VERIFY}" -ne 0 ]; then
    echo "[ERROR] 46 号批量预测存在未恢复失败（详见上方 error 记录）" >&2
    : > "${OUT}/screen.FAILED"
    exit 1
fi

echo "[DONE] $(date -u '+%F %T') screen"
date -u '+%F %T' > "${OUT}/screen.done"
mgx_end "screen"
