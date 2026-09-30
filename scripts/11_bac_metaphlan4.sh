#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 11_bac_metaphlan4.sh
# 功  能: MetaPhlAn4 细菌/古菌物种组成分析（菌株级精确分类）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt
#         ${WORKDIR}/result/metaphlan4/${SAMPLE}/${SAMPLE}.sam.bz2  (供 12_strainphlan4 使用)
# 临时文件: ${WORKDIR}/temp/metaphlan4/${SAMPLE}/
# 用  法: bash 11_bac_metaphlan4.sh -s SRR28210342 -t 16 -w /path/to/Project_example -r /path/to/CSCCD-MetagenomeFlow
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# --- 参数解析 ---

show_help() { cat << EOF

用法: bash 11_bac_metaphlan4.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

参数说明:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 8-16）
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

示例:
  bash 11_bac_metaphlan4.sh -s SRR28210342 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径设置 ---

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

TEMP_DIR="${WORKDIR}/temp/metaphlan4/${SAMPLE}"
RESULT_DIR="${WORKDIR}/result/metaphlan4/${SAMPLE}"

PROFILE_OUT="${RESULT_DIR}/${SAMPLE}_profile.txt"
SAM_OUT="${RESULT_DIR}/${SAMPLE}.sam.bz2"
MAPOUT="${TEMP_DIR}/${SAMPLE}.mapout.bz2"

DB_DIR="${REPO}/db/metaphlan4"
DB_INDEX="mpa_vOct22_CHOCOPhlAnSGB_202212"

# --- 输入检查 ---

if [ ! -f "${INPUT_R1}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R1}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi
if [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_R2}"
    echo "        请先运行 02_qc_kneaddata.sh"
    exit 1
fi

if [ ! -d "${DB_DIR}" ]; then
    echo "[ERROR] MetaPhlAn4 数据库不存在: ${DB_DIR}"
    exit 1
fi

# 检查数据库索引文件（任意一个 .bt2l 文件即可）
if ! ls "${DB_DIR}/${DB_INDEX}"*.bt2l &>/dev/null; then
    echo "[ERROR] 数据库索引未找到: ${DB_DIR}/${DB_INDEX}*.bt2l"
    exit 1
fi

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${PROFILE_OUT}" ] && [ -f "${SAM_OUT}" ]; then
    echo "[INFO] 输出已存在，跳过: ${SAMPLE}"
    echo "       ${PROFILE_OUT}"
    echo "       ${SAM_OUT}"
    exit 0
fi

# --- 创建目录 ---

mkdir -p "${TEMP_DIR}" "${RESULT_DIR}"

# 清理可能残留的 mapout 中间文件（MetaPhlAn4 拒绝覆盖已存在的 mapout）
if [ -f "${MAPOUT}" ]; then
    echo "[INFO] 清理残留 mapout 文件: ${MAPOUT}"
    rm -f "${MAPOUT}"
fi

echo "[metaphlan4] 开始物种组成分析: ${SAMPLE}"
echo "[metaphlan4] 输入: ${INPUT_R1}"
echo "[metaphlan4]       ${INPUT_R2}"
echo "[metaphlan4] 数据库: ${DB_DIR}/${DB_INDEX}"
echo "[metaphlan4] 线程: ${CPUS}"

# --- 运行 MetaPhlAn4 ---
# 使用 -1/-2 分别传入双端 reads；--samout 保存 SAM 供 StrainPhlAn4 使用
# --mapout 保存 bowtie2 比对中间结果到 temp（可重用，避免重复比对）

# MetaPhlAn4 v4.2.4 的双端输入需要合并为单文件（-1/-2 仅用于子采样模式）
MERGED_FASTQ="${TEMP_DIR}/${SAMPLE}_merged.fastq.gz"
echo "[INFO] 合并双端 reads..."
zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${MERGED_FASTQ}"

EXIT_CODE=0
mgx_try mgx_conda humann4 \
    metaphlan \
        "${MERGED_FASTQ}" \
        --input_type fastq \
        --db_dir "${DB_DIR}" \
        -x "${DB_INDEX}" \
        --nproc "${CPUS}" \
        --mapout "${MAPOUT}" \
        --samout "${RESULT_DIR}/${SAMPLE}.sam" \
        -o "${PROFILE_OUT}" \
        --offline \
        || EXIT_CODE=$?
rm -f "${MERGED_FASTQ}"
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] metaphlan4 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${PROFILE_OUT}" ]; then
    echo "[ERROR] 未生成 profile 文件: ${PROFILE_OUT}"
    exit 1
fi

# --- 压缩 SAM 文件（StrainPhlAn4 需要 .sam.bz2 格式）---

SAM_RAW="${RESULT_DIR}/${SAMPLE}.sam"
if [ -f "${SAM_RAW}" ]; then
    echo "[INFO] 压缩 SAM 文件..."
    bzip2 "${SAM_RAW}"
else
    echo "[WARN] SAM 文件未生成，StrainPhlAn4 步骤可能无法运行"
fi

# --- 统计摘要 ---

echo ""
echo "[metaphlan4] 物种分类统计:"
# 统计检测到的分类群数（排除注释行和未分类行）
SPECIES_COUNT=$(grep -v "^#" "${PROFILE_OUT}" | grep -c "s__" || echo 0)
GENUS_COUNT=$(grep -v "^#" "${PROFILE_OUT}" | grep -c "g__" || echo 0)
echo "             检测到菌属: ${GENUS_COUNT}，菌种: ${SPECIES_COUNT}"

# 输出相对丰度前 5 的物种（菌种级别）
echo "             相对丰度 Top5 菌种:"
grep -v "^#" "${PROFILE_OUT}" | grep "s__" | grep -v "t__" | \
    awk -F'\t' '{print $3"\t"$1}' | sort -k1,1rn | head -5 | \
    awk -F'\t' '{printf "               %.4f%%  %s\n", $1, $2}' || true

echo ""
echo "[metaphlan4] ${SAMPLE} 完成"
echo "[metaphlan4] 结果目录: ${RESULT_DIR}"
echo "[metaphlan4] Profile:  ${PROFILE_OUT}"
if [ -f "${SAM_OUT}" ]; then
    echo "[metaphlan4] SAM.bz2:  ${SAM_OUT} ($(du -h "${SAM_OUT}" | cut -f1))"
fi
mgx_end "metaphlan4"
