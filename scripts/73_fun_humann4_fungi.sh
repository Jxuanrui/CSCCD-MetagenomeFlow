#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 73_fun_humann4_fungi.sh
# 功  能: 从已计算的 HUMAnN 分层通路结果中提取真菌相关通路丰度
#         工具版本：grep/awk（conda env: humann4）
# 依  赖: 13_bac_humann3.sh 的输出（HUMAnN 分层 pathabundance）
#         72_fun_metaphlan4_euk.sh 的输出（真菌 profile，供 pipeline 依赖管理）
# 输  入: ${WORKDIR}/result/humann3/${SAMPLE}/${SAMPLE}_pathabundance_relab.tsv
# 输  出: ${WORKDIR}/result/fungi/humann4/${SAMPLE}/${SAMPLE}_fungi_pathabundance.tsv
# 用  法: bash 73_fun_humann4_fungi.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 73_fun_humann4_fungi.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数（本步骤为后处理，固定单线程；保留供 pipeline 统一调用）
  -w  工作目录
  -r  MaxMetagenome 项目根目录
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do if [ -z "${!v}" ]; then echo "[ERROR] 缺少必需参数"; exit 1; fi; done

SECONDS=0

INPUT_PATHABUNDANCE="${WORKDIR}/result/humann3/${SAMPLE}/${SAMPLE}_pathabundance_relab.tsv"
OUTDIR="${WORKDIR}/result/fungi/humann4/${SAMPLE}"
OUTPUT_TSV="${OUTDIR}/${SAMPLE}_fungi_pathabundance.tsv"

if [ ! -f "${INPUT_PATHABUNDANCE}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_PATHABUNDANCE}"
    echo "        请先运行 13_bac_humann3.sh"
    exit 1
fi

if [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${OUTPUT_TSV}"
    exit 0
fi

mkdir -p "${OUTDIR}"

conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
    bash -lc '
        set -euo pipefail
        grep -E "^#|^[^|]+\t|k__Fungi|p__Ascomycota|p__Basidiomycota|p__Mucoromycota|p__Chytridiomycota|p__Microsporidia" \
            "$1" > "$2"
    ' _ "${INPUT_PATHABUNDANCE}" "${OUTPUT_TSV}"
EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 真菌 HUMAnN4 后处理失败（exit: ${EXIT_CODE}）"
    rm -f "${OUTPUT_TSV}"
    exit ${EXIT_CODE}
fi

N_ROWS=$(grep -vc "^#" "${OUTPUT_TSV}" 2>/dev/null || echo "0")
echo "[fun_humann4] 完成，耗时 ${SECONDS}s | 保留行数: ${N_ROWS}"

