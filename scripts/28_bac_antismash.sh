#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 28_bac_antismash.sh
# 功  能: 次级代谢产物生物合成基因簇（BGC）预测（antiSMASH）
#         工具版本：antiSMASH 8.0.4（conda env: antismash8；Blin et al. 2025，101 cluster types；
#                   旧 7.1.0 env/db 冻结保留可回滚）
# 依  赖: 16_bac_megahit.sh 的输出（{sample}.contigs.fa，≥1000bp）
# 输  入: ${WORKDIR}/result/assembly/megahit/{sample}/{sample}.contigs.fa
# 输  出: ${WORKDIR}/result/antismash/{sample}/
#           {sample}.gbk           — 结果 GenBank 文件
#           {sample}.json          — 结果 JSON（API用）
#           index.html             — 可视化报告
#
# ── 注意 ─────────────────────────────────────────────────────────────────────
#   antiSMASH 按样本运行（per-sample），宏基因组模式下不使用全基因组注释步骤
#   --minimal 可跳过 NCBI taxonomy 查询，但会损失部分注释
#   --taxon bacteria 是宏基因组细菌最常用设置
#
# 参  考: Blin et al. 2025 NAR (antiSMASH 8)
# 用  法: bash 28_bac_antismash.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 28_bac_antismash.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本 ID
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
RESULT_DIR="${WORKDIR}/result/annotation/antismash/${SAMPLE}"
SENTINEL="${RESULT_DIR}/antismash_done.txt"
ANTISMASH_DB="${REPO}/db/antismash8"

if [ ! -f "${CONTIGS}" ] || [ ! -s "${CONTIGS}" ]; then
    echo "[ERROR] 组装文件不存在: ${CONTIGS}"; exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then
    echo "[INFO] antiSMASH 结果已存在，跳过: ${RESULT_DIR}/"; exit 0
fi

# antiSMASH 不允许写入已存在目录
[ -d "${RESULT_DIR}" ] && rm -rf "${RESULT_DIR}"
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then
    echo "[28_bac_antismash] 结果已存在，跳过: ${SENTINEL}"; exit 0
fi

mkdir -p "$(dirname "${RESULT_DIR}")"

echo "[antismash] 样本: ${SAMPLE} | 线程: ${CPUS}"

# E-HARD-02-ADOPT: chunked execution (validated equivalent to monolithic on
# Sample11, docs/plans/phase2_5_evidence/antismash_chunking_reconciliation.md).
# Purpose: reliability / resume / failure isolation ONLY - scientific params
# are byte-identical to the frozen monolithic command. Atomic unit = full
# FASTA record (never split a sequence). Per-chunk DONE/FAILED sentinels
# preserve the T-11 semantics; the sample-level done sentinel is written only
# after ALL chunks succeed (merge gate).
CHUNKS_DIR="${RESULT_DIR}/_chunks"
CHUNK_N=24

python3 - "${CONTIGS}" "${CHUNKS_DIR}" "${CHUNK_N}" <<'PYSPLIT'
import sys, os
src, outdir, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(outdir, exist_ok=True)
recs = []
name, seq = None, []
for line in open(src):
    if line.startswith(">"):
        if name: recs.append((name, "".join(seq)))
        name, seq = line, []
    else: seq.append(line.strip())
if name: recs.append((name, "".join(seq)))
recs.sort(key=lambda r: -len(r[1]))  # bp-balanced greedy (largest-first)
bins = [([], 0) for _ in range(k)]
for name, s in recs:
    bins.sort(key=lambda b: b[1])
    lst, load = bins[0]; lst.append((name, s)); bins[0] = (lst, load + len(s))
for i, (lst, _) in enumerate(bins):
    with open(os.path.join(outdir, f"chunk_{i:02d}.fa"), "w") as f:
        for name, s in lst: f.write(name + "\n" + s + "\n")
PYSPLIT

FAILED_ANY=0
for C_FA in "${CHUNKS_DIR}"/chunk_*.fa; do
    CID=$(basename "${C_FA}" .fa)
    C_DIR="${RESULT_DIR}/${CID}"
    if [ -f "${C_DIR}/antismash_done.txt" ]; then
        echo "[antismash] ${CID}: DONE (resume skip)"
        continue
    fi
    [ -d "${C_DIR}" ] && rm -rf "${C_DIR}"
    mkdir -p "${C_DIR}"
    EXIT_CODE=0
    mgx_try mgx_conda antismash8 \
        antismash "${C_FA}" \
            --taxon bacteria \
            --output-dir "${C_DIR}" \
            --cpus "${CPUS}" \
            --databases "${ANTISMASH_DB}" \
            --genefinding-tool prodigal-m \
            --minimal \
            --enable-nrps-pks || EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        # T-11: execution failure must never masquerade as "done with no BGC".
        {
            echo "status=FAILED"
            echo "timestamp=$(date -Iseconds)"
            echo "exit_code=${EXIT_CODE}"
            echo "note=antiSMASH did not complete; empty/partial output is NOT a valid result"
        } > "${C_DIR}/antismash_FAILED.txt"
        echo "[antismash] ERROR: ${CID} 失败（exit: ${EXIT_CODE}），已写入 ${C_DIR}/antismash_FAILED.txt"
        FAILED_ANY=1
        continue
    fi
    touch "${C_DIR}/antismash_done.txt"
done

if [ ${FAILED_ANY} -ne 0 ]; then
    echo "[antismash] ERROR: 存在失败 chunk，样本不标记完成（merge 门未通过）"
    exit 1
fi

# BGC 统计基于全部 chunk 的 region GBK(与既有 N_BGC 口径一致: gbk 计数)
N_BGC=$(find "${RESULT_DIR}"/chunk_* -maxdepth 1 -name "*.region*.gbk" 2>/dev/null | wc -l)
touch "${SENTINEL}"
echo "[antismash] 完成，耗时 ${SECONDS}s | BGC: ${N_BGC} | chunks: ${CHUNK_N} | 输出: ${RESULT_DIR}/"
