#!/usr/bin/env bash
# ==============================================================================
# discover.sh — Skills 自动发现引擎
# 每两周执行一次，扫描 GitHub + SkillsMP + skills.sh 发现新技能。
# 输出原始数据 → score.py 评分 → 生成月报。
#
# 用法:
#   bash discover.sh                    # 完整运行
#   bash discover.sh --dry-run          # 预览模式（不写入）
#   bash discover.sh --source github    # 仅扫描 GitHub
#   bash discover.sh --source hubs      # 仅扫描 Skill 市场
#
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$(dirname "$SCRIPT_DIR")"
DISCOVERY_DIR="${SCRIPT_DIR}"
SOURCES_DIR="${DISCOVERY_DIR}/sources"
REPORT_DIR="${DISCOVERY_DIR}/report"
# shellcheck disable=SC2034  # kept for debug/external sourcing
CONFIG_FILE="${DISCOVERY_DIR}/config.yaml"
LIFECYCLE_FILE="${SKILLS_DIR}/lifecycle.yaml"

DRY_RUN=false
SOURCE_FILTER="all"

# --- 参数解析 ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --source) SOURCE_FILTER="$2"; shift 2 ;;
        -h|--help)
            echo "用法: bash discover.sh [--dry-run] [--source github|hubs|all]"
            exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; exit 1 ;;
    esac
done

mkdir -p "${REPORT_DIR}"

# --- 辅助函数 ---

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[ERROR] $*" >&2; }

# 追加到原始发现 JSON
append_finding() {
    local json_file="$1"
    local entry="$2"
    if [ -f "${json_file}" ] && [ -s "${json_file}" ]; then
        # 在最后一个 ] 前插入
        sed -i '$s/]$/,\n  '"${entry}"'\n]/' "${json_file}"
    else
        echo "[" > "${json_file}"
        echo "  ${entry}" >> "${json_file}"
        echo "]" >> "${json_file}"
    fi
}

# ==============================================================================
# Step 1: GitHub 扫描
# ==============================================================================

scan_github() {
    log "[GitHub] 开始 GitHub 扫描..."
    local raw_file="${REPORT_DIR}/_raw_github.json"
    echo "[]" > "${raw_file}"

    # 1a. Topic 搜索
    log "[GitHub] Topic 搜索..."
    local source_file="${SOURCES_DIR}/github.yaml"
    if [ -f "${source_file}" ]; then
        # 读取 topic 查询（简单解析 YAML）
        local queries
        queries=$(grep -A1 "^.*repos.*topic" "${source_file}" 2>/dev/null | grep "^      - " | sed 's/^      - "//;s/"$//' || true)
        while IFS= read -r query; do
            [ -z "${query}" ] && continue
            log "[GitHub]   gh search ${query}"
            if command -v gh &>/dev/null && ! ${DRY_RUN}; then
                gh search "${query}" 2>/dev/null >> "${raw_file}" || warn "gh search 失败: ${query}"
            else
                log "        (gh CLI unavailable or dry-run)"
            fi
        done <<< "${queries}"
    fi

    # 1b. 聚合仓库扫描（git clone --depth 1 + 遍历 SKILL.md）
    log "[GitHub] 聚合仓库扫描..."
    local aggregators
    aggregators=$(grep -A20 "aggregation_repos" "${LIFECYCLE_FILE}" 2>/dev/null | grep "^      - " | sed 's/^      - "//;s/"$//' || true)
    local clone_dir="${REPORT_DIR}/_clones"
    mkdir -p "${clone_dir}"

    while IFS= read -r repo; do
        [ -z "${repo}" ] && continue
        local repo_name
        repo_name=$(basename "${repo}")
        log "[GitHub]   聚合仓库: ${repo}"

        if ! ${DRY_RUN}; then
            if [ -d "${clone_dir}/${repo_name}" ]; then
                log "         已缓存，更新..."
                (cd "${clone_dir}/${repo_name}" && git pull --depth 1 2>/dev/null) || true
            else
                git clone --depth 1 "https://github.com/${repo}.git" "${clone_dir}/${repo_name}" 2>/dev/null || {
                    warn "克隆失败: ${repo}（可能无网络访问）"; continue
                }
            fi

            # 统计 SKILL.md 文件
            local skill_count
            skill_count=$(find "${clone_dir}/${repo_name}" -name "SKILL.md" 2>/dev/null | wc -l)
            log "         ${skill_count} 个 SKILL.md 文件"

            # 解析部分 SKILL.md 获取 name + description
            find "${clone_dir}/${repo_name}" -name "SKILL.md" 2>/dev/null | while read -r skill_path; do
                local rel_path
                rel_path="${skill_path#${clone_dir}/${repo_name}/}"
                local skill_name=""
                local skill_desc=""

                skill_name=$(grep "^name:" "${skill_path}" 2>/dev/null | head -1 | sed 's/^name: *//' | tr -d '"' || true)
                skill_desc=$(grep "^description:" "${skill_path}" 2>/dev/null | head -1 | sed 's/^description: *//' | tr -d '"' || true)

                if [ -n "${skill_name}" ]; then
                    local stars
                    stars=$(gh api "repos/${repo}" --jq '.stargazers_count' 2>/dev/null || echo "0")
                    local updated
                    updated=$(gh api "repos/${repo}" --jq '.updated_at' 2>/dev/null || echo "")

                    local entry
                    entry=$(cat << JSONEOF
{
  "id": "${skill_name}",
  "name": "${skill_name}",
  "description": "${skill_desc:-No description}",
  "source": {"type": "github", "repo": "${repo}", "stars": ${stars}},
  "path": "${rel_path}",
  "stars": ${stars},
  "updated_at": "${updated}",
  "tags": [],
  "install_method": "repo: ${repo}, path: ${rel_path}"
}
JSONEOF
)
                    append_finding "${raw_file}" "${entry}"
                fi
            done
        fi
    done <<< "${aggregators}"

    log "[GitHub] 完成，发现 $(wc -l < "${raw_file}" 2>/dev/null || echo 0) 条目"
    echo "${raw_file}"
}

