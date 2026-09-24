#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 18_bac_cdhit.sh
# 功  能: 跨样本基因集去冗余，构建非冗余基因目录（NR gene catalog）
#         支持两种后端工具（--tool 参数选择）：
#           cdhit   — CD-HIT-EST v4.8.1（默认，成熟稳定，适合 ≤500万基因）
#           mmseqs  — MMseqs2 Linclust v13（线性时间，推荐用于 >500万基因）
#         工具环境：conda env assembly（两者均已安装）
#
# 依  赖: 17_bac_prodigal.sh 的输出（所有样本的 .fna 文件）
# 输  入: ${WORKDIR}/result/assembly/prodigal/*/${SAMPLE}.fna（自动发现）
# 输  出: ${WORKDIR}/result/assembly/cdhit/
#           nucleotide_nr.fa     — 非冗余核苷酸基因集（Salmon 定量输入）
#           protein_nr.fa        — 蛋白序列（eggNOG/CARD 等注释输入）
#           nucleotide_nr.fa.clstr — 聚类信息（CD-HIT 模式）
#           OR mmseqs_cluster_rep_seq.fasta — 代表序列（MMseqs2 模式，
#              脚本自动复制为 nucleotide_nr.fa 保持统一命名）
#
# ── CD-HIT 参数说明 ────────────────────────────────────────────────────────────
#   -c 0.95：95% 核苷酸序列相似度（MetaHIT/IGC 基因目录国际标准）
#   -aS 0.9：以短序列为基准，90% 比对覆盖度（partial match 关键）
#   -G 0：   局部比对模式（对可变长度的基因/片段更适合）
#   -g 1：   精确贪心聚类（比 -g 0 慢约 2×，但避免遗漏边界相似序列）
#   -r 1：   双链比较（比对 ++ 和 +- 两个方向）
#   -n 10：  word size（适合 -c 0.95；范围：0.9→8, 0.95→10, 1.0→11）
#   -M 0：   不限内存
#   -d 0：   保留完整序列描述行
#
# ── MMseqs2 Linclust 参数说明 ─────────────────────────────────────────────────
#   --min-seq-id 0.95：95% 序列相似度（与 CD-HIT -c 0.95 对应）
#   -c 0.9：           90% 比对覆盖度（与 CD-HIT -aS 0.9 对应）
#   --cov-mode 1：     以短序列长度为覆盖度基准（等效 CD-HIT -aS）
#   --cluster-mode 2： Greedy incremental clustering（等效 CD-HIT -g 0，速度更快）
#   算法复杂度：O(n)线性，适合超大规模基因目录（>500万序列）
#
# ── 速度对比（2.5M 基因，48核）────────────────────────────────────────────────
#   CD-HIT：  ~30-60 分钟（近 O(n²)，随数据量急剧增长）
#   MMseqs2： ~3-10 分钟（O(n) 线性，数据量增加时优势更显著）
#   建议：≤500万基因用 cdhit（结果更被同行认可）；>500万基因用 mmseqs
#
# ── 聚合步骤说明 ──────────────────────────────────────────────────────────────
#   本脚本为跨样本聚合步骤（aggregate rule），无 -s 参数。
#   自动发现 ${WORKDIR}/result/assembly/prodigal/*/*.fna 所有样本输出，
#   合并后过滤 <100 bp 基因，再运行去冗余。
#
# 参  考: Li & Godzik 2006 Bioinformatics; Fu et al. 2012 Bioinformatics (CD-HIT)
#         Steinegger & Söding 2018 Nature Comms (MMseqs2 Linclust)
#         Qin et al. 2010 Nature; Li et al. 2014 Nature Biotech (MetaHIT/IGC gene catalog)
#         https://github.com/weizhongli/cdhit
#         https://github.com/soedinglab/MMseqs2
#
# 用  法: bash 18_bac_cdhit.sh -t CPUS -w WORKDIR -r REPO [--tool cdhit|mmseqs]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 18_bac_cdhit.sh -t CPUS -w WORKDIR -r REPO [--tool cdhit|mmseqs]

