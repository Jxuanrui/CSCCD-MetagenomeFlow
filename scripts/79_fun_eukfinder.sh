#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 79_fun_eukfinder.sh
# 功  能: Eukfinder 组装后真核 contig 识别包装器
#         工具版本：Eukfinder v1.2.4（conda env: assembly）
#     注: eukfinder long_seqs 需要两个数据库：
#           必须：Centrifuge DB（--cdb，70 GB，4 个 .cf 文件）
#           推荐：PLAST DB（-p/-m，2.1 GB，提高注释精度）
# 依  赖: 78_fun_megahit.sh 的输出（真菌组装 contigs）
# 输  入: ${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa
# 输  出: ${WORKDIR}/result/fungi/eukfinder/${SAMPLE}/*.out（真核/原核/未知分组）
# 用  法: bash 79_fun_eukfinder.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--cdb CDB_PREFIX]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 79_fun_eukfinder.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO [--cdb CDB_PREFIX]

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --cdb  Centrifuge DB 路径前缀（若不传，脚本自动检测默认路径）
         默认：\${REPO}/db/eukfinder_db/centrifuge_db/Centrifuge_DB/Centrifuge_NewDB_Sept2020
EOF
}

CDB_OVERRIDE=""

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="cdb:CDB_OVERRIDE"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

INPUT_CONTIGS="${WORKDIR}/result/fungi/assembly/${SAMPLE}/${SAMPLE}.contigs.fa"
OUTDIR="${WORKDIR}/result/fungi/eukfinder/${SAMPLE}"

if [ ! -f "${INPUT_CONTIGS}" ]; then
    echo "[ERROR] 输入文件不存在: ${INPUT_CONTIGS}"
    echo "        请先运行 78_fun_megahit.sh"
    exit 1
fi

# 检查是否已有真实结果（.out 文件，非占位符）
if [ ${FORCE} -eq 0 ] && [ -d "${OUTDIR}" ] && ls "${OUTDIR}/"*.out 1>/dev/null 2>&1; then
    echo "[INFO] 真实结果已存在，跳过: ${OUTDIR}/"
    exit 0
fi

mkdir -p "${OUTDIR}"

# ── ETE3 NCBI taxonomy DB 检查 ──────────────────────────────────────────────
# ete3.NCBITaxa() 会在首次调用时下载 taxdump.tar.gz 到 cwd，然后解压到 ~/.etetoolkit/
# 为避免下载文件污染任意目录，强制在 /tmp 下执行初始化；清理遗留的 taxdump 文件
ETE3_DB="${HOME}/.etetoolkit/taxa.sqlite"
if [ ! -f "${ETE3_DB}" ]; then
    echo "[fun_eukfinder] ETE3 taxa.sqlite 未初始化，在 /tmp 下执行一次性初始化..."
    (cd /tmp && mgx_conda assembly \
        python -c "import ete3; ete3.NCBITaxa()" 2>&1)
    if [ ! -f "${ETE3_DB}" ]; then
        echo "[ERROR] ETE3 初始化失败，请检查网络或手动运行："
        echo "        (cd /tmp && conda run --prefix ${REPO}/envs/assembly python -c \"import ete3; ete3.NCBITaxa()\")"
        exit 1
    fi
    # ete3 的 bug：删除条件判断有误，taxdump.tar.gz 不会被自动删除
    rm -f /tmp/taxdump.tar.gz /tmp/taxdump.tar.gz.md5 /tmp/syn.tab /tmp/merged.tab /tmp/taxa.tab 2>/dev/null
    echo "[fun_eukfinder] ETE3 初始化完成：${ETE3_DB}"
fi
# 清理当前目录下可能残留的 taxdump（历史遗留或调用者 cwd 问题）
rm -f "${PWD}/taxdump.tar.gz" "${PWD}/taxdump.tar.gz.md5" 2>/dev/null

# 检查 eukfinder 是否可用
EUKFINDER_CMD=$(mgx_conda assembly \
    bash -lc 'command -v eukfinder || true' 2>/dev/null | tail -n 1)
if [ -z "${EUKFINDER_CMD}" ]; then
    echo "[ERROR] Eukfinder 未安装于 ${REPO}/envs/assembly"
    echo "        安装: conda install -p ${REPO}/envs/assembly -y eukfinder -c bioconda -c conda-forge"
    exit 1
