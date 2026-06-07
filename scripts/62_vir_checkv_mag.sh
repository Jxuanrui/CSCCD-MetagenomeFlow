#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 62_vir_checkv_mag.sh
# 功  能: vMAG 质量评估与过滤（CheckV per-bin）
#         工具版本：CheckV 1.0.3（conda env: checkv）
# 依  赖: 61_vir_vmag.sh 的 vMAG bins
# 输  入: ${WORKDIR}/result/virus/vmag/bins/vMAG/*.fasta
# 输  出: ${WORKDIR}/result/virus/vmag/checkv/
#           quality_summary.tsv       — 合并质量报告
#           {bin}/                    — 每个 vMAG 的 CheckV 结果
#           vmag_filtered/            — 高质量 vMAGs
#
# 参  考: Nayfach et al. 2021 Nat Biotechnol
# 用  法: bash 62_vir_checkv_mag.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() { cat << EOF
用法: bash 62_vir_checkv_mag.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; show_help; exit 1; fi
done

SECONDS=0
VMAGS_DIR="${WORKDIR}/result/virus/vmag/bins/vMAG"
CHKV_DIR="${WORKDIR}/result/virus/vmag/checkv"
SUMMARY="${CHKV_DIR}/quality_summary.tsv"
FILTERED_DIR="${WORKDIR}/result/virus/vmag/vmag_filtered"
CHK_DB="${REPO}/db/checkv"

if [ ! -d "${VMAGS_DIR}" ] || [ -z "$(ls "${VMAGS_DIR}"/*.fasta 2>/dev/null)" ]; then
    echo "[WARN] 无 vMAGs"; exit 0
fi

if [ -f "${SUMMARY}" ] && [ -s "${SUMMARY}" ]; then echo "[checkv_mag] 结果已存在，跳过"; exit 0; fi

mkdir -p "${CHKV_DIR}" "${FILTERED_DIR}"

echo "[checkv_mag] 批量 vMAG CheckV 评估 ..."
> "${SUMMARY}"
for fa in "${VMAGS_DIR}"/*.fasta; do
    bname=$(basename "$fa" .fasta)
    bin_out="${CHKV_DIR}/${bname}"
    mkdir -p "$bin_out"

    conda run --prefix "${REPO}/envs/checkv" --no-capture-output \
        checkv end_to_end \
            "$fa" \
            "$bin_out" \
            -d "${CHK_DB}" \
            -t "${CPUS}"

    if [ -f "${bin_out}/quality_summary.tsv" ]; then
        # 合并（去表头保留第一行表头）
        if [ ! -s "${SUMMARY}" ]; then
            head -1 "${bin_out}/quality_summary.tsv" > "${SUMMARY}"
        fi
        tail -n +2 "${bin_out}/quality_summary.tsv" >> "${SUMMARY}"
    fi
done

# 过滤高质量 vMAGs（complete / high-quality / medium-quality）
awk -F'\t' 'NR==1 || ($2!="Not-determined" && $2!="Low-quality")' "${SUMMARY}" > "${FILTERED_DIR}/quality_report.tsv"
awk -F'\t' 'NR>1 && $2!="Not-determined" && $2!="Low-quality" {print $1}' "${SUMMARY}" \
    | while read -r bin_name; do
        src="${VMAGS_DIR}/${bin_name}.fasta"
        [ -f "$src" ] && cp "$src" "${FILTERED_DIR}/"
    done

N_FILTERED=$(ls "${FILTERED_DIR}"/*.fasta 2>/dev/null | wc -l || echo 0)
echo "[checkv_mag] 完成，耗时 ${SECONDS}s | 过滤后 vMAGs: ${N_FILTERED}"
