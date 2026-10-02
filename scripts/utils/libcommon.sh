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
# enables). mgx_begin registers an EXIT trap that appends one JSON line per
# script run to ${WORKDIR}/logs/run_events.jsonl; field names align with
# scripts/write_provenance.py (ts[end time]/started_at/step_id/sample_id/
# params/exit_code/duration_sec/workdir; supervisor rectification P0-1a).
# Hard constraints (supervisor-approved):
#   - Default OFF: with MGX_MONITOR != 1 the observable behavior of every
#     sourcing script is byte-identical (no output, no files, same exit codes).
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
        _rc="$(printf '%s' "${1:-0}" | tr -cd '0-9' 2>/dev/null || true)"
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

# 计时开始
mgx_begin() {
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
    # ENG-6/run-monitor: opt-in per-step event emission (supervisor-approved, default OFF)
    if [ "${MGX_MONITOR:-0}" = "1" ]; then
        _MGX_STARTED_AT="$(date +%FT%T%z 2>/dev/null || printf '')"
        trap '_MGX_RC=$?; _MGX_ARGV="$*"; _mgx_emit "${_MGX_RC}"' EXIT
    fi
}

# 计时结束: 输出 [label] 耗时 ${SECONDS}s（label 可省略，默认 done）
mgx_end() {
    echo "[${1:-done}] 耗时 ${SECONDS}s"
}

# conda 环境执行包装: mgx_conda <envname> <cmd...>
# 等价 conda run --prefix "${REPO}/envs/<envname>" --no-capture-output <cmd...>（REPO 取调用方变量）
mgx_conda() {
    if [ -z "${REPO:-}" ]; then
        echo "[ERROR] mgx_conda: REPO 未设置"
        exit 1
    fi
    conda run --prefix "${REPO}/envs/$1" --no-capture-output "${@:2}"
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
