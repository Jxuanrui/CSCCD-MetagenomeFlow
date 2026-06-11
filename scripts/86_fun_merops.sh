#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 86_fun_merops.sh
# 功  能: MEROPS 蛋白酶注释（DIAMOND blastp 比对 MEROPS 数据库）
#         工具版本：DIAMOND 2.x（conda env: assembly）
# 依  赖: 80_fun_prodigal.sh 的输出（各样本 FAA，自动合并）
# 输  入: ${WORKDIR}/result/fungi/prodigal/*/*.faa（自动搜索合并）
# 输  出: ${WORKDIR}/result/fungi/merops/merops_hits.tsv
# 用  法: bash 86_fun_merops.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 86_fun_merops.sh -t CPUS -w WORKDIR -r REPO

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
for v in CPUS WORKDIR REPO; do if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; exit 1; fi; done

SECONDS=0

OUTDIR="${WORKDIR}/result/fungi/merops"
PRODIGAL_DIR="${WORKDIR}/result/fungi/prodigal"
COMBINED_FAA="${OUTDIR}/combined_fungi.faa"
OUTPUT_TSV="${OUTDIR}/merops_hits.tsv"
DB_FILE=$(find "${REPO}/db/merops" -name "*.dmnd" 2>/dev/null | head -1)

if [ ! -d "${PRODIGAL_DIR}" ]; then echo "[ERROR] Prodigal 目录不存在: ${PRODIGAL_DIR}"; exit 1; fi
if [ -z "${DB_FILE}" ]; then echo "[ERROR] 未找到 MEROPS 数据库: ${REPO}/db/merops/*.dmnd"; exit 1; fi

if [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"

mapfile -t FAA_FILES < <(find "${PRODIGAL_DIR}" -name "*.faa" 2>/dev/null | sort)
if [ ${#FAA_FILES[@]} -eq 0 ]; then echo "[ERROR] 未找到 FAA 文件"; exit 1; fi
cat "${FAA_FILES[@]}" > "${COMBINED_FAA}"

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    diamond blastp \
        --db "${DB_FILE}" \
        --query "${COMBINED_FAA}" \
        --out "${OUTPUT_TSV}" \
        --outfmt 6 qseqid sseqid pident length evalue bitscore \
        --evalue 1e-5 \
        --max-target-seqs 1 \
        --sensitive \
        --threads "${CPUS}"
EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] diamond blastp 失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

N_HITS=$(wc -l < "${OUTPUT_TSV}" 2>/dev/null || echo "0")
N_QUERY=$(grep -c "^>" "${COMBINED_FAA}" 2>/dev/null || echo "0")
echo "[fun_merops] 完成，耗时 ${SECONDS}s | 查询蛋白: ${N_QUERY} | 命中: ${N_HITS}"
