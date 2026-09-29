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

    echo "[CSCCD-MetagenomeFlow] 环境已激活  PROJ_DIR=${PROJ_DIR}"
