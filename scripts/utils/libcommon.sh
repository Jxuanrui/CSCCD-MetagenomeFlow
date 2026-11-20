#!/usr/bin/env bash
# ==============================================================================
# 脚本名: utils/libcommon.sh
# 功  能: scripts/ 分析脚本共享库（表驱动参数解析 / 必需参数检查 / 计时 / conda 执行包装）
# 依  赋: bash 4+；mgx_conda 依赖会话已激活的 conda（scripts/activate.sh）
# 用  法: 在分析脚本中 source 本库后调用：
#           source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"
#           MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"   # 短选项:变量名（空格分隔）
#           MGX_OPTS_FLAG="force skip-shap"                      # 布尔标志，--force → FORCE=1；
#                                     # 标志名中的 - 派生变量名时映射为 _（skip-shap → SKIP_SHAP=1）
#           MGX_OPTS_LONG="speed-mode:SPEED_MODE"                # 带值长选项:变量名（同样 - → _）
#           mgx_parse "$@"            # 支持 -s val / -s=val / --flag / --key val / --key=val；
#                                     # -h|--help → show_help 后 exit 0
#           mgx_require SAMPLE CPUS WORKDIR REPO   # 任一为空 → [ERROR] 缺少必需参数 后 exit 1
#           mgx_begin                  # SECONDS=0
#           mgx_end "fastp"            # 输出 [fastp] 耗时 ${SECONDS}s
#           mgx_conda fastp fastp ...  # conda run --prefix ${REPO}/envs/fastp --no-capture-output ...
#           mgx_try cmd ...            # 屏蔽 errexit 执行，返回命令退出码（不终止脚本）
# 说明: 本库为 sourced 库，不自行启用 set -e（调用方脚本自行 set -euo pipefail）；
#       show_help 由调用方定义（可选），mgx_parse/mgx_require 会自动调用。
# ==============================================================================

# 调用方定义了 show_help 则调用（未定义则跳过）
_mgx_help() {
    if declare -F show_help >/dev/null; then show_help; fi
}

# 未知参数统一报错（与既有各脚本错误文本一致）
_mgx_unknown() {
    echo "[ERROR] 未知参数: $1"
    _mgx_help
    exit 1
}

# 表查询: $1=短选项（如 -s），$2=选项表（如 MGX_OPTS_STRING 的值）；命中则输出变量名
_mgx_lookup() {
    local spec
    for spec in $2; do
        if [ "-${spec%%:*}" = "$1" ]; then
            printf '%s' "${spec#*:}"
            return 0
        fi
    done
    return 1
}

# 变量名派生: - 映射为 _ 后转大写（flag/长选项名 → 合法 bash 变量名，skip-shap → SKIP_SHAP）
_mgx_var() {
    local name="${1//-/_}"
    printf '%s' "${name^^}"
}

