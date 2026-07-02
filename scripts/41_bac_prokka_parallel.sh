#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 41_bac_prokka_parallel.sh
# 功  能: MAG 全基因组注释（Prokka 并行版本，使用 rush）
# 依  赖: 41_bac_prokka.sh（单 MAG 注释）
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
# 输  出: ${WORKDIR}/result/binning/prokka/{mag_name}/
#
# ── 并行策略 ──────────────────────────────────────────────────────────────────
#   使用 rush 并行调用 41_bac_prokka.sh -m {mag_name}
#   每个 Prokka 进程使用 -t 指定线程数
#   并发数 = 总核数 / 每个 Prokka 线程数
#
# 用  法: bash 41_bac_prokka_parallel.sh -t CPUS -w WORKDIR -r REPO [-j JOBS]
# ==============================================================================

show_help() { cat << EOF
用法: bash 41_bac_prokka_parallel.sh -t CPUS -w WORKDIR -r REPO [-j JOBS]
必需参数:
  -t  每个 Prokka 进程使用的线程数（默认 8）
  -w  工作目录
  -r  MaxMetagenome 项目根目录
可选参数:
  -j  并发任务数（默认自动计算：48核 / 8线程 = 6）
EOF
}

CPUS=8; WORKDIR=""; REPO=""; JOBS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -j) JOBS="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/binning/prokka"
LOGDIR="${WORKDIR}/temp/logs/prokka_parallel"

# 自动计算并发数
if [ -z "${JOBS}" ]; then
    TOTAL_CORES=$(nproc)
    JOBS=$((TOTAL_CORES / CPUS))
    if [ ${JOBS} -lt 1 ]; then JOBS=1; fi
    echo "[prokka_parallel] 自动计算并发数: ${TOTAL_CORES} 核 / ${CPUS} 线程 = ${JOBS} 并发"
fi

# 检查输入
if [ ! -d "${MAGS_DIR}" ]; then
    echo "[ERROR] dRep MAG 目录不存在: ${MAGS_DIR}"
    exit 1
fi

# 收集 MAG 列表
mapfile -t MAGS < <(find "${MAGS_DIR}" -maxdepth 1 -name "*.fa" -type f -exec basename {} .fa \; | sort)
if [ ${#MAGS[@]} -eq 0 ]; then
    echo "[ERROR] ${MAGS_DIR} 下未找到 *.fa MAGs"
    exit 1
fi

echo "[prokka_parallel] 找到 ${#MAGS[@]} 个 MAG"
echo "[prokka_parallel] 并行配置: ${JOBS} 并发 × ${CPUS} 线程"

mkdir -p "${LOGDIR}"
LOG="${LOGDIR}/rush_batch.log"

# 使用 rush 并行执行
printf "%s\n" "${MAGS[@]}" | \
  ${REPO}/miniforge3/bin/rush -j ${JOBS} -k \
  "bash ${REPO}/scripts/41_bac_prokka.sh \
     -m {} -t ${CPUS} \
     -w ${WORKDIR} -r ${REPO} \
     > ${LOGDIR}/{}.log 2>&1 && echo '[{}] prokka done'" \
  2>&1 | tee "${LOG}"

ELAPSED=$((SECONDS))

# 统计完成数
COMPLETED=$(grep "prokka done" "${LOG}" 2>/dev/null | wc -l)

echo "
============================== 并行注释完成 ==============================
总计: ${#MAGS[@]} 个 MAG
完成: ${COMPLETED}
耗时: ${ELAPSED} 秒
日志: ${LOG}
详细日志: ${LOGDIR}/*.log
========================================================================
"

if [ ${COMPLETED} -lt ${#MAGS[@]} ]; then
    FAILED=$((${#MAGS[@]} - ${COMPLETED}))
    echo "[WARNING] 有 ${FAILED} 个 MAG 注释失败或未完成，请检查日志"
    exit 1
fi

exit 0
