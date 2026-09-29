#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/install_git_hooks.sh
# Purpose: One-time setup to symlink scripts/hooks/pre-commit into
#          .git/hooks/pre-commit so it takes effect on this machine.
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
echo "[INFO] It runs shellcheck on staged .sh files (see scripts/hooks/pre-commit)."
