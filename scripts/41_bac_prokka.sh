#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 41_bac_prokka.sh
# 功  能: MAG 全基因组注释（Prokka，Bakta备选方案）
#         工具版本：Prokka 1.14+（conda env: prokka）
# 依  赖: 38_bac_drep.sh 的去冗余 MAGs
#         40_bac_gtdbtk.sh 的分类信息（可选，用于--genus参数提升精度）
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
#         ${WORKDIR}/result/binning/gtdbtk/gtdbtk.bac120.summary.tsv（可选）
# 输  出: ${WORKDIR}/result/binning/prokka/{mag_name}/
#           {mag_name}.tsv    — 注释汇总表
#           {mag_name}.gff    — GFF3 格式
#           {mag_name}.faa    — 预测蛋白
#           {mag_name}.ffn    — 预测基因（核酸）
#           {mag_name}.gbk    — GenBank 格式
#
# ── 批量策略 ──────────────────────────────────────────────────────────────────
#   对每个 MAG 循环调用 Prokka，自动跳过已有输出。
#   相比Bakta更稳定，但注释略简单（无RefSeq精确匹配）。
#
# 参  考: Seemann 2014 Bioinformatics (Prokka)
# 用  法: bash 41_bac_prokka.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 41_bac_prokka.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数（每个 Prokka 进程使用的线程数）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
可选参数:
  -m  单个MAG文件名（不含路径和.fa后缀，用于单样本测试）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO m:MAG_FILTER"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTDIR="${WORKDIR}/result/binning/prokka"
GTDBTK_TSV="${WORKDIR}/result/binning/gtdbtk/gtdbtk.bac120.summary.tsv"

# 检查输入
if [ ! -d "${MAGS_DIR}" ]; then
    echo "[ERROR] dRep MAG 目录不存在: ${MAGS_DIR}"
    exit 1
fi

# 读取GTDB-Tk分类信息（用于--genus参数）
declare -A MAG_GENUS
if [ -f "${GTDBTK_TSV}" ]; then
    echo "[prokka] 读取 GTDB-Tk 分类信息..."
    while IFS=$'\t' read -r user_genome classification rest; do
        if [[ "$user_genome" == "user_genome" ]]; then continue; fi  # skip header
        # 提取属名：d__;p__;c__;o__;f__;g__Genus;s__ → Genus
        genus=$(echo "$classification" | awk -F';' '{print $6}' | sed 's/g__//')
        if [[ -n "$genus" && "$genus" != "" ]]; then
            MAG_GENUS["$user_genome"]="$genus"
        fi
    done < "${GTDBTK_TSV}"
    echo "[prokka] 加载 ${#MAG_GENUS[@]} 个 MAG 的属名信息"
fi

# 收集MAG文件
if [ -n "${MAG_FILTER}" ]; then
    MAGS=("${MAGS_DIR}/${MAG_FILTER}.fa")
    if [ ! -f "${MAGS[0]}" ]; then
        echo "[ERROR] 指定的 MAG 文件不存在: ${MAGS[0]}"
        exit 1
    fi
    echo "[prokka] 单 MAG 模式: ${MAG_FILTER}"