必需参数:
  -t  线程数（推荐 16-48）
  -w  工作目录（Project 路径，含 result/assembly/prodigal/ 子目录）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
  --tool cdhit    使用 CD-HIT-EST（默认，≤500万基因推荐）
  --tool mmseqs   使用 MMseqs2 Linclust（>500万基因或追求速度时推荐）

示例:
  # 默认 CD-HIT（10样本）
  bash 18_bac_cdhit.sh -t 48 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \\
       -r ~/Course/CSCCD-MetagenomeFlow

  # MMseqs2 Linclust（50样本全量，>500万基因）
  bash 18_bac_cdhit.sh -t 48 --tool mmseqs \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

TOOL="cdhit"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="tool:TOOL"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

if [[ "${TOOL}" != "cdhit" && "${TOOL}" != "mmseqs" ]]; then
    echo "[ERROR] --tool 只接受 cdhit 或 mmseqs，当前值: ${TOOL}"
    exit 1
fi

mgx_begin

# --- 路径设置 ---

PRODIGAL_DIR="${WORKDIR}/result/assembly/prodigal"
RESULT_DIR="${WORKDIR}/result/assembly/cdhit"

COMBINED_FNA="${RESULT_DIR}/all_genes.fna"
FILTERED_FNA="${RESULT_DIR}/all_genes_min100.fna"
NR_FNA="${RESULT_DIR}/nucleotide_nr.fa"
NR_FAA="${RESULT_DIR}/protein_nr.fa"

# --- 输入检查 ---

mapfile -t FNA_FILES < <(find "${PRODIGAL_DIR}" -name "*.fna" -size +0c 2>/dev/null | sort)
N_SAMPLES="${#FNA_FILES[@]}"

if [ "${N_SAMPLES}" -eq 0 ]; then
    echo "[ERROR] 未在 ${PRODIGAL_DIR} 下找到任何 .fna 文件"
    echo "        请先对所有样本运行 17_bac_prodigal.sh"
    exit 1
fi

echo "[cdhit] 发现 ${N_SAMPLES} 个样本的 .fna 文件，使用后端: ${TOOL}"

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${NR_FNA}" ] && [ -s "${NR_FNA}" ]; then
    echo "[INFO] NR 基因集已存在，跳过（${NR_FNA}）"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

# --- Step 1: 合并所有样本基因序列 ---

echo "[cdhit] Step 1/4: 合并 ${N_SAMPLES} 个样本基因序列（添加样本名前缀防冲突）..."
for fna in "${FNA_FILES[@]}"; do
    sname=$(basename "$(dirname "$fna")")
    sed "s/^>/>${sname}|/" "$fna" >> "${COMBINED_FNA}"
done

N_RAW=$(grep -c "^>" "${COMBINED_FNA}" || echo "N/A")
echo "[cdhit] 合并基因总数: ${N_RAW}"

# --- Step 2: 过滤 <100 bp 的基因片段 ---

echo "[cdhit] Step 2/4: 过滤长度 <100 bp 的基因片段..."
mgx_conda assembly \
    seqkit seq -m 100 "${COMBINED_FNA}" > "${FILTERED_FNA}"

N_FILTERED=$(grep -c "^>" "${FILTERED_FNA}" || echo "N/A")
echo "[cdhit] 过滤后基因数: ${N_FILTERED}"

# --- Step 3: 去冗余（按 --tool 选择后端）---

if [ "${TOOL}" = "cdhit" ]; then

    echo "[cdhit] Step 3/4: 运行 CD-HIT-EST（95% identity，90% coverage）..."
    echo "[cdhit] 线程: ${CPUS}，≤500万基因预计 10-60 分钟"

    EXIT_CODE=0
    mgx_try mgx_conda assembly cd-hit-est \
        -i  "${FILTERED_FNA}" \
        -o  "${NR_FNA}" \
        -c  0.95 \
        -aS 0.9 \
        -G  0 \
        -g  1 \
        -r  1 \
        -n  10 \
        -T  "${CPUS}" \
        -M  0 \
        -d  0 || EXIT_CODE=$?

