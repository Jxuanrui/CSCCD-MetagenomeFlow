#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 18_bac_cdhit.sh
# 功  能: CD-HIT-EST 跨样本基因集去冗余，构建非冗余基因目录（NR gene catalog）
#         工具版本：CD-HIT v4.8.1 + seqkit（conda env: assembly）
# 依  赖: 17_bac_prodigal.sh 的输出（所有样本的 .fna 文件）
# 输  入: ${WORKDIR}/result/assembly/prodigal/*/${SAMPLE}.fna（自动发现）
# 输  出: ${WORKDIR}/result/assembly/cdhit/
#           nucleotide_nr.fa    — 非冗余核苷酸基因集（Salmon 定量输入）
#           protein_nr.fa       — 蛋白序列（eggNOG/CARD 等注释输入）
#           nucleotide_nr.fa.clstr — 聚类信息（各基因所属簇）
#
# ── 参数说明 ─────────────────────────────────────────────────────────────────
#
#   -c 0.95：95% 核苷酸序列相似度（MetaHIT/IGC 基因目录国际标准）
#   -aS 0.9：以短序列为基准，90% 比对覆盖度（partial match 关键）
#   -G 0：   局部比对模式（对可变长度的基因/片段更适合）
#   -g 1：   精确贪心聚类（比 -g 0 慢约 2×，但避免遗漏边界相似序列）
#   -r 1：   双链比较（比对 ++ 和 +- 两个方向）
#   -n 10：  word size（适合 -c 0.95；范围：0.9→8, 0.95→10, 1.0→11）
#   -M 0：   不限内存
#   -d 0：   保留完整序列描述行
#
# ── 聚合步骤说明 ──────────────────────────────────────────────────────────────
#
#   本脚本为跨样本聚合步骤（aggregate rule），无 -s 参数。
#   自动发现 ${WORKDIR}/result/assembly/prodigal/*/*.fna 所有样本输出，
#   合并后过滤 <100 bp 基因，再运行 CD-HIT-EST 去冗余。
#
# 参  考: Li & Godzik 2006 Bioinformatics; Fu et al. 2012 Bioinformatics (CD-HIT)
#         Qin et al. 2010 Nature; Li et al. 2014 Nature Biotech (MetaHIT/IGC gene catalog)
#         https://github.com/weizhongli/cdhit
# 用  法: bash 18_bac_cdhit.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 18_bac_cdhit.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 16-32，CD-HIT 支持多线程）
  -w  工作目录（Project 路径，含 result/assembly/prodigal/ 子目录）
  -r  MaxMetagenome 项目根目录

示例:
  bash 18_bac_cdhit.sh -t 16 \\
       -w ~/Course/Maxmetagenome/Project/Project_example \\
       -r ~/Course/Maxmetagenome
EOF
}

CPUS=""
WORKDIR=""
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-t/-w/-r）"
    show_help; exit 1
fi

SECONDS=0

# --- 路径设置 ---

PRODIGAL_DIR="${WORKDIR}/result/assembly/prodigal"
RESULT_DIR="${WORKDIR}/result/assembly/cdhit"

COMBINED_FNA="${RESULT_DIR}/all_genes.fna"
FILTERED_FNA="${RESULT_DIR}/all_genes_min100.fna"
NR_FNA="${RESULT_DIR}/nucleotide_nr.fa"
NR_FAA="${RESULT_DIR}/protein_nr.fa"

# --- 输入检查：确认存在至少一个 .fna 文件 ---

FNA_FILES=($(find "${PRODIGAL_DIR}" -name "*.fna" -size +0c 2>/dev/null | sort))
N_SAMPLES="${#FNA_FILES[@]}"

if [ "${N_SAMPLES}" -eq 0 ]; then
    echo "[ERROR] 未在 ${PRODIGAL_DIR} 下找到任何 .fna 文件"
    echo "        请先对所有样本运行 17_bac_prodigal.sh"
    exit 1
fi

echo "[cdhit] 发现 ${N_SAMPLES} 个样本的 .fna 文件"

# --- 幂等性检查 ---

if [ -f "${NR_FNA}" ] && [ -s "${NR_FNA}" ]; then
    echo "[INFO] CD-HIT-EST 结果已存在，跳过"
    echo "       ${NR_FNA}"
    exit 0
