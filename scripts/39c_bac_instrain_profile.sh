#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 39c_bac_instrain_profile.sh
# 功  能: 样本菌株微多样性分析（inStrain profile）
#         工具版本：inStrain 1.10+（conda env: instrain）
# 依  赖: 39b_bac_instrain_map.sh 的输出（sorted BAM）
# 输  入: ${WORKDIR}/result/binning/instrain_map/{sample}/{sample}.sorted.bam
#         ${WORKDIR}/result/binning/instrain_map/combined_mags.fa
#         ${WORKDIR}/result/binning/instrain_map/combined_mags.stb
# 输  出: ${WORKDIR}/result/binning/instrain_profile/{sample}/output/
#           {sample}_genome_info.tsv       — 基因组覆盖度/微多样性/popANI 统计
#           {sample}_scaffold_info.tsv     — scaffold 级详细统计
#           {sample}_SNVs.tsv              — SNV 位点表
#           {sample}_linkage.tsv           — SNV 连锁信息
#
# ── 说明 ──────────────────────────────────────────────────────────────────────
#   本步骤为 per-sample，产出该样本内的菌株级微多样性分析结果。
#   跨样本群体比较（popANI）由后续 39d_bac_instrain_compare.sh 完成。
#
# 参  考: Olm et al. 2021 Nat Biotechnol (inStrain)
# 用  法: bash 39c_bac_instrain_profile.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 39c_bac_instrain_profile.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

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
MAP_DIR="${WORKDIR}/result/binning/instrain_map"
BAM="${MAP_DIR}/${SAMPLE}/${SAMPLE}.sorted.bam"
COMBINED_FA="${MAP_DIR}/combined_mags.fa"
COMBINED_STB="${MAP_DIR}/combined_mags.stb"
OUTDIR="${WORKDIR}/result/binning/instrain_profile/${SAMPLE}"
OUTPUT_GENOME_INFO="${OUTDIR}/output/${SAMPLE}_genome_info.tsv"

if [ ! -f "${BAM}" ]; then
    echo "[ERROR] 比对 BAM 文件不存在: ${BAM}"; exit 1
fi

if [ ! -s "${BAM}" ]; then
    echo "[instrain_profile] WARNING: ${SAMPLE} BAM 为空哨兵（上游 MAGs 为 0），跳过"
    mkdir -p "${OUTDIR}/output"
    : > "${OUTPUT_GENOME_INFO}"
    exit 0
fi

if [ ! -f "${COMBINED_FA}" ] || [ ! -f "${COMBINED_STB}" ]; then
    echo "[ERROR] 合并参考或 stb 文件不存在: ${COMBINED_FA} / ${COMBINED_STB}"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_GENOME_INFO}" ] && [ -s "${OUTPUT_GENOME_INFO}" ]; then
    echo "[instrain_profile] ${SAMPLE} 结果已存在，跳过: ${OUTPUT_GENOME_INFO}"; exit 0
fi

mkdir -p "${OUTDIR}"

echo "[instrain_profile] ${SAMPLE} | 菌株微多样性分析 | 线程: ${CPUS}"
EXIT_CODE=0
mgx_try mgx_conda instrain inStrain profile \
        "${BAM}" \
        "${COMBINED_FA}" \
        -o "${OUTDIR}" \
        -s "${COMBINED_STB}" \
        -p "${CPUS}" \
        --pairing_filter all_reads || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] inStrain profile 失败"; exit ${EXIT_CODE}; fi

N_GENOMES=0
if [ -f "${OUTPUT_GENOME_INFO}" ]; then
    N_GENOMES=$(($(wc -l < "${OUTPUT_GENOME_INFO}") - 1))
fi

echo "[instrain_profile] ${SAMPLE} 分析了 ${N_GENOMES} 个基因组"
echo "[提示] 下一步: 运行 39d_bac_instrain_compare.sh 进行跨样本群体 ANI 比较"
mgx_end "instrain_profile"