# ==============================================================================
# Step 2: Skill Hub 扫描
# ==============================================================================

scan_hubs() {
    log "[Hubs]  开始 Skill 市场扫描..."
    local raw_file="${REPORT_DIR}/_raw_hubs.json"
    echo "[]" > "${raw_file}"
    local hubs_file="${SOURCES_DIR}/skill_hubs.yaml"

    if [ ! -f "${hubs_file}" ]; then
        warn "skill_hubs.yaml 不存在，跳过"
        echo "${raw_file}"
        return
    fi

    # 2a. SkillsMP API
    if grep -q "skillsmp.*enabled.*true" "${LIFECYCLE_FILE}" 2>/dev/null; then
        log "[Hubs]  SkillsMP 查询..."
        local base_url
        base_url=$(grep "base_url" "${hubs_file}" | head -1 | sed 's/.*base_url: *"//;s/"//' 2>/dev/null || true)
        local queries
        queries=$(grep "q=" "${hubs_file}" 2>/dev/null | sed 's/^.*- "//;s/"$//' || true)

        while IFS= read -r query; do
            [ -z "${query}" ] && continue
            local full_url="${base_url}?${query}"
            log "[Hubs]   SkillsMP: ${full_url}"
            if ! ${DRY_RUN}; then
                curl -sfL "${full_url}" 2>/dev/null >> "${raw_file}" || warn "SkillsMP API 失败"
            fi
        done <<< "${queries}"
    fi

    # 2b. skills.sh API
    if grep -q "skills_sh.*enabled.*true" "${LIFECYCLE_FILE}" 2>/dev/null; then
        log "[Hubs]  skills.sh 查询..."
        local endpoints
        endpoints=$(grep "https://skills.sh" "${hubs_file}" 2>/dev/null | sed 's/.*- "//;s/"$//' || true)
        while IFS= read -r endpoint; do
            [ -z "${endpoint}" ] && continue
            log "[Hubs]   skills.sh: ${endpoint}"
            if ! ${DRY_RUN}; then
                curl -sfL "${endpoint}" 2>/dev/null >> "${raw_file}" || warn "skills.sh API 失败"
            fi
        done <<< "${endpoints}"
    fi

    log "[Hubs]  完成"
    echo "${raw_file}"
}

