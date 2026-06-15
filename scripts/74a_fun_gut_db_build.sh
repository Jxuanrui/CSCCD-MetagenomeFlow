#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74a_fun_gut_db_build.sh
# 功  能: 构建肠道真菌数据库 Bowtie2 索引（一次性构建，Yan et al. 2024 Cell 187）
#
# 数据库来源: Gut_Fungi_DB/ (760 真菌基因组基因集 + 过滤库)
# 输  入:
#   ${REPO}/Gut_Fungi_DB/db.fungi.fa.gz        — 真菌基因集（核酸，760基因组）
#   ${REPO}/Gut_Fungi_DB/db.uhgg.fa.gz         — 细菌过滤库（UHGG）
#   ${REPO}/Gut_Fungi_DB/db.fungi_target.fa.gz — rRNA 过滤库
#   ${REPO}/Gut_Fungi_DB/db.human_chm13v2.fa.gz — 人类宿主过滤库
# 输  出:
#   ${REPO}/db/gut_fungi_db/bwt.index.gut_fungi_geneset.*
#   ${REPO}/db/gut_fungi_db/bwt.index.uhgg.*
#   ${REPO}/db/gut_fungi_db/bwt.index.fungi_target.*
#   ${REPO}/db/gut_fungi_db/bwt.index.human_chm13v2.*
# 用  法: bash 74a_fun_gut_db_build.sh -t CPUS -r REPO
#   注: -r 默认使用脚本所在目录的父目录
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 74a_fun_gut_db_build.sh -t CPUS -r REPO

参数:
  -t  线程数（默认: 1）
  -r  MaxMetagenome 项目根目录（默认: 脚本所在目录的父目录）

示例:
  bash 74a_fun_gut_db_build.sh -t 16 -r ~/Course/Maxmetagenome

WARNING:
  Each index can take 30-120 min depending on database size. Run in screen/tmux.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
CPUS="1"
REPO="${DEFAULT_REPO}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if ! [[ "${CPUS}" =~ ^[1-9][0-9]*$ ]]; then echo "[ERROR] -t 必须是正整数: ${CPUS}"; exit 1; fi
if [ ! -d "${REPO}" ]; then echo "[ERROR] REPO 不存在: ${REPO}"; exit 1; fi
REPO="$(cd "${REPO}" && pwd)"

SRC_DIR="${REPO}/Gut_Fungi_DB"
IDX_DIR="${REPO}/db/gut_fungi_db"
LOG_DIR="${REPO}/logs/gut_fungi_db_build"

if [ ! -d "${SRC_DIR}" ]; then echo "[ERROR] Gut_Fungi_DB 不存在: ${SRC_DIR}"; exit 1; fi
mkdir -p "${IDX_DIR}" "${LOG_DIR}"

SECONDS=0

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

    if { [ -f "${sentinel_bt2}" ] && [ -s "${sentinel_bt2}" ]; } || { [ -f "${sentinel_bt2l}" ] && [ -s "${sentinel_bt2l}" ]; }; then
        echo "[INFO] 索引已存在，跳过: ${idx_name}"
        continue
    fi

    echo "[gut_db_build] 构建索引: ${idx_name} ..."
    conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        bowtie2-build --threads "${CPUS}" \
            "${src}" "${idx}" \
        2>&1 | tee "${LOG_DIR}/${idx_name}.log"

    if { [ ! -f "${sentinel_bt2}" ] || [ ! -s "${sentinel_bt2}" ]; } && { [ ! -f "${sentinel_bt2l}" ] || [ ! -s "${sentinel_bt2l}" ]; }; then
        echo "[ERROR] 索引构建失败: ${idx_name}"
        exit 1
    fi
    echo "[INFO] 索引完成: ${idx_name}"
done

echo "[gut_db_build] 全部索引构建完成，耗时 ${SECONDS}s"
echo "[gut_db_build] 索引目录: ${IDX_DIR}/"
