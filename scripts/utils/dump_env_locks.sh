#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/utils/dump_env_locks.sh
# Purpose: Dump one conda lock manifest per environment under envs/ into
#          docs/manifests/envs/<name>.txt so the software stack can be
#          audited or rebuilt off-machine. Regenerate after any conda/pip
#          change:  bash scripts/utils/dump_env_locks.sh
# Output:  docs/manifests/envs/<env>.txt -- `conda list --explicit` when the
#          env supports it, `conda list --json` as fallback.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENVS_DIR="${REPO_ROOT}/envs"
OUT_DIR="${REPO_ROOT}/docs/manifests/envs"
BASE_CONDA="${REPO_ROOT}/miniforge3/bin/conda"

mkdir -p "${OUT_DIR}"

explicit=0
fallback=0
skipped=0

for env_path in "${ENVS_DIR}"/*/; do
    name="$(basename "${env_path}")"

    # Guard: only real conda environments carry conda-meta/; skip anything else.
    if [ ! -d "${env_path}conda-meta" ]; then
        echo "[SKIP] ${name}: no conda-meta/ (not a conda env)"
        skipped=$((skipped + 1))
        continue
    fi

    # Prefer an env-local conda binary; prefix envs normally only have the base one.
    conda_bin="${env_path}bin/conda"
    [ -x "${conda_bin}" ] || conda_bin="${BASE_CONDA}"
    if [ ! -x "${conda_bin}" ]; then
        echo "[SKIP] ${name}: no usable conda binary found"
        skipped=$((skipped + 1))
        continue
    fi

    out="${OUT_DIR}/${name}.txt"
    if "${conda_bin}" list --explicit -p "${env_path}" > "${out}" 2>/dev/null; then
        echo "[OK]   ${name} (explicit)"
        explicit=$((explicit + 1))
    elif "${conda_bin}" list --json -p "${env_path}" > "${out}" 2>/dev/null; then
        echo "[OK]   ${name} (json fallback)"
        fallback=$((fallback + 1))
    else
        echo "[FAIL] ${name}: conda list failed"
        skipped=$((skipped + 1))
    fi
done

echo ""
echo "=============================================================================="
echo "[SUMMARY] explicit: ${explicit}  json-fallback: ${fallback}  failed/skipped: ${skipped}"
echo "[SUMMARY] manifests written under ${OUT_DIR}"
echo "=============================================================================="
