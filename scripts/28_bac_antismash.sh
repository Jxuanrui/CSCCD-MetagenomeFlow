#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 28_bac_antismash.sh
# 功  能: 次级代谢产物生物合成基因簇（BGC）预测（antiSMASH）
#         工具版本：antiSMASH 7.x（conda env: antismash）
# 依  赖: 16_bac_megahit.sh 的输出（{sample}.contigs.fa，≥1000bp）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/annotation/antismash/{sample}/
#           {sample}.gbk           — 结果 GenBank 文件
#           {sample}.json          — 结果 JSON（API用）
#           index.html             — 可视化报告
#
# ── 注意 ─────────────────────────────────────────────────────────────────────
#   antiSMASH 按样本运行（per-sample），宏基因组模式下不使用全基因组注释步骤
#   --minimal 可跳过 NCBI taxonomy 查询，但会损失部分注释
#   --taxon bacteria 是宏基因组细菌最常用设置
#
# 参  考: Blin et al. 2023 NAR (antiSMASH 7)
# 用  法: bash 28_bac_antismash.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 28_bac_antismash.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

SAMPLE=""
CPUS=""
WORKDIR=""
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-s/-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
RESULT_DIR="${WORKDIR}/result/annotation/antismash/${SAMPLE}"
SENTINEL="${RESULT_DIR}/index.html"
ANTISMASH_DB="${REPO}/db/antismash"

if [ ! -f "${CONTIGS}" ] || [ ! -s "${CONTIGS}" ]; then
    echo "[ERROR] 组装文件不存在: ${CONTIGS}"; exit 1
fi

if [ -f "${SENTINEL}" ]; then
    echo "[INFO] antiSMASH 结果已存在，跳过: ${RESULT_DIR}/"; exit 0
fi

# antiSMASH 不允许写入已存在目录
[ -d "${RESULT_DIR}" ] && rm -rf "${RESULT_DIR}"
mkdir -p "$(dirname "${RESULT_DIR}")"

echo "[antismash] 样本: ${SAMPLE} | 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/antismash" --no-capture-output \
    antismash \
        "${CONTIGS}" \
        --taxon bacteria \
        --output-dir "${RESULT_DIR}" \
        --cpus "${CPUS}" \
        --databases "${ANTISMASH_DB}" \
        --genefinding-tool prodigal-m \
        --minimal \
        --enable-nrps-pks

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] antismash 失败（exit code: ${EXIT_CODE}）"; exit ${EXIT_CODE}
fi

N_BGC=$(grep -c '"cluster_blast_hit"' "${RESULT_DIR}"/*.json 2>/dev/null || \
        find "${RESULT_DIR}" -name "*.gbk" | wc -l)
echo "[antismash] 完成，耗时 ${SECONDS}s | BGC: ${N_BGC} | 输出: ${RESULT_DIR}/"
