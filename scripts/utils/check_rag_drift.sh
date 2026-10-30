#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/utils/check_rag_drift.sh
# 功  能: RAG drift guard — compares the live index state against the last
#         recorded benchmark run. If the index fingerprint (per-collection
#         chunk counts + BM25 mtimes) changed after the last benchmark, the
#         recorded metrics no longer describe the current index: print a
#         warning (exit 0, advisory) or fail (exit 1, --strict).
#
#         Typical wiring: run after any mcp/indexer.py / literature_pipeline /
#         index_mechanism_kb invocation, or in CI follow-ups. The benchmark
#         itself stays manual (needs the local embedding model + data).
# 用  法: bash scripts/utils/check_rag_drift.sh [--strict]
# ==============================================================================
set -euo pipefail

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LATEST=$(ls -t "${REPO}"/mcp/eval/results/benchmark_*.json 2>/dev/null | head -1 || true)

if [ -z "${LATEST}" ]; then
    echo "[rag-drift] no benchmark results found under mcp/eval/results/"
    echo "[rag-drift] run: envs/rag/bin/python3 mcp/eval/rag_benchmark.py"
    [ "${STRICT}" -eq 1 ] && exit 1 || exit 0
fi

FAIL=0
for coll in experience_kb literature_kb skill_design_kb mechanism_kb signature_kb; do
    live=$(python3 - "$REPO" "$coll" <<'EOF'
import sys, chromadb
repo, coll = sys.argv[1], sys.argv[2]
try:
    c = chromadb.PersistentClient(f"{repo}/mcp/chromadb_data")
    print(c.get_collection(coll).count())
except Exception:
    print(-1)
EOF
)
    recorded=$(python3 - "$LATEST" "$coll" <<'EOF'
import sys, json
path, coll = sys.argv[1], sys.argv[2]
try:
    fp = {f["collection"]: f["chunk_count"] for f in json.load(open(path)).get("index_fingerprint", [])}
    print(fp.get(coll, -1))
except Exception:
    print(-1)
EOF
)
    if [[ "${live}" != "${recorded}" ]]; then
        echo "[rag-drift] ${coll}: live=${live} vs benchmark=${recorded}  <-- STALE BENCHMARK"
        FAIL=1
    else
        echo "[rag-drift] ${coll}: live=${live} (matches benchmark)"
    fi
done

if [[ "${FAIL}" -eq 1 ]]; then
    echo "[rag-drift] index drifted since the last benchmark — recorded metrics are outdated."
    echo "[rag-drift] re-run: envs/rag/bin/python3 mcp/eval/rag_benchmark.py"
    [ "${STRICT}" -eq 1 ] && exit 1
else
    echo "[rag-drift] OK — index matches the last benchmark fingerprint."
fi
exit 0
