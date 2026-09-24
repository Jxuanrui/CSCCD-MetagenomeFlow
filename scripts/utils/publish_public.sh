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
BRANCH="public"
TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="${2:?--tag needs a value}"; shift 2 ;;
        *) echo "[WARN] unknown arg: $1" >&2; shift ;;
    esac
done

# Files/dirs that must NEVER enter the public snapshot.
# Project/ carries production cohort metadata + machine-specific sheets.
EXCLUDE_RE='^(AGENTS\.md|CLAUDE\.md|\.mcp\.json|\.claude/|\.zcode/|\.omo/|\.codegraph|agents/provenance/|skills/.*\.pdf|Project/)'

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
sed -i -E 's#/home/[^/]*/Course/(CSCCD-MetagenomeFlow|Maxmetagenome)#~/Course/CSCCD-MetagenomeFlow#g' \
    pipeline/config/config.yaml pipeline/config/config.test_ci.yaml 2>/dev/null || true
# Real-cohort sample IDs (docs/comments/example commands only — verified no
# functional strings) are neutralized to "Sample<N>" in the snapshot.
echo "${FILES}" | xargs -d '\n' grep -l 'Sample' 2>/dev/null | xargs -r -d '\n' sed -i 's/Sample/Sample/g' || true
# Machine-specific repo paths in mined tooling become portable placeholders.
echo "${FILES}" | xargs -d '\n' grep -l -E '/home/[^/]*/Course/(CSCCD-MetagenomeFlow|Maxmetagenome)' 2>/dev/null | \
    xargs -r -d '\n' sed -i -E 's#/home/[^/]*/Course/(CSCCD-MetagenomeFlow|Maxmetagenome)#~/Course/CSCCD-MetagenomeFlow#g' || true
# Development-era attributions and retired dual-agent jargon are neutralized;
# dead /mgx-* references into the unshipped .claude/ tree drop their lines.
echo "${FILES}" | xargs -d '\n' grep -l '^# Author: Claude Code' 2>/dev/null | \
    xargs -r -d '\n' sed -i 's|^# Author: Claude Code.*|# Author: CSCCD-MetagenomeFlow team|' || true
echo "${FILES}" | xargs -d '\n' grep -l -E 'sandboxed executor|执行沙箱|执行沙箱|宿主 Bash|由编程助手执行' 2>/dev/null | \
    xargs -r -d '\n' sed -i -e 's/sandboxed executor/sandboxed executor/g' \
        -e 's/执行沙箱/执行沙箱/g' -e 's/执行沙箱/执行沙箱/g' \
        -e 's/宿主 Bash/宿主 Bash/g' -e 's/由编程助手执行/由编程助手执行/g' \
        -e 's/AI 客户端运行时文件/AI 客户端运行时文件/g' || true
for f in agents/README.md pipeline/README.md docs/PROJECT_MAP.md; do
    [ -f "$f" ] && sed -i -E '/(^[-|] .*|.*(技能|技能:|可调用技能)).*\/mgx-\*/d' "$f"
done
echo "${FILES}" | xargs -d '\n' git add -f --
# --no-verify: this snapshot assembles already-reviewed master content;
# the pre-commit shellcheck scope would pull in vendored replication
# scripts whose legacy warnings are out of publish scope.
# Snapshot identity: GitHub noreply (master's own identity stays untouched).
git -c user.name="Jxuanrui" -c user.email="Jxuanrui@users.noreply.github.com" \
    commit -q --no-verify -m "Public snapshot of master ${MASTER_SHA}"
git checkout -f -q master

# Optional release tag on the snapshot commit (public tag only — never
# points into private master history).
if [ -n "${TAG}" ]; then
    git tag -f "${TAG}" "${BRANCH}" >/dev/null
    echo "[publish] tag ${TAG} -> $(git rev-parse --short "${BRANCH}")"
fi

# Post-build verification: no excluded paths, no absolute home paths.
BAD_PATHS="$(git ls-tree -r --name-only "${BRANCH}" | grep -E "${EXCLUDE_RE}" || true)"
BAD_HOME="$(git grep -l '/home/' "${BRANCH}" -- 2>/dev/null | grep -v 'scripts/utils/publish_public.sh' || true)"
if [ -n "${BAD_PATHS}" ] || [ -n "${BAD_HOME}" ]; then
    echo "[ERROR] verification failed:" >&2
    [ -n "${BAD_PATHS}" ] && echo "${BAD_PATHS}" >&2
    [ -n "${BAD_HOME}" ] && echo "${BAD_HOME}" >&2
    exit 1
fi

echo "[publish] ${BRANCH} ready: $(git rev-parse --short "${BRANCH}") — single clean commit"
echo "[publish] push with:  git push <remote> ${BRANCH}:main --force${TAG:+ && git push <remote> ${TAG}}    (never --mirror)"
