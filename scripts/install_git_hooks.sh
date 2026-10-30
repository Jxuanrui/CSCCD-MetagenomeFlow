#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/install_git_hooks.sh
# Purpose: Symlink scripts/hooks/pre-commit into .git/hooks/pre-commit
#          (idempotent, ln -sf). Invoked automatically by scripts/activate.sh
#          self-heal (2026-09-29) and by 0Install.sh §16; this manual entry
#          point remains as fallback for non-git-clone deployments.
# Usage:   bash scripts/install_git_hooks.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="${REPO_ROOT}/scripts/hooks/pre-commit"
HOOK_DST="${REPO_ROOT}/.git/hooks/pre-commit"

if [ ! -f "${HOOK_SRC}" ]; then
    echo "[ERROR] Hook source not found: ${HOOK_SRC}"
    exit 1
fi
if [ ! -d "${REPO_ROOT}/.git" ]; then
    echo "[ERROR] Not a git repository root: ${REPO_ROOT}"
    exit 1
fi

ln -sf "${HOOK_SRC}" "${HOOK_DST}"
chmod +x "${HOOK_SRC}" "${HOOK_DST}"

echo "[OK] pre-commit hook installed -> ${HOOK_DST}"
echo "[INFO] It runs 3 gates on staged files: Ponytail net-growth advisory, shellcheck (blocking), large/binary artifact block (see scripts/hooks/pre-commit)."