else
    mapfile -t MAGS < <(find "${MAGS_DIR}" -maxdepth 1 -name "*.fa" -type f | sort)
    if [ ${#MAGS[@]} -eq 0 ]; then
        echo "[ERROR] ${MAGS_DIR} 下未找到 *.fa MAGs"
        exit 1
    fi
    echo "[prokka] 找到 ${#MAGS[@]} 个 MAG"
fi

# A --force re-run must not leave stale per-MAG dirs from a previous MAG set behind
# (confirmed: 65 orphan dirs remained after a force run on a smaller drep set). The
# non-force path keeps its per-MAG skip logic, so only clear on --force.
if [ ${FORCE} -eq 1 ]; then rm -rf "${OUTDIR}"; fi
mkdir -p "${OUTDIR}"
LOG="${OUTDIR}/prokka_batch.log"
echo "[prokka] 开始批量注释..." | tee "${LOG}"
echo "[prokka] 输出目录: ${OUTDIR}" | tee -a "${LOG}"

COMPLETED=0
SKIPPED=0
FAILED=0

for mag in "${MAGS[@]}"; do
    mag_name=$(basename "$mag" .fa)
    mag_out="${OUTDIR}/${mag_name}"
    tsv_out="${mag_out}/${mag_name}.tsv"

    # 跳过已完成
    if [ ${FORCE} -eq 0 ] && [ -f "${tsv_out}" ] && [ -s "${tsv_out}" ]; then
        echo "[prokka] 跳过已完成: ${mag_name}" | tee -a "${LOG}"
        SKIPPED=$((SKIPPED+1))
        continue
    fi

    echo "[prokka] 注释 ${mag_name} ..." | tee -a "${LOG}"

    # 清理locus tag（Prokka要求字母数字和_-，但MAG名可能含.）
    locus_clean="${mag_name//./\_}"

    # 构建命令
    CMD="mgx_conda prokka prokka"
    CMD="$CMD --outdir ${mag_out}"
    CMD="$CMD --prefix ${mag_name}"
    CMD="$CMD --locustag ${locus_clean}"
    CMD="$CMD --cpus ${CPUS}"
    CMD="$CMD --kingdom Bacteria"
    CMD="$CMD --metagenome"
    CMD="$CMD --mincontiglen 200"
    CMD="$CMD --rfam"
    CMD="$CMD --force"

    # 如果GTDB-Tk提供了属名，加入--genus参数
    if [ -n "${MAG_GENUS[$mag_name]:-}" ]; then
        genus="${MAG_GENUS[$mag_name]}"
        CMD="$CMD --genus ${genus}"
        echo "  [提示] 使用 GTDB-Tk 属名: ${genus}" | tee -a "${LOG}"
    fi

    CMD="$CMD ${mag}"

    # 执行
    EXIT_CODE=0
    mgx_try eval "$CMD" >> "${LOG}" 2>&1 || EXIT_CODE=$?

    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "[prokka] WARNING: ${mag_name} 注释失败（exit code: ${EXIT_CODE}）" | tee -a "${LOG}"
        FAILED=$((FAILED+1))
        continue
    fi

    COMPLETED=$((COMPLETED+1))
    echo "[prokka] ✓ ${mag_name} 完成" | tee -a "${LOG}"
done

ELAPSED=$((SECONDS))
echo "
============================== 批量注释完成 ==============================
总计: ${#MAGS[@]} 个 MAG
完成: ${COMPLETED}
跳过: ${SKIPPED}
失败: ${FAILED}
耗时: ${ELAPSED} 秒
日志: ${LOG}
========================================================================
" | tee -a "${LOG}"

if [ ${FAILED} -gt 0 ]; then
    echo "[WARNING] 有 ${FAILED} 个 MAG 注释失败，请检查日志: ${LOG}"
    exit 1
fi

# 汇总所有 MAG 的注释表为单一 summary（供 Snakemake 追踪 + 41c pangenome 消费）
SUMMARY="${OUTDIR}/prokka_summary.tsv"
: > "${SUMMARY}"
for mag in "${MAGS[@]}"; do
    mag_name=$(basename "$mag" .fa)
    tsv_out="${OUTDIR}/${mag_name}/${mag_name}.tsv"
    if [ -f "${tsv_out}" ]; then
        awk -v mag="${mag_name}" 'BEGIN{OFS="\t"} FNR==1 && NR!=1{next} {print mag, $0}' "${tsv_out}" >> "${SUMMARY}"
    fi
done
touch "${OUTDIR}/prokka_done.txt"
echo "[prokka] 汇总表: ${SUMMARY}"

exit 0
