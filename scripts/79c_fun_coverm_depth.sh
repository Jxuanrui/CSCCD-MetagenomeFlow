#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79c_fun_coverm_depth.sh
# 功  能: 计算真核候选 contig 的 reads 覆盖度深度（CoverM + minimap2）
#         输出 MetaBAT2 分箱所需的深度表和 BAM
#         工具版本：CoverM（conda env: coverm，与32号细菌脚本共用）
#         VEBA (https://github.com/jolespin/veba) binning-eukaryotic 模块方法参考，
#         不拷贝 VEBA 源码（AGPLv3），CoverM 为 Apache-2.0，无许可证污染风险
# 依  赖: 79b_fun_veba_qc.sh 的输出（Tiara 域确认后的真核候选 contig）
# 输  入: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/eukarya_${SAMPLE}.euk_filtered.fasta
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/coverm/
#           ${SAMPLE}.bam  — 排序后的 BAM（MetaBAT2 输入）
#           depth.txt      — MetaBAT2 格式深度表
# 用  法: bash 79c_fun_coverm_depth.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 79c_fun_coverm_depth.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

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
CONTIGS="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/eukarya_${SAMPLE}.euk_filtered.fasta"
OUTDIR="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/coverm"
BAM="${OUTDIR}/${SAMPLE}.bam"
DEPTH="${OUTDIR}/depth.txt"
EMPTY_FLAG="${OUTDIR}/${SAMPLE}.coverm_empty.flag"
R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

# 79b 可能因低测序深度落入空结果分支，此时 eukarya_*.euk_filtered.fasta 不存在，
# 这是预期行为（非本脚本错误），不应报错退出
if [ ! -f "${CONTIGS}" ]; then
    mkdir -p "${OUTDIR}"
    cat > "${EMPTY_FLAG}" << EOF
[EMPTY] 79b 未产出 Tiara 确认真核候选序列（预期行为，测序深度不足或79b判空）
样本: ${SAMPLE}
时间: $(date -Iseconds)
EOF
    echo "[coverm_fungi] 79b 无候选真核序列可用，跳过覆盖度计算，正常退出"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -d "${OUTDIR}" ] && { { [ -f "${DEPTH}" ] && [ -s "${DEPTH}" ] && [ -f "${BAM}" ] && [ -s "${BAM}" ]; } || [ -f "${EMPTY_FLAG}" ]; }; then
    echo "[coverm_fungi] 结果已存在，跳过: ${OUTDIR}/"
    exit 0
fi

mkdir -p "${OUTDIR}"
rm -f "${EMPTY_FLAG}"

if [ ! -f "${BAM}" ] || [ ! -s "${BAM}" ]; then
    echo "[coverm_fungi] 步骤 1/2: minimap2 比对生成 BAM ..."
    EXIT_CODE=0
    mgx_try mgx_conda coverm \
        coverm make \
            -p minimap2-sr \
            -t "${CPUS}" \
            -r "${CONTIGS}" \
            -1 "${R1}" -2 "${R2}" \
            -o "${OUTDIR}" \
            || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm make 失败"; exit ${EXIT_CODE}; fi
    # coverm make 输出 BAM 文件名包含 contig/read 信息，重命名为标准格式
    GENERATED_BAM=$(ls "${OUTDIR}"/*.bam 2>/dev/null | head -1)
    if [ -n "${GENERATED_BAM}" ] && [ "${GENERATED_BAM}" != "${BAM}" ]; then
        mv "${GENERATED_BAM}" "${BAM}"
    fi
fi

if [ ! -f "${DEPTH}" ] || [ ! -s "${DEPTH}" ]; then
    echo "[coverm_fungi] 步骤 2/2: 生成深度表 ..."
    EXIT_CODE=0
    mgx_try mgx_conda coverm \
        coverm contig \
            -t "${CPUS}" \
            --methods metabat \
            --bam-files "${BAM}" \
            -o "${DEPTH}" \
            || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] coverm contig 失败"; exit ${EXIT_CODE}; fi
fi

echo "[coverm_fungi] 完成 | 输出: ${OUTDIR}/"
mgx_end "coverm_fungi"
