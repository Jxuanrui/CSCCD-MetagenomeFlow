#!/usr/bin/env bash
# ==============================================================================
# 脚本名: check_project_cleanliness.sh
# 功  能: 检查项目路径整洁性，识别意外的文件/目录
# 用  法: bash scripts/check_project_cleanliness.sh
# ==============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=============================================================================="
echo "CSCCD-MetagenomeFlow 项目路径整洁性检查"
echo "=============================================================================="
echo ""

ISSUES=0

# 1. 检查项目根目录下的异常文件
echo "[1] 检查项目根目录异常文件..."

# 不应出现在根目录的文件类型
UNWANTED_FILES=(
    "*.log"
    "*.tmp"
    "*.temp"
    "*.cache"
    "*.bak"
    "*.old"
)

for pattern in "${UNWANTED_FILES[@]}"; do
    files=$(ls "${REPO}/"${pattern} 2>/dev/null || true)
    if [ -n "${files}" ]; then
        echo "  ⚠️  发现根目录异常文件: ${pattern}"
        echo "      ${files}"
        ISSUES=$((ISSUES+1))
    fi
done

# 2. 检查异常的数据库目录
echo ""
echo "[2] 检查异常数据库目录（应在 db/ 下）..."

UNWANTED_DIRS=(
    "phylophlan_databases"
    "*_database"
    "*_databases"
)

for pattern in "${UNWANTED_DIRS[@]}"; do
    dirs=$(find "${REPO}" -maxdepth 1 -type d -name "${pattern}" 2>/dev/null)
    if [ -n "${dirs}" ]; then
        echo "  ⚠️  发现异常数据库目录: ${pattern}"
        echo "      ${dirs}"
        ISSUES=$((ISSUES+1))
    fi
done

# 3. 检查 Project/ 下的测试数据目录
echo ""
echo "[3] 检查 Project/ 下的测试数据目录..."

test_data_dirs=$(find "${REPO}/Project" -type d -name "test_data" 2>/dev/null)
if [ -n "${test_data_dirs}" ]; then
    echo "  ⚠️  发现测试数据目录（应清理）:"
    echo "${test_data_dirs}"
    ISSUES=$((ISSUES+1))
fi

# 4. 检查日志文件位置（应在 logs/ 或 Project/*/logs/ 下）
echo ""
echo "[4] 检查日志文件位置..."

misplaced_logs=$(find "${REPO}/Project" -maxdepth 2 -name "*.log" -type f 2>/dev/null | grep -v "/logs/" || true)
if [ -n "${misplaced_logs}" ]; then
    echo "  ⚠️  发现位置错误的日志文件（应在 logs/ 下）:"
    echo "${misplaced_logs}"
    ISSUES=$((ISSUES+1))
fi

# 5. 检查 temp/ 目录大小（超过 10GB 提示清理）
echo ""
echo "[5] 检查临时目录大小..."

for project_dir in "${REPO}/Project"/*; do
    [ ! -d "${project_dir}" ] && continue
    temp_dir="${project_dir}/temp"
    if [ -d "${temp_dir}" ]; then
        size=$(du -sm "${temp_dir}" 2>/dev/null | cut -f1)
        if [ "${size}" -gt 10240 ]; then  # 10GB = 10240 MB
            echo "  ⚠️  临时目录过大: ${temp_dir} (${size} MB)"
            echo "      考虑清理: rm -rf ${temp_dir}/*"
            ISSUES=$((ISSUES+1))
        fi
    fi
done

# 6. 检查 result/ 下的空目录（可能是失败任务残留）
echo ""
echo "[6] 检查空结果目录..."

empty_result_dirs=$(find "${REPO}/Project/*/result" -type d -empty 2>/dev/null | head -10)
if [ -n "${empty_result_dirs}" ]; then
    echo "  ℹ️  发现空结果目录（可能是失败任务）:"
    echo "${empty_result_dirs}"
fi

# 7. 统计项目总大小（按目录分类）
echo ""
echo "[7] 项目磁盘使用统计..."

echo "  db/        : $(du -sh ${REPO}/db 2>/dev/null | cut -f1 || echo NA)"
echo "  envs/      : $(du -sh ${REPO}/envs 2>/dev/null | cut -f1 || echo NA)"
echo "  Project/   : $(du -sh ${REPO}/Project 2>/dev/null | cut -f1 || echo NA)"
echo "  scripts/   : $(du -sh ${REPO}/scripts 2>/dev/null | cut -f1 || echo NA)"
echo "  pipeline/  : $(du -sh ${REPO}/pipeline 2>/dev/null | cut -f1 || echo NA)"

# 汇总
echo ""
echo "=============================================================================="
if [ ${ISSUES} -eq 0 ]; then
    echo "✓ 项目路径整洁，未发现异常"
else
    echo "⚠️  发现 ${ISSUES} 个问题，请检查上述输出"
fi
echo "=============================================================================="

exit ${ISSUES}
