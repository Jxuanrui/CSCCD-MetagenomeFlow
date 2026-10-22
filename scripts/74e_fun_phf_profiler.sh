#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74e_fun_phf_profiler.sh
# 功  能: 肠道真菌丰度定量（Yan et al. 2024 Cell 187 原方法）
#         五步 Bowtie2 过滤 + Singular/Escrow 算法（GPA.py）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
#         74a_fun_gut_db_build.sh 构建的 Bowtie2 索引
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_*.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/phf_profiler/${SAMPLE}/${SAMPLE}.rc
#         ${WORKDIR}/result/fungi/phf_profiler/${SAMPLE}/${SAMPLE}.rc.cmd.log
# 用  法: bash 74e_fun_phf_profiler.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 74e_fun_phf_profiler.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录（含 result/kneaddata/）
  -r  CSCCD-MetagenomeFlow 项目根目录

输出:
  \${WORKDIR}/result/fungi/phf_profiler/SAMPLE/SAMPLE.rc  — 相对丰度表（Singular+Escrow）

算法说明（Yan et al. 2024 Cell 187 Singular/Escrow）:
  1. 比对 reads 到真菌基因集 → 提取真菌 reads
  2. 过滤人类宿主 reads
  3. 过滤细菌 reads（UHGG）
  4. 过滤 rRNA reads
  5. 重新比对（-k 1000，允许多重比对）
  6. GPA.py: singular reads（唯一比对）直接计数；escrow reads（多重比对）
     按 singular 比例分配；normalize by cluster gene length → 相对丰度
EOF
}

CPUS="1"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

if ! [[ "${CPUS}" =~ ^[1-9][0-9]*$ ]]; then echo "[ERROR] -t 必须是正整数: ${CPUS}"; exit 1; fi
REPO="$(cd "${REPO}" && pwd)"

mgx_begin

# Paths
KNEADDATA_DIR="${WORKDIR}/result/kneaddata/${SAMPLE}"
OUTDIR="${WORKDIR}/result/fungi/phf_profiler/${SAMPLE}"
TMPDIR_BASE="${OUTDIR}/tmp_${SAMPLE}"
OUT_PREFIX="${OUTDIR}/${SAMPLE}"

IDX_DIR="${REPO}/db/gut_fungi_db"
IDX_FUNGI="${IDX_DIR}/bwt.index.gut_fungi_geneset"
IDX_HUMAN="${IDX_DIR}/bwt.index.human_chm13v2"
IDX_UHGG="${IDX_DIR}/bwt.index.uhgg"
IDX_RRNA="${IDX_DIR}/bwt.index.fungi_target"
GPA_PY="${REPO}/db/gut_fungi_db/GPA.py"

RESULT="${OUT_PREFIX}.rc"

# Validate
if [ ${FORCE} -eq 0 ] && [ -f "${RESULT}" ] && [ -s "${RESULT}" ]; then
    echo "[INFO] 结果已存在，跳过: ${RESULT}"; exit 0
fi

# Find kneaddata paired reads
R1="${KNEADDATA_DIR}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${KNEADDATA_DIR}/${SAMPLE}_2.kneaddata.fastq.gz"

if [ ! -f "${R1}" ] || [ ! -s "${R1}" ]; then
    echo "[WARN] kneaddata R1 不存在，跳过: ${R1}"; exit 0
fi

# Check indexes
for idx in "${IDX_FUNGI}" "${IDX_HUMAN}" "${IDX_UHGG}" "${IDX_RRNA}"; do
    if { [ ! -f "${idx}.1.bt2" ] || [ ! -s "${idx}.1.bt2" ]; } && { [ ! -f "${idx}.1.bt2l" ] || [ ! -s "${idx}.1.bt2l" ]; }; then
        echo "[ERROR] Bowtie2 索引不存在: ${idx}.1.bt2/.1.bt2l"
        echo "请先运行: bash scripts/74a_fun_gut_db_build.sh -t ${CPUS} -r ${REPO}"
        exit 1
    fi
done

if [ ! -f "${GPA_PY}" ]; then
    echo "[ERROR] GPA.py 不存在: ${GPA_PY}"; exit 1
fi

