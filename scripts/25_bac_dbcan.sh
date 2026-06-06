#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 25_bac_dbcan.sh
# 功  能: 碳水化合物活性酶（CAZyme）注释（dbCAN3）
#         工具版本：run_dbcan 4.x（conda env: dbcan）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/annotation/dbcan/
#           overview.txt  — 三工具投票综合结果（HMMER/DIAMOND/eCAMI）
#           hmmer.out     — HMMER HMM 搜索结果
#           diamond.out   — DIAMOND 比对结果
#
# ── 关键参数 ──────────────────────────────────────────────────────────────────
#   --tools all          — 同时运行 HMMER + DIAMOND + eCAMI 三种方法
#   --db_dir             — CAZy 数据库目录
#
# 参  考: Zheng et al. 2023 NAR (dbCAN3); Yin et al. 2012 NAR (原始)
# 用  法: bash 25_bac_dbcan.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 25_bac_dbcan.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""
WORKDIR=""
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/dbcan"
DBCAN_DB="${REPO}/db/dbcan"
SENTINEL="${RESULT_DIR}/overview.txt"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"; exit 1
fi

if [ ! -d "${DBCAN_DB}" ]; then
    echo "[ERROR] dbCAN 数据库目录不存在: ${DBCAN_DB}"; exit 1
fi

if [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] dbCAN 结果已存在，跳过: ${SENTINEL}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[dbcan] 开始 CAZyme 注释 | 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/dbcan" --no-capture-output \
    run_dbcan \
        "${PROTEIN_NR}" \
        protein \
        --tools all \
        --db_dir "${DBCAN_DB}" \
        --out_dir "${RESULT_DIR}" \
        --cpu "${CPUS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] run_dbcan 失败（exit code: ${EXIT_CODE}）"; exit ${EXIT_CODE}
fi

N_CAZYMES=$(awk 'NR>1' "${SENTINEL}" 2>/dev/null | wc -l || echo "N/A")
echo "[dbcan] 完成，耗时 ${SECONDS}s | CAZyme 注释: ${N_CAZYMES} 条 | 输出: ${RESULT_DIR}/"
