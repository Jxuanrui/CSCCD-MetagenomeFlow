#!/usr/bin/env bash
# CheckM 数据库路径配置 — 由 0Install.sh 生成
# 每次迁移到新服务器后执行一次，将项目内数据库路径写入 ~/.checkm/DATA_CONFIG
set -euo pipefail
PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p ~/.checkm
echo "dataRoot: ${PROJ_DIR}/db/checkm" > ~/.checkm/DATA_CONFIG
echo "manifestType: CheckM" >> ~/.checkm/DATA_CONFIG
echo "CheckM 数据库路径已配置: ${PROJ_DIR}/db/checkm"
