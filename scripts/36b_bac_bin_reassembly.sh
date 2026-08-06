#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 36b_bac_bin_reassembly.sh
# 功  能: Post-binning reassembly（用原始 reads 对每个 bin 重新精细组装以提升质量）
#         工具版本：metaWRAP reassemble_bins（conda env: metawrap）
# 依  赖: 36_bac_dastool.sh 的 bins + 02_qc_kneaddata.sh 的 clean reads
# 输  入: ${WORKDIR}/result/binning/dastool/{sample}/{sample}_DASTool_bins/*.fa
#         ${WORKDIR}/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz (+_2)
# 输  出: ${WORKDIR}/result/binning/reassembly/{sample}/reassembled_bins/*.fa
#           — 重组装成功的 bin 用重组装结果；重组装失败的 bin 回退为原始 bin
#             （确保输出集合与输入 bin 集合一一对应，供 37_checkm2 统一重新评估）
#
# ── 说明 ──────────────────────────────────────────────────────────────────────
#   本步骤跳过 metaWRAP 内建的 CheckM(1.x) 评估与"最优bin"筛选（--skip-checkm），
#   因为项目下游 37_bac_checkm2.sh 已用 CheckM2 对全部 bin 统一质控，无需在此
#   重复跑一次旧版 CheckM；本脚本产出全部交给 37 重新评估筛选。
#
# 参  考: Uritskiy et al. 2018 Microbiome (metaWRAP)
# 用  法: bash 36b_bac_bin_reassembly.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

show_help() { cat << EOF
用法: bash 36b_bac_bin_reassembly.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
可选参数:
  -m  内存上限 GB（默认: 64）
  --parallel  多个 bin 的 SPAdes 组装并行跑（各用 1 线程），bin 数多时大幅提速；
              内存有限时不建议开启（多个 SPAdes 进程同时占用内存）
  --force  强制重新运行（忽略已存在的结果）
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""; MEM=64
FORCE=0
PARALLEL_FLAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -m) MEM="$2";     shift 2 ;;
        --parallel) PARALLEL_FLAG="--parallel"; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
BINS_DIR="${WORKDIR}/result/binning/dastool/${SAMPLE}/${SAMPLE}_DASTool_bins"
READS_1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
READS_2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/binning/reassembly/${SAMPLE}"
FINAL_DIR="${OUTDIR}/reassembled_bins"
SENTINEL="${OUTDIR}/${SAMPLE}.reassembly_done.txt"
MW_WORKDIR="${OUTDIR}/metawrap_work"

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[bin_reassembly] 结果已存在，跳过: ${SENTINEL}"
    exit 0
fi

if [ ! -d "${BINS_DIR}" ] || [ -z "$(ls -A "${BINS_DIR}"/*.fa 2>/dev/null)" ]; then
    echo "[bin_reassembly] WARNING: 样本 ${SAMPLE} 无 DAS_Tool bins，写空 sentinel"
    mkdir -p "${FINAL_DIR}"
    : > "${SENTINEL}"
    exit 0
fi

if [ ! -f "${READS_1}" ] || [ ! -f "${READS_2}" ]; then
    echo "[ERROR] Clean reads 不存在: ${READS_1} / ${READS_2}"
    exit 1
fi

