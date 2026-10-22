#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 31c_bac_pfam.sh
# 功  能: Pfam-A 蛋白功能域注释（seqkit 分块 + rush 并行 hmmscan）
#         覆盖 eggNOG/KEGG/Swiss-Prot 注释之外的结构域信息
#         工具版本：HMMER 3.x（conda env: dbcan，已含 hmmscan）
#         分块工具：seqkit split2（conda env: assembly）
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
#   --cpu          : 每个 hmmscan 进程的线程数（hmmscan 参数名不是 --threads）
#   DB             : db/pfam/Pfam-A.hmm（需要 hmmpress 完成，.h3f/.h3i/.h3m/.h3p 已就绪）
#
# ── 并行策略 ──────────────────────────────────────────────────────────────────
#   seqkit split2 将 protein_nr.fa 拆成 N 个分块
#   rush 并行运行 N 个独立 hmmscan 进程
#   总线程预算来自 -t；默认每个 hmmscan 约 2 线程，分块数限制在 4..32
#
# 参  考: Mistry et al. 2021 NAR (Pfam v35); Eddy 2011 PLoS Comput Biol (HMMER3)
#         https://www.ebi.ac.uk/interpro/download/Pfam/
# 用  法: bash 31c_bac_pfam.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 31c_bac_pfam.sh -t CPUS -w WORKDIR -r REPO

必需参数:
  -t  总线程预算（推荐 16+；脚本会拆分为多个 hmmscan 进程）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）

示例:
  bash scripts/31c_bac_pfam.sh -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

if ! [[ "${CPUS}" =~ ^[0-9]+$ ]] || [ "$((10#${CPUS}))" -lt 1 ]; then
    echo "[ERROR] -t 必须是正整数: ${CPUS}"
    exit 1
