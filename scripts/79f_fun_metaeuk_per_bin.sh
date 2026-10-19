#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79f_fun_metaeuk_per_bin.sh
# 功  能: 对 79e MetaBAT2 产出的每个真核候选 bin 独立预测蛋白编码基因
#         （79b/79e 的 BUSCO 只做完整度评估，marker 片段 .faa 不是完整蛋白集；
#         细菌 MAG 有 Prokka 全蛋白预测，病毒 vOTU 有 pharokka/prodigal，
#         本脚本补齐真菌侧缺口，供后续跨域正交基因组检测 98f 使用）
#         MetaEuk 1.x（conda env: metaeuk，MIT 许可），复用已部署的
#         db/metaeuk_db/fungi_refseq_mmseqs 数据库
#         VEBA (https://github.com/jolespin/veba) binning-eukaryotic 模块方法参考，
#         不拷贝 VEBA 源码
# 依  赖: 79e_fun_euk_qc_per_bin.sh 的输出（euk_mags/bin.*.fa）
# 输  入: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/euk_mags/bin.*.fa
# 输  出: ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/euk_mags/{bin_id}/
#           {bin_id}.faa   — MetaEuk 预测蛋白序列（下游注释/正交基因组检测兼容）
#           {bin_id}.fas / {bin_id}.codon.fas — MetaEuk 原始蛋白/CDS 输出
#         ${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/euk_mags/${SAMPLE}.metaeuk_done.txt
#           — 汇总 sentinel（0个bin时也会写出，空表示合法结果）
# 用  法: bash 79f_fun_metaeuk_per_bin.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 79f_fun_metaeuk_per_bin.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --db     MetaEuk 数据库前缀 [默认: {REPO}/db/metaeuk_db/fungi_refseq_mmseqs]
  --force  强制重新运行（忽略已存在的结果）

EOF
}

DB=""

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="db:DB"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin
REPO="$(readlink -f "${REPO}")"
WORKDIR="$(readlink -f "${WORKDIR}")"
DB="${DB:-${REPO}/db/metaeuk_db/fungi_refseq_mmseqs}"
EUK_MAGS_DIR="${WORKDIR}/result/fungi/veba_qc/${SAMPLE}/euk_mags"
SENTINEL="${EUK_MAGS_DIR}/${SAMPLE}.metaeuk_done.txt"

mapfile -t BIN_FILES < <(find "${EUK_MAGS_DIR}" -maxdepth 1 -name 'bin.*.fa' 2>/dev/null | sort)
if [ "${#BIN_FILES[@]}" -eq 0 ]; then
    mkdir -p "${EUK_MAGS_DIR}"
    echo -e "bin_id\tfaa_path\tn_proteins" > "${SENTINEL}"
    echo "[metaeuk_per_bin] ${SAMPLE} 无候选 bin（预期行为），跳过蛋白预测"
    exit 0
fi

if [ ! -e "${DB}.dbtype" ]; then
    echo "[ERROR] MetaEuk 数据库不存在: ${DB}"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[metaeuk_per_bin] 结果已存在，跳过: ${SENTINEL}"
    exit 0
fi

echo -e "bin_id\tfaa_path\tn_proteins" > "${SENTINEL}"

for BIN_FA in "${BIN_FILES[@]}"; do
    BIN_ID=$(basename "${BIN_FA}" .fa)
    BIN_OUTDIR="${EUK_MAGS_DIR}/${BIN_ID}"
    mkdir -p "${BIN_OUTDIR}"
    OUT_PREFIX="${BIN_OUTDIR}/${BIN_ID}"
    FAS="${OUT_PREFIX}.fas"
    FAA="${OUT_PREFIX}.faa"
    TMP_DIR="${BIN_OUTDIR}/tmp_${BIN_ID}"

    if [ ${FORCE} -eq 0 ] && [ -f "${FAA}" ] && [ -s "${FAA}" ]; then
        N_PROT=$(grep -c "^>" "${FAA}" || echo 0)
        echo -e "${BIN_ID}\t${FAA}\t${N_PROT}" >> "${SENTINEL}"
        echo "[metaeuk_per_bin] ${BIN_ID} 已存在，跳过"
        continue
    fi

    echo "[metaeuk_per_bin] ${SAMPLE} | ${BIN_ID} | MetaEuk 蛋白预测 ..."
    EXIT_CODE=0
    mgx_try mgx_conda metaeuk \
        metaeuk easy-predict \
            "${BIN_FA}" \
            "${DB}" \
            "${OUT_PREFIX}" \
            "${TMP_DIR}" \
            --threads "${CPUS}" \
            -s 7.5 \
            --min-length 100 \
            --translation-table 1 \
            || EXIT_CODE=$?

    if [ ${EXIT_CODE} -ne 0 ] || [ ! -s "${FAS}" ]; then
        echo "[metaeuk_per_bin] ${BIN_ID}: MetaEuk 失败或无蛋白输出（exit ${EXIT_CODE}），记为 0 蛋白，不中断其他 bin"
        rm -rf "${TMP_DIR}"
        echo -e "${BIN_ID}\tNA\t0" >> "${SENTINEL}"
        continue
    fi

    cp -f "${FAS}" "${FAA}"
    rm -rf "${TMP_DIR}"
    N_PROT=$(grep -c "^>" "${FAA}" || echo 0)
    echo -e "${BIN_ID}\t${FAA}\t${N_PROT}" >> "${SENTINEL}"
done

echo "[metaeuk_per_bin] ${SAMPLE} 完成 | bins 处理数: ${#BIN_FILES[@]}"
echo "[metaeuk_per_bin] 汇总: ${SENTINEL}"
mgx_end "metaeuk_per_bin"
