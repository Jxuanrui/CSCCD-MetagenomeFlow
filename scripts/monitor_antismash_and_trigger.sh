#!/usr/bin/env bash
# ==============================================================================
# 脚本名: monitor_antismash_and_trigger.sh
# 功  能: 监控 antiSMASH 进度，完成后自动启动新增注释脚本
# 运行方式: 后台持续监控，每 5 分钟检查一次
# 用  法: bash monitor_antismash_and_trigger.sh -w WORKDIR [-r REPO]
# ==============================================================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=""

show_help() {
cat << EOF
用法: bash monitor_antismash_and_trigger.sh -w WORKDIR [-r REPO]

必需参数:
  -w  工作目录（项目目录，如 Project/Project01）

可选参数:
  -r  CSCCD-MetagenomeFlow 项目根目录（默认自动检测: ${REPO}）
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ]; then
    echo "[ERROR] 缺少必需参数 -w"; show_help; exit 1
fi
RUSH_LOG="${WORKDIR}/temp/logs/antismash/rush_batch.log"
TRIGGER_SCRIPT="${REPO}/scripts/auto_start_new_annotations.sh"
SENTINEL="${WORKDIR}/temp/logs/antismash/.auto_triggered"

# 检查 antiSMASH 完成状态
check_antismash() {
    if [ ! -f "${RUSH_LOG}" ]; then
        echo "[monitor] rush_batch.log 不存在，等待..."
        return 1
    fi

    local completed
    completed=$(grep -c "antismash done" "${RUSH_LOG}" 2>/dev/null)
    local total=10

    echo "[monitor] antiSMASH 进度: ${completed}/${total}"

    if [ ${completed} -ge ${total} ]; then
        return 0
    else
        return 1
    fi
}

# 检查是否已触发
if [ -f "${SENTINEL}" ]; then
    echo "[monitor] 自动化脚本已触发过，退出监控"
    exit 0
fi

echo "[monitor] 开始监控 antiSMASH 进度..."
echo "[monitor] 检查间隔: 5 分钟"
echo "[monitor] 日志: ${RUSH_LOG}"

while true; do
    if check_antismash; then
        echo "[monitor] ✓ antiSMASH 全部完成！"
        echo "[monitor] 创建 sentinel 文件..."
        touch "${SENTINEL}"

        echo "[monitor] 启动自动化注释流程..."
        mkdir -p "${WORKDIR}/temp/logs/auto_annotations"
        nohup bash "${TRIGGER_SCRIPT}" -w "${WORKDIR}" -r "${REPO}" \
          > "${WORKDIR}/temp/logs/auto_annotations/main.log" 2>&1 &

        TRIGGER_PID=$!
        echo "[monitor] 自动化脚本已启动 (PID: ${TRIGGER_PID})"
        echo "[monitor] 日志: ${WORKDIR}/temp/logs/auto_annotations/main.log"

        # 更新 Tutorial.md（标记 antiSMASH 完成）
        echo "[monitor] 更新 Tutorial.md 进度..."
        # 这里可以调用 CC 更新 Tutorial.md，暂时仅记录

        echo "[monitor] 监控任务完成，退出"
        exit 0
    fi

    echo "[monitor] 等待中，下次检查: $(date -d '+5 minutes' '+%H:%M:%S')"
    sleep 300  # 5 分钟
done
