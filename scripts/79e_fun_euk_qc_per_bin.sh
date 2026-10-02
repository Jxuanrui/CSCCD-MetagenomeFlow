#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79e_fun_euk_qc_per_bin.sh
# 功  能: 对 79d MetaBAT2 产出的每个真核候选 bin 独立评估 BUSCO 谱系完整度
#         （79b 是对全候选序列集合整体评估，本脚本是逐 bin 评估，粒度对齐
#         dRep 细菌 MAG 的"一个基因组一个文件"标准，供后续跨域 cluster 模块使用）
#         VEBA (https://github.com/jolespin/veba) binning-eukaryotic 模块方法参考，
#         不拷贝 VEBA 源码；BUSCO 6.1.0（conda env: busco，MIT 许可）
# 依  赖: 79d_fun_metabat2.sh 的输出（bin.*.fa）
# 输  入: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/metabat2/bin.*.fa
# 输  出: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/euk_mags/
#           bin.{n}.fa            — 逐 bin MAG（从 metabat2/ 拷贝，独立目录便于下游引用）
#           bin.{n}.busco/        — 该 bin 的 BUSCO 原始输出
#           ${SAMPLE}.euk_mags_summary.tsv — 每行一个 bin 的完整度/重复度/缺失
# 用  法: bash 79e_fun_euk_qc_per_bin.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 79e_fun_euk_qc_per_bin.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
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
REPO="$(readlink -f "${REPO}")"
WORKDIR="$(readlink -f "${WORKDIR}")"
METABAT_DIR="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/metabat2"
OUTDIR="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/euk_mags"
SUMMARY="${OUTDIR}/${SAMPLE}.euk_mags_summary.tsv"
# 项目级共享 lineage 缓存目录（多bin/多样本共用，避免重复下载相同数据集）
BUSCO_DOWNLOAD_PATH="${REPO}/db/busco_downloads"
mkdir -p "${BUSCO_DOWNLOAD_PATH}"

# 79d 可能因上游全链路空结果而产出 0 个 bin（合法结果，非错误）
mapfile -t BIN_FILES < <(find "${METABAT_DIR}" -maxdepth 1 -name 'bin.*.fa' 2>/dev/null | sort)
if [ "${#BIN_FILES[@]}" -eq 0 ]; then
    mkdir -p "${OUTDIR}"
    echo -e "sample\tbin_id\tlineage\tcomplete_pct\tduplicated_pct\tmissing_pct\tn_contigs\tsize_bp" > "${SUMMARY}"
    echo "[euk_qc_per_bin] 79d 无 bin 产出（预期行为），跳过逐 bin BUSCO"
    echo "[euk_qc_per_bin] ${SAMPLE} 完成，耗时 ${SECONDS}s"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SUMMARY}" ] && [ -s "${SUMMARY}" ]; then
    echo "[euk_qc_per_bin] 结果已存在，跳过: ${SUMMARY}"
    exit 0
fi

mkdir -p "${OUTDIR}"
echo -e "sample\tbin_id\tlineage\tcomplete_pct\tduplicated_pct\tmissing_pct\tn_contigs\tsize_bp" > "${SUMMARY}"

for BIN_FA in "${BIN_FILES[@]}"; do
    BIN_ID=$(basename "${BIN_FA}" .fa)
    LOCAL_FA="${OUTDIR}/${BIN_ID}.fa"
    cp -f "${BIN_FA}" "${LOCAL_FA}"

    N_CONTIGS=$(grep -c "^>" "${LOCAL_FA}" || echo 0)
    SIZE_BP=$(mgx_conda assembly \
        seqkit stats -T "${LOCAL_FA}" | tail -n1 | cut -f5)

    echo "[euk_qc_per_bin] ${SAMPLE} | ${BIN_ID} | BUSCO 评估 (${N_CONTIGS} contigs, ${SIZE_BP} bp) ..."
    BUSCO_OUT="${BIN_ID}.busco"
    BUSCO_EXIT=0
    (
        cd "${OUTDIR}"
        mgx_conda busco \
            busco -i "${LOCAL_FA}" -o "${BUSCO_OUT}" \
                  -m genome --auto-lineage-euk -c "${CPUS}" -f \
                  --download_path "${BUSCO_DOWNLOAD_PATH}"
    ) || BUSCO_EXIT=$?

    BUSCO_SUMMARY_FILE=$(find "${OUTDIR}/${BUSCO_OUT}" -maxdepth 1 -name "short_summary.*.txt" 2>/dev/null | head -n 1)

    if [ ${BUSCO_EXIT} -ne 0 ] || [ -z "${BUSCO_SUMMARY_FILE}" ]; then
        echo "[euk_qc_per_bin] ${BIN_ID}: BUSCO 评估失败/无结果，记为 NA（不中断其他 bin 处理）"
        echo -e "${SAMPLE}\t${BIN_ID}\tNA\tNA\tNA\tNA\t${N_CONTIGS}\t${SIZE_BP}" >> "${SUMMARY}"
        continue
    fi

    COMPLETE=$(grep -oP '(?<=C:)[0-9.]+(?=%)' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")
    DUPLICATED=$(grep -oP '(?<=D:)[0-9.]+(?=%)' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")
    MISSING=$(grep -oP '(?<=M:)[0-9.]+(?=%)' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")
    LINEAGE=$(grep -oP '(?<=lineage dataset is: ).*(?= \()' "${BUSCO_SUMMARY_FILE}" | head -n1 || echo "NA")

    echo -e "${SAMPLE}\t${BIN_ID}\t${LINEAGE}\t${COMPLETE}\t${DUPLICATED}\t${MISSING}\t${N_CONTIGS}\t${SIZE_BP}" >> "${SUMMARY}"
done

echo "[euk_qc_per_bin] ${SAMPLE} 完成 | bins 评估数: ${#BIN_FILES[@]}"
echo "[euk_qc_per_bin] 质量摘要: ${SUMMARY}"
mgx_end "euk_qc_per_bin"
