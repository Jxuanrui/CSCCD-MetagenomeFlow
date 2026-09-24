#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 42_bac_mge.sh
# 功  能: 可移动遗传元素（MGE）综合注释
#         五种 MGE 类型并行分析，覆盖水平基因转移（HGT）关键载体：
#           ISfinder    — 插入序列（Insertion Sequences, IS elements）
#           ICEberg     — 整合接合元件（ICEs / IMEs）
#           integrall   — 整合子（Integrons，class 1/2/3）
#           transposase — 转座酶 HMM（Tn 转座子）
#           mobileOG    — 综合 MGE 分类（质粒/IS/转座子/整合子/噬菌体）
#
# 依  赖: 16_bac_megahit.sh（组装 contig，供 ICEberg/integrall blastn）
#         17_bac_prodigal.sh（per-sample 蛋白预测，供 ISfinder/transposase/mobileOG）
#         18_bac_cdhit.sh（NR 蛋白集，供 mobileOG 汇总级注释）
#
# 输  入（per-sample）:
#   ${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa
#   ${WORKDIR}/result/assembly/prodigal/${SAMPLE}/${SAMPLE}.faa
# 输  入（aggregate，mobileOG）:
#   ${WORKDIR}/result/assembly/cdhit/protein_nr.fa
#
# 输  出: ${WORKDIR}/result/mge/
#   isfinder/${SAMPLE}/isfinder_hits.tsv      — IS 元件（mmseqs easy-search）
#   iceberg/${SAMPLE}/iceberg_hits.tsv        — ICE/IME（blastn，含注释字段）
#   integrall/${SAMPLE}/integrall_hits.tsv    — 整合子（blastn，含 class 字段）
#   transposase/${SAMPLE}/transposase_hits.tsv— 转座酶 HMM（hmmscan tblout）
#   mobileog/mobileog_nr_hits.tsv             — NR 蛋白级 MGE 分类（diamond）
#
# ── 工具与 conda 环境 ─────────────────────────────────────────────────────────
#   ISfinder / mobileOG : DIAMOND + MMseqs2  → envs/assembly
#   ICEberg / integrall  : BLAST blastn       → envs/assembly（blast 已含）
#   transposase          : hmmscan HMMER      → envs/dbcan
#
# ── 关键参数来源 ──────────────────────────────────────────────────────────────
#   ISfinder    : --min-seq-id 0.9 -e 1e-5（来自 Metagenomics_Apptainer_pipline ISfinder-kit.sh）
#   ICEberg     : blastn -perc_identity 70 -evalue 1e-5（来自 ICEberg.sh）
#   integrall   : blastn -evalue 1e-5 -perc_identity 90（来自 integrall.sh）
#   transposase : hmmscan（来自 transposase.sh）
#   mobileOG    : diamond --evalue 1e-5 --id 60 --min-score 30（来自 mobileOG.sh）
#
# 参  考:
#   ISfinder : Siguier et al. 2006 NAR; https://isfinder.biotoul.fr/
#   ICEberg  : Liu et al. 2019 NAR; https://db-mml.sjtu.edu.cn/ICEberg2/
#   integrall: Moura et al. 2009 NAR; https://integrall.bio.ua.pt/
#   mobileOG : Brown et al. 2022 NAR; https://mobileogdb.flsi.cloud.vt.edu/
#   DIAMOND  : Buchfink et al. 2015 Nature Methods
#   HMMER    : Eddy 2011 PLoS Comput Biol
#
# 用  法: bash 42_bac_mge.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 42_bac_mge.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名称
  -t  线程数（推荐 16+）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --skip-isfinder     跳过 ISfinder 分析
  --skip-iceberg      跳过 ICEberg 分析
  --skip-integrall    跳过 integrall 分析
  --skip-transposase  跳过 transposase 分析
  --skip-mobileog     跳过 mobileOG NR 级分析（仅首个样本需要；已存在则自动跳过）

示例:
  bash scripts/42_bac_mge.sh -s S01 -t 16 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
# （--skip-* 连字符布尔标志经 mgx_parse 映射为 SKIP_* 变量，默认 0）
export MGX_OPTS_STRING="s:SAMPLE t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force skip-isfinder skip-iceberg skip-integrall skip-transposase skip-mobileog"
mgx_parse "$@"
mgx_require SAMPLE CPUS WORKDIR REPO

mgx_begin

# --- 路径定义 ---
CONTIGS="${WORKDIR}/result/assembly/megahit/${SAMPLE}/${SAMPLE}.contigs.fa"
PROTEINS="${WORKDIR}/result/assembly/prodigal/${SAMPLE}/${SAMPLE}.faa"
PROTEIN_NR="${WORKDIR}/result/assembly/cdhit/protein_nr.fa"

MGE_BASE="${WORKDIR}/result/mge"

# --- DB 路径 ---
DB_ISFINDER="${REPO}/db/ISfinder/mmseqs/ISfinder"
DB_ICEBERG="${REPO}/db/ICEberg/blast/ICEberg"
DB_INTEGRALL="${REPO}/db/integrall/integrall"
DB_TRANSPOSASE="${REPO}/db/transposase-db/transposase.hmm"
DB_MOBILEOG="${REPO}/db/mobileog/mobileOG-db/diamond/mobileOG.dmnd"

