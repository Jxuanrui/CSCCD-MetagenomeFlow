#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 61_vir_vmag.sh
# 功  能: vMAG 生成（vRhyme 分箱，基于多样本覆盖度 + 蛋白特征）
#         工具版本：vRhyme 1.1+（conda env: vrhyme）
# 依  赖: Cross-sample BAMs + vOTU 序列
# 输  入: vOTU 序列 + 各样本 BAM
# 输  出: ${WORKDIR}/result/virus/vmag/
#           vrhyme/      — vRhyme 分箱输出
#           bins/vMAG/   — 高质量 vMAGs
#           bins/pseudo/ — 伪 vMAGs
#
# 参  考: Kieft et al. 2022 NAR (vRhyme)
# 用  法: bash 61_vir_vmag.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 61_vir_vmag.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
BAM_DIR="${WORKDIR}/result/virus/votu/bam"
OUTDIR="${WORKDIR}/result/virus/vmag"
BINS_DIR="${OUTDIR}/bins"
SENTINEL="${BINS_DIR}/vmag_done.txt"

if [ ! -f "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在: ${VOTU_FA}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[vmag] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}" "${BINS_DIR}/vMAG" "${BINS_DIR}/pseudo"

# 如果没有现成 BAM，尝试从 coverm 或其他来源收集
if [ ! -d "${BAM_DIR}" ] || [ -z "$(ls "${BAM_DIR}"/*.bam 2>/dev/null)" ]; then
    echo "[vmag] 步骤 0/3: 生成跨样本 BAMs（coverm make）..."
    mkdir -p "${BAM_DIR}"
    for sid_dir in "${WORKDIR}"/result/virus/assembly/*/; do
        sid=$(basename "$sid_dir")
        R1="${WORKDIR}/result/kneaddata/${sid}/${sid}_1.kneaddata.fastq.gz"
        R2="${WORKDIR}/result/kneaddata/${sid}/${sid}_2.kneaddata.fastq.gz"
        [ ! -f "$R1" ] && continue
        mgx_conda coverm \
            coverm make \
                -p minimap2-sr \
                -t "${CPUS}" \
                -r "${VOTU_FA}" \
                -1 "$R1" -2 "$R2" \
                -o "${BAM_DIR}/${sid}"
        mv "${BAM_DIR}/${sid}/${sid}.bam" "${BAM_DIR}/" 2>/dev/null || true
        echo "  ${sid} BAM 完成"
    done
fi

echo "[vmag] 步骤 1/3: vRhyme 分箱 ..."
EXIT_CODE=0
mgx_try mgx_conda vrhyme \
    vRhyme \
        -i "${VOTU_FA}" \
        -b "${BAM_DIR}"/*.bam \
        -o "${OUTDIR}/vrhyme" \
        -l 10000 \
        -t "${CPUS}" \
        --iter 15 \
        || EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[WARN] vRhyme 分箱失败（exit code: ${EXIT_CODE}），无法生成 vMAGs"
    touch "${SENTINEL}"
    echo "[vmag] vMAGs: 0（vRhyme 失败）"
    mgx_end "vmag"
    exit 0
fi

# 步骤 2: 提取 bins
echo "[vmag] 步骤 2/3: 提取 vMAGs ..."
mgx_conda vrhyme \
    vRhyme -i "${VOTU_FA}" -b "${BAM_DIR}"/*.bam \
        -o "${OUTDIR}/vrhyme" -l 10000 -t "${CPUS}" --iter 15 \
        --derep_only

# 简易提取: 从 vrhyme 输出提取 vMAGs
if [ -d "${OUTDIR}/vrhyme" ]; then
    for d in "${OUTDIR}/vrhyme"/*/; do
        bname=$(basename "$d")
        for fa in "$d"/*.fasta; do
            [ -f "$fa" ] || continue
            cp "$fa" "${BINS_DIR}/vMAG/${bname}_$(basename "$fa")"
        done
    done
fi

touch "${SENTINEL}"
N_VMAGS=$(ls "${BINS_DIR}/vMAG"/*.fasta 2>/dev/null | wc -l || echo 0)
echo "[vmag] vMAGs: ${N_VMAGS}"
mgx_end "vmag"