# 表驱动参数解析（替代各脚本的 while/case 与 getopts 解析块）
mgx_parse() {
    local opt var flag
    # 布尔标志默认 0（--flag 出现时置 1）
    for flag in ${MGX_OPTS_FLAG:-}; do
        printf -v "$(_mgx_var "${flag}")" '%s' 0
    done
    # 带值选项默认空串（质量审核终审 2026-10-15 P0-1：set -u 脚本未传可选参数时
    # unbound variable 崩溃——41 号 MAG_FILTER 实爆；一次覆盖全部脚本）。
    # 2026-10-16 修正：仅对"完全未设置"的变量预置空串——91/93 曾在 mgx_parse
    # 前给非空默认值（GROUP_COL="group"、NET_TYPE="all"），被无条件覆盖成空串
    # 导致 gate 烟测三连败（regression 由 W5 gate 在统计段启动前拦截）
    for opt in ${MGX_OPTS_STRING:-} ${MGX_OPTS_LONG:-}; do
        local pvar
        pvar="$(_mgx_var "${opt#*:}")"
        if [ -z "${!pvar+x}" ]; then
            printf -v "$pvar" '%s' ""
        fi
    done
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                _mgx_help
                exit 0
                ;;
            --*)
                opt="${1#--}"
                var=""
                for flag in ${MGX_OPTS_FLAG:-}; do
                    if [ "${flag}" = "${opt}" ]; then var="$(_mgx_var "${flag}")"; break; fi
                done
                if [ -n "${var}" ]; then
                    printf -v "${var}" '%s' 1
                    shift
                elif var="$(_mgx_lookup "-${opt%%=*}" "${MGX_OPTS_LONG:-}")"; then
                    var="${var//-/_}"
                    if [ "${opt}" != "${opt%%=*}" ]; then
                        printf -v "${var}" '%s' "${opt#*=}"   # --key=val
                        shift
                    elif [ $# -lt 2 ]; then
                        echo "[ERROR] 参数 $1 缺少值"
                        _mgx_help
                        exit 1
                    else
                        printf -v "${var}" '%s' "$2"          # --key val
                        shift 2
                    fi
                else
                    _mgx_unknown "$1"
                fi
                ;;
            -?=?*)
                opt="${1%%=*}"
                var="$(_mgx_lookup "${opt}" "${MGX_OPTS_STRING:-}")" || _mgx_unknown "$1"
                printf -v "${var}" '%s' "${1#*=}"
                shift
                ;;
            -*)
                var="$(_mgx_lookup "$1" "${MGX_OPTS_STRING:-}")" || _mgx_unknown "$1"
                if [ $# -lt 2 ]; then
                    echo "[ERROR] 参数 $1 缺少值"
                    _mgx_help
                    exit 1
                fi
                printf -v "${var}" '%s' "$2"
                shift 2
                ;;
            *)
                _mgx_unknown "$1"
                ;;
        esac
    done
}

# 必需参数检查: 任一命名变量为空 → 报错 + show_help + exit 1
mgx_require() {
    local v
    for v in "$@"; do
        if [ -z "${!v:-}" ]; then
            echo "[ERROR] 缺少必需参数"
            _mgx_help
            exit 1
        fi
    done
}

# ==============================================================================
# ENG-6/run-monitor: opt-in per-step run-event hook (default OFF; MGX_MONITOR=1
# enables). mgx_begin writes ONE start event immediately (exit_code=-1 marker,
# negative-only: a real $? is 0-255 so genuine failure codes can never collide
# with the marker — supervisor stage-3 P0-1) and registers an EXIT trap that
# appends ONE end event per script run to ${WORKDIR}/logs/run_events.jsonl —
# a start/end pair per execution (field set unchanged; user-approved
# semantics extension 2026-10-02, marker value corrected same day). 7 field names align with
# scripts/write_provenance.py (started_at/step_id/sample_id/params/exit_code/
# duration/workdir->duration_sec) plus one extension field ts (end time).
# Type note: params here is the raw argv string, NOT write_provenance.py's
# key-value object — merging the two record families requires conversion
# (supervisor C1, 2026-10-02).
# Hard constraints (supervisor-approved):
#   - Default OFF: with MGX_MONITOR != 1 the observable behavior of every
#     sourcing script is byte-identical (no output, no files, same exit
#     codes) — EXCEPT the pre-existing P2-HYGIENE-01 production guard below,
#     which scripts acquire by calling mgx_begin at all: newly-hooked scripts
#     (02_qc_kneaddata ce6495b; six stat scripts 2efc6c7) now exit 60 on
#     Project01 + --force regardless of MGX_MONITOR (supervisor C1, 2026-10-02).
#   - The hook must never alter the caller's exit code and never write to the
#     caller's stdout: every internal failure is swallowed (2>/dev/null || true).
#   - The append is a single printf >> redirection, but NFS does not guarantee
#     atomic append across nodes (interleaving is possible under multi-node
#     parallelism).
#   - Scripts that register their own EXIT trap after mgx_begin override this
#     hook (last trap wins) and become monitor blind spots.
#   - Scripts not calling mgx_begin are coverage blind spots (02_qc_kneaddata.sh
#     fixed in ce6495b; any future script that skips mgx_begin reopens the gap).
#   - params is snapshotted in the trap's fire-time scope ("$*"), i.e. the
#     script's arguments for top-level exits (function-local arguments if the
#     exit happens inside a function).
#   - Project01 write guard: events are skipped when the realpath of WORKDIR
#     is */Project/Project01 or below, unless PRODUCTION_WRITE_ALLOWED=true.
# ==============================================================================