fi

# ── Centrifuge DB（必须）──────────────────────────────────────────────────────
# 默认路径（来自 Eukfinder download_db 解压结构）
DEFAULT_CDB="${REPO}/db/eukfinder_db/centrifuge_db/EukDB"
CDB="${CDB_OVERRIDE:-${DEFAULT_CDB}}"

# 检测 4 个 .cf 文件
CDB_OK=false
if ls "${CDB}".*.cf 1>/dev/null 2>&1 && [ "$(ls "${CDB}".*.cf 2>/dev/null | wc -l)" -ge 4 ]; then
    CDB_OK=true
fi

if [ "${CDB_OK}" = false ]; then
    cat > "${OUTDIR}/results.txt" << EOF
[PENDING] Centrifuge DB not ready: ${CDB}.*.cf (need 4 .cf files)

Eukfinder requires the Centrifuge DB (~70 GB) to classify sequences.
Download in progress: ${REPO}/db/eukfinder_db/centrifuge_db/download.log

Once the download + extraction completes, re-run:
  bash 79_fun_eukfinder.sh -s ${SAMPLE} -t ${CPUS} -w ${WORKDIR} -r ${REPO}

Or pass the DB path explicitly:
  bash 79_fun_eukfinder.sh -s ${SAMPLE} -t ${CPUS} -w ${WORKDIR} -r ${REPO} \\
    --cdb /path/to/Centrifuge_NewDB_Sept2020
EOF
    echo "[fun_eukfinder] Centrifuge DB 尚未就绪，已生成等待说明文件"
    echo "[fun_eukfinder] DB 路径: ${CDB}.*.cf"
    echo "[fun_eukfinder] 下载进度: ${REPO}/db/eukfinder_db/centrifuge_db/download.log"
    exit 0
fi
echo "[fun_eukfinder] Centrifuge DB 已就绪: ${CDB}"

# ── PLAST DB（可选，推荐）────────────────────────────────────────────────────
PLAST_DB="${REPO}/db/eukfinder_db/PlastDB.fasta"
PLAST_MAP="${REPO}/db/eukfinder_db/PlastDB_map.txt"
PLAST_FLAGS=""
if [ -f "${PLAST_DB}" ] && [ -f "${PLAST_MAP}" ]; then
    PLAST_FLAGS="-p ${PLAST_DB} -m ${PLAST_MAP}"
    echo "[fun_eukfinder] PLAST DB 已就绪，启用蛋白级分类"
else
    echo "[WARN] PLAST DB 未找到，将仅使用 Centrifuge 分类（精度略低）"
fi

# ── 运行 Eukfinder long_seqs ─────────────────────────────────────────────────
# 注意：eukfinder 将日志写入运行时工作目录，需 cd 到 OUTDIR
cd "${OUTDIR}"
EXIT_CODE=0
mgx_try mgx_conda assembly \
    bash -lc "
        set -e
        eukfinder long_seqs \\
            -l '${INPUT_CONTIGS}' \\
            -o '${SAMPLE}' \\
            -n '${CPUS}' \\
            --mhlen 200 \\
            --cdb '${CDB}' \\
            ${PLAST_FLAGS}
    " \
    || EXIT_CODE=$?
cd - > /dev/null

if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] Eukfinder 运行失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# 汇总结果
{
    echo "Eukfinder completed for ${SAMPLE}"
    echo "Output directory: ${OUTDIR}"
    echo "Output files:"
    find "${OUTDIR}" -maxdepth 3 -type f | sort
} > "${OUTDIR}/results.txt"

# 将 Eukfinder 自动生成的 Long_seqs_*.log 移至项目 logs 目录（避免污染结果目录）
LOG_DEST="${WORKDIR}/logs/fungi"
mkdir -p "${LOG_DEST}"
for stray_log in "${OUTDIR}"/Long_seqs_*.log; do
    [ -f "${stray_log}" ] && mv "${stray_log}" "${LOG_DEST}/" && \
        echo "[fun_eukfinder] 日志已移至 ${LOG_DEST}/$(basename "${stray_log}")"
done

echo "[fun_eukfinder] ${SAMPLE} 完成"
echo "[fun_eukfinder] 输出目录: ${OUTDIR}"
mgx_end "fun_eukfinder"

