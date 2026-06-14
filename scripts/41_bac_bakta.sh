#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 41_bac_bakta.sh
# 功  能: MAG 全基因组精细注释（Bakta，批量处理所有去冗余 MAGs）
#         工具版本：Bakta 1.11+（conda env: bakta）
#         数  据：db/bakta/db-light（轻量数据库）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
# 输  出: ${WORKDIR}/result/binning/bakta/{mag_name}/
#           {mag_name}.tsv    — 注释汇总表
#           {mag_name}.gff3   — GFF3 格式
#           {mag_name}.faa    — 预测蛋白
#           {mag_name}.ffn    — 预测基因（核酸）
#           {mag_name}.gbff   — GenBank 格式
#
# ── 批量策略 ──────────────────────────────────────────────────────────────────
#   对每个 MAG 循环调用 Bakta，自动跳过已有输出。
#   如 MAG 数量大（>50），建议在 Snakemake 中按 MAG 独立调度。
#
# 参  考: Schwengers et al. 2021 Bioinformatics (Bakta)
# 用  法: bash 41_bac_bakta.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 41_bac_bakta.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数（每个 Bakta 进程使用 ${CPUS:-1} 线程，总负载 = MAGs × CPUS）
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/binning/bakta"
BAKTA_DB="${REPO}/db/bakta/db-light"
SUMMARY="${OUTDIR}/bakta_summary.tsv"

N_MAGS=0
if [ -d "${MAGS_DIR}" ]; then
    N_MAGS=$(find "${MAGS_DIR}" -maxdepth 1 -type f -name "*.fa" | wc -l)
fi
if [ "${N_MAGS}" -eq 0 ]; then
    echo "[bakta] WARNING: 去冗余 MAGs 为 0，创建空结果哨兵: ${SUMMARY}"
    mkdir -p "${OUTDIR}"
    : > "${SUMMARY}"
    exit 0
fi

mkdir -p "${OUTDIR}"

MAGS=("${MAGS_DIR}"/*.fa)
TOTAL=${#MAGS[@]}
COMPLETED=0
SKIPPED=0

echo "[bakta] 批量注释 ${TOTAL} 个 MAGs | db: ${BAKTA_DB}"

for mag in "${MAGS[@]}"; do
    mag_name=$(basename "$mag" .fa)
    mag_out="${OUTDIR}/${mag_name}"
    tsv_out="${mag_out}/${mag_name}.tsv"

    if [ -f "${tsv_out}" ] && [ -s "${tsv_out}" ]; then
        ((SKIPPED++))
        continue
    fi

    echo "[bakta] 注释 ${mag_name} ..."
    mkdir -p "${mag_out}"

    conda run --prefix "${REPO}/envs/bakta" --no-capture-output \
        bakta \
            --db "${BAKTA_DB}" \
            --threads "${CPUS}" \
            --locus-tag "${mag_name}_" \
            --locus "${mag_name}" \
            --prefix "${mag_name}" \
            --tmp-dir "${mag_out}/_tmp" \
            -o "${mag_out}" \
            "${mag}" \
            2>&1 | tail -3

    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[bakta] WARNING: ${mag_name} 注释失败"; continue
    fi
    rm -rf "${mag_out}/_tmp"
    ((COMPLETED++))
done

# 汇总：收集所有 .tsv（表头保留第一行）
echo "[bakta] 生成汇总表 ..."
{
    first=true
    for mag in "${MAGS[@]}"; do
        mag_name=$(basename "$mag" .fa)
        tsv="${OUTDIR}/${mag_name}/${mag_name}.tsv"
        [ -f "$tsv" ] || continue
        if [ "$first" = true ]; then
            cat "$tsv"
            first=false
        else
            tail -n +2 "$tsv"
        fi
    done
} > "${SUMMARY}"

echo "[bakta] 完成，耗时 ${SECONDS}s | 已完成: ${COMPLETED} | 跳过: ${SKIPPED} | 总计: ${TOTAL}"