# JSON 字符串转义: 转义反斜杠与双引号，剔除控制字符（0x00-0x1F）。
# 输入: 优先 $1，无参数时读 stdin。任何内部失败都不影响调用方。
_mgx_json_escape() {
    local _raw=""
    if [ "$#" -gt 0 ]; then
        _raw="$1"
    else
        _raw="$(cat 2>/dev/null || true)"
    fi
    { printf '%s' "${_raw}" | tr -d '\000-\037' 2>/dev/null \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' 2>/dev/null; } || true
    return 0
}

# 追加一条当前脚本运行的 JSON 事件（见上方头注释）。Usage: _mgx_emit <exit_code>
_mgx_emit() {
    [ "${MGX_MONITOR:-0}" = "1" ] || return 0
    {
        local LC_ALL=C
        local _rc _ts _started _step _sample _dur _wd_esc _params _line _budget _wd_real
        [ -n "${WORKDIR:-}" ] || return 0
        _wd_real="$(realpath -m "${WORKDIR}" 2>/dev/null || printf '%s' "${WORKDIR}")"
        case "${_wd_real}" in
            */Project/Project01|*/Project/Project01/*)
                [ "${PRODUCTION_WRITE_ALLOWED:-false}" = "true" ] || return 0
                ;;
        esac
        mkdir -p "${WORKDIR}/logs" 2>/dev/null || true
        _rc_raw="${1:-0}"
        case "${_rc_raw}" in
            # Negative marker (step-start = -1): real $? is always 0-255, so a
            # negative value can never collide with a genuine exit code
            # (supervisor stage-3 P0-1: a real exit 2 was misread as "running").
            -[0-9]*) _rc="-${_rc_raw#-}" ;;
            *) _rc="$(printf '%s' "${_rc_raw}" | tr -cd '0-9' 2>/dev/null || true)" ;;
        esac
        [ -n "${_rc}" ] || _rc=0
        _dur="$(printf '%s' "${SECONDS:-0}" | tr -cd '0-9' 2>/dev/null || true)"
        [ -n "${_dur}" ] || _dur=0
        _ts="$(_mgx_json_escape "$(date +%FT%T%z 2>/dev/null || true)")"
        _started="$(_mgx_json_escape "${_MGX_STARTED_AT:-}")"
        _step="$(_mgx_json_escape "$(basename "$0" 2>/dev/null || true)")"
        _sample="$(_mgx_json_escape "${SAMPLE:-${SAMPLE_ID:-}}")"
        _wd_esc="$(_mgx_json_escape "${WORKDIR}")"
        _params="$(_mgx_json_escape "${_MGX_ARGV:-}")"
        # 整行预算 4096 字节: 先测出 params 为空时的行长，再截断转义后的
        # params（截断回退到合法转义边界——剥离尾部悬空反斜杠，避免切在
        # \\ 或 \" 转义序列中间产生非法 JSON；以尾部 "..." 标记）。
        _line="$(printf '{"ts":"%s","started_at":"%s","step_id":"%s","sample_id":"%s","params":"","exit_code":%s,"duration_sec":%s,"workdir":"%s"}' \
            "${_ts}" "${_started}" "${_step}" "${_sample}" "${_rc}" "${_dur}" "${_wd_esc}")"
        _budget=$(( 4096 - ${#_line} - 8 ))
        if [ "${#_params}" -gt "${_budget}" ]; then
            if [ "${_budget}" -gt 3 ]; then
                _params="${_params:0:$(( _budget - 3 ))}"
                while [ "${#_params}" -gt 0 ] && [ "${_params: -1}" = '\' ]; do
                    _params="${_params%?}"
                done
                _params="${_params}..."
            else
                _params=""
            fi
        fi
        printf '{"ts":"%s","started_at":"%s","step_id":"%s","sample_id":"%s","params":"%s","exit_code":%s,"duration_sec":%s,"workdir":"%s"}\n' \
            "${_ts}" "${_started}" "${_step}" "${_sample}" "${_params}" "${_rc}" "${_dur}" "${_wd_esc}" \
            >> "${WORKDIR}/logs/run_events.jsonl" 2>/dev/null || true
    } 2>/dev/null || true
    return 0
}

# 计时开始（先统一转绝对路径：cd 后相对路径嵌套 + Project01 守卫绕过都源于此）
mgx_begin() {
    # Normalize WORKDIR/REPO to absolute paths (supervisor incident review E1+E6)
    # Fixes: (a) scripts that cd into TEMP_DIR break relative --output paths;
    # (b) Project01 write guard pattern */Project/Project01 fails to match
    # relative paths (security bypass). realpath -m handles nonexistent dirs.
    if [ -n "${WORKDIR:-}" ]; then
        WORKDIR="$(realpath -m "${WORKDIR}" 2>/dev/null || echo "${WORKDIR}")"
    fi
    if [ -n "${REPO:-}" ]; then
        REPO="$(realpath -m "${REPO}" 2>/dev/null || echo "${REPO}")"
    fi
    # P2-HYGIENE-01 production write guard: refuse Project01 + --force
    # unless PRODUCTION_WRITE_ALLOWED=true is explicitly exported.
    # Read-only use (no --force) is unaffected; scientific output unchanged.
    if [ "${FORCE:-0}" -eq 1 ] && [ "${PRODUCTION_WRITE_ALLOWED:-false}" != "true" ]; then
        case "${WORKDIR:-}" in
            */Project/Project01|*/Project/Project01/*)
                echo "[GUARD] production write blocked: WORKDIR=${WORKDIR} + --force on Project01."
                echo "[GUARD] export PRODUCTION_WRITE_ALLOWED=true to override (P2-DEV-01 discipline)."
                exit 60
                ;;
        esac
    fi
    SECONDS=0
    # flock 单实例锁（质量审核 CP3 计划联审 W4，approve #3）：锁键 = (WORKDIR, 脚本名,
    # 样本)。按质量审核要求精确到实例级——同脚本不同样本的合法并行不受影响，
    # 同 workdir+step+sample 的重复启动（事故档案 #2 家族）被拒。非阻塞获取
    # 失败即 exit 65；fd 生命周期与进程绑定，正常/异常退出均自动释放。
    if [ -n "${MGX_LOCK_DISABLE:-}" ] && [ "${MGX_LOCK_DISABLE}" = "1" ]; then
        :
    else
        _MGX_LOCK_DIR="${TMPDIR:-/tmp}/mgx_locks"
        mkdir -p "${_MGX_LOCK_DIR}" 2>/dev/null || true
        _MGX_LOCK_KEY="$(printf '%s|%s|%s' "${WORKDIR:-?}" "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}" "${SAMPLE:-${SAMPLE_NAME:-${SAMPLE_ID:-}}}" | md5sum | cut -d' ' -f1)"
        exec 9>>"${_MGX_LOCK_DIR}/${_MGX_LOCK_KEY}.lock"
        if ! flock -n 9; then
            echo "[GUARD] 同一 (workdir, step, sample) 已有实例在运行（flock 拒绝重复启动，事故档案 #2 家族）"
            echo "[GUARD] key=${_MGX_LOCK_KEY}; 确认无残留后可 MGX_LOCK_DISABLE=1 跳过（不推荐）"
            exit 65
        fi
    fi
    # ENG-6/run-monitor: opt-in per-step event emission (supervisor-approved, default OFF)
    if [ "${MGX_MONITOR:-0}" = "1" ]; then
        _MGX_STARTED_AT="$(date +%FT%T%z 2>/dev/null || printf '')"
        # Start event (exit_code=-1 running marker — negative can never be a
        # real $? (0-255), so genuine failures with exit 2 are not misread as
        # "running" (supervisor stage-3 P0-1); SECONDS=0 → duration_sec=0).
        # _MGX_ARGV was snapshotted at source time (caller's argv — inside this
        # function $* would be mgx_begin's own empty argument list); the trap
        # below re-snapshots it at EXIT fire-time scope (unchanged).
        _mgx_emit -1
        trap '_MGX_RC=$?; _MGX_ARGV="$*"; _mgx_emit "${_MGX_RC}"' EXIT
    fi
    # R-task decision B（P0-5）：30s /proc 进程树 RSS 采样器（Fig1-B/C + pilot 校准数据源）。
    # 开关 MGX_RSS_SAMPLE=1（opt-in，默认 OFF 保持既往行为字节级不变）；落盘
    # logs/rss/<script>/<sample|aggregate>.csv（timestamp,rss_kb,nthreads）。
    # 生命周期：分离式看护循环 kill -0 检测父进程死亡（≤30s 感知）+ 24h 保险丝，
    # 不注册任何 trap（规避 L164 "last trap wins" 覆盖风险）；自身输出全重定向，
    # 不持有 stdout/stderr 句柄。
    if [ "${MGX_RSS_SAMPLE:-0}" = "1" ] && [ -n "${WORKDIR:-}" ]; then
        local _rss_script _rss_sample _rss_csv _rss_root
        _rss_script="$(basename "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}" 2>/dev/null || echo unknown)"
        _rss_sample="${SAMPLE:-${SAMPLE_NAME:-${SAMPLE_ID:-aggregate}}}"
        _rss_root="$$"
        _rss_csv="${WORKDIR}/logs/rss/${_rss_script}/${_rss_sample}.csv"
        mkdir -p "$(dirname "${_rss_csv}")" 2>/dev/null || true
        (
            _csv="${_rss_csv}"
            _root="${_rss_root}"
            [ -f "$_csv" ] || echo "timestamp,rss_kb,nthreads" >> "$_csv"
            _n=0
            while kill -0 "$_root" 2>/dev/null && [ "$_n" -lt 2880 ]; do
                _line="$(ps -eo pid=,ppid=,rss=,nlwp= --no-headers 2>/dev/null | awk -v root="$_root" '
                    { rss[$1]=$3; nth[$1]=$4; pp[$1]=$2; ids[NR]=$1 }
                    END { for (i=1; i<=NR; i++) { p=ids[i]; q=p; d=0
                        while (q > 0) { if (q == root) { d=1; break } q=pp[q] }
                        if (d) { tr += rss[p]; tn += nth[p] } }
                        print tr+0 "," tn+0 }')"
                echo "$(date +%FT%T%z),$_line" >> "$_csv"
                _n=$((_n + 1))
                sleep 30
            done
        ) >/dev/null 2>&1 &
    fi
}

# 计时结束: 输出 [label] 耗时 ${SECONDS}s（label 可省略，默认 done）
mgx_end() {
    echo "[${1:-done}] 耗时 ${SECONDS}s"
}

# ENG-6/run-monitor: snapshot the sourcing script's argv ONCE at source time
# (inside mgx_begin, $* would be the function's own empty argument list), so
# the start event written by mgx_begin carries the raw argv like the end event
# does (the EXIT trap re-snapshots at fire-time scope, unchanged). Guarded by
# MGX_MONITOR so the OFF state stays untouched.
if [ "${MGX_MONITOR:-0}" = "1" ]; then
    _MGX_ARGV="$*"
fi

# ── 临时目录（scratch）管理：优先 NVMe，磁盘不足回退；EXIT 强制清理 ────
# 用法（注意：必须直接调用，禁止用 $(...) 包裹！命令替换会在子 shell 中执行，
#       trap 随子 shell 退出立即触发，目录会被当场删除）：
#   mgx_scratch_init megahit
#   MEGAHIT_TMP="${MGX_SCRATCH_DIR}"
#   - 基础目录 $MGX_SCRATCH_BASE（默认 /tmp/mgx_scratch，NVMe）
#   - 可用空间 < $MGX_SCRATCH_MIN_FREE_GB（默认 1500）→ 回退 $MGX_SCRATCH_FALLBACK
#   - **只创建父目录，返回尚不存在的最终目录**（MEGAHIT 要求 -o 不存在）
#   - 目录名含脚本 PID + RANDOM（并发安全，PID 可用于存活判定）
#   - 启动时清扫：同名族、mtime > $MGX_SCRATCH_MAX_AGE_MIN（默认 360 分钟）、
#     且目录名中的 PID 已不存在（避免误删运行中的任务）
#   - 链式 EXIT trap（保留 mgx_begin 的 monitor trap）：
#     set +e 保证 cleanup 后仍能 eval 旧 trap，退出码原样透传
mgx_scratch_init() {
    local purpose="${1:?mgx_scratch_init 需要 purpose}"
    local base="${MGX_SCRATCH_BASE:-/tmp/mgx_scratch}"
    local min_free_gb="${MGX_SCRATCH_MIN_FREE_GB:-1500}"
    local fallback="${MGX_SCRATCH_FALLBACK:-${WORKDIR:-.}/temp/scratch}"
    local max_age_min="${MGX_SCRATCH_MAX_AGE_MIN:-360}"
    local avail_gb dir probe pid

    # 陈旧清扫（base 与 fallback 都扫；跳过仍存活的 PID）
    for _b in "${base}" "${fallback}"; do
        [ -d "${_b}" ] || continue
        while IFS= read -r _d; do
            [ -d "${_d}" ] || continue
            pid="$(basename "${_d}" | awk -F_ '{print $(NF-1)}')"
            if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
                continue   # 进程仍在 → 不删
            fi
            rm -rf "${_d}" 2>/dev/null || true
        done < <(find "${_b}" -maxdepth 1 -type d -name "mgx_${purpose}_*" -mmin +"${max_age_min}" 2>/dev/null)
    done

    # 磁盘守卫（目标目录可能尚不存在 → 用最近已存在祖先）
    probe="${base}"
    while [ ! -d "${probe}" ] && [ "${probe}" != "/" ] && [ "${probe}" != "." ]; do
        probe="$(dirname "${probe}")"
    done
    avail_gb=$(df -BG --output=avail "${probe}" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -z "${avail_gb}" ] || [ "${avail_gb}" -lt "${min_free_gb}" ]; then
        base="${fallback}"
        probe="${base}"
        while [ ! -d "${probe}" ] && [ "${probe}" != "/" ] && [ "${probe}" != "." ]; do
            probe="$(dirname "${probe}")"
        done
        avail_gb=$(df -BG --output=avail "${probe}" 2>/dev/null | tail -1 | tr -dc '0-9')
        echo "[scratch] NVMe 空间不足(<${min_free_gb}G)或不可用，回退: ${base} (free ${avail_gb:-?}G)" >&2
    fi
    mkdir -p "${base}" || { echo "[scratch] ERROR 无法创建 ${base}" >&2; return 1; }

    # 只建父目录；最终目录留给工具自己创建（MEGAHIT -o 要求不存在）
    dir="${base}/mgx_${purpose}_${SAMPLE:-x}_${BASHPID}_${RANDOM}"
    MGX_SCRATCH_DIR="${dir}"
    export MGX_SCRATCH_DIR
    echo "[scratch] ${dir} (free ${avail_gb:-?}G)" >&2

    # 链式 EXIT trap（当前 shell，非子 shell）
    local _old
    _old="$(trap -p EXIT 2>/dev/null | sed -E "s/^trap -- '(.*)' EXIT$/\1/")"
    export _MGX_OLD_EXIT_TRAP="${_old}"
    # SC2154: _mgx_scratch_rc 在 trap 字符串内赋值（trap 作用域），静态检查不可见
    # shellcheck disable=SC2154
    trap '_mgx_scratch_rc=$?; set +e; mgx_scratch_cleanup; ( exit ${_mgx_scratch_rc} ); eval "${_MGX_OLD_EXIT_TRAP:-:}"; exit ${_mgx_scratch_rc}' EXIT
    # SIGTERM/SIGINT：显式以 143/130 退出，保证 EXIT trap 与 monitor 事件拿到真实信号码
    # （bash 默认被信号终止时 EXIT trap 内 $? 为 0，会把 monitor 记成 exit=0——质量审核第33轮 P1）
    trap 'exit 143' TERM
    trap 'exit 130' INT
    return 0
}

# 登记需随清理删除的临时文件（如跨盘发布的 *.tmp）；空格分隔
mgx_cleanup_register_file() {
    [ -n "${1:-}" ] && MGX_CLEANUP_FILES="${MGX_CLEANUP_FILES:-} $1"
    return 0
}

# 清理当前 scratch（幂等；只删路径含 /mgx_ 的目录，防误删）+ 登记的临时文件
mgx_scratch_cleanup() {
    case "${MGX_SCRATCH_DIR:-}" in
        */mgx_*) rm -rf "${MGX_SCRATCH_DIR}" 2>/dev/null || true ;;
    esac
    MGX_SCRATCH_DIR=""
    local _f
    for _f in ${MGX_CLEANUP_FILES:-}; do
        rm -f "${_f}" 2>/dev/null || true
    done
    MGX_CLEANUP_FILES=""
}

# ── 真菌阴性门槛（R-20261116-31，3b）────────────────────────────────
# 用法：if mgx_fungi_gate >/dev/null; then ... 阳性分支 ...; else ... 阴性分支 ...; fi
#   （禁止 GATE=$(mgx_fungi_gate) 裸赋值——阴性 return 1 会被 set -e 杀掉脚本）
#   stdout 输出 positive|negative；退出码：阳性 0 / 阴性 1 / rc 缺失 2
#   读 ${WORKDIR}/result/fungi/phf_profiler/${SAMPLE}/${SAMPLE}.rc
#   PHF rc 缺失/空 → [ERROR] exit 2（PHF 必须先跑，DAG 已加 phf_rc 依赖边）
#   阈值：任一 contig 丰度 > $MGX_FUNGI_MIN_ABUND（默认 0.05）→ positive
#   negative 时自动写 ${WORKDIR}/result/fungi/${SAMPLE}/fungi_negative.flag
#   （该 flag 是下游"空产物放行"的统一判定入口）
mgx_fungi_gate() {
    local rc="${WORKDIR}/result/fungi/phf_profiler/${SAMPLE}/${SAMPLE}.rc"
    if [ ! -s "${rc}" ]; then
        echo "[ERROR] PHF rc 缺失（PHF 必须先跑）: ${rc}" >&2
        return 2
    fi
    local pos
    pos=$(awk -v t="${MGX_FUNGI_MIN_ABUND:-0.05}" '$2+0 > t' "${rc}" | wc -l)
    local flag_dir="${WORKDIR}/result/fungi/${SAMPLE}"
    mkdir -p "${flag_dir}"
    if [ "${pos}" -eq 0 ]; then
        echo "fungi_negative" > "${flag_dir}/fungi_negative.flag"
        echo negative
        return 1
    fi
    rm -f "${flag_dir}/fungi_negative.flag" 2>/dev/null || true
    echo positive
    return 0
}

# conda 环境执行包装: mgx_conda <envname> <cmd...>
# 等价 conda run --prefix "${REPO}/envs/<envname>" --no-capture-output <cmd...>（REPO 取调用方变量）
mgx_conda() {
    if [ -z "${REPO:-}" ]; then
        echo "[ERROR] mgx_conda: REPO 未设置"
        exit 1
    fi
    # R-task：conda 自举（2026-11-20 10:03 事故实证）——续接会话/后台泳道的 PATH
    # 可能无 conda（7 任务同发 exit 127），此处就近初始化，落实 P0-2
    # 「调用点级环境隔离」哲学：不依赖任何会话层状态。
    if ! command -v conda >/dev/null 2>&1; then
        local _conda_sh="${REPO}/miniforge3/etc/profile.d/conda.sh"
        # R-task 遗留修正：${HOME}=/home/admin-user 无 miniforge，数据目录 /data/admin-user 才有
        [ -f "${_conda_sh}" ] || _conda_sh="/data/admin-user/miniforge3/etc/profile.d/conda.sh"
        if [ -f "${_conda_sh}" ]; then
            # shellcheck disable=SC1090  # 动态路径系设计使然（REPO 内置/家目录回退，均已实证存在）
            . "${_conda_sh}"
        else
            echo "[ERROR] mgx_conda: PATH 无 conda 且未定位到 conda.sh（候选: ${REPO}/miniforge3, ~/miniforge3）"
            exit 127
        fi
    fi
    # 质量审核终审 2026-10-15 P0-2：调用点级环境隔离（会话层 activate.sh 的策略对
    # nohup 泳道/续接会话无效；~/.local numpy 曾遮蔽环境内 numpy 致 53/70 二爆）
    PYTHONNOUSERSITE=1 conda run --prefix "${REPO}/envs/$1" --no-capture-output "${@:2}"
}

# --force 重跑前的产物备份钩子（质量审核终审 2026-10-15 P0-5）：把将被覆盖的目录
# 移入 temp/trash/<时间戳>/（调用方自行清理，建议保留 72h）。只护"唯一副本"
# 类高危步骤（W1 基线被 --force 覆盖丢失的教训）。
mgx_force_backup() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local trash
    trash="${WORKDIR:-.}/temp/trash/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$trash"
    mv "$dir" "$trash/$(basename "$dir")" && echo "[mgx] 已备份 ${dir} -> ${trash}/"
    return 0
}