# ──────────────────────────────────────────────────────────────────────────────
# 1. ISfinder — 插入序列（MMseqs2 easy-search vs 蛋白 .faa）
# ──────────────────────────────────────────────────────────────────────────────
IS_OUT="${MGE_BASE}/isfinder/${SAMPLE}/isfinder_hits.tsv"
IS_TMP="${WORKDIR}/temp/mge/isfinder/${SAMPLE}"

if [ ${SKIP_ISFINDER} -eq 0 ]; then
    if [ ${FORCE} -eq 0 ] && [ -f "${IS_OUT}" ] && [ -s "${IS_OUT}" ]; then
        echo "[mge:isfinder] 已存在，跳过: ${IS_OUT}"
    elif [ ! -f "${PROTEINS}" ] || [ ! -s "${PROTEINS}" ]; then
        echo "[mge:isfinder] 跳过 ${SAMPLE}：蛋白文件不存在 ${PROTEINS}"
    else
        mkdir -p "$(dirname "${IS_OUT}")" "${IS_TMP}"
        echo "[mge:isfinder] ${SAMPLE}: MMseqs2 搜索插入序列..."
        EXIT_IS=0
        mgx_try mgx_conda assembly mmseqs easy-search \
                --threads    "${CPUS}" \
                --max-accept 1 \
                -e           1e-5 \
                --min-seq-id 0.9 \
                --format-output "query,target,fident,alnlen,mismatch,gapopen,qstart,qend,tstart,tend,evalue,bits,qcov" \
                -v           1 \
                "${PROTEINS}" \
                "${DB_ISFINDER}" \
                "${IS_OUT}" \
                "${IS_TMP}" || EXIT_IS=$?
        rm -rf "${IS_TMP}"
        if [ ${EXIT_IS} -ne 0 ]; then
            echo "[WARN] ISfinder 搜索失败（exit: ${EXIT_IS}），已跳过"
        else
            echo "[mge:isfinder] ${SAMPLE}: 命中 $(wc -l < "${IS_OUT}") 条 IS 元件"
        fi
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. ICEberg — 整合接合元件（blastn vs 组装 contig）
# ──────────────────────────────────────────────────────────────────────────────
ICE_OUT="${MGE_BASE}/iceberg/${SAMPLE}/iceberg_hits.tsv"

if [ ${SKIP_ICEBERG} -eq 0 ]; then
    if [ -f "${ICE_OUT}" ] && [ -s "${ICE_OUT}" ]; then
        echo "[mge:iceberg] 已存在，跳过: ${ICE_OUT}"
    elif [ ! -f "${CONTIGS}" ] || [ ! -s "${CONTIGS}" ]; then
        echo "[mge:iceberg] 跳过 ${SAMPLE}：contig 文件不存在 ${CONTIGS}"
    else
        mkdir -p "$(dirname "${ICE_OUT}")"
        echo "[mge:iceberg] ${SAMPLE}: blastn 搜索整合接合元件..."
        EXIT_ICE=0
        mgx_try mgx_conda assembly blastn \
                -task           blastn \
                -num_threads    "${CPUS}" \
                -query          "${CONTIGS}" \
                -db             "${DB_ICEBERG}" \
                -evalue         1e-5 \
                -perc_identity  70 \
                -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen qcovs" \
                -max_target_seqs 5 \
                -out            "${ICE_OUT}" || EXIT_ICE=$?
        if [ ${EXIT_ICE} -ne 0 ]; then
            echo "[WARN] ICEberg 搜索失败（exit: ${EXIT_ICE}），已跳过"
        else
            echo "[mge:iceberg] ${SAMPLE}: 命中 $(wc -l < "${ICE_OUT}") 条 ICE/IME 片段"
        fi
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. integrall — 整合子 class 1/2/3（blastn vs 基因核苷酸 .fna）
# ──────────────────────────────────────────────────────────────────────────────
INT_OUT="${MGE_BASE}/integrall/${SAMPLE}/integrall_hits.tsv"
FNA_FILE="${WORKDIR}/result/assembly/prodigal/${SAMPLE}/${SAMPLE}.fna"

