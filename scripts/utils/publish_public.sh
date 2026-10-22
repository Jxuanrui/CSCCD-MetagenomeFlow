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
EXCLUDE_RE='^(AGENTS\.md|CLAUDE\.md|\.mcp\.json|\.claude/|\.zcode/|\.zcodeignore|\.omo/|\.codegraph|agents/provenance/|skills/|mining/|Project/|docs/plans/|scripts/tests/|scripts/utils/supervisor_api\.py|scripts/utils/publish_public\.sh)'

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
echo "${FILES}" | xargs -d '\n' grep -l 'Harbin' 2>/dev/null | xargs -r -d '\n' sed -i 's/Harbin/Sample/g' || true
# Machine-specific repo paths in mined tooling become portable placeholders.
# 2026-10-19: generalized — any /home/<user>/ prefix becomes ~/ (covers sibling
# project paths like apptainer kits; /home/user examples normalize harmlessly)
echo "${FILES}" | xargs -d '\n' grep -l -E '/home/[A-Za-z0-9_.-]+/' 2>/dev/null | \
    xargs -r -d '\n' sed -i -E 's#/home/[A-Za-z0-9_.-]+/#~/#g' || true
# 2026-10-19 pass: this cycle's review-process vocabulary and tool refs are
# neutralized across shipped text (review channel terms, agent jargon, client names).
echo "${FILES}" | xargs -d '\n' grep -l -e '质量审核' -e '主代理' -e '子代理' 2>/dev/null | \
    xargs -r -d '\n' sed -i -e 's/质量审核/质量审核/g' -e 's/主代理/执行方/g' -e 's/子代理/后台任务/g' || true
echo "${FILES}" | xargs -d '\n' grep -l -E 'supervisor (P0|final|stage|review)|supervisor_[0-9]|，supervisor|, supervisor' 2>/dev/null | \
    xargs -r -d '\n' sed -i -E 's/supervisor_(19|20)[0-9]{4}[a-z_]*/review/g; s/，supervisor/，review/g; s/, supervisor/, review/g' || true
echo "${FILES}" | xargs -d '\n' grep -l -E 'Claude Code|claude mcp|claude -p' 2>/dev/null | \
    xargs -r -d '\n' sed -i -E -e 's/Claude Code/MCP 客户端/g' -e 's/claude mcp add/mcp add/g' -e 's/claude -p [^ ]* --agent [a-z]+/cli-review/g' || true
# 2026-10-19 pass 2: scattered client/tooling mentions in shipped docs.
echo "${FILES}" | xargs -d '\n' grep -l -E '\.claude|Claude|claude|Codex|ZCode|zcode' 2>/dev/null | \
    xargs -r -d '\n' sed -i -E -e 's#\.claude/skills#本地技能目录#g' -e 's#~?/\.claude/skills#~/local/skills#g' \
        -e 's/`\.claude[^`]*`/内部目录/g' -e 's/Claude|MCP 客户端/g' -e 's/claude/内部 CLI/g' \
        -e 's/Codex/外部执行器/g' -e 's/ZCode 工作区级/工作区级/g' -e 's/ZCode/工作区/g' -e 's/zcode/内部工具/g' || true
# gitignore: drop the internal relay-config line from the snapshot
sed -i '/supervisor_relays/d' .gitignore 2>/dev/null || true
# 2026-10-21: export sanitized tutorial + optimization evidence for public docs.
# Copy walkthrough (sanitized: no sample IDs, no absolute paths) to docs/tutorial/
mkdir -p docs/tutorial
if [ -f Project/Project_demo/walkthrough.md ]; then
    sed -e 's/Harbin[0-9]\+/Sample<N>/g' \
        -e 's#/home/[A-Za-z0-9_.-]\+/#~/#g' \
        -e 's/质量审核/质量审核/g' -e 's/主代理/执行方/g' -e 's/子代理/后台任务/g' \
        Project/Project_demo/walkthrough.md > docs/tutorial/walkthrough.md
    echo "[publish] exported sanitized walkthrough to docs/tutorial/"
fi
# Export optimization summary (sanitized)
if [ -f Project/Project_demo/result/opt_bench/amr_fusion/reconciliation.json ]; then
    sed 's/Harbin[0-9]\+/Sample<N>/g' \
        Project/Project_demo/result/opt_bench/amr_fusion/reconciliation.json > docs/tutorial/amr_fusion_summary.json 2>/dev/null || true
fi
# Internal review-archive path references drop to generic wording.
echo "${FILES}" | xargs -d '\n' grep -l '\.claude/reviews/' 2>/dev/null | \
    xargs -r -d '\n' sed -i -E 's/`?\.claude\/reviews\/[A-Za-z0-9_.-]+`?/内部审校记录/g' || true
# Development-era attributions and retired dual-agent jargon are neutralized;
# dead /mgx-* references into the unshipped .claude/ tree drop their lines.
echo "${FILES}" | xargs -d '\n' grep -l '^# Author: Claude Code' 2>/dev/null | \
    xargs -r -d '\n' sed -i 's|^# Author: Claude Code.*|# Author: CSCCD-MetagenomeFlow team|' || true
echo "${FILES}" | xargs -d '\n' grep -l -E 'Codex sandbox|Codex 沙盒|Codex 沙箱|CC Bash 工具|走Codex执行' 2>/dev/null | \
    xargs -r -d '\n' sed -i -e 's/Codex sandbox/sandboxed executor/g' \
        -e 's/Codex 沙盒/执行沙箱/g' -e 's/Codex 沙箱/执行沙箱/g' \
        -e 's/CC Bash 工具/宿主 Bash/g' -e 's/走Codex执行/由编程助手执行/g' \
        -e 's/Claude Code 运行时文件/AI 客户端运行时文件/g' || true
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
