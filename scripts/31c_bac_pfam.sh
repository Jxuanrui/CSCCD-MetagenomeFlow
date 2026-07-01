#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 31c_bac_pfam.sh
# 功  能: Pfam-A 蛋白功能域注释（hmmscan，HMM 比对）
#         覆盖 eggNOG/KEGG/Swiss-Prot 注释之外的结构域信息
#         工具版本：HMMER 3.x（conda env: dbcan，已含 hmmscan）
# 依  赖: 18_bac_cdhit.sh 的输出（protein_nr.fa）
# 输  入: ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
# 输  出: ${WORKDIR}/result/annotation/pfam/
#           pfam_hits.tblout     — --tblout 格式（gene-level 最佳命中，解析友好）
#           pfam_hits.domtblout  — --domtblout 格式（domain-level，含坐标信息）
#
# ── 参数说明 ──────────────────────────────────────────────────────────────────
#   --cut_ga       : 使用 Pfam 内置 Gathering threshold（各 HMM 家族特异性阈值）
#                    比固定 -E 1e-5 更准确，Pfam 官方推荐
#   --noali        : 不输出序列比对（大幅减小输出体积，tblout 已足够下游使用）
#   --cpu          : 线程数（hmmscan 参数名不是 --threads）
#   DB             : db/pfam/Pfam-A.hmm（需要 hmmpress 完成，.h3f/.h3i/.h3m/.h3p 已就绪）
#
# 参  考: Mistry et al. 2021 NAR (Pfam v35); Eddy 2011 PLoS Comput Biol (HMMER3)
#         https://www.ebi.ac.uk/interpro/download/Pfam/
# 用  法: bash 31c_bac_pfam.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 31c_bac_pfam.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  线程数（推荐 16+，hmmscan 多线程效率较低，建议与核数匹配）
  -w  工作目录
  -r  MaxMetagenome 项目根目录

示例:
  bash scripts/31c_bac_pfam.sh -t 16 \\
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
    echo "[ERROR] 缺少必需参数（-t/-w/-r）"; show_help; exit 1
fi

SECONDS=0

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/pfam"
TBLOUT="${RESULT_DIR}/pfam_hits.tblout"
DOMTBLOUT="${RESULT_DIR}/pfam_hits.domtblout"

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"
    echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi

PFAM_HMM="${REPO}/db/pfam/Pfam-A.hmm"
if [ ! -f "${PFAM_HMM}.h3i" ]; then
    echo "[ERROR] Pfam HMM 索引未找到: ${PFAM_HMM}.h3i"
    echo "        请确认 db/pfam/ 下有 hmmpress 生成的 .h3f/.h3i/.h3m/.h3p 文件"
    exit 1
fi

if [ -f "${TBLOUT}" ] && [ -s "${TBLOUT}" ]; then
    echo "[INFO] Pfam 注释结果已存在，跳过: ${TBLOUT}"; exit 0
fi

mkdir -p "${RESULT_DIR}"

N_QUERY=$(grep -c "^>" "${PROTEIN_NR}" 2>/dev/null || echo "N/A")
echo "[pfam] 开始 Pfam-A 域注释 | 蛋白数: ${N_QUERY} | 线程: ${CPUS}"
echo "[pfam] HMM 数据库: ${PFAM_HMM}"
echo "[pfam] 使用 --cut_ga（Pfam Gathering threshold，官方推荐）"

# hmmscan 在 dbcan 环境（dbcan env 已含 HMMER 3.x）
conda run --prefix "${REPO}/envs/dbcan" --no-capture-output \
    hmmscan \
        --cpu        "${CPUS}" \
        --cut_ga \
        --noali \
        --tblout     "${TBLOUT}" \
        --domtblout  "${DOMTBLOUT}" \
        "${PFAM_HMM}" \
        "${PROTEIN_NR}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] hmmscan 失败（exit code: ${EXIT_CODE}）"
    rm -f "${TBLOUT}" "${DOMTBLOUT}"; exit ${EXIT_CODE}
fi

N_HITS=$(grep -v "^#" "${TBLOUT}" 2>/dev/null | wc -l || echo "N/A")
N_DOM=$(grep -v "^#" "${DOMTBLOUT}" 2>/dev/null | wc -l || echo "N/A")
echo ""
echo "[pfam] 完成，耗时 ${SECONDS}s"
echo "    蛋白命中数（gene-level）: ${N_HITS}"
echo "    域命中数（domain-level）: ${N_DOM}"
echo "    输出:"
echo "    ├── pfam_hits.tblout     (基因级，下游解析用）"
echo "    └── pfam_hits.domtblout  (域坐标级，结构域边界分析用）"
echo "[提示] 结合 25_bac_dbcan.sh（CAZyme 也用 hmmscan）结果可做跨域功能对比"
