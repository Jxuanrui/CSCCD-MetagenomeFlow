#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 66_vir_vog.sh
# 功  能: VOG HMM 扫描（跨界病毒 HMM 数据库）
#         工具版本：HMMER 3.3+（conda env: bacphlip）
# 依  赖: 64_vir_pharokka.sh 的预测蛋白（phanotate.faa）
# 输  入: ${WORKDIR}/result/virus/pharokka/phanotate.faa
# 输  出: ${WORKDIR}/result/virus/vog/
#           vog_hits.tsv    — HMM 命中表
#           vog_annot.tsv   — VOG 功能注释
#
# 参  考: VOGDB (vogdb.org); HMMER3 (Eddy 2011)
# 用  法: bash 66_vir_vog.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 66_vir_vog.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
PROTEINS="${WORKDIR}/result/virus/pharokka/phanotate.faa"
[ -f "$PROTEINS" ] || PROTEINS="${WORKDIR}/result/virus/pharokka/phanotate.faa"
OUTDIR="${WORKDIR}/result/virus/vog"
HITS="${OUTDIR}/vog_hits.tsv"
VOG_HMM="${REPO}/db/vogdb/VOG.hmm"
VOG_ANNOT="${REPO}/db/vogdb/vog_annotations.tsv"

if [ ! -f "${PROTEINS}" ] || [ ! -s "${PROTEINS}" ]; then
    echo "[WARN] 无病毒蛋白序列；尝试从 pharokka 结果收集 ..."
    for f in "${WORKDIR}"/result/virus/pharokka/*/phanotate.faa; do
        [ -f "$f" ] && { PROTEINS="$f"; break; }
    done 2>/dev/null
fi
if [ ! -f "${PROTEINS}" ]; then echo "[ERROR] 无法找到病毒蛋白序列"; exit 1; fi
if [ ! -f "${VOG_HMM}" ]; then echo "[WARN] VOG HMM 数据库不存在: ${VOG_HMM}"; mkdir -p "${OUTDIR}"; touch "${HITS}"; exit 0; fi

if [ -f "${HITS}" ] && [ -s "${HITS}" ]; then echo "[vog] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[vog] VOG HMM 扫描 ..."
mgx_conda bacphlip \
    hmmsearch \
        -E 1e-5 \
        --cpu "${CPUS}" \
        -o /dev/null \
        --tblout "${HITS}" \
        "${VOG_HMM}" \
        "${PROTEINS}"

# 若提供了注释文件，补充功能描述
if [ ${FORCE} -eq 0 ] && [ -f "${VOG_ANNOT}" ]; then
    python3 -c "
import sys
annot = {}
with open('${VOG_ANNOT}') as f:
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 2: annot[parts[0]] = parts[1]
with open('${HITS}') as f:
    for line in f:
        if line.startswith('#'): continue
        cols = line.strip().split()
        if len(cols) >= 3:
            vog = cols[2].split('.')[0] if '.' in cols[2] else cols[2]
            func = annot.get(vog, 'Unknown')
            print(f'{cols[2]}\t{cols[0]}\t{func}')
" > "${OUTDIR}/vog_annot.tsv" 2>/dev/null || true
fi

N_HITS=$(grep -vc '^#' "${HITS}" 2>/dev/null || echo 0)
echo "[vog] VOG 命中: ${N_HITS}"
mgx_end "vog"
