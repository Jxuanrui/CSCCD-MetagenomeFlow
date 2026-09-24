#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 38b_bac_gunc.sh
# 功  能: MAG 质量二次评估 —— GUNC 嵌合/污染检测（CheckM2 的互补层）
#         基于谱系同质性（lineage homogeneity）识别跨谱系嵌合 bin，检出
#         CheckM2 单一完整度/污染度指标易漏的 mis-binning；输出 per-MAG
#         GUNC 分数与可选的 taxlevel 明细。
#         工具版本：GUNC 1.0.3（conda env: gunc, DB: progenomes2.1）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
# 输  出: ${WORKDIR}/result/binning/gunc/
#           GUNC.progenomes_2.1.maxCSS_level.tsv — per-MAG 主结果（含 pass/fail）
#           GUNC.*.tsv                            — 其它 taxlevel / 明细表
#
# ── 定位说明 ──────────────────────────────────────────────────────────────────
#
#   与 CheckM2(37) 互补，不替代：CheckM2 报完整度/污染度（基于单拷贝标记基因），
#   GUNC 报跨谱系嵌合（基于参考库谱系一致性）。二者联合是当前 MAG QC 的标准做法
#   （CheckM2 + GUNC）。本脚本对去冗余后的最终 MAG 集做二次质检，默认不入
#   rule all（按需请求输出触发）。
#
# ── 数据库说明 ────────────────────────────────────────────────────────────────
#
#   GUNC progenomes2.1 DiamondDB（约 10GB）：
#     ${REPO}/db/gunc/gunc_db_progenomes2.1.dmnd
#   获取：envs/gunc/bin/gunc download_db db/gunc -db progenomes
#         （解压 .gz 后得到 .dmnd）
#
# 参  考: Orakov et al. 2021 Genome Biology (GUNC)
#         https://github.com/grp-bork/gunc
# 用  法: bash 38b_bac_gunc.sh -t CPUS -w WORKDIR -r REPO [--force] [--sensitive]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 38b_bac_gunc.sh -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --sensitive  高灵敏模式（更严格，更多嵌合被标记）
  --force      强制重新运行
  -h           显示帮助
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
# （--sensitive 布尔长选项 → SENSITIVE=0/1，透传给 gunc 时用 ${SENSITIVE:+--sensitive}）
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force sensitive"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin

MAG_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUT_DIR="${WORKDIR}/result/binning/gunc"
TEMP_DIR="${WORKDIR}/temp/gunc"
GUNC_ENV="${REPO}/envs/gunc"
GUNC_BIN="${GUNC_ENV}/bin/gunc"
GUNC_DB="${REPO}/db/gunc/gunc_db_progenomes2.1.dmnd"

if [ ! -d "${MAG_DIR}" ] || [ -z "$(ls -A "${MAG_DIR}"/*.fa 2>/dev/null)" ]; then
    echo "[ERROR] 输入 MAG 目录为空或不存在: ${MAG_DIR}"
    echo "        请先运行 38_bac_drep.sh"
    exit 1
fi

if [ ! -x "${GUNC_BIN}" ]; then
    echo "[ERROR] GUNC 未安装: ${GUNC_BIN}"
    echo "        安装: conda create -y -p ${GUNC_ENV} -c bioconda -c conda-forge gunc"
    exit 1
fi

if [ ! -f "${GUNC_DB}" ]; then
    echo "[ERROR] GUNC 数据库未找到: ${GUNC_DB}"
    echo "        获取: envs/gunc/bin/gunc download_db db/gunc -db progenomes 然后 gunzip"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && ls "${OUT_DIR}"/GUNC.*.tsv >/dev/null 2>&1; then
    echo "[INFO] GUNC 输出已存在，跳过（--force 可强制重跑）: ${OUT_DIR}"
    exit 0
fi

mkdir -p "${OUT_DIR}" "${TEMP_DIR}"

echo "[gunc] MAG 输入目录: ${MAG_DIR} ($(find "${MAG_DIR}" -maxdepth 1 -name '*.fa' 2>/dev/null | wc -l) 个 MAG)"
echo "[gunc] 数据库: ${GUNC_DB}"
echo "[gunc] 线程: ${CPUS} | 模式: $([ "${SENSITIVE}" -eq 1 ] && echo sensitive || echo default)"

GUNC_TIMEOUT="${GUNC_TIMEOUT:-21600}"
# timeout 外层守卫（diamond 子进程挂起防护）使本调用无法走 mgx_conda 包装，保留原 conda run 形式
EXIT_CODE=0
mgx_try timeout --signal=TERM --kill-after=60 "${GUNC_TIMEOUT}" \
    conda run --prefix "${GUNC_ENV}" --no-capture-output \
    gunc run \
        -d "${MAG_DIR}" \
        -e .fa \
        -r "${GUNC_DB}" \
        -t "${CPUS}" \
        -o "${OUT_DIR}" \
        --temp_dir "${TEMP_DIR}" \
        --detailed_output \
        ${SENSITIVE:+--sensitive} || EXIT_CODE=$?

if [ "${EXIT_CODE}" -eq 124 ]; then
    echo "[ERROR] gunc run 超时（${GUNC_TIMEOUT}s）。已知失败模式：diamond 子进程意外退出后 gunc 永久空转（无报错、无输出）。"
    echo "        清理 ${TEMP_DIR} 与 ${OUT_DIR} 后以 --force 重跑。"
    exit 124
fi
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] gunc run 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

MAIN_TSV="$(find "${OUT_DIR}" -maxdepth 1 -name 'GUNC.*.tsv' 2>/dev/null | head -1)"
if [ -z "${MAIN_TSV}" ]; then
    echo "[ERROR] 未生成 GUNC 结果表: ${OUT_DIR}"
    exit 1
fi

PASS_N=$(awk -F'\t' 'NR>1 && $NF=="True"' "${MAIN_TSV}" 2>/dev/null | wc -l)
FAIL_N=$(awk -F'\t' 'NR>1 && $NF=="False"' "${MAIN_TSV}" 2>/dev/null | wc -l)
echo ""
echo "[gunc] 结果表: ${MAIN_TSV}"
echo "[gunc] pass/fail: ${PASS_N}/${FAIL_N}"
mgx_end "gunc"
