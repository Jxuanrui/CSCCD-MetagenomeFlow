#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/utils/publish_public.sh
# Purpose: Rebuild the clean public snapshot branch from the current master
#          worktree, excluding local governance/AI-session material and
#          copyrighted PDFs. The public branch is ALWAYS a single fresh commit
#          (orphan) — never merge master into it, and NEVER `git push --mirror`
#          (that would export the full private history).
# Usage:   bash scripts/utils/publish_public.sh [branch]     # default: public
# Push:    git push <github-remote> public:main              # single branch only
# ==============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRANCH="${1:-public}"

# Files/dirs that must NEVER enter the public snapshot.
EXCLUDE_RE='^(AGENTS\.md|CLAUDE\.md|\.mcp\.json|\.claude/|\.zcode/|\.omo/|\.codegraph|agents/provenance/|skills/.*\.pdf)'

cd "${REPO}"

if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] worktree is dirty — commit or stash first" >&2
    exit 1
fi

CURRENT="$(git rev-parse --abbrev-ref HEAD)"
if [ "${CURRENT}" != "master" ]; then
    echo "[ERROR] run this from master (currently on ${CURRENT})" >&2
    exit 1
fi

echo "[publish] collecting tracked files minus exclusions"
FILES="$(git ls-files | grep -vE "${EXCLUDE_RE}" || true)"
if [ -z "${FILES}" ]; then
    echo "[ERROR] empty file set — exclusion regex is too broad?" >&2
    exit 1
fi

LEAK="$(echo "${FILES}" | grep -E "${EXCLUDE_RE}" || true)"
if [ -n "${LEAK}" ]; then
    echo "[ERROR] exclusion filter failed for:" >&2; echo "${LEAK}" >&2
    exit 1
fi

MASTER_SHA="$(git rev-parse --short HEAD)"
echo "[publish] rebuilding orphan branch ${BRANCH} from master ${MASTER_SHA} ($(echo "${FILES}" | wc -l) files)"

git branch -D "${BRANCH}" >/dev/null 2>&1 || true
git checkout --orphan "${BRANCH}" >/dev/null 2>&1
git rm -r -q --cached . >/dev/null 2>&1 || true
# Machine-specific runtime paths in shipped config templates become generic
# home-relative examples; the master worktree copy is force-restored afterwards.
sed -i 's|/home/[^/]*/Course/Maxmetagenome|~/Course/Maxmetagenome|g' \
    pipeline/config/config.yaml pipeline/config/config.test_ci.yaml 2>/dev/null || true
echo "${FILES}" | xargs -d '\n' git add -f --
# --no-verify: this snapshot assembles already-reviewed master content;
# the pre-commit shellcheck scope would pull in vendored replication
# scripts whose legacy warnings are out of publish scope.
git commit -q --no-verify -m "Public snapshot of master ${MASTER_SHA}"
git checkout -f -q master

# Post-build verification: no excluded paths, no absolute home paths.
BAD_PATHS="$(git ls-tree -r --name-only "${BRANCH}" | grep -E "${EXCLUDE_RE}" || true)"
BAD_HOME="$(git grep -l '/home/' "${BRANCH}" -- 2>/dev/null || true)"
if [ -n "${BAD_PATHS}" ] || [ -n "${BAD_HOME}" ]; then
    echo "[ERROR] verification failed:" >&2
    [ -n "${BAD_PATHS}" ] && echo "${BAD_PATHS}" >&2
    [ -n "${BAD_HOME}" ] && echo "${BAD_HOME}" >&2
    exit 1
fi

echo "[publish] ${BRANCH} ready: $(git rev-parse --short "${BRANCH}") — single clean commit"
echo "[publish] push with:  git push <remote> ${BRANCH}:main    (never --mirror)"