fi

mkdir -p "${RESULT_DIR}"

# --- Step 1: 合并所有样本基因序列 ---

echo "[cdhit] Step 1/4: 合并 ${N_SAMPLES} 个样本基因序列..."
cat "${FNA_FILES[@]}" > "${COMBINED_FNA}"

N_RAW=$(grep -c "^>" "${COMBINED_FNA}" || echo "N/A")
echo "[cdhit] 合并基因总数: ${N_RAW}"

# --- Step 2: 过滤 <100 bp 的基因片段 ---
# 遵循 MetaHIT/IGC 标准：ORF ≥ 100 nt（33 aa）才纳入基因目录

echo "[cdhit] Step 2/4: 过滤长度 <100 bp 的基因片段..."
conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    seqkit seq -m 100 "${COMBINED_FNA}" > "${FILTERED_FNA}"

N_FILTERED=$(grep -c "^>" "${FILTERED_FNA}" || echo "N/A")
echo "[cdhit] 过滤后基因数: ${N_FILTERED}"

# --- Step 3: CD-HIT-EST 去冗余 ---
# -c 0.95: 95% 核苷酸序列相似度（MetaHIT/IGC 国际标准）
# -aS 0.9: 90% 比对覆盖度（以短序列为基准）
# -G 0:    局部比对（适合可变长度基因）
# -g 1:    精确贪心聚类（更慢但更准确）
# -r 1:    双链比较（++ 和 +-）
# -n 10:   word size（-c 0.95 推荐 10）
# -M 0:    不限内存
# -d 0:    保留完整序列 ID（避免截断）

echo "[cdhit] Step 3/4: 运行 CD-HIT-EST（95% identity，90% coverage）..."
echo "[cdhit] 线程: ${CPUS}，预计耗时 10-60 分钟（取决于基因规模）"

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    cd-hit-est \
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
        -d  0

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] CD-HIT-EST 运行失败（exit code: ${EXIT_CODE}）"
    rm -f "${NR_FNA}" "${NR_FNA}.clstr"
    exit ${EXIT_CODE}
fi

if [ ! -f "${NR_FNA}" ] || [ ! -s "${NR_FNA}" ]; then
    echo "[ERROR] nucleotide_nr.fa 未生成或为空"
    exit 1
fi

# --- Step 4: 翻译蛋白序列 ---
# 从 NR 核苷酸集翻译为蛋白（供后续 eggNOG/CARD/dbCAN 注释使用）
# --trim: 去除终止密码子（*）

echo "[cdhit] Step 4/4: 翻译蛋白序列（seqkit translate）..."
conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    seqkit translate --trim "${NR_FNA}" > "${NR_FAA}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[WARN] seqkit translate 失败（exit code: ${EXIT_CODE}），蛋白序列文件未生成"
fi

# 清理中间文件
rm -f "${COMBINED_FNA}" "${FILTERED_FNA}"

# --- 统计摘要 ---

N_NR=$(grep -c "^>" "${NR_FNA}" 2>/dev/null || echo "N/A")
N_FAA=$(grep -c "^>" "${NR_FAA}" 2>/dev/null || echo "N/A")

echo ""
echo "[cdhit] 去冗余完成，耗时 ${SECONDS}s"
echo "[cdhit] 结果目录: ${RESULT_DIR}/"
echo "    输入样本数:    ${N_SAMPLES}"
echo "    合并基因数:    ${N_RAW}"
echo "    ≥100bp 基因:   ${N_FILTERED}"
echo "    非冗余基因数:  ${N_NR}  (去冗余率 $(awk "BEGIN{if(${N_FILTERED}>0) printf \"%.1f\", (1-${N_NR}/${N_FILTERED})*100; else print \"N/A\"}") %)"
echo "    关键输出:"
echo "    ├── nucleotide_nr.fa      (NR 核苷酸基因集，→ 19_bac_salmon_build)"
echo "    ├── nucleotide_nr.fa.clstr (聚类信息)"
echo "    └── protein_nr.fa         (NR 蛋白序列，→ 21-31 功能注释)"
echo ""
echo "[提示] 下一步: 运行 19_bac_salmon_build.sh 构建 Salmon 定量索引"
