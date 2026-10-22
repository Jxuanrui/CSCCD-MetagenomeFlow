#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98g_cross_domain_correlation.sh
# 功  能: 构建细菌、病毒和真菌的跨域丰度 Spearman 相关性网络
# 依  赖: MetaPhlAn4 丰度表、vOTU abundance table、可选 PHF/iPHoP 结果
# 环  境: envs/phagcn3（pandas/networkx/scipy>=1.11；BH-FDR 校正依赖
#         scipy.stats.false_discovery_control，旧版 scipy 无此 API）
# 输  出: ${WORKDIR}/result/cross_domain/correlation/
#           abundance_matrix.tsv, network_edges.tsv, network_nodes.tsv,
#           network_summary.txt
# 用  法: bash 98g_cross_domain_correlation.sh -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat <<'EOF'
用法: bash 98g_cross_domain_correlation.sh -t CPUS -w WORKDIR -r REPO [--virus-value-column tpm|count] [--force]
必需参数:
  -t  线程数（保留用于与跨域分析脚本一致；相关性计算按块执行）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --virus-value-column  病毒表使用的丰度列后缀（tpm 或 count，默认 tpm）
  --force  强制重新运行（忽略已存在的结果）
EOF
}

VIRUS_VALUE_COLUMN="tpm"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="virus-value-column:VIRUS_VALUE_COLUMN"
mgx_parse "$@"
if [[ "${VIRUS_VALUE_COLUMN}" != "tpm" && "${VIRUS_VALUE_COLUMN}" != "count" ]]; then
    echo "[ERROR] --virus-value-column 仅支持 tpm 或 count"
    exit 1
fi
mgx_require CPUS WORKDIR REPO

mgx_begin
REPO="$(readlink -f "${REPO}")"
WORKDIR="$(readlink -f "${WORKDIR}")"
OUTDIR="${WORKDIR}/result/cross_domain/correlation"
SUMMARY="${OUTDIR}/network_summary.txt"
VIRUS_TABLE="${WORKDIR}/result/virus/votu/votu_table.tsv"
IPHOP_FILE="${WORKDIR}/result/virus/iphop/Host_prediction_to_genome_m90.csv"
PYTHON_ENV="${REPO}/envs/phagcn3"

if [ ${FORCE} -eq 0 ] && [ -s "${SUMMARY}" ]; then
    echo "[cross_domain_corr] 结果已存在，跳过: ${SUMMARY}"
    exit 0
fi
if [ ! -f "${VIRUS_TABLE}" ]; then
    echo "[ERROR] 未找到病毒 vOTU 表: ${VIRUS_TABLE}"
    exit 1
fi
if [ ! -x "${PYTHON_ENV}/bin/python3" ]; then
    echo "[ERROR] 未找到含 pandas/scipy/networkx 的环境: ${PYTHON_ENV}"
    exit 1
fi

BACTERIA_INPUT=""
for candidate in \
    "${WORKDIR}/result/metaphlan4/merged/taxonomy_species.tsv" \
    "${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv"; do
    if [ -s "${candidate}" ]; then BACTERIA_INPUT="${candidate}"; break; fi
done
if [ -z "${BACTERIA_INPUT}" ] && compgen -G "${WORKDIR}/result/metaphlan4/*/*_profile.txt" > /dev/null; then
    BACTERIA_INPUT="${WORKDIR}/result/metaphlan4"
fi
if [ -z "${BACTERIA_INPUT}" ]; then
    echo "[ERROR] 未找到细菌 MetaPhlAn4 丰度数据"
    exit 1
fi

FUNGI_INPUT=""
for candidate in \
    "${WORKDIR}/result/integration/fungi/normalized/funomic_species_relab.tsv" \
    "${WORKDIR}/result/integration/fungi/funomic_species_count.tsv" \
    "${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy_species.tsv" \
    "${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy.tsv"; do
    if [ -s "${candidate}" ]; then FUNGI_INPUT="${candidate}"; break; fi
done
if [ -z "${FUNGI_INPUT}" ] && compgen -G "${WORKDIR}/result/fungi/metaphlan4/*/*_profile.txt" > /dev/null; then
    FUNGI_INPUT="${WORKDIR}/result/fungi/metaphlan4"
fi

mkdir -p "${OUTDIR}"
echo "[cross_domain_corr] 细菌输入: ${BACTERIA_INPUT}"
echo "[cross_domain_corr] 病毒输入: ${VIRUS_TABLE}"
if [ -n "${FUNGI_INPUT}" ]; then
    echo "[cross_domain_corr] 真菌输入: ${FUNGI_INPUT}"
else
    echo "[cross_domain_corr] 未找到真菌数据，将输出细菌-病毒网络"
fi

command=(
    "${PYTHON_ENV}/bin/python3" "${REPO}/scripts/98g_cross_domain_corr.py"
    --bacteria "${BACTERIA_INPUT}"
    --virus "${VIRUS_TABLE}"
    --virus-value-column "${VIRUS_VALUE_COLUMN}"
    --iphop "${IPHOP_FILE}"
    --outdir "${OUTDIR}"
)
if [ -n "${FUNGI_INPUT}" ]; then
    command+=(--fungi "${FUNGI_INPUT}")
fi

# 相关性计算依赖 numpy/scipy 底层 BLAS 并行，CPUS 通过环境变量传递而非
# argparse（Python 侧本身是单进程分块计算，并行度由 BLAS 线程池控制）
export OMP_NUM_THREADS="${CPUS}"
export OPENBLAS_NUM_THREADS="${CPUS}"
export MKL_NUM_THREADS="${CPUS}"
"${command[@]}"

mgx_end "cross_domain_corr"
printf '%s\n' "[cross_domain_corr] 输出: ${OUTDIR}/abundance_matrix.tsv" \
                  "[cross_domain_corr] 输出: ${OUTDIR}/network_edges.tsv" \
                  "[cross_domain_corr] 输出: ${OUTDIR}/network_nodes.tsv" \
                  "[cross_domain_corr] 输出: ${SUMMARY}"
