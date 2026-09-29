#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 39b_bac_instrain_map.sh
# 功  能: 样本 reads 比对到去冗余 MAG 集，生成菌株追踪（inStrain）所需 BAM
#         工具版本：CoverM 0.7+（minimap2-sr，conda env: coverm）
# 依  赖: 38_bac_drep.sh 的输出（dereplicated_genomes/*.fa）
# 输  入: ${WORKDIR}/result/binning/drep/dereplicated_genomes/*.fa
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/binning/instrain_map/
#           combined_mags.fa            — 全部去冗余 MAG 拼接为单一参考（跨样本共享，只构建一次）
#           combined_mags.stb           — scaffold-to-bin 映射（跨样本共享，parse_stb.py 生成）
#           {sample}/{sample}.sorted.bam — 该样本比对到 combined_mags.fa 的排序 BAM
#
# ── 说明 ──────────────────────────────────────────────────────────────────────
#   combined_mags.fa/combined_mags.stb 由多个样本的 Snakemake 任务并行触发，
#   用 mkdir 原子锁避免重复构建；已存在时直接复用。
#
# 参  考: Olm et al. 2021 Nat Biotechnol (inStrain); CoverM docs
# 用  法: bash 39b_bac_instrain_map.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 39b_bac_instrain_map.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

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
MAGS_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
BASE_DIR="${WORKDIR}/result/binning/instrain_map"
COMBINED_FA="${BASE_DIR}/combined_mags.fa"
COMBINED_STB="${BASE_DIR}/combined_mags.stb"
LOCK_DIR="${BASE_DIR}/.combined_ref.lock"
OUTDIR="${BASE_DIR}/${SAMPLE}"
BAM="${OUTDIR}/${SAMPLE}.sorted.bam"
R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

if [ ! -f "${R1}" ] || [ ! -f "${R2}" ]; then
    echo "[ERROR] 质控 reads 不存在: ${R1} / ${R2}"; exit 1
fi

mkdir -p "${BASE_DIR}" "${OUTDIR}"

N_MAGS=0
if [ -d "${MAGS_DIR}" ]; then
    N_MAGS=$(find "${MAGS_DIR}" -maxdepth 1 -type f -name "*.fa" | wc -l)
fi
if [ "${N_MAGS}" -eq 0 ]; then
    echo "[instrain_map] WARNING: 去冗余 MAGs 为 0，创建空结果哨兵: ${BAM}"
    : > "${BAM}"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${BAM}" ] && [ -s "${BAM}" ]; then
    echo "[instrain_map] ${SAMPLE} 结果已存在，跳过: ${BAM}"; exit 0
fi

# 若 dRep 产出比合并参考更新（重新分箱/重新去冗余），需要重建，避免 BAM 用陈旧 scaffold 体系比对
COMBINED_STALE=0
if [ -f "${COMBINED_FA}" ] && [ -s "${COMBINED_FA}" ]; then
    for FA in "${MAGS_DIR}"/*.fa; do
        [ -f "${FA}" ] || continue
        if [ "${FA}" -nt "${COMBINED_FA}" ]; then COMBINED_STALE=1; break; fi
    done
fi

# ── 构建跨样本共享的合并参考 + .stb（并行样本竞争，用 mkdir 原子锁）──────────────
if [ ${FORCE} -eq 1 ] || [ ${COMBINED_STALE} -eq 1 ] || [ ! -f "${COMBINED_FA}" ] || [ ! -s "${COMBINED_FA}" ] || [ ! -f "${COMBINED_STB}" ] || [ ! -s "${COMBINED_STB}" ]; then
    RETRY=0
    while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
        if [ ${COMBINED_STALE} -eq 0 ] && [ -f "${COMBINED_FA}" ] && [ -s "${COMBINED_FA}" ] && [ -f "${COMBINED_STB}" ] && [ -s "${COMBINED_STB}" ]; then
            break
        fi
        RETRY=$((RETRY + 1))
        if [ ${RETRY} -gt 600 ]; then
            echo "[ERROR] 等待其他样本构建 combined_mags.fa/.stb 超时"; exit 1
        fi
        sleep 2
    done

    if [ ${COMBINED_STALE} -eq 1 ] || [ ! -f "${COMBINED_FA}" ] || [ ! -s "${COMBINED_FA}" ] || [ ! -f "${COMBINED_STB}" ] || [ ! -s "${COMBINED_STB}" ]; then
        echo "[instrain_map] 构建合并参考 combined_mags.fa（${N_MAGS} 个去冗余 MAG）..."
        # 为每个 MAG 的 scaffold 添加唯一前缀（避免重复）
        # 并移除 FASTA header 中的额外信息（只保留 scaffold ID，避免 BAM/FASTA 不匹配）
        : > "${COMBINED_FA}.tmp"
        : > "${COMBINED_STB}.tmp"
        for FA in "${MAGS_DIR}"/*.fa; do
            MAG_NAME=$(basename "${FA}" .fa)
            # 修改 FASTA header：>scaffold flag=0 multi=X len=Y → >MAG_NAME__scaffold（只保留ID）
            awk -v mag="${MAG_NAME}" '/^>/ {split($1, a, ">"); print ">" mag "__" a[2]; next} {print}' "${FA}" >> "${COMBINED_FA}.tmp"
            # 手动构建 .stb：scaffold\tMAG_NAME
            grep "^>" "${FA}" | sed 's/^>//' | cut -d' ' -f1 | sed "s/^/${MAG_NAME}__/" | awk -v mag="${MAG_NAME}" '{print $1 "\t" mag}' >> "${COMBINED_STB}.tmp"
        done
        mv "${COMBINED_FA}.tmp" "${COMBINED_FA}"
        mv "${COMBINED_STB}.tmp" "${COMBINED_STB}"
    fi

    if [ -d "${LOCK_DIR}" ]; then rmdir "${LOCK_DIR}" 2>/dev/null || true; fi
fi

echo "[instrain_map] ${SAMPLE} | 比对到合并 MAG 参考 | 线程: ${CPUS}"
EXIT_CODE=0
mgx_try mgx_conda coverm coverm make \
        -p minimap2-sr \
        -t "${CPUS}" \
        -r "${COMBINED_FA}" \
        -1 "${R1}" -2 "${R2}" \
        -o "${OUTDIR}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] coverm make 失败"; exit ${EXIT_CODE}; fi

GENERATED_BAM=$(find "${OUTDIR}" -maxdepth 1 -name "*.bam" 2>/dev/null | head -1)
if [ -z "${GENERATED_BAM}" ]; then
    echo "[ERROR] coverm make 未生成 BAM 文件: ${OUTDIR}"; exit 1
fi
if [ "${GENERATED_BAM}" != "${BAM}" ]; then
    mv "${GENERATED_BAM}" "${BAM}"
fi

echo "[instrain_map] ${SAMPLE} | 索引 BAM（inStrain profile 需要）..."
EXIT_CODE=0
mgx_try mgx_conda coverm samtools index -@ "${CPUS}" "${BAM}" || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] samtools index 失败"; exit ${EXIT_CODE}; fi

echo "[instrain_map] ${SAMPLE} 完成 | 输出: ${BAM}"
echo "[提示] 下一步: 运行 39c_bac_instrain_profile.sh 进行菌株微多样性分析"
mgx_end "instrain_map"