# ==============================================================================
# Step 3: Web 搜索兜底
# ==============================================================================

scan_web() {
    log "[Web]   开始 Web 搜索兜底..."
    local raw_file="${REPORT_DIR}/_raw_web.json"
    echo "[]" > "${raw_file}"
    local hubs_file="${SOURCES_DIR}/skill_hubs.yaml"

    local queries
    queries=$(grep "web_discovery" -A10 "${hubs_file}" 2>/dev/null | grep "^      - " | sed 's/^      - "//;s/"$//' || true)
    while IFS= read -r query; do
        [ -z "${query}" ] && continue
        log "[Web]   ${query}"
        # Web 搜索仅做日志输出（需要人工查阅后再审核）
        echo "{\"query\": \"${query}\", \"note\": \"Web search results require manual review\"}" >> "${raw_file}"
    done <<< "${queries}"

    log "[Web]  完成"
    echo "${raw_file}"
}

# ==============================================================================
# Step 4: 合并 + 评分
# ==============================================================================

run_scoring() {
    local merged_file="${REPORT_DIR}/_all_findings.json"
    local github_file="${REPORT_DIR}/_raw_github.json}"
    local hubs_file="${REPORT_DIR}/_raw_hubs.json"
    local web_file="${REPORT_DIR}/_raw_web.json"

    log "[Merge] 合并所有发现..."
    # 合并 JSON 数组
    python3 -c "
import json
import sys
data = []
for f in ['${github_file//\'}', '${hubs_file//\'}', '${web_file//\'}']:
    try:
        with open(f) as fh:
            d = json.load(fh)
            if isinstance(d, list):
                data.extend(d)
    except (json.JSONDecodeError, FileNotFoundError):
        pass
with open('${merged_file}', 'w') as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
print(f'Merged {len(data)} findings')
" 2>&1 || warn "合并失败"

    log "[Score] 运行评分引擎..."
    local score_script="${DISCOVERY_DIR}/score.py"

    if ${DRY_RUN}; then
        python3 "${score_script}" --input "${merged_file}" --output "${REPORT_DIR}" --dry-run
    else
        python3 "${score_script}" --input "${merged_file}" --output "${REPORT_DIR}"
    fi

    if [ $? -eq 0 ]; then
        log "[Done]  月报已生成"
    else
        fail "评分引擎运行失败"
    fi

    # 清理原始文件（keep _all_findings.json for reference）
    if ! ${DRY_RUN}; then
        rm -f "${REPORT_DIR}/_raw_github.json" "${REPORT_DIR}/_raw_hubs.json" "${REPORT_DIR}/_raw_web.json"
    fi
}

# ==============================================================================
# 主流程
# ==============================================================================

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  CSCCD-MetagenomeFlow Skills 发现引擎              ║"
echo "║  $(date '+%Y-%m-%d %H:%M')                     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# shellcheck disable=SC2034  # kept for debug/external sourcing
# shellcheck disable=SC2034  # kept for debug/external sourcing
GITHUB_FILE=""
# shellcheck disable=SC2034  # kept for debug/external sourcing
# shellcheck disable=SC2034  # kept for debug/external sourcing
HUBS_FILE=""
# shellcheck disable=SC2034  # kept for debug/external sourcing
# shellcheck disable=SC2034  # kept for debug/external sourcing
WEB_FILE=""

case "${SOURCE_FILTER}" in
    github|gh)
        # shellcheck disable=SC2034  # kept for debug/external sourcing
        GITHUB_FILE=$(scan_github)
        ;;
    hubs)
        # shellcheck disable=SC2034  # kept for debug/external sourcing
        HUBS_FILE=$(scan_hubs)
        # shellcheck disable=SC2034  # kept for debug/external sourcing
        WEB_FILE=$(scan_web)
        ;;
    all|*)
        # shellcheck disable=SC2034  # kept for debug/external sourcing
        GITHUB_FILE=$(scan_github)
        # shellcheck disable=SC2034  # kept for debug/external sourcing
        HUBS_FILE=$(scan_hubs)
        # shellcheck disable=SC2034  # kept for debug/external sourcing
        WEB_FILE=$(scan_web)
        ;;
esac

run_scoring

echo ""
echo "[discover] 完成"
