#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 45_ref_registry.sh
# 功  能: 参考库登记——把功能肽分支实际依赖的外部资源固化成版本戳清单：
#           miProbe API（openapi 版本、端点清单、33 模型名+数据集+AUC、访问时间）
#         Quorumpeps/DRAMP 等扩展参考库按 D4 决策暂缓拉取，登记为 pending。
# 输  出: ${WORKDIR}/result/peptide/refs/registry.json
# 用  法: bash 45_ref_registry.sh -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 45_ref_registry.sh -w WORKDIR -r REPO [--force]

Stamps the external resource versions actually used by the peptide branch.
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

OUT="${WORKDIR}/result/peptide/refs"
LOG="${WORKDIR}/logs/peptide/refs"
mkdir -p "${OUT}" "${LOG}"
LOG_FILE="${LOG}/45_ref_registry_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

SENTINEL="${OUT}/registry.done"
rm -f "${SENTINEL}" "${SENTINEL}.FAILED"

echo "[INFO] 45 号参考库登记启动 $(date -u '+%F %T')"

python3 - "${OUT}" <<'PYEOF'
import json, subprocess, sys, time, datetime

out = sys.argv[1]
API = "https://www.biosino.org/iMAC/miProbe/api"
NOW = datetime.datetime.now(datetime.timezone.utc).isoformat()

def curl(url):
    r = subprocess.run(["curl", "-s", "--max-time", "60", url],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"curl rc={r.returncode} for {url}")
    return r.stdout

spec = json.loads(curl(f"{API}/openapi.json"))
models = json.loads(curl(f"{API}/prediction/bioactivity/models"))

registry = {
    "registered_at_utc": NOW,
    "miProbe": {
        "base_url": "https://www.biosino.org/iMAC/miProbe/api",
        "api_title": spec["info"]["title"],
        "api_version": spec["info"]["version"],
        "access": "open, no authentication",
        "endpoints": sorted(spec["paths"].keys()),
        "bioactivity_models": [
            {"name": m["name"], "display_name": m["display_name"],
             "category_label": m["category_label"], "dataset": m.get("dataset"),
             "auc": m.get("auc")} for m in models
        ],
        "accessed_at_utc": NOW,
        "transport": "curl (urllib blocked by Cloudflare TLS fingerprint)",
        "notes": "batch cap: bioactivity max 10 seqs/call (11-model subset used at 3 seqs/call "
                 "against the 60s gateway window); embedding-search single sequence, k<=20, min len 5",
    },
    "deferred_references": {
        "quorumpeps": {"status": "pending", "reason": "D4: 一期类别集未含 QS 专项比对（托管 quorum_sensing 模型已覆盖试点）"},
        "dramp": {"status": "pending", "reason": "同上；且 hosted bioactivity 已含抗感染 16 类"},
        "bagel4_hmm": {"status": "blocked", "reason": "条款未读，支路按用户决策关闭"},
        "signalp6_standalone": {"status": "pending", "reason": "学术注册待机构信息；托管 deeptmhmm-signalp 端点可代位"},
    },
}
path = f"{out}/registry.json"
with open(path, "w", encoding="utf-8") as f:
    json.dump(registry, f, ensure_ascii=False, indent=1)
print(f"[done] registry: {path}")
print(f"  miProbe {registry['miProbe']['api_version']} | "
      f"{len(registry['miProbe']['endpoints'])} endpoints | "
      f"{len(models)} bioactivity models | accessed {NOW}")
PYEOF

date -u '+%F %T' > "${SENTINEL}"
echo "[DONE] $(date -u '+%F %T') ref_registry"
mgx_end "refs"
