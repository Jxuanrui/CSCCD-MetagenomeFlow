#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 15c_bac_sylph.sh
# 功  能: sylph 快速物种分类（abundance-corrected minhash sketch，GTDB-R220）
#         工具版本：sylph v0.9.0 + sylph-tax v1.9.1（conda env: sylph）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/sylph/${SAMPLE}/
#           ${SAMPLE}.sylph_profile.tsv      — sylph 原始输出（无物种名，genome ID）
#           ${SAMPLE}.sylphmpa               — sylph-tax 标注后的物种级 profile（MetaPhlAn 风格）
#
# ── 定位说明 ──────────────────────────────────────────────────────────────────
#
#   与现有 MetaPhlAn4（精确，慢）、Kraken2+Bracken（k-mer，77G库）并列，
#   不替代：sylph 用 minhash sketch 做物种级分类，速度远快于二者（官方数据
#   >50x 于同类工具），对 GTDB-R220 全库（110k+ genomes）内存仅需 ~15GB，
#   适合作为快速预筛选选项。
#
# ── 数据库说明 ────────────────────────────────────────────────────────────────
#
#   GTDB-R220 sketch 库（113,104 个物种代表基因组，2024-04-24，-c200 灵敏版）：
#     ${REPO}/db/sylph/gtdb-r220-c200-dbv1.syldb   (~13.1G)
#   taxonomy metadata（用于 sylph-tax 把 genome ID 转成物种名）：
#     ${REPO}/db/sylph/gtdb_r220_metadata.tsv.gz
#
# 参  考: Shaw & Yu, Nature Biotechnology 2024 (sylph)
#         https://github.com/bluenote-1577/sylph
#         https://github.com/bluenote-1577/sylph-tax
# 用  法: bash 15c_bac_sylph.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force] [--min-ani 95]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 15c_bac_sylph.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16）
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force    强制重新运行（忽略已存在的结果）
  --min-ani  Profile 最低 ANI 阈值（默认 95，sylph 官方建议不低于 95 以保证精度）

示例:
  bash 15c_bac_sylph.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

MIN_ANI="95"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="min-ani:MIN_ANI"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/sylph/${SAMPLE}"

DB_SYLDB="${REPO}/db/sylph/gtdb-r220-c200-dbv1.syldb"
DB_METADATA="${REPO}/db/sylph/gtdb_r220_metadata.tsv.gz"

PROFILE_TSV="${RESULT_DIR}/${SAMPLE}.sylph_profile.tsv"
SYLPHMPA="${RESULT_DIR}/${SAMPLE}.sylphmpa"

# --- 输入检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
if [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    exit 1
fi
if [ ! -f "${DB_SYLDB}" ] || [ ! -s "${DB_SYLDB}" ]; then
    echo "[ERROR] sylph GTDB-R220 数据库不存在或为空: ${DB_SYLDB}"
    echo "        请先下载数据库（参考 0Install.sh sylph 章节）"
    exit 1
fi
if [ ! -f "${DB_METADATA}" ] || [ ! -s "${DB_METADATA}" ]; then
    echo "[ERROR] sylph taxonomy metadata 不存在或为空: ${DB_METADATA}"
    echo "        请先运行: conda run --prefix ${REPO}/envs/sylph sylph-tax download --download-to ${REPO}/db/sylph"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${SYLPHMPA}" ] && [ -s "${SYLPHMPA}" ]; then
    echo "[INFO] sylph 结果已存在，跳过: ${SAMPLE}"
    echo "       ${RESULT_DIR}/"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[sylph] 开始物种分类: ${SAMPLE}"
echo "[sylph] 线程: ${CPUS}，最低 ANI: ${MIN_ANI}"
echo "[sylph] 数据库: ${DB_SYLDB}"

# --- 运行 sylph profile ---
# profile 子命令支持直接传入原始 fastq（自动 sketch），无需单独跑 sylph sketch

echo "[sylph] 运行 sylph profile..."
EXIT_CODE=0
mgx_try mgx_conda sylph \
    sylph profile \
        "${DB_SYLDB}" \
        -1 "${INPUT_R1}" -2 "${INPUT_R2}" \
        -t "${CPUS}" \
        -m "${MIN_ANI}" \
        -o "${PROFILE_TSV}" \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] sylph profile 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${PROFILE_TSV}" ] || [ ! -s "${PROFILE_TSV}" ]; then
    echo "[ERROR] sylph profile 输出未生成或为空: ${PROFILE_TSV}"
    exit 1
fi

echo "[sylph] sylph profile 完成，运行 sylph-tax 物种名标注..."

# --- 运行 sylph-tax taxprof（把 genome ID 转成 MetaPhlAn 风格物种名 profile）---
# sylph-tax taxprof 按 Sample_file 列的文件名生成输出：<prefix><basename(fastq)>.sylphmpa
# -1 (basename of INPUT_R1) 是 sylph profile 的 Sample_file 列值，需要匹配前缀策略

EXIT_CODE=0
mgx_try mgx_conda sylph \
    sylph-tax taxprof \
        "${PROFILE_TSV}" \
        -t "${DB_METADATA}" \
        -o "${RESULT_DIR}/${SAMPLE}_" \
        --overwrite \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] sylph-tax taxprof 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# sylph-tax taxprof 输出文件名基于 Sample_file 列（即 -1 fastq 的 basename），
# 而非样本名，需要重命名为统一的 ${SAMPLE}.sylphmpa 约定
GENERATED_MPA=$(find "${RESULT_DIR}" -maxdepth 1 -name "${SAMPLE}_*.sylphmpa" 2>/dev/null | head -1)
if [ -z "${GENERATED_MPA}" ] || [ ! -s "${GENERATED_MPA}" ]; then
    echo "[ERROR] sylph-tax taxprof 输出未生成或为空: ${RESULT_DIR}/${SAMPLE}_*.sylphmpa"
    exit 1
fi
mv "${GENERATED_MPA}" "${SYLPHMPA}"

# --- 统计摘要 ---

N_TAXA=$(tail -n+3 "${SYLPHMPA}" 2>/dev/null | grep -vc "NO_TAXONOMY$" || echo "0")

echo ""
echo "[sylph] ${SAMPLE} 完成"
echo "[sylph] 结果目录: ${RESULT_DIR}/"
echo "    检测到分类条目数: ${N_TAXA}"
echo "    关键输出:"
echo "    ├── ${SAMPLE}.sylph_profile.tsv    (sylph 原始输出)"
echo "    └── ${SAMPLE}.sylphmpa             (物种级 profile，MetaPhlAn 风格)"
echo ""
echo "[提示] 所有样本完成后运行 15d_bac_sylph_merge.sh 合并丰度矩阵"
mgx_end "sylph"