N_INPUT_BINS=$(ls "${BINS_DIR}"/*.fa | wc -l)
echo "[bin_reassembly] 样本 ${SAMPLE} | 输入 bins: ${N_INPUT_BINS} | 线程: ${CPUS} | 内存: ${MEM}GB"

# MEGAHIT contig header 形如 ">k127_32323 flag=0 multi=144.1171 len=63675"，
# metaWRAP 内部的 filter_reads_for_bin_reassembly.py 按整行（含空格后字段）建立
# contig→bin 映射，但 SAM 的 RNAME 字段只取第一个空格前的 token，两者不匹配会
# 导致全部 reads 在拆分阶段被丢弃（reads_for_reassembly/ 产出为空、进而所有 bin
# 重组装失败）。这里在喂给 metaWRAP 前，用简化 header（仅保留第一个 token）的
# 临时拷贝规避此问题，不影响原始 bin 文件。
BINS_CLEAN_DIR="${OUTDIR}/bins_clean_header"
rm -rf "${BINS_CLEAN_DIR}"
mkdir -p "${BINS_CLEAN_DIR}"
for bin_fa in "${BINS_DIR}"/*.fa; do
    sed 's/^>\([^ ]*\).*/>\1/' "${bin_fa}" > "${BINS_CLEAN_DIR}/$(basename "${bin_fa}")"
done

# 注: 不清空已存在的 MW_WORKDIR——metaWRAP reassemble_bins 内部自带续跑逻辑
# （已建好索引/已产出 scaffolds.fasta 的 bin 会跳过），中途中断（如超时）后
# 直接重跑本脚本即可从断点继续，无需从零开始
mkdir -p "${OUTDIR}" "${MW_WORKDIR}"
set +e
conda run --prefix "${REPO}/envs/metawrap" --no-capture-output \
    metaWRAP reassemble_bins \
        -b "${BINS_CLEAN_DIR}" \
        -o "${MW_WORKDIR}" \
        -1 "${READS_1}" \
        -2 "${READS_2}" \
        -t "${CPUS}" \
        -m "${MEM}" \
        --skip-checkm ${PARALLEL_FLAG}

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] metaWRAP reassemble_bins 失败 (sample=${SAMPLE})"
    exit ${EXIT_CODE}
fi

# --skip-checkm 模式下 metaWRAP 跳过内部"最优bin挑选"环节（该环节本身依赖CheckM
# comp/cont 分数），reassembled_bins/ 下只会保留未合并的 {bin_name}.strict.fa /
# {bin_name}.permissive.fa 两个变体，不会产出 {bin_name}.fa。这里手动在两个变体
# 间选择：以组装总长度（bp）作为无CheckM场景下的替代判定指标——总长度越接近或
# 超过原始bin，说明重组装填补的gap越多；两者都不存在才回退原始bin。
mkdir -p "${FINAL_DIR}"
N_REASSEMBLED=0
N_FALLBACK=0
for bin_fa in "${BINS_DIR}"/*.fa; do
    bin_name="$(basename "${bin_fa}" .fa)"
    strict="${MW_WORKDIR}/reassembled_bins/${bin_name}.strict.fa"
    permissive="${MW_WORKDIR}/reassembled_bins/${bin_name}.permissive.fa"
    best=""
    if [ -s "${strict}" ] && [ -s "${permissive}" ]; then
        len_s=$(grep -v '^>' "${strict}" | tr -d '\n' | wc -c)
        len_p=$(grep -v '^>' "${permissive}" | tr -d '\n' | wc -c)
        if [ "${len_s}" -ge "${len_p}" ]; then best="${strict}"; else best="${permissive}"; fi
    elif [ -s "${strict}" ]; then
        best="${strict}"
    elif [ -s "${permissive}" ]; then
        best="${permissive}"
    fi
    if [ -n "${best}" ]; then
        cp "${best}" "${FINAL_DIR}/${bin_name}.fa"
        N_REASSEMBLED=$((N_REASSEMBLED+1))
    else
        cp "${bin_fa}" "${FINAL_DIR}/${bin_name}.fa"
        N_FALLBACK=$((N_FALLBACK+1))
    fi
done

# 清理中间文件（组装临时目录体量大，成功产出已复制到 reassembled_bins，无需保留）
rm -rf "${MW_WORKDIR}" "${BINS_CLEAN_DIR}"

echo "N_INPUT_BINS=${N_INPUT_BINS}" > "${SENTINEL}"
echo "N_REASSEMBLED=${N_REASSEMBLED}" >> "${SENTINEL}"
echo "N_FALLBACK_TO_ORIGINAL=${N_FALLBACK}" >> "${SENTINEL}"

echo "[bin_reassembly] 完成，耗时 ${SECONDS}s | 输入: ${N_INPUT_BINS} | 重组装成功: ${N_REASSEMBLED} | 回退原始bin: ${N_FALLBACK}"
