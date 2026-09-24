#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74a_fun_gut_db_build.sh
# 功  能: 构建肠道真菌数据库 Bowtie2 索引（一次性构建，Yan et al. 2024 Cell 187）
#
# 数据库来源: db/gut_fungi_db/ (760 真菌基因组基因集 + 过滤库，Yan et al. 2024 Cell 187)
# 输  入:
#   ${REPO}/db/gut_fungi_db/db.fungi.fa.gz        — 真菌基因集（核酸，760基因组）
#   ${REPO}/db/gut_fungi_db/db.uhgg.fa.gz         — 细菌过滤库（UHGG）
#   ${REPO}/db/gut_fungi_db/db.fungi_target.fa.gz — rRNA 过滤库
#   ${REPO}/db/gut_fungi_db/db.human_chm13v2.fa.gz — 人类宿主过滤库
# 输  出:
#   ${REPO}/db/gut_fungi_db/bwt.index.gut_fungi_geneset.*
#   ${REPO}/db/gut_fungi_db/bwt.index.uhgg.*
#   ${REPO}/db/gut_fungi_db/bwt.index.fungi_target.*
#   ${REPO}/db/gut_fungi_db/bwt.index.human_chm13v2.*
# 用  法: bash 74a_fun_gut_db_build.sh -t CPUS -r REPO
#   注: -t/-r 必需（原静默默认值已移除，防止误触发了小时级索引构建）
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 74a_fun_gut_db_build.sh -t CPUS -r REPO

必需参数:
  -t  线程数
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash 74a_fun_gut_db_build.sh -t 16 -r ~/Course/CSCCD-MetagenomeFlow

WARNING:
  Each index can take 30-120 min depending on database size. Run in screen/tmux.
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS REPO

if ! [[ "${CPUS}" =~ ^[1-9][0-9]*$ ]]; then echo "[ERROR] -t 必须是正整数: ${CPUS}"; exit 1; fi
if [ ! -d "${REPO}" ]; then echo "[ERROR] REPO 不存在: ${REPO}"; exit 1; fi
REPO="$(cd "${REPO}" && pwd)"

SRC_DIR="${REPO}/db/gut_fungi_db"
IDX_DIR="${REPO}/db/gut_fungi_db"
LOG_DIR="${REPO}/logs/gut_fungi_db_build"

if [ ! -d "${SRC_DIR}" ]; then echo "[ERROR] db/gut_fungi_db 不存在: ${SRC_DIR}"; exit 1; fi
mkdir -p "${IDX_DIR}" "${LOG_DIR}"

mgx_begin

declare -A DB_MAP=(
    ["db.fungi.fa.gz"]="bwt.index.gut_fungi_geneset"
    ["db.uhgg.fa.gz"]="bwt.index.uhgg"
    ["db.fungi_target.fa.gz"]="bwt.index.fungi_target"
    ["db.human_chm13v2.fa.gz"]="bwt.index.human_chm13v2"
)

# Build order matters: fungi first (largest, used in step1 and step5)
BUILD_ORDER=("db.fungi.fa.gz" "db.uhgg.fa.gz" "db.fungi_target.fa.gz" "db.human_chm13v2.fa.gz")

for db_file in "${BUILD_ORDER[@]}"; do
    idx_name="${DB_MAP[$db_file]}"
    src="${SRC_DIR}/${db_file}"
    idx="${IDX_DIR}/${idx_name}"
    sentinel_bt2="${idx}.1.bt2"
    sentinel_bt2l="${idx}.1.bt2l"

    if [ ! -f "${src}" ]; then
        echo "[ERROR] 数据库文件不存在: ${src}"
        exit 1
    fi

    if [ ${FORCE} -eq 0 ] && { [ -f "${sentinel_bt2}" ] && [ -s "${sentinel_bt2}" ]; } || { [ -f "${sentinel_bt2l}" ] && [ -s "${sentinel_bt2l}" ]; }; then
        echo "[INFO] 索引已存在，跳过: ${idx_name}"
        continue
    fi

    echo "[gut_db_build] 构建索引: ${idx_name} ..."
    mgx_conda assembly \
        bowtie2-build --threads "${CPUS}" \
            "${src}" "${idx}" \
        2>&1 | tee "${LOG_DIR}/${idx_name}.log"

    if { [ ! -f "${sentinel_bt2}" ] || [ ! -s "${sentinel_bt2}" ]; } && { [ ! -f "${sentinel_bt2l}" ] || [ ! -s "${sentinel_bt2l}" ]; }; then
        echo "[ERROR] 索引构建失败: ${idx_name}"
        exit 1
    fi
    echo "[INFO] 索引完成: ${idx_name}"
done

echo "[gut_db_build] 全部索引构建完成"
echo "[gut_db_build] 索引目录: ${IDX_DIR}/"
mgx_end "gut_db_build"
