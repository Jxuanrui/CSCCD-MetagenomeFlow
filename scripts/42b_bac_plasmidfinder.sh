#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 42b_bac_plasmidfinder.sh
# 功  能: 质粒识别与分类（PlasmidFinder 2.1.6，基于质粒复制子序列比对）
#         识别组装 contig 中的质粒起源，覆盖 Enterobacteriaceae/Gram+ 等主要菌群
#         补充 42_bac_mge.sh 的质粒维度（MGE 完整链路）
#
# 依  赖: 16_bac_megahit.sh 的输出（组装 contig）
# 输  入: ${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/mge/plasmidfinder/${SAMPLE}/
#           results_tab.tsv      — 质粒命中结果（制表符分隔，含 replicon 类型）
#           Hit_in_genome_seq.fsa— 命中的 contig 序列
#
# ── 工具说明 ──────────────────────────────────────────────────────────────────
#   PlasmidFinder 2.1.6（conda env: plasmidfinder）
#   DB：conda 包内置（share/plasmidfinder-2.1.6/database/，无需单独配置）
#   方法：blastn vs 质粒复制子序列库（enterobacteriaceae + gram_positive 两库）
#   阈值：覆盖度 ≥60%（-l），相似度 ≥95%（-t）—— PlasmidFinder 官方推荐
#
# ── 与 mobileOG 的关系 ────────────────────────────────────────────────────────
#   mobileOG（42_bac_mge.sh 内）对所有 MGE 做基因层面分类，含质粒基因
#   PlasmidFinder 在 contig 层面识别完整质粒，给出 replicon 类型和不相容群
#   两者互补：mobileOG 知道哪些基因来自质粒，PlasmidFinder 知道质粒是什么类型
#
# 参  考: Carattoli et al. 2014 AAC; Roer et al. 2017 AAC
#         https://bitbucket.org/genomicepidemiology/plasmidfinder
# 用  法: bash 42b_bac_plasmidfinder.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 42b_bac_plasmidfinder.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名称
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  -l  最低覆盖度（默认 0.60，即 60%）
  -T  序列相似度阈值（默认 0.95，即 95%）

示例:
  bash scripts/42b_bac_plasmidfinder.sh -s S01 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO l:MIN_COV T:THRESHOLD"
export MGX_OPTS_FLAG="force"
MIN_COV="0.60"
THRESHOLD="0.95"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
RESULT_DIR="${WORKDIR}/result/mge/plasmidfinder/${SAMPLE}"
TMP_DIR="${WORKDIR}/temp/plasmidfinder/${SAMPLE}"
SENTINEL="${RESULT_DIR}/results_tab.tsv"

if [ ! -f "${CONTIGS}" ] || [ ! -s "${CONTIGS}" ]; then
    echo "[ERROR] Contig 文件不存在: ${CONTIGS}"
    echo "        请先运行 16_bac_megahit.sh"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[INFO] PlasmidFinder 结果已存在，跳过: ${SENTINEL}"; exit 0
fi

mkdir -p "${RESULT_DIR}" "${TMP_DIR}"

# 获取 conda env 中 PlasmidFinder 内置 DB 路径
# PlasmidFinder 是脚本式安装（非可导入 Python 包），此 import 必然失败；
# 加 `|| true` 避免 set -e 在这个预期失败的探测尝试上提前终止脚本，
# 交由下方 find 兜底逻辑定位真实数据库路径
# 注: 探测调用无 --no-capture-output（仅取 stdout），保留原 conda run 形式
DB_PATH=$(conda run --prefix "${REPO}/envs/plasmidfinder" \
    python -c "import os, plasmidfinder; \
    print(os.path.join(os.path.dirname(plasmidfinder.__file__), 'database'))" 2>/dev/null || true)

if [ -z "${DB_PATH}" ] || [ ! -d "${DB_PATH}" ]; then
    # 备用：直接从 conda share 目录查找
    DB_PATH=$(find "${REPO}/envs/plasmidfinder" -path "*/plasmidfinder*/database" -type d 2>/dev/null | head -1)
fi

if [ -z "${DB_PATH}" ] || [ ! -d "${DB_PATH}" ]; then
    echo "[ERROR] 无法定位 PlasmidFinder 数据库路径"
    echo "        请确认 envs/plasmidfinder 已安装（conda install -c bioconda plasmidfinder）"
    exit 1
fi

echo "[plasmidfinder] ${SAMPLE}: 质粒识别"
echo "  Contig 输入: ${CONTIGS}"
echo "  DB 路径: ${DB_PATH}"
echo "  覆盖度阈值: ${MIN_COV} | 相似度阈值: ${THRESHOLD}"

EXIT_CODE=0
mgx_try mgx_conda plasmidfinder plasmidfinder.py \
        -i  "${CONTIGS}" \
        -o  "${RESULT_DIR}" \
        -tmp "${TMP_DIR}" \
        -p  "${DB_PATH}" \
        -l  "${MIN_COV}" \
        -t  "${THRESHOLD}" \
        -x \
        -q || EXIT_CODE=$?
rm -rf "${TMP_DIR}"

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] PlasmidFinder 运行失败（exit code: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

N_PLASMID=$(grep -v "^#\|^Database\|^Plasmidfinder" "${SENTINEL}" 2>/dev/null | \
            grep -v "^$" | wc -l || echo "N/A")

echo "[plasmidfinder] ${SAMPLE}: 完成"
echo "  质粒 replicon 命中: ${N_PLASMID} 条"
echo "  输出: ${RESULT_DIR}/"
echo "[提示] results_tab.tsv 含 replicon 类型 + 不相容群（Inc group），可与 AMR 结果关联"
mgx_end "plasmidfinder"
