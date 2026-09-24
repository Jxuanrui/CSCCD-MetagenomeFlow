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

# 计时开始
mgx_begin() {
    SECONDS=0
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