mkdir -p "${OUTDIR}" "${TMPDIR_BASE}"
CMD_LOG="${OUT_PREFIX}.rc.cmd.log"
: > "${CMD_LOG}"

echo "[phf_profiler] 开始: ${SAMPLE} | 线程: ${CPUS} | 算法: Singular+Escrow"

# Merge R1+R2 for single-end bowtie2 (paper uses merged/interleaved reads)
MERGED_FQ="${TMPDIR_BASE}/${SAMPLE}_merged.fastq.gz"
if [ -f "${R2}" ] && [ -s "${R2}" ]; then
    cat "${R1}" "${R2}" > "${MERGED_FQ}"
else
    cp "${R1}" "${MERGED_FQ}"
fi

IN="${MERGED_FQ}"

# Step 1: Map to fungi gene set → extract fungi reads
STEP1="${TMPDIR_BASE}/${SAMPLE}.step1_fungi.fq.gz"
echo "# Step 1: map to fungi gene set" >> "${CMD_LOG}"
mgx_conda assembly \
    bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
        -U "${IN}" -x "${IDX_FUNGI}" -S /dev/null \
        --al-gz "${STEP1}" -p "${CPUS}" \
    2>> "${CMD_LOG}"

if [ ! -s "${STEP1}" ]; then
    echo "[INFO] ${SAMPLE}: Step1 无真菌 reads，生成空结果"
    echo -e "cluster\t${SAMPLE}" > "${RESULT}"
    rm -rf "${TMPDIR_BASE}"; exit 0
fi

# Step 2: Filter human reads
STEP2="${TMPDIR_BASE}/${SAMPLE}.step2_rmHost.fq.gz"
echo "# Step 2: remove human" >> "${CMD_LOG}"
mgx_conda assembly \
    bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
        -U "${STEP1}" -x "${IDX_HUMAN}" -S /dev/null \
        --un-gz "${STEP2}" -p "${CPUS}" \
    2>> "${CMD_LOG}"

# Step 3: Filter bacterial reads (UHGG)
STEP3="${TMPDIR_BASE}/${SAMPLE}.step3_rmUHGG.fq.gz"
echo "# Step 3: remove UHGG bacteria" >> "${CMD_LOG}"
mgx_conda assembly \
    bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
        -U "${STEP2}" -x "${IDX_UHGG}" -S /dev/null \
        --un-gz "${STEP3}" -p "${CPUS}" \
    2>> "${CMD_LOG}"

# Step 4: Filter rRNA reads
STEP4="${TMPDIR_BASE}/${SAMPLE}.step4_rmrRNA.fq.gz"
echo "# Step 4: remove rRNA" >> "${CMD_LOG}"
mgx_conda assembly \
    bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
        -U "${STEP3}" -x "${IDX_RRNA}" -S /dev/null \
        --un-gz "${STEP4}" -p "${CPUS}" \
    2>> "${CMD_LOG}"

# Step 5: Re-map with -k 1000 for multi-mapping (Escrow reads)
STEP5_SAM="${TMPDIR_BASE}/${SAMPLE}.step5_fungi.sam"
echo "# Step 5: re-map k=1000 for Singular+Escrow" >> "${CMD_LOG}"
mgx_conda assembly \
    bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
        -U "${STEP4}" -x "${IDX_FUNGI}" -S "${STEP5_SAM}" \
        -k 1000 -p "${CPUS}" \
    2>> "${CMD_LOG}"

# Step 6: GPA.py — Singular+Escrow abundance
echo "# Step 6: GPA.py Singular+Escrow abundance" >> "${CMD_LOG}"
mgx_conda assembly \
    python "${GPA_PY}" \
        -i "${STEP5_SAM}" \
        -o "${RESULT}" \
        -s 0.95

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] GPA.py 失败（exit: ${EXIT_CODE}）"; rm -f "${RESULT}"; exit ${EXIT_CODE}
fi

rm -rf "${TMPDIR_BASE}"

N_CLUSTERS=$(tail -n +2 "${RESULT}" 2>/dev/null | wc -l | tr -d ' ')
echo "[phf_profiler] ${SAMPLE} 完成 | 检出真菌簇: ${N_CLUSTERS} | 输出: ${RESULT}"
mgx_end "phf_profiler"