else  # mmseqs

    echo "[cdhit] Step 3/4: 运行 MMseqs2 Linclust（95% identity，90% coverage）..."
    echo "[cdhit] 线程: ${CPUS}，O(n) 线性算法，预计 5-15 分钟"

    MMSEQS_PREFIX="${RESULT_DIR}/mmseqs_cluster"
    MMSEQS_TMP="${RESULT_DIR}/mmseqs_tmp"
    mkdir -p "${MMSEQS_TMP}"

    EXIT_CODE=0
    mgx_try mgx_conda assembly mmseqs easy-linclust \
        "${FILTERED_FNA}" \
        "${MMSEQS_PREFIX}" \
        "${MMSEQS_TMP}" \
        --min-seq-id 0.95 \
        -c 0.9 \
        --cov-mode 1 \
        --cluster-mode 2 \
        --threads "${CPUS}" \
        -v 1 || EXIT_CODE=$?

    # easy-linclust 输出 *_rep_seq.fasta，统一重命名为 nucleotide_nr.fa
    if [ "${EXIT_CODE}" -eq 0 ] && [ -f "${MMSEQS_PREFIX}_rep_seq.fasta" ]; then
        cp "${MMSEQS_PREFIX}_rep_seq.fasta" "${NR_FNA}"
        # 清理 MMseqs2 临时目录
        rm -rf "${MMSEQS_TMP}"
    fi

fi

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] 去冗余运行失败（exit code: ${EXIT_CODE}，tool: ${TOOL}）"
    rm -f "${NR_FNA}"
    exit ${EXIT_CODE}
fi

if [ ! -f "${NR_FNA}" ] || [ ! -s "${NR_FNA}" ]; then
    echo "[ERROR] nucleotide_nr.fa 未生成或为空"
    exit 1
fi

# --- Step 4: 翻译蛋白序列 ---

echo "[cdhit] Step 4/4: 翻译蛋白序列（seqkit translate）..."
set +e
mgx_conda assembly \
    seqkit translate --trim "${NR_FNA}" | \
    mgx_conda assembly \
    seqkit seq -m 1 > "${NR_FAA}"

EXIT_CODE=$?
set -e
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[WARN] seqkit translate 失败（exit code: ${EXIT_CODE}），蛋白序列文件未生成"
fi

# 清理中间合并文件
rm -f "${COMBINED_FNA}" "${FILTERED_FNA}"

# --- 统计摘要 ---

N_NR=$(grep -c "^>" "${NR_FNA}" 2>/dev/null || echo "N/A")

DEDUP_RATE=$(awk "BEGIN{if(\"${N_FILTERED}\" ~ /^[0-9]+$/ && \"${N_NR}\" ~ /^[0-9]+$/ && ${N_FILTERED}>0) printf \"%.1f\", (1-${N_NR}/${N_FILTERED})*100; else print \"N/A\"}")

echo ""
echo "[cdhit] 去冗余完成（后端: ${TOOL}）"
echo "[cdhit] 结果目录: ${RESULT_DIR}/"
echo "    输入样本数:    ${N_SAMPLES}"
echo "    合并基因数:    ${N_RAW}"
echo "    ≥100bp 基因:   ${N_FILTERED}"
echo "    非冗余基因数:  ${N_NR}  (去冗余率 ${DEDUP_RATE} %)"
echo "    关键输出:"
echo "    ├── nucleotide_nr.fa      (NR 核苷酸基因集，→ 19_bac_salmon_build)"
echo "    ├── nucleotide_nr.fa.clstr (聚类信息，CD-HIT 模式)"
echo "    └── protein_nr.fa         (NR 蛋白序列，→ 21-31 功能注释)"
echo ""
echo "[提示] 下一步: 运行 19_bac_salmon_build.sh 构建 Salmon 定量索引"
mgx_end "cdhit"
