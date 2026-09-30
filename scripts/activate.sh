#!/usr/bin/env bash
# ==============================================================================
# CSCCD-MetagenomeFlow 会话激活脚本
# 用法：source <项目路径>/scripts/activate.sh
# 说明：每次分析前执行，激活项目内的 conda 环境，设置所有路径变量
# ==============================================================================

    # 获取本脚本所在目录的上级（即项目根目录）
    PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # 激活项目内的 Miniforge3
    source ${PROJ_DIR}/miniforge3/etc/profile.d/conda.sh

    # 导出所有路径变量
    export PROJ_DIR
    export soft=${PROJ_DIR}/miniforge3
    export envs=${PROJ_DIR}/envs
    export db=${PROJ_DIR}/db
    export tools=${PROJ_DIR}/tools

    # 将项目工具目录加入 PATH
    export PATH=${PROJ_DIR}/miniforge3/bin:${PROJ_DIR}/tools:${PATH}

    # 数据库路径环境变量（迁移后自动适配）
    export CHECKM2DB="${PROJ_DIR}/db/checkm2/CheckM2_database/uniref100.KO.1.dmnd"
    export GTDBTK_DATA_PATH="${PROJ_DIR}/db/gtdbtk"

    # R 包库路径（项目内 Rlib，不依赖系统写权限）
    export R_LIBS_USER="${PROJ_DIR}/Rlib"

    # 优先使用项目内 conda R（与 Bioconductor 包版本一致）
    export PATH="${PROJ_DIR}/miniforge3/bin:${PATH}"

    # pre-commit 门禁自愈安装（.git/hooks 不进 git，clone/换机后自动补装；幂等）
    # -f 而非 -x：tarball/权限丢失场景下仍可经 bash 调用，避免静默跳过（监工 P1-1）
    if [ -d "${PROJ_DIR}/.git" ] && [ ! -e "${PROJ_DIR}/.git/hooks/pre-commit" ]; then
        if [ -f "${PROJ_DIR}/scripts/install_git_hooks.sh" ]; then
            bash "${PROJ_DIR}/scripts/install_git_hooks.sh" >/dev/null 2>&1 \
                || echo "[WARN] pre-commit hook 自愈安装失败，请手动执行: bash ${PROJ_DIR}/scripts/install_git_hooks.sh" >&2
        else
            echo "[WARN] ${PROJ_DIR}/scripts/install_git_hooks.sh 不存在，pre-commit 门禁未安装" >&2
        fi
    fi

    # 隔离用户目录 Python 包（2026-09-29 监工建议+用户批准）：各 env 只用自身
    # site-packages，杜绝 ~/.local 串包（曾致 pip 清单虚高 89 个幻影包）。
    # 已在 Test_CI_fixture 验证：L1/L3 全绿、L2 6/6 绿（test_28 antismash 缺陷
    # T-22 已于 2026-09-30 修复，全量 CI 三层 8/8 PASS）。
    export PYTHONNOUSERSITE=1

    echo "[CSCCD-MetagenomeFlow] 环境已激活  PROJ_DIR=${PROJ_DIR}"