# errexit 屏蔽执行: 运行命令并返回其退出码，不终止当前 shell（set +e; cmd; set -e 的函数化）
mgx_try() {
    local rc=0 errexit=0
    if [[ $- == *e* ]]; then errexit=1; fi
    set +e
    "$@"
    rc=$?
    if [ "${errexit}" -eq 1 ]; then set -e; fi
    return "${rc}"
}

# samplesheet 校验 (T-14): 列数 / 样本 ID 格式 / 唯一性 / R1+R2 存在性。
# 用法: mgx_validate_samplesheet <csv>  — 失败时打印带行号的错误并 exit 1。
# 约定列: sample_id,R1,R2,host_type[,workdir]（与 00_pipeline_*.sh 的 IFS 解析一致）。
mgx_validate_samplesheet() {
    local csv="$1" line_no=1
    if [ ! -f "${csv}" ]; then
        echo "[ERROR] samplesheet 不存在: ${csv}"; exit 1
    fi
    local -a ids=()
    local line id r1 r2
    # Header row is skipped (line 1), matching the pipelines' tail -n+2 read.
    while IFS= read -r line; do
        line_no=$((line_no + 1))
        case "${line}" in ''|\#*) continue ;; esac
        IFS=',' read -r id r1 r2 _ <<< "${line}"
        id=$(echo "${id}" | tr -d ' "')
        r1=$(echo "${r1}" | tr -d ' "')
        r2=$(echo "${r2}" | tr -d ' "')
        if [ -z "${id}" ] || ! echo "${id}" | grep -qE '^[A-Za-z0-9_.-]+$'; then
            echo "[ERROR] samplesheet 第 ${line_no} 行: 非法样本 ID '${id}'（仅允许字母/数字/点/下划线/连字符）"; exit 1
        fi
        for seen in "${ids[@]:-}"; do
            if [ "${seen}" = "${id}" ]; then
                echo "[ERROR] samplesheet 第 ${line_no} 行: 样本 ID 重复 '${id}'"; exit 1
            fi
        done
        ids+=("${id}")
        if [ ! -f "${r1}" ]; then
            echo "[ERROR] samplesheet 第 ${line_no} 行 (${id}): R1 不存在: ${r1}"; exit 1
        fi
        if [ ! -f "${r2}" ]; then
            echo "[ERROR] samplesheet 第 ${line_no} 行 (${id}): R2 不存在: ${r2}"; exit 1
        fi
    done < <(tail -n+2 "${csv}")
    echo "[pipeline] samplesheet 校验通过: ${#ids[@]} 样本"
}