if [ ${SKIP_INTEGRALL} -eq 0 ]; then
    if [ -f "${INT_OUT}" ] && [ -s "${INT_OUT}" ]; then
        echo "[mge:integrall] 已存在，跳过: ${INT_OUT}"
    elif [ ! -f "${FNA_FILE}" ] || [ ! -s "${FNA_FILE}" ]; then
        echo "[mge:integrall] 跳过 ${SAMPLE}：核苷酸基因文件不存在 ${FNA_FILE}"
    else
        mkdir -p "$(dirname "${INT_OUT}")"
        echo "[mge:integrall] ${SAMPLE}: blastn 搜索整合子..."
        EXIT_INT=0
        mgx_try mgx_conda assembly blastn \
                -task           blastn \
                -query          "${FNA_FILE}" \
                -db             "${DB_INTEGRALL}" \
                -num_threads    "${CPUS}" \
                -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovs" \
                -max_target_seqs 1 \
                -out            "${INT_OUT}" || EXIT_INT=$?
        if [ ${EXIT_INT} -ne 0 ]; then
            echo "[WARN] integrall 搜索失败（exit: ${EXIT_INT}），已跳过"
        else
            echo "[mge:integrall] ${SAMPLE}: 命中 $(wc -l < "${INT_OUT}") 条整合子相关基因"
        fi
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. transposase — 转座酶 HMM（hmmscan vs 蛋白 .faa）
# ──────────────────────────────────────────────────────────────────────────────
TN_OUT="${MGE_BASE}/transposase/${SAMPLE}/transposase_hits.tsv"

if [ ${SKIP_TRANSPOSASE} -eq 0 ]; then
    if [ -f "${TN_OUT}" ] && [ -s "${TN_OUT}" ]; then
        echo "[mge:transposase] 已存在，跳过: ${TN_OUT}"
    elif [ ! -f "${PROTEINS}" ] || [ ! -s "${PROTEINS}" ]; then
        echo "[mge:transposase] 跳过 ${SAMPLE}：蛋白文件不存在 ${PROTEINS}"
    else
        mkdir -p "$(dirname "${TN_OUT}")"
        echo "[mge:transposase] ${SAMPLE}: hmmscan 搜索转座酶..."
        EXIT_TN=0
        mgx_try mgx_conda dbcan hmmscan \
                --cpu     "${CPUS}" \
                --noali \
                --tblout  "${TN_OUT}" \
                "${DB_TRANSPOSASE}" \
                "${PROTEINS}" || EXIT_TN=$?
        if [ ${EXIT_TN} -ne 0 ]; then
            echo "[WARN] transposase hmmscan 失败（exit: ${EXIT_TN}），已跳过"
        else
            N_TN=$(grep -v "^#" "${TN_OUT}" 2>/dev/null | wc -l || echo "N/A")
            echo "[mge:transposase] ${SAMPLE}: 命中 ${N_TN} 条转座酶 HMM"
        fi
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5. mobileOG — NR 蛋白级综合 MGE 分类（diamond blastp vs NR gene catalog）
#    注意：此步骤使用 NR 蛋白集（protein_nr.fa），为 aggregate 步骤
#    多样本只需运行一次，已存在则自动跳过
# ──────────────────────────────────────────────────────────────────────────────
MOG_OUT="${MGE_BASE}/mobileog/mobileog_nr_hits.tsv"

if [ ${SKIP_MOBILEOG} -eq 0 ]; then
    if [ -f "${MOG_OUT}" ] && [ -s "${MOG_OUT}" ]; then
        echo "[mge:mobileog] NR 级结果已存在，跳过: ${MOG_OUT}"
    elif [ ! -f "${PROTEIN_NR}" ] || [ ! -s "${PROTEIN_NR}" ]; then
        echo "[mge:mobileog] 跳过：NR 蛋白集不存在 ${PROTEIN_NR}（请先运行 18_bac_cdhit.sh）"
    else
        mkdir -p "$(dirname "${MOG_OUT}")"
        echo "[mge:mobileog] 运行 mobileOG NR 级综合 MGE 注释..."
        EXIT_MOG=0
        mgx_try mgx_conda assembly diamond blastp \
                --db     "${DB_MOBILEOG}" \
                --query  "${PROTEIN_NR}" \
                --out    "${MOG_OUT}" \
                --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
                --evalue       1e-5 \
                --id           60 \
                --min-score    30 \
                --max-target-seqs 1 \
                --very-sensitive \
                --threads "${CPUS}" \
                --quiet || EXIT_MOG=$?
        if [ ${EXIT_MOG} -ne 0 ]; then
            echo "[WARN] mobileOG 搜索失败（exit: ${EXIT_MOG}），已跳过"
        else
            echo "[mge:mobileog] NR 级命中: $(wc -l < "${MOG_OUT}") 条 MGE"
        fi
    fi
fi

# --- 摘要 ---
echo ""
echo "[mge] 样本 ${SAMPLE} MGE 分析完成"
echo "    输出目录: ${MGE_BASE}/"
echo "    ISfinder    : ${MGE_BASE}/isfinder/${SAMPLE}/isfinder_hits.tsv"
echo "    ICEberg     : ${MGE_BASE}/iceberg/${SAMPLE}/iceberg_hits.tsv"
echo "    integrall   : ${MGE_BASE}/integrall/${SAMPLE}/integrall_hits.tsv"
echo "    transposase : ${MGE_BASE}/transposase/${SAMPLE}/transposase_hits.tsv"
echo "    mobileOG    : ${MGE_BASE}/mobileog/mobileog_nr_hits.tsv（NR 汇总，所有样本共享）"
echo "[提示] 结合 Salmon TPM + mobileOG 层级分类（hierarchy.txt）可量化各 MGE 类型丰度"
mgx_end "mge"
