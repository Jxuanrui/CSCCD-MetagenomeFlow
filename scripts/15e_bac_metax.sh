#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 15e_bac_metax.sh
# 功  能: MetaX 跨域统一分类（coverage-informed 覆盖度建模 + EM 丰度细化）
#         一次运行同时分类 细菌/古菌/真核/病毒/宿主，并用 OEBR/COEBR 覆盖度
#         比值过滤 reference 污染、同源误配与试剂组 DNA（kitome）伪阳性。
#         工具版本：MetaX 0.9.22（conda env: metax）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/metax/${SAMPLE}/
#           ${SAMPLE}.profile.txt    — 最终分类丰度（13 列，含覆盖度/presence 似然）
#           ${SAMPLE}.classify.txt   — 每条 read 分类（大文件；分数索引下不产出）
#           ${SAMPLE}.log            — 运行日志
#           ${SAMPLE}.sam.gz         — 压缩比对中间文件（-z 压缩；--reuse-sam 可复用）
#                                      注意：不加 -z 时该 SAM 未压缩，约 33 GB/样本
#           ${SAMPLE}.readfrac.tsv   — 读段占比派生表（taxon/reads/read_fraction_pct），
#                                      由 profile 第 4 列派生，用于与 MetaPhlAn4/Kraken2 直接比较
#
# ── 定位说明 ──────────────────────────────────────────────────────────────────
#
#   与现有单域工具并列、互补而非替代：
#   - MetaPhlAn4(11)/Centrifuger(15)：细菌单域精确分类
#   - Kraken2(14)：k-mer 快速分类
#   - geNomad(52)/CheckV(54)/iPHoP(68)：病毒专用
#   本脚本作为**跨域综合验证层**：单次运行给出跨界的统一覆盖度证据，用于
#   与上述单域结果交叉验证，尤其适合低深度/宿主污染样本的伪阳性排查。
#   默认不入 Snakemake rule all（内存较高、性质为验证），按需 -R 触发。
#
# ── 数据库说明 ────────────────────────────────────────────────────────────────
#
#   预构建参考库（RefSeq 2022-08-10，33,143 基因组；细菌/古菌/病毒/真菌/原生动物/人）：
#     ${REPO}/db/metax/  （metax_db.json + 索引；见 MANUAL 解压布局）
#   NCBI taxonomy dump（nodes.dmp/names.dmp/merged.dmp）：
#     ${REPO}/db/metax/taxonomy/
#
# 参  考: Deng, Safaei & McHardy, bioRxiv 2025 (MetaX)
#         https://github.com/hzi-bifo/Metax
# 用  法: bash 15e_bac_metax.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--force] [--mode default|recall|precision]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 15e_bac_metax.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -s  样本名（不含后缀，如 SRR28210342）
  -t  线程数（推荐 16-32）
  -w  工作目录（绝对路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --mode  证据预设：default（推荐）/ recall（高灵敏）/ precision（高特异）
  --force 强制重新运行（忽略已存在的结果）
  -h      显示帮助
EOF
}

MODE="default"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="mode:MODE"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

case "${MODE}" in
    default|recall|precision) ;;
    *) echo "[ERROR] --mode 必须为 default/recall/precision，收到: ${MODE}"; exit 1 ;;
esac

mgx_begin

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

RESULT_DIR="${WORKDIR}/result/metax/${SAMPLE}"
OUT_PREFIX="${RESULT_DIR}/${SAMPLE}"
PROFILE_OUT="${OUT_PREFIX}.profile.txt"

METAX_ENV="${REPO}/envs/metax"
METAX_BIN="${METAX_ENV}/bin/metax"
METAX_DB_ROOT="${REPO}/db/metax"
DMP_DIR="${METAX_DB_ROOT}/taxonomy"

if [ ! -f "${INPUT_R1}" ] || [ ! -f "${INPUT_R2}" ]; then
    echo "[ERROR] 输入文件不存在，请先运行 02_qc_kneaddata.sh:"
    echo "        ${INPUT_R1}"
    echo "        ${INPUT_R2}"
    exit 1
fi

if [ ! -x "${METAX_BIN}" ]; then
    echo "[ERROR] MetaX 未安装: ${METAX_BIN}"
    echo "        安装: conda create -y -p ${METAX_ENV} -c zldeng -c bioconda metax=0.9.22 ma=1.1.4"
    exit 1
fi

METAX_DB_JSON="$(find "${METAX_DB_ROOT}" -maxdepth 3 -name 'metax_db.json' -type f 2>/dev/null | head -1)"
if [ -z "${METAX_DB_JSON}" ]; then
    echo "[ERROR] MetaX 数据库未找到（metax_db.json）: ${METAX_DB_ROOT}"
    echo "        下载: curl -L -o metax_db.tar.xz https://research.bifo.helmholtz-hzi.de/downloads/metax/metax_db.tar.xz"
    exit 1
fi

if [ ! -f "${DMP_DIR}/nodes.dmp" ] || [ ! -f "${DMP_DIR}/names.dmp" ]; then
    echo "[ERROR] taxonomy dump 不全: ${DMP_DIR}（需 nodes.dmp + names.dmp + merged.dmp）"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -s "${PROFILE_OUT}" ]; then
    echo "[INFO] 输出已存在，跳过: ${SAMPLE}（--force 可强制重跑）"
    echo "       ${PROFILE_OUT}"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

echo "[metax] 样本: ${SAMPLE}"
echo "[metax] 输入: ${INPUT_R1}"
echo "[metax]       ${INPUT_R2}"
echo "[metax] 数据库: ${METAX_DB_JSON}"
echo "[metax] taxonomy: ${DMP_DIR}"
echo "[metax] 模式: ${MODE} | 线程: ${CPUS}"

EXIT_CODE=0
mgx_try mgx_conda metax \
    metax profile \
        --db "${METAX_DB_JSON}" \
        --dmp-dir "${DMP_DIR}" \
        -i "${INPUT_R1},${INPUT_R2}" \
        -p \
        -z \
        --sequencer Illumina \
        --mode "${MODE}" \
        -o "${OUT_PREFIX}" \
        -t "${CPUS}" \
        || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] metax profile 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -s "${PROFILE_OUT}" ]; then
    echo "[ERROR] 未生成 profile 文件: ${PROFILE_OUT}"
    exit 1
fi

READFRAC_OUT="${OUT_PREFIX}.readfrac.tsv"
awk -F'\t' 'BEGIN{OFS="\t"; print "taxon","reads","read_fraction_pct"}
    {r=$4+0; tot+=r; n[NR]=$1; v[NR]=r}
    END{for(i=1;i<=NR;i++) printf "%s\t%.0f\t%.4f\n", n[i], v[i], (tot>0? v[i]/tot*100 : 0)}
' "${PROFILE_OUT}" > "${READFRAC_OUT}"

echo ""
echo "[metax] ${SAMPLE} 完成"
echo "[metax] 检出分类单元数: $(wc -l < "${PROFILE_OUT}")"
echo "[metax] 结果目录: ${RESULT_DIR}"
echo "[metax] Profile:  ${PROFILE_OUT}"
mgx_end "metax"
