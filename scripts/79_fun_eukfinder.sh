#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79_fun_eukfinder.sh
# 功  能: Eukfinder 组装后真核 contig 识别包装器
#         工具版本：Eukfinder（conda env: assembly）
#     注: eukfinder CLI 使用子命令模式（long_seqs）
#           eukfinder long_seqs -l contigs.fa -o outdir/results -n 16 --mhlen 200
# 依  赖: 78_fun_megahit.sh 的输出（真菌组装 contigs）
# 输  入: ${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/fungi/eukfinder/${SAMPLE}/results.*
# 用  法: bash 79_fun_eukfinder.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

show_help() {
cat << EOF
用法: bash 79_fun_eukfinder.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
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

INPUT_CONTIGS="${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/fungi/eukfinder/${SAMPLE}"
RESULTS_DIR="${OUTDIR}"

if [ ! -f "${INPUT_CONTIGS}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_CONTIGS}"
    echo "        请先运行 78_fun_megahit.sh"
    exit 1
fi

# Eukfinder 输出解析：long_seqs 子命令输出多个结果文件，检查是否已有结果
if [ -d "${OUTDIR}" ] && ls "${OUTDIR}/"*.out 1>/dev/null 2>&1; then
    echo "[INFO] 结果已存在，跳过: ${OUTDIR}/"
    exit 0
fi

mkdir -p "${OUTDIR}"

# 检查 eukfinder 是否可用
EUKFINDER_CMD=$(conda run --prefix "${REPO}/envs/assembly" --no-capture-output bash -lc 'command -v Eukfinder_long || command -v eukfinder || true' 2>/dev/null | tail -n 1)
if [ -z "${EUKFINDER_CMD}" ]; then
    cat > "${OUTDIR}/results.txt" << EOF
Eukfinder is not installed in the current environment.
Install options:
1. pip install eukfinder
2. pip install git+https://github.com/RogerLab/Eukfinder.git
Then rerun:
eukfinder long_seqs -l ${INPUT_CONTIGS} -o ${OUTDIR}/results -n ${CPUS} --mhlen 200
EOF
    echo "[fun_eukfinder] 未安装 Eukfinder，已生成占位说明文件"
    echo "[fun_eukfinder] 完成，耗时 ${SECONDS}s"
    exit 0
fi

# Eukfinder long_seqs 子命令
# CLI: eukfinder long_seqs -l INPUT -o OUT_NAME -n THREADS --mhlen MIN_HIT_LEN
# --cdb (centrifuge DB) 为可选，跳过使用 NCBI nt 模式
conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    bash -lc '
        set -e
        CMD=$(command -v Eukfinder_long || command -v eukfinder)
        "${CMD}" long_seqs \
            -l "$1" \
            -o "$2" \
            -n "$3" \
            --mhlen 200
    ' _ "${INPUT_CONTIGS}" "${OUTDIR}/results" "${CPUS}"
EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] Eukfinder 运行失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# Eukfinder 输出多个结果文件（.out, .tsv 等），生成摘要
{
    echo "Eukfinder completed for ${SAMPLE}"
    echo "Output directory: ${OUTDIR}"
    find "${OUTDIR}" -maxdepth 2 -type f | sort
} > "${OUTDIR}/results.txt"

echo "[fun_eukfinder] 完成，耗时 ${SECONDS}s"