fi
CPUS=$((10#${CPUS}))

mgx_begin

PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"
RESULT_DIR="${WORKDIR}/result/annotation/pfam"
TBLOUT="${RESULT_DIR}/pfam_hits.tblout"
DOMTBLOUT="${RESULT_DIR}/pfam_hits.domtblout"
TMP_DIR="${WORKDIR}/temp/pfam_split"
SPLIT_DIR="${TMP_DIR}/chunks"
RUSH_LOG="${TMP_DIR}/rush_batch.log"
PFAM_HMM="${REPO}/db/pfam/Pfam-A.hmm"
CONDA="${REPO}/miniforge3/bin/conda"
RUSH="${REPO}/miniforge3/bin/rush"

if [ ${FORCE} -eq 0 ] && [ -f "${TBLOUT}" ] && [ -s "${TBLOUT}" ]; then
    echo "[INFO] Pfam 注释结果已存在，跳过: ${TBLOUT}"; exit 0
fi

if [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
    echo "[ERROR] 蛋白序列文件不存在: ${PROTEIN_NR}"
    echo "        请先运行 18_bac_cdhit.sh"
    exit 1
fi

if [ ! -f "${PFAM_HMM}.h3i" ]; then
    echo "[ERROR] Pfam HMM 索引未找到: ${PFAM_HMM}.h3i"
    echo "        请确认 db/pfam/ 下有 hmmpress 生成的 .h3f/.h3i/.h3m/.h3p 文件"
    exit 1
fi

if [ ! -x "${CONDA}" ]; then
    echo "[ERROR] conda 不可执行: ${CONDA}"
    exit 1
fi

if [ ! -x "${RUSH}" ]; then
    echo "[ERROR] rush 不可执行: ${RUSH}"
    exit 1
fi

mkdir -p "${RESULT_DIR}"

N_QUERY=$(grep -c "^>" "${PROTEIN_NR}" 2>/dev/null || true)
if [ -z "${N_QUERY}" ] || [ "${N_QUERY}" -lt 1 ]; then
    echo "[ERROR] 蛋白序列文件中未找到 FASTA 记录: ${PROTEIN_NR}"
    exit 1
fi

CHUNKS=$((CPUS / 2))
if [ "${CHUNKS}" -lt 4 ]; then
    if [ "${CPUS}" -ge 4 ]; then
        CHUNKS=4
    else
        CHUNKS=${CPUS}
    fi
fi
if [ "${CHUNKS}" -gt 32 ]; then CHUNKS=32; fi
if [ "${CHUNKS}" -gt "${CPUS}" ]; then CHUNKS=${CPUS}; fi
if [ "${CHUNKS}" -gt "${N_QUERY}" ]; then CHUNKS=${N_QUERY}; fi
THREADS_PER_CHUNK=$((CPUS / CHUNKS))
if [ "${THREADS_PER_CHUNK}" -lt 1 ]; then THREADS_PER_CHUNK=1; fi

echo "[pfam] 开始 Pfam-A 域注释 | 蛋白数: ${N_QUERY} | 总线程预算: ${CPUS}"
echo "[pfam] 并行配置: ${CHUNKS} chunks × ${THREADS_PER_CHUNK} threads/chunk"
echo "[pfam] HMM 数据库: ${PFAM_HMM}"
echo "[pfam] 使用 --cut_ga（Pfam Gathering threshold，官方推荐）"

rm -rf "${TMP_DIR}"
mkdir -p "${SPLIT_DIR}"

echo "[pfam] 拆分蛋白 FASTA: ${SPLIT_DIR}"
SPLIT_EXIT=0
mgx_try "${CONDA}" run --prefix "${REPO}/envs/assembly" --no-capture-output \
    seqkit split2 \
        -p "${CHUNKS}" \
        -O "${SPLIT_DIR}" \
        --by-part-prefix chunk_ \
        -1 "${PROTEIN_NR}" || SPLIT_EXIT=$?
if [ "${SPLIT_EXIT}" -ne 0 ]; then
    echo "[ERROR] seqkit split2 失败（exit code: ${SPLIT_EXIT}）"
    echo "        临时目录保留用于排查: ${TMP_DIR}"
    exit ${SPLIT_EXIT}
fi

mapfile -t CHUNK_FILES < <(find "${SPLIT_DIR}" -maxdepth 1 -type f -name "chunk_*" | sort)
if [ ${#CHUNK_FILES[@]} -eq 0 ]; then
    echo "[ERROR] seqkit split2 未生成 chunk 文件: ${SPLIT_DIR}"
    echo "        临时目录保留用于排查: ${TMP_DIR}"
    exit 1
fi
CHUNKS=${#CHUNK_FILES[@]}
THREADS_PER_CHUNK=$((CPUS / CHUNKS))
if [ "${THREADS_PER_CHUNK}" -lt 1 ]; then THREADS_PER_CHUNK=1; fi

echo "[pfam] 运行 hmmscan: ${CHUNKS} chunks × ${THREADS_PER_CHUNK} threads/chunk | rush -j ${CHUNKS}"
set +e
printf "%s\n" "${CHUNK_FILES[@]}" | \
  "${RUSH}" -j "${CHUNKS}" -k \
  "\"${CONDA}\" run --prefix \"${REPO}/envs/dbcan\" --no-capture-output \
     hmmscan \
       --cpu ${THREADS_PER_CHUNK} \
       --cut_ga \
       --noali \
       --tblout \"{}.tblout\" \
       --domtblout \"{}.domtblout\" \
       \"${PFAM_HMM}\" \
       \"{}\" \
       > \"{}.log\" 2>&1 \
     && touch \"{}.ok\" \
     && echo \"[pfam] chunk done: {}\" \
     || { code=\$?; echo \"[pfam] chunk failed: {} (exit code: \${code})\"; exit \${code}; }" \
  2>&1 | tee "${RUSH_LOG}"
RUSH_EXIT=${PIPESTATUS[1]}
set -e

FAILED_CHUNKS=()
for CHUNK in "${CHUNK_FILES[@]}"; do
    if [ ! -f "${CHUNK}.ok" ]; then
        FAILED_CHUNKS+=("${CHUNK}")
    fi
done

if [ ${RUSH_EXIT} -ne 0 ] || [ ${#FAILED_CHUNKS[@]} -gt 0 ]; then
    echo "[ERROR] hmmscan 分块任务失败（rush exit code: ${RUSH_EXIT}）"
    echo "[ERROR] 失败或未完成的 chunk:"
    printf "    %s\n" "${FAILED_CHUNKS[@]}"
    echo "        临时目录保留用于排查: ${TMP_DIR}"
    if [ ${RUSH_EXIT} -ne 0 ]; then
        exit ${RUSH_EXIT}
    else
        exit 1
    fi
fi

TMP_TBLOUT="${TMP_DIR}/pfam_hits.tblout.tmp"
TMP_DOMTBLOUT="${TMP_DIR}/pfam_hits.domtblout.tmp"
: > "${TMP_TBLOUT}"
: > "${TMP_DOMTBLOUT}"

MERGE_FAILED=0
for CHUNK in "${CHUNK_FILES[@]}"; do
    if [ ! -f "${CHUNK}.tblout" ] || [ ! -f "${CHUNK}.domtblout" ]; then
        echo "[ERROR] chunk 输出缺失: ${CHUNK}"
        MERGE_FAILED=1
        continue
    fi
    awk 'NF && $0 !~ /^#/' "${CHUNK}.tblout" >> "${TMP_TBLOUT}" || MERGE_FAILED=1
    awk 'NF && $0 !~ /^#/' "${CHUNK}.domtblout" >> "${TMP_DOMTBLOUT}" || MERGE_FAILED=1
done

if [ ${MERGE_FAILED} -ne 0 ]; then
    echo "[ERROR] 合并 hmmscan 输出失败"
    echo "        临时目录保留用于排查: ${TMP_DIR}"
    exit 1
fi

mv "${TMP_TBLOUT}" "${TBLOUT}"
mv "${TMP_DOMTBLOUT}" "${DOMTBLOUT}"

rm -rf "${TMP_DIR}"

N_HITS=$(wc -l < "${TBLOUT}" | tr -d ' ')
N_DOM=$(wc -l < "${DOMTBLOUT}" | tr -d ' ')
echo ""
echo "    chunks: ${CHUNKS}"
echo "    每个 chunk 线程数: ${THREADS_PER_CHUNK}"
echo "    蛋白命中数（gene-level）: ${N_HITS}"
echo "    域命中数（domain-level）: ${N_DOM}"
echo "    输出:"
echo "    ├── pfam_hits.tblout     (基因级，下游解析用）"
echo "    └── pfam_hits.domtblout  (域坐标级，结构域边界分析用）"
echo "[提示] 结合 25_bac_dbcan.sh（CAZyme 也用 hmmscan）结果可做跨域功能对比"
mgx_end "pfam"
